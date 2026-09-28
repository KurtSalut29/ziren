"""
seed_demo_data._jitter must never place a point outside Biliran's real
coastline — see that function's own docstring for why a plain circle around
a station used to fail this constantly (a demo "fire" report pinned in open
water, reported 2026-09-26).
"""

import pathlib
import random
import sys

import pytest
from shapely.geometry import Point

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

from seed_demo_data import _BILIRAN_LAND, _jitter  # noqa: E402

# The province's actual seeded stations (migration 002) — real, surveyed,
# on-land points, including ones close enough to the coast (~1.3km) that the
# old ~3km-radius jitter would cross open water on some draws.
REAL_STATIONS = [
    (11.5836, 124.4063),
    (11.5841, 124.4078),
    (11.5830, 124.4055),
    (11.6512, 124.4301),
    (11.6520, 124.4310),
    (11.6505, 124.4295),
]


@pytest.mark.parametrize("lat,lng", REAL_STATIONS)
def test_jitter_never_leaves_the_island(lat, lng):
    rng = random.Random(2026)
    for _ in range(500):
        jlat, jlng = _jitter(lat, lng, rng)
        assert _BILIRAN_LAND.contains(Point(jlng, jlat)), (
            f"jittered ({jlat},{jlng}) from station ({lat},{lng}) landed outside Biliran"
        )


def test_jitter_actually_moves_the_point():
    # Not a no-op that just returns the station's own coordinates every time
    # — the whole point is visible scatter around it.
    rng = random.Random(7)
    lat, lng = REAL_STATIONS[0]
    points = {_jitter(lat, lng, rng) for _ in range(50)}
    assert len(points) > 40


def test_biliran_land_polygon_is_valid():
    assert _BILIRAN_LAND.is_valid
    assert _BILIRAN_LAND.area > 0
