"""Evaluator finding #28: a triage pass says which stage did what.

signals.pipeline_trace lists each stage with its time, and a failure is
logged with the stage it happened in, so a wrong severity can be followed
without tracing client -> router -> service -> model by hand.
See docs/TRIAGE_PIPELINE.md.
"""

from unittest.mock import patch

import pytest

from app.models.incident import IncidentCategory
from app.services import triage_service


@pytest.fixture(scope="module", autouse=True)
def _model():
    if not triage_service.load():
        pytest.skip("triage model not available in this environment")


def test_every_stage_is_recorded_in_order():
    out = triage_service.triage(report_text="May sunog sa bahay, may naipit na tao",
                                incident_category=IncidentCategory.fire)
    stages = [s["stage"] for s in out["signals"]["pipeline_trace"]]
    assert stages == ["normalise", "classify", "signals", "wizard", "verify", "severity", "routing"]
    assert all(s["ms"] >= 0 for s in out["signals"]["pipeline_trace"])


def test_a_report_with_no_text_skips_the_text_stages():
    out = triage_service.triage(report_text="", incident_category=IncidentCategory.fire)
    stages = [s["stage"] for s in out["signals"]["pipeline_trace"]]
    assert stages[0] == "wizard" and "classify" not in stages


def test_a_failure_names_the_stage_it_happened_in():
    with patch.object(triage_service._Z, "severity", side_effect=RuntimeError("bad rule file")), \
         patch.object(triage_service, "log") as log:
        assert triage_service.triage(report_text="sunog") is None
    kwargs = log.error.call_args.kwargs
    assert kwargs["stage"] == "severity"
    assert kwargs["completed"][-1] == "verify"
