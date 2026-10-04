"""Test double for audit_service.action().

State-changing endpoints write their audit row through the action() context
manager (evaluator finding #6), not record(). Patching action() with this lets
a test assert on the call's keyword arguments exactly as it used to with
record(), and on whatever the block filled in on the entry afterwards.

The context manager returned does NOT swallow exceptions: a bare MagicMock's
__exit__ returns a truthy mock, which would silently eat the HTTPException an
endpoint raises inside the block and turn a 4xx into a 200.
"""

from contextlib import contextmanager
from unittest.mock import MagicMock, patch

from app.services.audit_service import AuditEntry


def patch_audit_action():
    entries: list[AuditEntry] = []

    @contextmanager
    def fake(**kwargs):
        entry = AuditEntry(
            id="audit-1", action=kwargs.get("action"), target_label=kwargs.get("target_label"),
            new=kwargs.get("new"), metadata=kwargs.get("metadata"),
        )
        entries.append(entry)
        yield entry

    mock = MagicMock(side_effect=fake)
    mock.entries = entries
    return patch("app.services.audit_service.action", mock)
