"""
Geodesy for Ziren: how far apart are two points on the ground?

WHY THIS IS NOT JUST HAVERSINE

Every distance the product shows or decides on goes through this module: which
station a report is routed to, which responders are close enough to be told about
a new incident, the ETA a resident sees. Until now all of them used the Haversine
formula, which treats the Earth as a SPHERE (radius 6371 km). The Earth is an
oblate spheroid, and a sphere is wrong in a direction that matters here:

  * Near the equator a degree of latitude is SHORTER than the sphere assumes
    (the meridian radius of curvature is about 6335 km at 0 deg, 6336 km at
    Biliran's 11.6 deg N, against the sphere's flat 6371 km). Haversine therefore
    overstates every north-south leg by about half a percent.
  * East-west it is slightly the other way (prime-vertical radius 6378 km).

Concretely, for two points 0.09 deg of latitude apart at Naval, the true distance
is 9,955.7 m and Haversine says 10,007.5 m: 52 m too long, on a 10 km leg. Small
in absolute terms, but it is a systematic bias in exactly the quantity a
"nearest unit" decision compares, and it is free to remove.

WHAT IS USED

`geodesic_m` is Vincenty's inverse formula on the WGS-84 ellipsoid: the shortest
path ON the ellipsoid, accurate to about half a millimetre, which is the model
GPS itself reports positions in (and the one PostGIS uses for geography
distances). Vincenty is iterative and can fail to converge for nearly antipodal
points, which cannot happen inside one province but must not crash a dispatch
path, so a non-converging pair falls back to Haversine instead of raising.

`haversine_m` is kept for that fallback and as the cheap pre-filter it is good
for; `bbox` gives a conservative box around a point so a caller can discard the
obviously-far candidates before paying for the iteration.

WHAT THIS IS NOT

Straight-line (geodesic) distance is a lower bound on the distance a crew drives.
There is no road graph for Biliran's barangay roads worth paying for, so travel
time is estimated from the geodesic distance at an assumed speed (see
`estimate_eta_minutes`), rounded UP: a crew arriving before the app said they
would is a good surprise; the opposite is a family watching an empty street.
"""

from __future__ import annotations

import math
import re

# WGS-84 ellipsoid.
_A = 6378137.0                    # semi-major axis, metres
_F = 1.0 / 298.257223563          # flattening
_B = _A * (1.0 - _F)              # semi-minor axis, metres

#: Mean Earth radius (IUGG), used only by the spherical fallback / pre-filter.
_MEAN_RADIUS_M = 6371008.7714

#: Assumed average road speed for the ETA, in km/h.
#:
#: Low on purpose. These are provincial roads - single carriageway, unlit, with
#: barangay traffic on them - and the number is applied to a STRAIGHT-LINE
#: distance, which always understates the real route. Both errors point the same
#: way, so the ETA runs long rather than short.
ASSUMED_SPEED_KMH = 30.0

#: The `incidents.eta_minutes` column's CHECK ceiling.
_ETA_MAX_MINUTES = 600


def valid_coordinates(lat: object, lng: object) -> bool:
    """True for a real latitude/longitude pair (finite, within range)."""
    try:
        la, lo = float(lat), float(lng)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return False
    return (
        math.isfinite(la) and math.isfinite(lo)
        and -90.0 <= la <= 90.0 and -180.0 <= lo <= 180.0
    )


_WKT_POINT = re.compile(
    r"POINT\s*\(\s*([-+]?[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?)\s+"
    r"([-+]?[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?)\s*\)",
    re.IGNORECASE,
)


def parse_point(location: object) -> tuple[float | None, float | None]:
    """(latitude, longitude) of a PostGIS point as PostgREST hands it back.

    PostgREST returns a geometry column as a GeoJSON object, whose coordinate
    pair is ordered [LONGITUDE, LATITUDE] - the opposite of every screen in this
    product. Some paths return WKT ("POINT(lng lat)") or EWKT
    ("SRID=4326;POINT(lng lat)") instead. Getting the order wrong does not
    error: it puts the incident in the sea off Somalia. Returns (None, None) for
    anything unreadable or out of range, never raises.
    """
    lat: float | None = None
    lng: float | None = None
    try:
        if isinstance(location, dict):
            pair = location.get("coordinates")
            if isinstance(pair, (list, tuple)) and len(pair) >= 2:
                lng, lat = float(pair[0]), float(pair[1])
        elif isinstance(location, str):
            match = _WKT_POINT.search(location)
            if match:
                lng, lat = float(match.group(1)), float(match.group(2))
    except (TypeError, ValueError):
        return None, None
    if lat is None or lng is None or not valid_coordinates(lat, lng):
        return None, None
    return lat, lng


def _check(lat1: float, lon1: float, lat2: float, lon2: float) -> None:
    if not (valid_coordinates(lat1, lon1) and valid_coordinates(lat2, lon2)):
        raise ValueError(
            f"invalid coordinates: ({lat1}, {lon1}) -> ({lat2}, {lon2})"
        )


def haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Great-circle distance in metres on a SPHERE of mean Earth radius.

    A pre-filter and a fallback, not the answer: see the module docstring for why
    it is up to ~0.5% off on the ellipsoid.
    """
    _check(lat1, lon1, lat2, lon2)
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = phi2 - phi1
    dlmb = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlmb / 2) ** 2
    return _MEAN_RADIUS_M * 2.0 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a))


def geodesic_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Shortest distance in metres between two points ON the WGS-84 ellipsoid.

    Vincenty's inverse formula (T. Vincenty, 1975), iterated to 1e-12 rad, which
    is sub-millimetre. Symmetric in its arguments. Raises ValueError for a
    coordinate that is not a real latitude/longitude - callers filter those out
    first, because a silently wrong distance in a dispatch decision is worse than
    a loud failure in a test.
    """
    _check(lat1, lon1, lat2, lon2)
    if lat1 == lat2 and lon1 == lon2:
        return 0.0

    L = math.radians(lon2 - lon1)
    U1 = math.atan((1.0 - _F) * math.tan(math.radians(lat1)))
    U2 = math.atan((1.0 - _F) * math.tan(math.radians(lat2)))
    sinU1, cosU1 = math.sin(U1), math.cos(U1)
    sinU2, cosU2 = math.sin(U2), math.cos(U2)

    lam = L
    for _ in range(200):
        sin_lam, cos_lam = math.sin(lam), math.cos(lam)
        sin_sigma = math.hypot(
            cosU2 * sin_lam,
            cosU1 * sinU2 - sinU1 * cosU2 * cos_lam,
        )
        if sin_sigma == 0.0:
            return 0.0  # coincident points
        cos_sigma = sinU1 * sinU2 + cosU1 * cosU2 * cos_lam
        sigma = math.atan2(sin_sigma, cos_sigma)
        sin_alpha = cosU1 * cosU2 * sin_lam / sin_sigma
        cos_sq_alpha = 1.0 - sin_alpha ** 2
        # cos_sq_alpha is 0 only on the equator; the term is then defined as 0.
        cos_2sm = (
            cos_sigma - 2.0 * sinU1 * sinU2 / cos_sq_alpha
            if cos_sq_alpha != 0.0 else 0.0
        )
        C = _F / 16.0 * cos_sq_alpha * (4.0 + _F * (4.0 - 3.0 * cos_sq_alpha))
        lam_prev = lam
        lam = L + (1.0 - C) * _F * sin_alpha * (
            sigma + C * sin_sigma * (
                cos_2sm + C * cos_sigma * (-1.0 + 2.0 * cos_2sm ** 2)
            )
        )
        if abs(lam - lam_prev) < 1e-12:
            break
    else:
        # Nearly antipodal: Vincenty does not converge. Never crash a dispatch
        # path over it.
        return haversine_m(lat1, lon1, lat2, lon2)

    u_sq = cos_sq_alpha * (_A ** 2 - _B ** 2) / (_B ** 2)
    big_a = 1.0 + u_sq / 16384.0 * (4096.0 + u_sq * (-768.0 + u_sq * (320.0 - 175.0 * u_sq)))
    big_b = u_sq / 1024.0 * (256.0 + u_sq * (-128.0 + u_sq * (74.0 - 47.0 * u_sq)))
    delta_sigma = big_b * sin_sigma * (
        cos_2sm + big_b / 4.0 * (
            cos_sigma * (-1.0 + 2.0 * cos_2sm ** 2)
            - big_b / 6.0 * cos_2sm
            * (-3.0 + 4.0 * sin_sigma ** 2) * (-3.0 + 4.0 * cos_2sm ** 2)
        )
    )
    return _B * big_a * (sigma - delta_sigma)


def geodesic_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """`geodesic_m` in kilometres."""
    return geodesic_m(lat1, lon1, lat2, lon2) / 1000.0


def bbox(lat: float, lng: float, radius_m: float) -> tuple[float, float, float, float]:
    """(min_lat, min_lng, max_lat, max_lng) of a box that CONTAINS the circle.

    Conservative on purpose: it uses the smallest metres-per-degree figures, so
    the box is never smaller than the true radius. A caller discards whatever
    lies outside it and then measures the rest properly.
    """
    if not valid_coordinates(lat, lng):
        raise ValueError(f"invalid coordinates: ({lat}, {lng})")
    radius_m = max(0.0, float(radius_m))
    # 110,574 m is the shortest degree of latitude (at the equator).
    dlat = radius_m / 110574.0
    # A degree of longitude shrinks with cos(lat); its equatorial length is
    # 111,319.49 m, rounded DOWN here so the box can only ever be too big. Guarded
    # near the poles, where the box simply spans every longitude.
    cos_lat = math.cos(math.radians(lat))
    dlng = 180.0 if cos_lat < 1e-6 else min(180.0, radius_m / (111319.0 * cos_lat))
    return (
        max(-90.0, lat - dlat), max(-180.0, lng - dlng),
        min(90.0, lat + dlat), min(180.0, lng + dlng),
    )


def in_bbox(box: tuple[float, float, float, float], lat: float, lng: float) -> bool:
    """Whether (lat, lng) lies inside a box from `bbox`."""
    return box[0] <= lat <= box[2] and box[1] <= lng <= box[3]


def initial_bearing_deg(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Compass bearing (0-360, clockwise from north) to head from point 1 to 2.

    A spherical bearing. Its error over a few kilometres is far below what a
    person reading "north-east" could notice, so the ellipsoidal version would be
    precision nobody can use.
    """
    _check(lat1, lon1, lat2, lon2)
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dlmb = math.radians(lon2 - lon1)
    y = math.sin(dlmb) * math.cos(phi2)
    x = math.cos(phi1) * math.sin(phi2) - math.sin(phi1) * math.cos(phi2) * math.cos(dlmb)
    return (math.degrees(math.atan2(y, x)) + 360.0) % 360.0


_COMPASS = ("N", "NE", "E", "SE", "S", "SW", "W", "NW")


def compass_point(bearing_deg: float) -> str:
    """The 8-point compass name for a bearing."""
    return _COMPASS[int(((bearing_deg % 360.0) + 22.5) // 45.0) % 8]


def estimate_eta_minutes(distance_km: float) -> int:
    """Minutes to cover `distance_km` at the assumed road speed, rounded UP.

    Never 0 (a crew is never "already there" by arithmetic), capped at the
    column's CHECK ceiling. Shared by every ETA in the product so a responder's
    ping and a "who is nearest" ranking can never disagree about the same trip.
    """
    minutes = int(max(0.0, distance_km) / ASSUMED_SPEED_KMH * 60.0) + 1
    return max(1, min(minutes, _ETA_MAX_MINUTES))
