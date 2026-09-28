"""A small in-memory stand-in for the parts of the Supabase client the services use.

MagicMock chains prove that a call was made; they cannot prove that a QUERY is
right - a wrong column, a missing filter or a swapped id all "pass" against a
mock, which is how the suite has been fooled before. This double actually
evaluates eq / in_ / is_ / gte / lt filters against rows and honours the JSON-path
column syntax (`metadata->>incident_id`), so a test of the proximity service is a
test of what it would return, not of what it asked for.

Only what the services in question use is implemented. Embedded selects
("stations(name)") are not - tests that need one use a MagicMock instead.
"""

from __future__ import annotations

import copy
import uuid
from datetime import datetime, timezone
from typing import Any, Callable


class Result:
    def __init__(self, data: Any = None):
        self.data = data
        self.count = None if data is None else (len(data) if isinstance(data, list) else 1)


def _get(row: dict, col: str) -> Any:
    if "->>" in col:
        base, key = col.split("->>", 1)
        value = row.get(base)
        if not isinstance(value, dict) or value.get(key) is None:
            return None
        return str(value[key])
    return row.get(col)


def _eq(a: Any, b: Any) -> bool:
    if a == b:
        return True
    return a is not None and b is not None and str(a) == str(b)


def _as_time(value: Any):
    if isinstance(value, datetime):
        return value
    if isinstance(value, str):
        try:
            dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
            return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)
        except ValueError:
            return None
    return None


def _cmp(a: Any, b: Any):
    ta, tb = _as_time(a), _as_time(b)
    if ta is not None and tb is not None:
        return ta, tb
    return a, b


class Query:
    def __init__(self, db: "FakeDB", name: str):
        self.db = db
        self.name = name
        self.filters: list[Callable[[dict], bool]] = []
        self._order: tuple[str, bool] | None = None
        self._limit: int | None = None
        self._mode = "select"
        self._payload: Any = None
        self._single: str | None = None

    # -- modes
    def select(self, *_args, **_kwargs) -> "Query":
        self._mode = "select"
        return self

    def insert(self, payload) -> "Query":
        self._mode, self._payload = "insert", payload
        return self

    def update(self, payload) -> "Query":
        self._mode, self._payload = "update", payload
        return self

    def delete(self) -> "Query":
        self._mode = "delete"
        return self

    # -- filters
    def eq(self, col, val) -> "Query":
        self.filters.append(lambda r: _eq(_get(r, col), val))
        return self

    def neq(self, col, val) -> "Query":
        self.filters.append(lambda r: not _eq(_get(r, col), val))
        return self

    def in_(self, col, vals) -> "Query":
        wanted = {str(v) for v in vals}
        self.filters.append(lambda r: _get(r, col) is not None and str(_get(r, col)) in wanted)
        return self

    def is_(self, col, val) -> "Query":
        want_null = str(val).lower() == "null"
        self.filters.append(lambda r: (_get(r, col) is None) == want_null)
        return self

    def gte(self, col, val) -> "Query":
        def f(r):
            a, b = _cmp(_get(r, col), val)
            return a is not None and a >= b
        self.filters.append(f)
        return self

    def lt(self, col, val) -> "Query":
        def f(r):
            a, b = _cmp(_get(r, col), val)
            return a is not None and a < b
        self.filters.append(f)
        return self

    # -- shape
    def order(self, col, desc: bool = False, **_kwargs) -> "Query":
        self._order = (col, bool(desc))
        return self

    def limit(self, n) -> "Query":
        self._limit = n
        return self

    def maybe_single(self) -> "Query":
        self._single = "maybe"
        return self

    def single(self) -> "Query":
        self._single = "single"
        return self

    # -- run
    def _rows(self) -> list[dict]:
        return [r for r in self.db.tables.setdefault(self.name, []) if all(f(r) for f in self.filters)]

    def execute(self) -> Result:
        if self._mode == "insert" and self.name in self.db.fail_on_insert:
            raise RuntimeError(f"forced insert failure on {self.name}")
        if self._mode == "select" and self.name in self.db.fail_on_select:
            raise RuntimeError(f"forced select failure on {self.name}")

        if self._mode == "insert":
            payloads = self._payload if isinstance(self._payload, list) else [self._payload]
            stored = []
            for p in payloads:
                row = copy.deepcopy(p)
                row.setdefault("id", str(uuid.uuid4()))
                row.setdefault("created_at", self.db.clock().isoformat())
                self.db.tables.setdefault(self.name, []).append(row)
                stored.append(copy.deepcopy(row))
            self.db.inserted.setdefault(self.name, []).extend(copy.deepcopy(stored))
            return Result(stored)

        if self._mode == "update":
            rows = self._rows()
            for r in rows:
                r.update(copy.deepcopy(self._payload))
            return Result(copy.deepcopy(rows))

        if self._mode == "delete":
            rows = self._rows()
            table = self.db.tables.setdefault(self.name, [])
            for r in rows:
                table.remove(r)
            return Result(copy.deepcopy(rows))

        rows = [copy.deepcopy(r) for r in self._rows()]
        if self._order:
            col, desc = self._order
            rows.sort(key=lambda r: (_get(r, col) is None, str(_get(r, col))), reverse=desc)
        if self._limit is not None:
            rows = rows[: self._limit]
        if self._single:
            if not rows:
                if self._single == "single":
                    raise RuntimeError("PGRST116: no rows")
                return Result(None)
            return Result(rows[0])
        return Result(rows)


class FakeDB:
    """`db.table(name)` -> Query. `tables` holds the rows; `inserted` logs every insert."""

    def __init__(self, tables: dict[str, list[dict]] | None = None, *, clock=None):
        self.tables: dict[str, list[dict]] = {k: copy.deepcopy(v) for k, v in (tables or {}).items()}
        self.inserted: dict[str, list[dict]] = {}
        self.fail_on_insert: set[str] = set()
        self.fail_on_select: set[str] = set()
        self.clock = clock or (lambda: datetime.now(timezone.utc))

    def table(self, name: str) -> Query:
        return Query(self, name)

    def rows(self, name: str) -> list[dict]:
        return self.tables.get(name, [])
