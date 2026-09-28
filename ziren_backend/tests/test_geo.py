"""Distances the product decides on: ellipsoidal, checked against an independent library.

The reference values below were computed with Karney's algorithm (geographiclib),
which is independent of the Vincenty implementation under test. The first pair is
Vincenty's own published test line (Flinders Peak to Buninyong, Geoscience
Australia), so a regression in the formula cannot hide behind a self-consistent
copy of itself.

Run with: pytest tests/test_geo.py -v
"""

import math

import pytest

from app.core import geo

# (lat1, lon1, lat2, lon2, metres) - Karney reference.
GOLDEN = {
    "flinders_buninyong": (
        -(37 + 57 / 60 + 3.72030 / 3600), 144 + 25 / 60 + 29.52440 / 3600,
        -(37 + 39 / 60 + 10.15610 / 3600), 143 + 55 / 60 + 35.38390 / 3600,
        54972.271,
    ),
    "naval_north_0_09deg": (11.5600, 124.4000, 11.6500, 124.4000, 9955.7301),
    "naval_east_0_09deg":  (11.5600, 124.4000, 11.5600, 124.4915, 9980.4614),
    "naval_diagonal":      (11.5600, 124.4000, 11.6100, 124.4500, 7767.2481),
    "cabucgayan_to_naval": (11.4500, 124.5600, 11.5600, 124.4000, 21278.1054),
    "short_200m":          (11.5600, 124.4000, 11.5617, 124.4010, 217.3962),
}


@pytest.mark.parametrize("name", GOLDEN)
def test_geodesic_matches_the_reference_to_a_millimetre(name):
    lat1, lon1, lat2, lon2, expected = GOLDEN[name]
    assert geo.geodesic_m(lat1, lon1, lat2, lon2) == pytest.approx(expected, abs=0.001)


def test_geodesic_is_symmetric():
    lat1, lon1, lat2, lon2, _ = GOLDEN["cabucgayan_to_naval"]
    assert geo.geodesic_m(lat1, lon1, lat2, lon2) == pytest.approx(
        geo.geodesic_m(lat2, lon2, lat1, lon1), abs=1e-6,
    )


def test_the_same_point_is_zero_metres_away():
    assert geo.geodesic_m(11.56, 124.4, 11.56, 124.4) == 0.0
    assert geo.haversine_m(11.56, 124.4, 11.56, 124.4) == 0.0


def test_a_point_on_the_equator_and_the_poles_do_not_break_the_iteration():
    # cos^2(alpha) = 0 on the equator is the classic divide-by-zero.
    assert geo.geodesic_m(0.0, 0.0, 0.0, 1.0) == pytest.approx(111319.4908, abs=0.01)
    assert geo.geodesic_m(89.9, 0.0, 89.9, 180.0) > 0
    assert geo.geodesic_m(-90.0, 0.0, 90.0, 0.0) == pytest.approx(20003931.4586, abs=0.01)


def test_nearly_antipodal_points_fall_back_instead_of_raising():
    # Vincenty famously fails to converge here. A dispatch path must not crash on it.
    d = geo.geodesic_m(0.0, 0.0, 0.5, 179.7)
    assert 19_900_000 < d < 20_100_000


def test_haversine_overstates_a_north_south_leg_at_biliran_and_geodesic_does_not():
    """The reason this module exists: a sphere is ~0.5% long going north-south here."""
    lat1, lon1, lat2, lon2, truth = GOLDEN["naval_north_0_09deg"]
    sphere = geo.haversine_m(lat1, lon1, lat2, lon2)
    assert sphere - truth == pytest.approx(51.8, abs=0.5)      # ~52 m long on a 10 km leg
    assert abs(geo.geodesic_m(lat1, lon1, lat2, lon2) - truth) < 0.001


def test_haversine_stays_within_half_a_percent_everywhere_in_the_province():
    """So it is safe as a pre-filter: it never misjudges by more than 0.6%."""
    for lat1, lon1, lat2, lon2, truth in GOLDEN.values():
        if truth < 1000 or abs(lat1) > 20:
            continue
        assert abs(geo.haversine_m(lat1, lon1, lat2, lon2) - truth) / truth < 0.006


@pytest.mark.parametrize("bad", [
    (91, 0, 0, 0), (-91, 0, 0, 0), (0, 181, 0, 0), (0, -181, 0, 0),
    (float("nan"), 0, 0, 0), (0, float("inf"), 0, 0), (None, 0, 0, 0), ("x", 0, 0, 0),
])
def test_impossible_coordinates_are_refused_loudly(bad):
    with pytest.raises(ValueError):
        geo.geodesic_m(*bad)
    with pytest.raises(ValueError):
        geo.haversine_m(*bad)


def test_valid_coordinates():
    assert geo.valid_coordinates(11.5, 124.4)
    assert geo.valid_coordinates("11.5", "124.4")     # PostgREST can hand back strings
    assert not geo.valid_coordinates(None, 124.4)
    assert not geo.valid_coordinates(11.5, float("nan"))
    assert not geo.valid_coordinates(95, 0)


# ── the pre-filter box ──────────────────────────────────────────────────────


def test_bbox_always_contains_the_circle_it_was_made_for():
    lat, lng = 11.56, 124.40
    for radius_m in (500, 4_000, 10_000, 15_000, 50_000):
        box = geo.bbox(lat, lng, radius_m)
        for bearing in range(0, 360, 15):
            # a point exactly radius_m away in that direction (spherical destination)
            br = math.radians(bearing)
            ang = radius_m / 6378137.0
            phi1, lmb1 = math.radians(lat), math.radians(lng)
            phi2 = math.asin(math.sin(phi1) * math.cos(ang) + math.cos(phi1) * math.sin(ang) * math.cos(br))
            lmb2 = lmb1 + math.atan2(
                math.sin(br) * math.sin(ang) * math.cos(phi1),
                math.cos(ang) - math.sin(phi1) * math.sin(phi2),
            )
            plat, plng = math.degrees(phi2), math.degrees(lmb2)
            assert geo.in_bbox(box, plat, plng), (radius_m, bearing)


def test_bbox_excludes_what_is_obviously_far():
    box = geo.bbox(11.56, 124.40, 5_000)
    assert not geo.in_bbox(box, 11.56, 124.60)      # ~22 km east
    assert not geo.in_bbox(box, 11.90, 124.40)      # ~38 km north
    assert geo.in_bbox(box, 11.57, 124.41)


def test_bbox_near_a_pole_spans_all_longitudes_instead_of_dividing_by_zero():
    box = geo.bbox(90.0, 0.0, 1_000)
    assert box[1] == -180.0 and box[3] == 180.0


# ── bearings ────────────────────────────────────────────────────────────────


@pytest.mark.parametrize("to,expected", [
    ((11.66, 124.40), 0.0), ((11.56, 124.50), 90.0), ((11.46, 124.40), 180.0), ((11.56, 124.30), 270.0),
])
def test_bearing_cardinal_directions(to, expected):
    assert geo.initial_bearing_deg(11.56, 124.40, *to) == pytest.approx(expected, abs=0.6)


def test_compass_names():
    assert [geo.compass_point(b) for b in (0, 44, 90, 135, 180, 225, 270, 315, 359.9)] == [
        "N", "NE", "E", "SE", "S", "SW", "W", "NW", "N",
    ]


# ── ETA ─────────────────────────────────────────────────────────────────────


def test_eta_rounds_up_and_is_never_zero():
    assert geo.estimate_eta_minutes(0.0) == 1
    assert geo.estimate_eta_minutes(0.2) == 1
    assert geo.estimate_eta_minutes(1.0) == 3            # 2 min at 30 km/h, +1 for rounding up
    assert geo.estimate_eta_minutes(15.0) == 31


def test_eta_never_exceeds_the_database_ceiling():
    assert geo.estimate_eta_minutes(10_000) == 600
    assert geo.estimate_eta_minutes(-5) == 1


# ── reading a PostGIS point ─────────────────────────────────────────────────


def test_parse_point_reads_geojson_longitude_first():
    assert geo.parse_point({"type": "Point", "coordinates": [124.4, 11.56]}) == (11.56, 124.4)


def test_parse_point_reads_wkt_and_ewkt():
    assert geo.parse_point("POINT(124.4 11.56)") == (11.56, 124.4)
    assert geo.parse_point("SRID=4326;POINT(124.4 11.56)") == (11.56, 124.4)
    assert geo.parse_point("point( 124.4   -11.56 )") == (-11.56, 124.4)


@pytest.mark.parametrize("bad", [
    None, "", "POINT EMPTY", "LINESTRING(0 0, 1 1)", {"coordinates": []}, {"coordinates": ["x", "y"]},
    {"coordinates": [200, 11.56]}, "POINT(124.4 95)", 12, [124.4, 11.56],
])
def test_parse_point_never_raises_and_says_nothing_for_junk(bad):
    assert geo.parse_point(bad) == (None, None)
