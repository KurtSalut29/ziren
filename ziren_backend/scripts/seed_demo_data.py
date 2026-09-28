"""
Fill a Ziren database with realistic DEMO data, so the dashboards can be judged
under load instead of on the handful of rows a dev database normally holds.

    python scripts/seed_demo_data.py --dry-run          # plan only, writes nothing
    python scripts/seed_demo_data.py                     # seed
    python scripts/seed_demo_data.py --clean             # remove everything it made
    python scripts/seed_demo_data.py --clean --then-seed # wipe and reseed

What it creates
---------------
  * Residents across every municipality, in a spread of verification states
    (verified, phone-verified, unverified, and a pending review queue).
  * Responders for every agency that has a station, on and off duty, plus a few
    still awaiting approval.
  * Incidents over the last 90 days, weighted so the last two weeks are busy,
    with a weekday/hour rhythm, every status, severity and category, a
    handful open right now, and a matching dispatch_log trail.
  * A few pending Agency Admin access requests.

It creates NO agencies, stations or admins: every incident lands on a real
station, so every station and both provincial roles see data. Maripipi has no
stations in this database, so it receives residents but no incidents.

How it stays removable
----------------------
Every account it makes has an email ending in @seed.ziren.test, and every
incident it makes is filed by one of those accounts. `--clean` deletes exactly
that set (dispatch_log -> incidents -> access requests -> accounts) and nothing
else. The accounts get random passwords that are thrown away: nobody can log in
as them, and no invitation or confirmation email is sent.

Talks to whatever project SUPABASE_URL points at (service role), so read the
URL it prints before answering the prompt.
"""

from __future__ import annotations

import argparse
import json
import math
import pathlib
import random
import secrets
import sys
import uuid
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone

from shapely.geometry import Point, shape

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from app.core.config import settings  # noqa: E402
from app.db.supabase_client import get_supabase  # noqa: E402

# Biliran's real coastline (OpenStreetMap relation 3749388, simplified to
# ~270 points — see app/data/biliran_boundary.geojson's own header for how
# and why). Used by _jitter() below to keep a synthetic point on the actual
# island instead of a plausible-looking circle that ignores the coastline.
_BILIRAN_LAND = shape(
    json.loads((ROOT / "app" / "data" / "biliran_boundary.geojson").read_text(encoding="utf-8"))
)

DOMAIN = "seed.ziren.test"
PH = timedelta(hours=8)  # Philippine time is UTC+8, no daylight saving.

# Share of residents, and of incidents, by municipality. Maripipi has no
# stations, so it is left out of the incident weights.
RESIDENT_WEIGHT = {"Naval": 28, "Biliran": 14, "Almeria": 10, "Cabucgayan": 10,
                   "Caibiran": 12, "Culaba": 8, "Kawayan": 10, "Maripipi": 8}
INCIDENT_WEIGHT = {k: v for k, v in RESIDENT_WEIGHT.items() if k != "Maripipi"}

FIRST = ["Jonel", "Maricel", "Rogelio", "Analyn", "Jhon", "Carla", "Ramil", "Dolores",
         "Mark", "Jenny", "Rey", "Liza", "Arnel", "Gemma", "Nestor", "Cristina",
         "Bong", "Rowena", "Joel", "Mylene", "Danilo", "Shiela", "Erwin", "Marites",
         "Allan", "Vilma", "Jerome", "Leah", "Ferdie", "Aileen", "Renato", "Joanna",
         "Ernesto", "Cherry", "Ronald", "Grace", "Elmer", "Beth", "Noel", "Sheryl"]
LAST = ["Abella", "Bacus", "Caballero", "Cabalida", "Datu", "Espina", "Fabillar", "Gabon",
        "Labrador", "Lumen", "Maglinte", "Nierra", "Ocenar", "Pacatang", "Quirog",
        "Rosales", "Sabando", "Tagra", "Ubaldo", "Vicente", "Yabut", "Zamora",
        "Ibañez", "Larrazabal", "Sabalza", "Tan", "Uy", "Bautista", "Cordova", "Dumaog"]
MIDDLE = ["A.", "B.", "C.", "D.", "E.", "G.", "L.", "M.", "P.", "R.", "S.", "T."]
PUROK = ["Purok 1", "Purok 2", "Purok 3", "Purok 4", "Purok 5", "Sitio Riverside", "Sitio Centro"]

CATEGORY_WEIGHT = {"medical_trauma": 24, "vehicular": 22, "fire": 14,
                   "flood_landslide_calamity": 12, "domestic_dispute_crime": 16, "other": 12}
AGENCY_BY_CATEGORY = {
    "fire": {"BFP": 90, "MDRRMO": 10},
    "medical_trauma": {"MDRRMO": 70, "BFP": 30},
    "vehicular": {"PNP": 50, "MDRRMO": 40, "BFP": 10},
    "flood_landslide_calamity": {"MDRRMO": 90, "BFP": 10},
    "domestic_dispute_crime": {"PNP": 95, "MDRRMO": 5},
    "other": {"PNP": 34, "BFP": 33, "MDRRMO": 33},
}
SEVERITY_BY_CATEGORY = {  # critical, high, medium, low
    "fire": (25, 40, 25, 10), "medical_trauma": (20, 35, 30, 15),
    "vehicular": (10, 30, 40, 20), "flood_landslide_calamity": (10, 30, 35, 25),
    "domestic_dispute_crime": (6, 24, 40, 30), "other": (2, 10, 38, 50),
}
SEVERITIES = ["critical", "high", "medium", "low"]
LEVEL_NAME = {"critical": "CRITICAL", "high": "HIGH", "medium": "MODERATE", "low": "LOW"}

TEXT = {
    "fire": ["May sunog sa {p}, nagdaku na an kalayo! Tabang gad.",
             "Fire at a house near {p}. Smoke is already coming out of the roof.",
             "Nasusunog ang kusina namin dito sa {p}, kumakalat na.",
             "Grass fire spreading toward houses in {p}, need the fire truck."],
    "medical_trauma": ["Nahulog an tatay ko halin sa kahoy dinhi sa {p}, dae na nagigising.",
                       "Someone collapsed and is having chest pains at {p}. Please send an ambulance.",
                       "Buntis na manganganak na, hindi na kaya ihatid sa {p}. Emergency po.",
                       "Child with a deep cut on the leg, bleeding a lot, {p}."],
    "vehicular": ["Rasklashado haka motor ngan tricycle sa {p}, may gasugat.",
                  "Motorcycle crash on the highway near {p}, one rider not moving.",
                  "Nabangga po ang isang bata ng van sa {p}. Bilis po.",
                  "Truck overturned at the curve in {p}, road is blocked."],
    "flood_landslide_calamity": ["Nagbaha na dinhi sa {p}, gintutuok na an mga balay.",
                                 "Landslide blocked the road in {p}, two houses affected.",
                                 "Rising river water in {p}, families need to be evacuated.",
                                 "Natumba ang malaking puno sa {p} at tumakip sa daan."],
    "domestic_dispute_crime": ["May nag-aaway na mag-asawa sa {p}, may hawak na itak.",
                               "Theft reported at a sari-sari store in {p}, suspect ran off.",
                               "Nagpaputok ng baril ang lasing dito sa {p}.",
                               "Suspicious men trying to open a motorcycle in {p}."],
    "other": ["Need help po sa {p}, hindi ko alam ang gagawin.",
              "Loud noise and a crowd gathering at {p}, please check.",
              "Stray dogs attacking people near the school in {p}.",
              "Power line down across the road in {p}."],
}
OUTCOMES = [("handled_on_scene", 55), ("transported", 15), ("turned_over", 8), ("false_alarm", 8),
            ("nobody_found", 4), ("refused_assistance", 3), ("unable_to_access", 2), ("other", 5)]
REJECT_REASONS = ["Duplicate of an earlier report.", "Not an emergency for this agency.",
                  "Caller could not be reached and the location was unclear."]

# Hour-of-day weights in Philippine time: quiet overnight, busy late afternoon
# and evening. Weekday weights: busier towards the weekend.
HOUR_W = [2, 1.5, 1.2, 1, 1, 1.5, 3, 4.5, 5, 5, 4.5, 5, 5, 4.5, 4.5, 5, 6, 7.5, 8.5, 9, 8, 6.5, 4.5, 3]
DOW_W = [0.9, 0.85, 0.9, 0.95, 1.15, 1.3, 1.2]  # Monday first


def wchoice(rng: random.Random, weights: dict):
    keys = list(weights)
    return rng.choices(keys, [weights[k] for k in keys])[0]


# Biliran is a small, coastal island — most stations sit near the shore, and a
# scatter this generator used to draw as two INDEPENDENT uniform offsets on
# lat and lng (up to +-0.02 deg each, ~3.1km at the corners of that square)
# routinely placed a demo incident out in open water. A real report's GPS
# fix is wherever the phone actually was, always on land; a synthetic one
# needs the same property enforced by construction. This draws a point
# uniformly inside a CIRCLE of the given radius instead (sqrt(random) is the
# standard trick for that — a uniform radius alone clusters points at the
# center), and keeps the radius small enough (400m default) to read as
# "somewhere near this station" on the map without wandering past whatever
# shoreline is nearby.
def _jitter(lat: float, lng: float, rng: random.Random, radius_km: float = 0.4) -> tuple[float, float]:
    """A point within `radius_km` of (lat, lng), guaranteed to land inside
    Biliran's real coastline (_BILIRAN_LAND) — a circle alone isn't enough:
    a station a kilometre or two from shore has a circle that crosses into
    open water on one side of it, and a naive draw takes that water as often
    as the land. Resampled up to 40 times before giving up and returning the
    station's own (real, surveyed, on-land) point unmoved — for any station
    this codebase actually seeds, that ceiling is never reached; it exists so
    a station placed absurdly close to the waterline degrades to "no visible
    scatter" rather than an infinite loop.
    """
    for _ in range(40):
        r_km = radius_km * math.sqrt(rng.random())
        angle = rng.uniform(0, 2 * math.pi)
        dlat = (r_km / 111.32) * math.cos(angle)
        dlng = (r_km / (111.32 * math.cos(math.radians(lat)))) * math.sin(angle)
        cand_lat, cand_lng = lat + dlat, lng + dlng
        if _BILIRAN_LAND.contains(Point(cand_lng, cand_lat)):
            return cand_lat, cand_lng
    return lat, lng


class Seeder:
    def __init__(self, seed: int):
        self.rng = random.Random(seed)
        self.db = get_supabase()
        self.now = datetime.now(timezone.utc)

    # ── reference data ────────────────────────────────────────────────
    def load_reference(self):
        db = self.db
        self.agencies = {a["id"]: a for a in db.table("agencies").select("*").eq("is_active", True).execute().data}
        self.stations = db.table("stations").select("id, agency_id, name, location").eq("is_active", True).execute().data
        self.stations_by_agency = defaultdict(list)
        for s in self.stations:
            self.stations_by_agency[s["agency_id"]].append(s)
        self.barangays = defaultdict(list)
        for b in db.table("barangays").select("id, name, municipality").execute().data:
            self.barangays[b["municipality"]].append(b)
        admins = db.table("users").select("id, agency_id").eq("role", "agency_admin").execute().data
        self.admin_of = {}
        for a in admins:
            self.admin_of.setdefault(a["agency_id"], a["id"])
        # (municipality, type) -> agency
        self.agency_for = {(a["municipality"], a["agency_type"]): a for a in self.agencies.values()}
        self.responders = defaultdict(list)  # agency_id -> [user ids], filled by seeding + existing
        for r in db.table("users").select("id, agency_id").eq("role", "responder").eq("approval_status", "approved").execute().data:
            self.responders[r["agency_id"]].append(r["id"])

    # ── accounts ──────────────────────────────────────────────────────
    def make_account(self, email: str, full_name: str, role: str) -> str | None:
        try:
            res = self.db.auth.admin.create_user({
                "email": email, "password": secrets.token_urlsafe(24), "email_confirm": True,
                "user_metadata": {"full_name": full_name, "role": role},
            })
            return str(res.user.id)
        except Exception as exc:  # noqa: BLE001 — report and carry on with the rest
            print(f"  ! could not create {email}: {exc}")
            return None

    def person(self):
        first, last = self.rng.choice(FIRST), self.rng.choice(LAST)
        mid = self.rng.choice(MIDDLE)
        return first, mid, last, f"{first} {mid} {last}"

    def phone(self):
        return "09" + "".join(str(self.rng.randint(0, 9)) for _ in range(9))

    def seed_residents(self, n: int, pending: int):
        rng, muni_w = self.rng, RESIDENT_WEIGHT
        self.residents = defaultdict(list)  # municipality -> ids
        rows = []
        for i in range(n):
            muni = wchoice(rng, muni_w)
            first, mid, last, full = self.person()
            uid = self.make_account(f"resident.{i + 1:04d}@{DOMAIN}", full, "resident")
            if not uid:
                continue
            brgy = rng.choice(self.barangays[muni])
            created = self.now - timedelta(days=rng.random() ** 0.8 * 120, hours=rng.random() * 12)
            row = {
                "id": uid, "email": f"resident.{i + 1:04d}@{DOMAIN}", "full_name": full, "role": "resident",
                "first_name": first, "middle_name": mid, "last_name": last, "phone_number": self.phone(),
                "barangay": f"Brgy. {brgy['name']}", "barangay_id": brgy["id"], "municipality_address": muni,
                "purok_sitio": rng.choice(PUROK), "sex": rng.choice(["male", "female"]),
                "date_of_birth": (self.now - timedelta(days=rng.randint(18 * 365, 74 * 365))).date().isoformat(),
                "terms_accepted_at": created.isoformat(), "terms_version": "1.0", "privacy_version": "1.0",
                "consent_locale": rng.choice(["en", "fil"]), "created_at": created.isoformat(),
                "preferred_language": rng.choice(["English", "Waray", "Filipino"]),
                "is_pwd": rng.random() < 0.05,
            }
            if i < pending:
                # Waiting in the Verification queue: documents submitted, undecided.
                row.update(self.pending_docs(uid, created))
            else:
                roll = rng.random()
                if roll < 0.55:
                    when = created + timedelta(hours=rng.randint(2, 96))
                    row.update({"verification_level": 2, "is_verified": True, "verified_at": when.isoformat(),
                                "verification_method": rng.choice(["government_id", "barangay_official", "government_id", "pwd_id"]),
                                "valid_id_type": rng.choice(["barangay_id", "voters_id", "philsys", "drivers_license", "umid"]),
                                "valid_id_number": f"{rng.randint(1000, 9999)}-{rng.randint(10000, 99999)}"})
                elif roll < 0.70:
                    row.update({"verification_level": 1, "verification_method": "phone_otp",
                                "verified_at": (created + timedelta(minutes=5)).isoformat()})
            # Rows in one batch must share their keys: PostgREST fills a key that
            # some rows lack with NULL, which the NOT NULL columns reject.
            row.setdefault("is_verified", False)
            row.setdefault("verification_level", 0)
            if row.get("is_pwd"):
                row["pwd_id_number"] = f"PWD-{rng.randint(100000, 999999)}"
            rows.append(row)
            self.residents[muni].append(uid)
        self.upsert("users", rows)
        print(f"  residents: {len(rows)}  (pending review: {min(pending, len(rows))})")

    def pending_docs(self, uid: str, created: datetime):
        rng = self.rng
        verdict = rng.choices(["match", "uncertain", "no_match", "no_face_on_id", "unavailable"], [50, 20, 10, 5, 15])[0]
        return {
            "verification_level": 0, "valid_id_type": rng.choice(["barangay_id", "voters_id", "philsys", "drivers_license"]),
            "valid_id_number": f"{rng.randint(1000, 9999)}-{rng.randint(10000, 99999)}",
            "valid_id_image_path": f"demo-seed/{uid}/id.jpg", "selfie_image_path": f"demo-seed/{uid}/selfie.jpg",
            "residency_proof_type": rng.choice(["lgu_id", "national_id", "barangay_certificate"]),
            "liveness_method": "mlkit_blink", "liveness_asserted_at": created.isoformat(),
            "face_match_verdict": verdict, "face_match_score": round(rng.uniform(0.2, 0.95), 3),
            "face_match_checked_at": created.isoformat(), "id_number_source": rng.choice(["typed", "ocr", "ocr_edited"]),
            "id_checks": {"readable": verdict != "no_face_on_id", "expired": rng.random() < 0.08,
                          "face_found": verdict != "no_face_on_id"},
        }

    def seed_responders(self, per_agency: tuple[int, int], pending: int):
        rng = self.rng
        rows, n = [], 0
        for agency_id, stations in self.stations_by_agency.items():
            agency = self.agencies.get(agency_id)
            if not agency:
                continue
            for _ in range(rng.randint(*per_agency)):
                n += 1
                first, mid, last, full = self.person()
                email = f"responder.{n:03d}@{DOMAIN}"
                # Born as a resident: users_agency_required_check rejects a responder
                # row with no agency, and the signup trigger cannot know the agency.
                # The upsert below sets role and agency_id together.
                uid = self.make_account(email, full, "resident")
                if not uid:
                    continue
                st = rng.choice(stations)
                lng, lat = st["location"]["coordinates"]
                jlat, jlng = _jitter(lat, lng, rng, radius_km=0.3)
                is_pending = n <= pending
                rows.append({
                    "id": uid, "email": email, "full_name": full, "role": "responder", "agency_id": agency_id,
                    "first_name": first, "middle_name": mid, "last_name": last, "phone_number": self.phone(),
                    "badge_id": f"{agency['agency_type']}-2026-{n:04d}",
                    "approval_status": "pending" if is_pending else "approved",
                    "availability": "on_duty" if (not is_pending and rng.random() < 0.6) else "off_duty",
                    "rank_or_position": rng.choice(["Responder I", "Responder II", "Team Leader", "Officer"]),
                    "date_joined": (self.now - timedelta(days=rng.randint(30, 1500))).date().isoformat(),
                    "location": f"SRID=4326;POINT({jlng:.6f} {jlat:.6f})",
                    "terms_accepted_at": self.now.isoformat(), "terms_version": "1.0", "privacy_version": "1.0",
                })
                if not is_pending:
                    self.responders[agency_id].append(uid)
        self.upsert("users", rows)
        print(f"  responders: {len(rows)}  (awaiting approval: {min(pending, len(rows))})")

    def seed_access_requests(self, n: int):
        picks = self.rng.sample(list(self.agencies.values()), min(n, len(self.agencies)))
        rows = []
        for i, a in enumerate(picks):
            _, _, _, full = self.person()
            rows.append({"full_name": full, "email": f"admin.request.{i + 1}@{DOMAIN}", "agency_id": a["id"],
                         "position": self.rng.choice(["Station Commander", "Operations Officer", "MDRRMO Officer", "Duty Officer"]),
                         "created_at": (self.now - timedelta(days=self.rng.randint(0, 9), hours=self.rng.randint(0, 20))).isoformat()})
        self.insert("access_requests", rows)
        print(f"  access requests: {len(rows)}")

    # ── incidents ─────────────────────────────────────────────────────
    def created_at(self, live: bool) -> datetime:
        rng = self.rng
        if live:
            return self.now - timedelta(minutes=rng.uniform(3, 14 * 60))
        while True:
            days_ago = rng.uniform(0.6, 90)
            # Busier the closer to today; the last two weeks are the busiest.
            recency = 1.0 + 1.6 * math.exp(-days_ago / 9)
            day = self.now - timedelta(days=days_ago)
            local = day + PH
            w = DOW_W[local.weekday()] * recency
            if rng.random() > w / (1.3 * 2.6):
                continue
            hour = rng.choices(range(24), HOUR_W)[0]
            local = local.replace(hour=hour, minute=rng.randint(0, 59), second=rng.randint(0, 59), microsecond=0)
            t = local - PH
            if t < self.now - timedelta(hours=14):
                return t

    def build_incident(self, live: bool):
        rng = self.rng
        category = wchoice(rng, CATEGORY_WEIGHT)
        atype = wchoice(rng, AGENCY_BY_CATEGORY[category])
        muni = wchoice(rng, INCIDENT_WEIGHT)
        agency = self.agency_for.get((muni, atype))
        if not agency or not self.stations_by_agency.get(agency["id"]):
            return None
        station = rng.choice(self.stations_by_agency[agency["id"]])
        pool = self.residents.get(muni) or [r for v in self.residents.values() for r in v]
        reporter = rng.choice(pool)
        brgy = rng.choice(self.barangays[muni])["name"]
        lng, lat = station["location"]["coordinates"]
        jlat, jlng = _jitter(lat, lng, rng)
        created = self.created_at(live)
        severity = rng.choices(SEVERITIES, SEVERITY_BY_CATEGORY[category])[0]
        via = rng.choices(["internet", "offline_sync", "sos"], [78, 7, 15])[0]
        admin = self.admin_of.get(agency["id"])
        responders = self.responders.get(agency["id"]) or []

        row = {
            "id": str(uuid.uuid4()), "reporter_id": reporter,
            "report_text": rng.choice(TEXT[category]).format(p=f"Brgy. {brgy}"),
            "location": f"SRID=4326;POINT({jlng:.6f} {jlat:.6f})",
            "location_address": f"{brgy}, {muni}, Biliran",
            "severity": severity, "incident_category": category, "submitted_via": via, "sos_flagged": via == "sos",
            "suggested_agency_id": agency["id"], "assigned_agency_id": agency["id"], "station_id": station["id"],
            "created_at": created.isoformat(), "review_status": "pending",
            "signals": {"engine": "ziren-model", "engine_version": "2.1.5", "severity_level": LEVEL_NAME[severity],
                        "severity_rule": "SR010", "user_selected": category, "routing_agencies": [atype],
                        "demo_seed": True},
        }
        log = []

        def accept_review(at: datetime):
            row.update({"review_status": "accepted", "reviewed_at": at.isoformat(), "reviewed_by": admin})

        def stamp(action: str, at: datetime, notes: str | None = None):
            if admin:
                log.append({"incident_id": row["id"], "dispatcher_id": admin, "agency_id": agency["id"],
                            "suggested_severity": severity, "chosen_severity": severity, "suggested_agency_id": agency["id"],
                            "chosen_agency_id": agency["id"], "action": action, "notes": notes, "created_at": at.isoformat()})

        if live:
            status = rng.choices(["received", "processing", "dispatched", "en_route", "arrived"], [25, 10, 25, 20, 20])[0]
            row["status"] = status
            if status != "received":
                accept_review(created + timedelta(minutes=rng.uniform(0.5, 3)))
            if status in ("dispatched", "en_route", "arrived"):
                disp = created + timedelta(minutes=rng.uniform(2, 9))
                row.update({"dispatched_at": disp.isoformat(), "eta_minutes": rng.randint(4, 25),
                            "assigned_responder_id": rng.choice(responders) if responders else None})
                stamp("dispatched", disp)
                if status in ("en_route", "arrived") or rng.random() < 0.6:
                    row["accepted_at"] = (disp + timedelta(minutes=rng.uniform(0.3, 5))).isoformat()
            return row, log

        roll = rng.random()
        if roll < 0.84:
            disp = created + timedelta(minutes=min(45, max(0.5, rng.lognormvariate(1.4, 0.6))))
            acc = disp + timedelta(minutes=rng.uniform(0.3, 8))
            span = {"fire": (25, 240), "flood_landslide_calamity": (40, 300)}.get(category, (10, 150))
            res = acc + timedelta(minutes=rng.uniform(*span))
            outcome = wchoice(rng, dict(OUTCOMES))
            accept_review(created + timedelta(minutes=rng.uniform(0.5, 3)))
            row.update({"status": "resolved", "dispatched_at": disp.isoformat(), "accepted_at": acc.isoformat(),
                        "resolved_at": res.isoformat(), "outcome": outcome, "closed_by": admin,
                        "assigned_responder_id": rng.choice(responders) if responders else None,
                        "casualties_injured": rng.choice([0, 0, 0, 1, 2, 3]) if outcome != "false_alarm" else 0,
                        "casualties_fatal": 1 if severity == "critical" and rng.random() < 0.12 else 0,
                        "casualties_transported": rng.choice([1, 2]) if outcome == "transported" else 0})
            stamp("dispatched", disp)
            stamp("resolved", res)
        else:
            rejected = rng.random() < 0.5
            when = created + timedelta(minutes=rng.uniform(2, 30))
            row.update({"status": "cancelled", "review_status": "rejected" if rejected else "accepted",
                        "reviewed_at": when.isoformat(), "reviewed_by": admin, "closed_by": admin})
            if rejected:
                row["rejection_reason"] = rng.choice(REJECT_REASONS)
            stamp("rejected" if rejected else "cancelled", when, row.get("rejection_reason"))
        return row, log

    def seed_incidents(self, n: int, live: int):
        incidents, logs = [], []
        for i in range(n):
            built = self.build_incident(live=i < live)
            if built:
                incidents.append(built[0])
                logs.extend(built[1])
        self.insert("incidents", incidents)
        self.insert("dispatch_log", logs)
        by_status = Counter(r["status"] for r in incidents)
        print(f"  incidents: {len(incidents)}  {dict(by_status)}")
        print(f"  dispatch_log entries: {len(logs)}")

    # ── db helpers ────────────────────────────────────────────────────
    def insert(self, table: str, rows: list[dict], batch: int = 100):
        for i in range(0, len(rows), batch):
            self.db.table(table).insert(rows[i:i + batch]).execute()

    def upsert(self, table: str, rows: list[dict], batch: int = 50):
        for i in range(0, len(rows), batch):
            self.db.table(table).upsert(rows[i:i + batch], on_conflict="id").execute()


def seed_user_ids(db) -> list[str]:
    out, start = [], 0
    while True:
        page = db.table("users").select("id").like("email", f"%@{DOMAIN}").range(start, start + 999).execute().data
        out += [r["id"] for r in page]
        if len(page) < 1000:
            return out
        start += 1000


def clean():
    db = get_supabase()
    ids = seed_user_ids(db)
    if not ids:
        print("Nothing to clean.")
        return
    inc_ids: list[str] = []
    for i in range(0, len(ids), 100):
        inc_ids += [r["id"] for r in db.table("incidents").select("id").in_("reporter_id", ids[i:i + 100]).execute().data]
    for i in range(0, len(inc_ids), 100):
        chunk = inc_ids[i:i + 100]
        db.table("dispatch_log").delete().in_("incident_id", chunk).execute()
        db.table("incidents").delete().in_("id", chunk).execute()
    db.table("access_requests").delete().like("email", f"%@{DOMAIN}").execute()
    gone = 0
    for uid in ids:
        try:
            db.auth.admin.delete_user(uid)
            gone += 1
        except Exception as exc:  # noqa: BLE001
            print(f"  ! could not delete {uid}: {exc}")
    print(f"Removed {len(inc_ids)} incidents and {gone} of {len(ids)} accounts.")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--residents", type=int, default=260)
    ap.add_argument("--incidents", type=int, default=800)
    ap.add_argument("--live", type=int, default=30, help="how many of the incidents are open right now")
    ap.add_argument("--seed", type=int, default=2026, help="random seed, for a repeatable dataset")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--clean", action="store_true", help="remove everything this script created")
    ap.add_argument("--then-seed", action="store_true", help="with --clean: seed again afterwards")
    ap.add_argument("--yes", action="store_true", help="skip the confirmation prompt")
    args = ap.parse_args()

    print(f"Target project: {settings.supabase_url}")
    if args.dry_run:
        print(f"Would create {args.residents} residents, about 60 responders, "
              f"{args.incidents} incidents ({args.live} open now), 6 access requests. Nothing written.")
        return
    if not args.yes and input("Write to this database? [y/N] ").strip().lower() != "y":
        print("Cancelled.")
        return

    if args.clean:
        clean()
        if not args.then_seed:
            return
    db = get_supabase()
    if seed_user_ids(db):
        sys.exit("Demo data is already present. Run with --clean first (or --clean --then-seed).")

    s = Seeder(args.seed)
    s.load_reference()
    print("Seeding…")
    s.seed_residents(args.residents, pending=18)
    s.seed_responders((2, 4), pending=6)
    s.seed_access_requests(6)
    s.seed_incidents(args.incidents, args.live)
    print("Done. Undo with: python scripts/seed_demo_data.py --clean")


if __name__ == "__main__":
    main()
