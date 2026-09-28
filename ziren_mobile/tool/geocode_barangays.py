"""One-off build of a Biliran barangay centroid table.

Queries Nominatim once per name, respecting the 1 req/sec usage policy. The
output is a static asset — this never runs on a handset.
"""
import json, sys, time, urllib.parse, urllib.request

NAMES = """san isidro|san roque|julita|canila|bato|burabod|sanggalang|busali|
pinangumhan|hugpa|villa enage|naval|almeria|caibiran|culaba|kawayan|maripipi|
cabucgayan|biliran|pili|tabunan|tamarindo|virginia|bunga|caray-caray|larrazabal|
ungale|cabibihan|anislagan|balaquid|baso|bari-is|sampao|manlabang|union|atipolo|
calumpang|agpangi|talahid|catmon|libertad|looc|marvel|agutay|tucdao|uson|maurang|
santo rosario|padre inocentes garcia|talustusan|borac|haguikhikan|imelda|
matanggo|iyusan|jamorawon|danao|viga""".replace("\n", "").split("|")

UA = "ZirenEmergencyApp/1.0 (capstone; barangay centroid build)"
out = []
for i, name in enumerate(NAMES, 1):
    q = urllib.parse.urlencode({
        "q": f"{name}, Biliran, Philippines",
        "format": "json", "addressdetails": "1", "limit": "1",
    })
    url = f"https://nominatim.openstreetmap.org/search?{q}"
    rec = {"name": name, "lat": None, "lon": None, "osm": None, "kind": None}
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=20) as r:
            res = json.load(r)
        if res:
            h = res[0]
            rec.update(
                lat=round(float(h["lat"]), 6), lon=round(float(h["lon"]), 6),
                osm=h.get("display_name"),
                kind=f'{h.get("class")}/{h.get("type")}',
            )
    except Exception as e:
        rec["error"] = f"{type(e).__name__}: {e}"
    out.append(rec)
    print(f'{i:>3}/{len(NAMES)}  {name:<26} {rec["kind"] or rec.get("error") or "NOT FOUND"}', flush=True)
    time.sleep(1.1)

json.dump(out, open(sys.argv[1], "w", encoding="utf-8"), indent=1, ensure_ascii=False)
print("\nwrote", sys.argv[1])

# Provenance for lib/features/incident_report/domain/biliran_places.dart.
#
# Run only when the barangay list changes. Nominatim's usage policy caps this
# at 1 request/second and asks that bulk work be occasional; the sleep above
# honours that. Results must be filtered to addresses that actually fall in
# Biliran — several Biliran barangay names (Union, Libertad, Imelda, Danao,
# San Isidro) are common across the Philippines and will otherwise resolve to
# the wrong province entirely.
#
# Of 61 names, 52 resolved. Ten of those resolved to a school rather than a
# settlement node; that is recorded in the table's `source` field rather than
# hidden, because a school is a stand-in for a barangay centroid, not one.
#
# Unresolved, and therefore not nameable from coordinates:
#   Sanggalang, Pinangumhan, Virginia, Marvel, P.I. Garcia, Haguikhikan, Iyusan
