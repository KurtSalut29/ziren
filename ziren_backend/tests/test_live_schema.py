"""
Every select the backend sends, asked of the LIVE schema.

Week 9 plan item 2 (carried since Week 1): "run the history and My Reports
selects against the live schema and assert that each column a screen reads is
present." The unit suites cannot do this: their fake databases return whatever
column a test asks for, so a select naming a column the real table does not
have passes every test and fails only in production (Week 8, Problem 2).

How: the `.table("x").select("...")` calls are read out of app/ with the AST
(a new query is covered the day it is written), and each one is sent to
PostgREST with the PUBLIC anon key and `limit=0`. Nothing is read and nothing
is written. Postgres resolves column names while it parses a query, before it
checks privileges, so the anon key is enough to tell the two answers apart:

    42501 permission denied  -> every column exists (the anon role just may
                                not read the table): pass
    42703 / PGRST200 / PGRST205 / PGRST100 -> a column, relationship or table
                                the query names is not there: FAIL

Runs only when asked (it talks to the live project):

    ZIREN_LIVE_SCHEMA=1 SUPABASE_URL=... SUPABASE_ANON_KEY=... pytest tests/test_live_schema.py
"""

from __future__ import annotations

import ast
import os
import re
from pathlib import Path
from urllib.parse import quote

import pytest

APP = Path(__file__).resolve().parents[1] / "app"

#: Answers that mean the query's names all resolved.
FINE = {"42501"}
#: Answers that mean the query names something the live schema lacks.
BROKEN = {"42703", "PGRST200", "PGRST201", "PGRST205", "PGRST100", "42P01"}


# ── Reading the queries out of the code ──────────────────────────────────────

def _constants(tree: ast.Module, _seen: frozenset[str] = frozenset()) -> dict[str, ast.AST]:
    """Module-level names, including ones imported from another app module
    (`from app.core.resident_trust import REPORTER_EMBED`), so a column list
    shared between services is still read and still checked."""
    out: dict[str, ast.AST] = {}
    for node in tree.body:
        if isinstance(node, ast.ImportFrom) and node.module and node.module.startswith("app."):
            src = APP.parent / (node.module.replace(".", "/") + ".py")
            if src.is_file() and node.module not in _seen:
                other = _constants(ast.parse(src.read_text(encoding="utf-8")), _seen | {node.module})
                # What the imported value is built from (REPORTER_EMBED reads
                # REPORTER_COLUMNS); this module's own names still win below.
                for name, value in other.items():
                    out.setdefault(name, value)
                for alias in node.names:
                    if alias.name in other:
                        out[alias.asname or alias.name] = other[alias.name]
    for node in tree.body:
        if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
            out[node.targets[0].id] = node.value
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name) and node.value is not None:
            out[node.target.id] = node.value
    return out


def _text(node: ast.AST, consts: dict[str, ast.AST], depth: int = 0) -> str | None:
    """A select string the code spells out: a literal, a module constant, or
    a sum of those. None for anything built at run time (an f-string)."""
    if depth > 5:
        return None
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.Name) and node.id in consts:
        return _text(consts[node.id], consts, depth + 1)
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        a, b = _text(node.left, consts, depth + 1), _text(node.right, consts, depth + 1)
        return a + b if a is not None and b is not None else None
    return None


def _table_of(receiver: ast.AST) -> str | None:
    """Walk `db.table("x")....` back to the table name."""
    node = receiver
    while isinstance(node, (ast.Call, ast.Attribute)):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == "table":
            if node.args and isinstance(node.args[0], ast.Constant) and isinstance(node.args[0].value, str):
                return node.args[0].value
            return None
        node = node.func if isinstance(node, ast.Call) else node.value
    return None


def collect_selects() -> list[tuple[str, str, str]]:
    """(where, table, select) for every statically known select in app/."""
    found: dict[tuple[str, str], str] = {}
    for path in sorted(APP.rglob("*.py")):
        tree = ast.parse(path.read_text(encoding="utf-8"))
        consts = _constants(tree)
        for node in ast.walk(tree):
            if not (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
                    and node.func.attr == "select" and node.args):
                continue
            table = _table_of(node.func.value)
            text = _text(node.args[0], consts)
            if table is None or text is None:
                continue
            select = re.sub(r"\s+", "", text)
            where = f"{path.relative_to(APP.parent).as_posix()}:{node.lineno}"
            found.setdefault((table, select), where)
    return sorted((where, table, select) for (table, select), where in found.items())


MOBILE = APP.parents[1] / "ziren_mobile" / "lib"
_DART_SELECT = re.compile(r"\.from\(\s*'(\w+)'\s*\)\s*\.select\(\s*((?:'[^']*'\s*)+)", re.S)


def collect_mobile_selects() -> list[tuple[str, str, str]]:
    """The app's own reads (it queries Supabase directly for a few things -
    sign-in role, barangays, stations, hotlines), spelled as Dart literals."""
    if not MOBILE.is_dir():
        return []
    out = []
    for path in sorted(MOBILE.rglob("*.dart")):
        text = path.read_text(encoding="utf-8")
        for m in _DART_SELECT.finditer(text):
            select = re.sub(r"\s+", "", "".join(re.findall(r"'([^']*)'", m.group(2))))
            line = text[: m.start()].count("\n") + 1
            out.append((f"{path.relative_to(MOBILE.parent).as_posix()}:{line}", m.group(1), select))
    return out


def test_the_queries_are_found():
    """The reader itself: it finds the selects the history and My Reports
    screens depend on, so an empty catalogue cannot pass for a clean one."""
    selects = collect_selects()
    tables = {t for _, t, _ in selects}
    assert len(selects) > 100
    assert {"incidents", "users", "notifications", "audit_logs"} <= tables
    assert any("users(" in s or "reporter" in s for _, t, s in selects if t == "incidents")


# ── Asking the live schema ───────────────────────────────────────────────────

LIVE = os.environ.get("ZIREN_LIVE_SCHEMA") == "1"
URL = os.environ.get("SUPABASE_URL", "").rstrip("/")
ANON = os.environ.get("SUPABASE_ANON_KEY", "")


def _probe(table: str, select: str) -> tuple[int, str | None, str]:
    import httpx

    r = httpx.get(
        f"{URL}/rest/v1/{table}?select={quote(select, safe='(),:*!.')}&limit=0",
        headers={"apikey": ANON, "Authorization": f"Bearer {ANON}"},
        timeout=20,
    )
    try:
        body = r.json()
    except ValueError:
        body = {}
    code = body.get("code") if isinstance(body, dict) else None
    message = body.get("message", "") if isinstance(body, dict) else ""
    return r.status_code, code, message


@pytest.mark.skipif(not (LIVE and URL and ANON), reason="live schema check: set ZIREN_LIVE_SCHEMA=1, SUPABASE_URL, SUPABASE_ANON_KEY")
@pytest.mark.parametrize("where,table,select", collect_selects() + collect_mobile_selects())
def test_every_select_names_what_the_live_schema_has(where, table, select):
    status, code, message = _probe(table, select)
    assert code not in BROKEN, f"{where}: {table}?select={select} -> {status} {code} {message}"
    assert status == 200 or code in FINE, f"{where}: {table} -> {status} {code} {message}"
