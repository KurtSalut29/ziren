"""
printable_reports — the two documents Reports & Export prints.

Stations asked for Reports & Export to print exactly two things, and to print
them clean and formatted: the incident records for a period, and the narrative
reports (Incident Record Forms). Everything here is built for paper first:

  * Incident Records Report — landscape, a formal letterhead (Republic of the
    Philippines / Province of Biliran / agency / station), the period and
    filters it covers, a summary strip, one row per incident, and a signature
    block. The same rows download as CSV or Excel.
  * Narrative Reports — a cover page listing every report in the bundle,
    then each Incident Record Form on its own pages, exactly as the single
    report prints from its editor (incident_narrative_service.irf_flowables).

Both carry "Page X of Y" and the generation time on every page, because a
printed page that leaves the stack has to say where it came from.

Scoping is never re-implemented here: incident rows come from
dispatch_service.get_incident_history and narrative reports from
incident_narrative_service.load_for_print, the same functions the Incident
Records page and the narrative editor already use, so a printout can never
show a row the screen would not.
"""

from __future__ import annotations

import io
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from fastapi import HTTPException, status

from app.db.supabase_client import get_supabase
from app.services import dispatch_service, incident_narrative_service, report_service

# A fixed +08:00, not ZoneInfo("Asia/Manila"): the Philippines keeps no
# daylight saving, and Windows ships no tz database for ZoneInfo to read.
PH_TZ = incident_narrative_service.PH_TZ
LOGO = Path(__file__).resolve().parent.parent / "assets" / "ziren-logo.png"

#: Ceiling on one printout. A period holding more than this is a data export,
#: not a document — the CSV/Excel download has the same cap for the same
#: reason, and the PDF says so on its face when it is hit.
MAX_RECORDS = 3000
MAX_NARRATIVES = 50

AGENCY_FULL_NAME = {
    "BFP": "Bureau of Fire Protection",
    "PNP": "Philippine National Police",
    "MDRRMO": "Municipal Disaster Risk Reduction and Management Office",
}
CATEGORY_LABEL = {
    "fire": "Fire",
    "medical_trauma": "Medical / trauma",
    "vehicular": "Vehicular accident",
    "flood_landslide_calamity": "Flood / landslide / calamity",
    "domestic_dispute_crime": "Dispute / crime",
    "other": "Other",
}
STATUS_LABEL = {
    "received": "Received", "processing": "Processing", "dispatched": "Dispatched",
    "en_route": "En route", "arrived": "On scene", "resolved": "Resolved", "cancelled": "Cancelled",
}
STATUS_FILTER_LABEL = {None: "All statuses", "open": "Open only", "resolved": "Resolved only", "cancelled": "Cancelled only"}
SEVERITY_ORDER = ("critical", "high", "medium", "low")

# Print palette. Red only ever marks critical severity — same rule as the
# console (ziren_dashboard/app/globals.css).
INK = "#1A1A1A"
MUTED = "#5A5A62"
RULE = "#D6D3CD"
ZEBRA = "#F7F6F3"
BRAND = "#FC5A05"
HEAD = "#23252B"
SEV_HEX = {"critical": "#C8102E", "high": "#C2410C", "medium": "#A16207", "low": "#15803D"}


# =============================================================================
# Shared page furniture
# =============================================================================

def _now_ph() -> datetime:
    return datetime.now(PH_TZ)


def _ph(value: Any) -> datetime | None:
    if not value:
        return None
    try:
        dt = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(PH_TZ)


def _stamp(value: Any) -> str:
    dt = _ph(value)
    return dt.strftime("%b %d, %Y %I:%M %p").replace(" 0", " ") if dt else "—"


def _period_label(start_date: str | None, end_date: str | None) -> str:
    def nice(d: str) -> str:
        try:
            return datetime.fromisoformat(d).strftime("%B %d, %Y").replace(" 0", " ")
        except ValueError:
            return d
    if start_date and end_date:
        return nice(start_date) if start_date == end_date else f"{nice(start_date)} to {nice(end_date)}"
    if start_date:
        return f"From {nice(start_date)}"
    if end_date:
        return f"Up to {nice(end_date)}"
    return "All records to date"


def _issuer(actor: dict) -> dict:
    """Who the document is from: agency name lines for the letterhead."""
    agency_type = actor.get("agency_type")
    station = None
    municipality = None
    if actor.get("role") == "agency_admin" and actor.get("agency_id"):
        row = (
            get_supabase().table("agencies")
            .select("name, agency_type, municipality")
            .eq("id", actor["agency_id"])
            .maybe_single()
            .execute()
        )
        data = row.data if row is not None and isinstance(row.data, dict) else {}
        station = data.get("name")
        municipality = data.get("municipality")
        agency_type = data.get("agency_type") or agency_type
    return {
        "agency_type": agency_type,
        "agency_full": AGENCY_FULL_NAME.get(agency_type or "", agency_type or "Ziren"),
        "station": station or (f"{agency_type} — all stations" if agency_type else "All stations"),
        "municipality": municipality,
    }


def _numbered_canvas(footer_left: str, header_right: str, draw_header_from: int = 2):
    """A canvas class that knows the page count, for "Page X of Y".

    ReportLab draws each page as it goes and only learns the total at the end,
    so every page's state is kept and the footer (and, from page two, a
    running header) is drawn in a final pass.
    """
    from reportlab.lib import colors
    from reportlab.pdfgen import canvas as rl_canvas

    class NumberedCanvas(rl_canvas.Canvas):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, **kwargs)
            self._saved: list[dict] = []

        def showPage(self):  # noqa: N802 — ReportLab's name
            self._saved.append(dict(self.__dict__))
            self._startPage()

        def save(self):
            total = len(self._saved)
            for state in self._saved:
                self.__dict__.update(state)
                self._furniture(total)
                super().showPage()
            super().save()

        def _furniture(self, total: int):
            w, h = self._pagesize
            page = self._pageNumber
            self.saveState()
            self.setStrokeColor(colors.HexColor(RULE))
            self.setLineWidth(0.6)
            self.line(36, 34, w - 36, 34)
            self.setFont("Helvetica", 7.5)
            self.setFillColor(colors.HexColor(MUTED))
            self.drawString(36, 22, footer_left)
            self.drawRightString(w - 36, 22, f"Page {page} of {total}")
            if page >= draw_header_from:
                if LOGO.exists():
                    self.drawImage(str(LOGO), 36, h - 30, width=16, height=16, mask="auto")
                self.setFont("Helvetica-Bold", 8)
                self.setFillColor(colors.HexColor(INK))
                self.drawString(56, h - 25, "ZIREN")
                self.setFont("Helvetica", 8)
                self.setFillColor(colors.HexColor(MUTED))
                self.drawRightString(w - 36, h - 25, header_right)
                self.setStrokeColor(colors.HexColor(BRAND))
                self.setLineWidth(1.2)
                self.line(36, h - 34, w - 36, h - 34)
            self.restoreState()

    return NumberedCanvas


def _styles():
    from reportlab.lib import colors
    from reportlab.lib.enums import TA_CENTER, TA_LEFT
    from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet

    base = getSampleStyleSheet()["Normal"]

    def s(name, **kw):
        return ParagraphStyle(name, parent=base, **kw)

    return {
        "gov": s("Gov", fontName="Helvetica", fontSize=8.5, leading=10.5, alignment=TA_CENTER, textColor=colors.HexColor(MUTED)),
        "agency": s("Agency", fontName="Helvetica-Bold", fontSize=10.5, leading=13, alignment=TA_CENTER, textColor=colors.HexColor(INK)),
        "station": s("Station", fontName="Helvetica", fontSize=9, leading=11, alignment=TA_CENTER, textColor=colors.HexColor(INK)),
        "title": s("DocTitle", fontName="Helvetica-Bold", fontSize=16, leading=20, alignment=TA_CENTER, textColor=colors.HexColor(INK), spaceBefore=2),
        "subtitle": s("DocSub", fontName="Helvetica", fontSize=9, leading=12, alignment=TA_CENTER, textColor=colors.HexColor(MUTED)),
        "cap": s("Cap", fontName="Helvetica-Bold", fontSize=6.8, leading=8.5, textColor=colors.HexColor(MUTED)),
        "val": s("Val", fontName="Helvetica", fontSize=9, leading=11.5, textColor=colors.HexColor(INK)),
        "num": s("Num", fontName="Helvetica-Bold", fontSize=15, leading=18, textColor=colors.HexColor(INK)),
        "th": s("Th", fontName="Helvetica-Bold", fontSize=7.4, leading=9, textColor=colors.white),
        "td": s("Td", fontName="Helvetica", fontSize=7.6, leading=9.4, textColor=colors.HexColor(INK), alignment=TA_LEFT),
        "tdb": s("TdB", fontName="Helvetica-Bold", fontSize=7.6, leading=9.4, textColor=colors.HexColor(INK)),
        "note": s("Note", fontName="Helvetica-Oblique", fontSize=8, leading=10.5, textColor=colors.HexColor(MUTED)),
        "sign": s("Sign", fontName="Helvetica", fontSize=8.5, leading=11, alignment=TA_CENTER, textColor=colors.HexColor(INK)),
        "signb": s("SignB", fontName="Helvetica-Bold", fontSize=9, leading=11, alignment=TA_CENTER, textColor=colors.HexColor(INK)),
    }


def _esc(x: Any) -> str:
    from xml.sax.saxutils import escape
    return escape(str(x)) if x not in (None, "") else ""


def _letterhead(width: float, issuer: dict, st: dict, title: str, subtitle: str) -> list:
    """Logo | government lines | balancing blank, then the document title."""
    from reportlab.lib import colors
    from reportlab.lib.units import inch
    from reportlab.platypus import Image, Paragraph, Spacer, Table, TableStyle

    logo = Image(str(LOGO), width=0.85 * inch, height=0.85 * inch) if LOGO.exists() else ""
    lines = [
        Paragraph("Republic of the Philippines", st["gov"]),
        Paragraph("Province of Biliran", st["gov"]),
        Paragraph(_esc(issuer["agency_full"]).upper(), st["agency"]),
        Paragraph(_esc(issuer["station"]) + (f", {_esc(issuer['municipality'])}" if issuer.get("municipality") else ""), st["station"]),
    ]
    head = Table([[logo, lines, ""]], colWidths=[1.1 * inch, width - 2.2 * inch, 1.1 * inch])
    head.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("ALIGN", (0, 0), (0, 0), "LEFT"),
        ("LEFTPADDING", (0, 0), (-1, -1), 0), ("RIGHTPADDING", (0, 0), (-1, -1), 0),
    ]))
    bar = Table([[""]], colWidths=[width], rowHeights=[2.2])
    bar.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, -1), colors.HexColor(BRAND))]))
    return [
        head, Spacer(1, 6), bar, Spacer(1, 10),
        Paragraph(_esc(title), st["title"]),
        Paragraph(_esc(subtitle), st["subtitle"]),
        Spacer(1, 10),
    ]


def _meta_grid(width: float, cells: list[tuple[str, str]], st: dict):
    from reportlab.lib import colors
    from reportlab.platypus import Paragraph, Table, TableStyle

    row = [[Paragraph(_esc(c).upper(), st["cap"]), Paragraph(_esc(v) or "—", st["val"])] for c, v in cells]
    t = Table([row], colWidths=[width / len(cells)] * len(cells))
    t.setStyle(TableStyle([
        ("BOX", (0, 0), (-1, -1), 0.6, colors.HexColor(RULE)),
        ("INNERGRID", (0, 0), (-1, -1), 0.6, colors.HexColor(RULE)),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 7), ("RIGHTPADDING", (0, 0), (-1, -1), 7),
        ("TOPPADDING", (0, 0), (-1, -1), 5), ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
    ]))
    return t


def _signatures(width: float, st: dict, prepared_by: str, prepared_role: str):
    from reportlab.platypus import Paragraph, Spacer, Table, TableStyle

    def block(caption: str, name: str, role: str):
        return [
            Paragraph(caption, st["cap"]),
            Spacer(1, 26),
            Paragraph("_" * 38, st["sign"]),
            Paragraph(_esc(name) or "&nbsp;", st["signb"]),
            Paragraph(_esc(role), st["sign"]),
        ]

    t = Table([[
        block("PREPARED BY", prepared_by, prepared_role),
        "",
        block("NOTED BY", "", "Station Commander / Head of Office"),
    ]], colWidths=[width * 0.4, width * 0.2, width * 0.4])
    t.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP")]))
    return t


# =============================================================================
# Incident Records Report
# =============================================================================

RECORD_HEADERS = [
    "Record No.", "Date & Time Reported", "Type of Incident", "Severity", "Location",
    "Station", "Responder", "Status", "Mins. to Dispatch", "Resolved At", "Outcome",
]


def _fetch_records(actor: dict, *, start_date, end_date, status_filter, severity) -> tuple[list[dict], dict, bool]:
    """Every incident in the window, through the Incident Records page's own
    query (role scoping, filters, counts). Paged in its native page size."""
    rows: list[dict] = []
    counts: dict = {}
    offset = 0
    page = dispatch_service.HISTORY_PAGE_MAX
    total = 0
    while True:
        result = dispatch_service.get_incident_history(
            actor, days=0, limit=page, offset=offset, status=status_filter, severity=severity,
            date_from=start_date, date_to=end_date,
        )
        batch = result.get("items") or []
        if offset == 0:
            counts = result.get("counts") or {}
            total = result.get("total") or 0
        rows.extend(batch)
        offset += page
        if not batch or offset >= total or len(rows) >= MAX_RECORDS:
            break
    truncated = total > MAX_RECORDS
    return rows[:MAX_RECORDS], {**counts, "total": total}, truncated


def _minutes_between(a: Any, b: Any) -> int | None:
    da, db_ = _ph(a), _ph(b)
    if not da or not db_:
        return None
    return max(0, round((db_ - da).total_seconds() / 60))


def _record_row(r: dict) -> list:
    station = r.get("stations") or {}
    severity = r.get("severity") or r.get("suggested_severity")
    return [
        r.get("record_number") or "—",
        _stamp(r.get("created_at")),
        CATEGORY_LABEL.get(r.get("incident_category") or "other", r.get("incident_category") or "Other"),
        (severity or "untriaged").capitalize(),
        r.get("location_address") or "—",
        station.get("name") or "—",
        (r.get("responder") or {}).get("full_name") or "—",
        STATUS_LABEL.get(r.get("status") or "", r.get("status") or "—"),
        _minutes_between(r.get("created_at"), r.get("dispatched_at")) if r.get("dispatched_at") else "—",
        _stamp(r.get("resolved_at")) if r.get("resolved_at") else "—",
        str(r.get("outcome") or "").replace("_", " ").capitalize() or "—",
    ]


def build_incident_records(
    actor: dict,
    fmt: str,
    *,
    start_date: str | None = None,
    end_date: str | None = None,
    status_filter: str | None = None,
    severity: str | None = None,
) -> tuple[bytes, str, str]:
    if fmt not in report_service.FORMATS:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="format must be csv, xlsx or pdf.")
    if status_filter not in STATUS_FILTER_LABEL:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="status must be open, resolved or cancelled.")
    if severity is not None and severity not in SEVERITY_ORDER:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Unknown severity.")

    records, counts, truncated = _fetch_records(
        actor, start_date=start_date, end_date=end_date, status_filter=status_filter, severity=severity,
    )
    rows = [_record_row(r) for r in records]
    stamp = _now_ph().strftime("%Y-%m-%d")
    filename = f"incident_records_{stamp}.{fmt}"

    if fmt == "csv":
        return report_service._to_csv(RECORD_HEADERS, rows), filename, "text/csv"
    if fmt == "xlsx":
        return (
            report_service._to_xlsx(RECORD_HEADERS, rows),
            filename,
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        )

    pdf = _incident_records_pdf(
        actor, records, counts, truncated,
        start_date=start_date, end_date=end_date, status_filter=status_filter, severity=severity,
    )
    return pdf, filename, "application/pdf"


def _incident_records_pdf(actor, records, counts, truncated, *, start_date, end_date, status_filter, severity) -> bytes:
    from reportlab.lib import colors
    from reportlab.lib.pagesizes import landscape, letter
    from reportlab.lib.units import inch
    from reportlab.platypus import KeepTogether, Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

    st = _styles()
    issuer = _issuer(actor)
    W = 10 * inch
    period = _period_label(start_date, end_date)
    generated = _now_ph().strftime("%B %d, %Y · %I:%M %p PHT").replace(" 0", " ")
    filters = f"{STATUS_FILTER_LABEL[status_filter]} · {severity.capitalize() + ' severity' if severity else 'All severities'}"
    prepared_by = actor.get("full_name") or ""
    role_label = (
        f"{issuer['agency_type']} Provincial Admin" if actor.get("role") == "provincial_admin"
        else f"{issuer['agency_type'] or ''} Agency Admin".strip()
    )

    els: list = _letterhead(W, issuer, st, "INCIDENT RECORDS REPORT", period)
    els.append(_meta_grid(W, [
        ("Reporting period", period),
        ("Filters", filters),
        ("Prepared by", f"{prepared_by} ({role_label})" if prepared_by else role_label),
        ("Date generated", generated),
    ], st))
    els.append(Spacer(1, 8))

    total = counts.get("total") or 0
    resolved = counts.get("resolved") or 0
    cancelled = counts.get("cancelled") or 0
    avg = counts.get("avg_response_minutes")
    summary = [
        ("Total records", total),
        ("Resolved", resolved),
        ("Still open", max(0, total - resolved - cancelled)),
        ("Cancelled", cancelled),
        ("Critical", counts.get("critical") or 0),
        ("Avg. minutes to dispatch", f"{round(avg)}" if isinstance(avg, (int, float)) else "—"),
    ]
    strip = Table(
        [[[Paragraph(_esc(label).upper(), st["cap"]), Paragraph(_esc(value), st["num"])] for label, value in summary]],
        colWidths=[W / len(summary)] * len(summary),
    )
    strip.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor(ZEBRA)),
        ("BOX", (0, 0), (-1, -1), 0.6, colors.HexColor(RULE)),
        ("INNERGRID", (0, 0), (-1, -1), 0.6, colors.HexColor(RULE)),
        ("LEFTPADDING", (0, 0), (-1, -1), 8), ("TOPPADDING", (0, 0), (-1, -1), 6), ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
    ]))
    els.append(strip)
    els.append(Spacer(1, 12))

    # Record numbers never wrap (1.12in holds "BFP-2026-000123" in bold).
    widths = [1.12, 1.05, 1.1, 0.62, 1.58, 1.05, 0.95, 0.72, 0.6, 0.9, 0.81]
    col_w = [w * inch for w in widths]
    head = ["#"] + RECORD_HEADERS[:-1]
    # "#" takes room from Outcome, which is usually blank on open records.
    col_w = [0.3 * inch] + col_w[:-1]
    col_w[-1] += (W - sum(col_w))
    header_row = [Paragraph(_esc(h), st["th"]) for h in head]

    if not records:
        els.append(_meta_grid(W, [("Records", "No incident matches this period and these filters.")], st))
    else:
        data = [header_row]
        for i, r in enumerate(records, start=1):
            row = _record_row(r)[:-1]
            cells = [Paragraph(str(i), st["td"])]
            for j, v in enumerate(row):
                if j == 3 and (r.get("severity") or r.get("suggested_severity") or "").lower() in SEV_HEX:
                    # Severity is coloured AND spelled out — never colour alone.
                    hexcol = SEV_HEX[(r.get("severity") or r.get("suggested_severity")).lower()]
                    cells.append(Paragraph(f'<font color="{hexcol}"><b>{_esc(v)}</b></font>', st["td"]))
                else:
                    cells.append(Paragraph(_esc(v), st["tdb"] if j == 0 else st["td"]))
            data.append(cells)
        table = Table(data, colWidths=col_w, repeatRows=1)
        table.setStyle(TableStyle([
            ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor(HEAD)),
            ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor(ZEBRA)]),
            ("LINEBELOW", (0, 0), (-1, -1), 0.4, colors.HexColor(RULE)),
            ("BOX", (0, 0), (-1, -1), 0.6, colors.HexColor(RULE)),
            ("LEFTPADDING", (0, 0), (-1, -1), 4), ("RIGHTPADDING", (0, 0), (-1, -1), 4),
            ("TOPPADDING", (0, 0), (-1, -1), 4), ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ]))
        els.append(table)

    if truncated:
        els.append(Spacer(1, 6))
        els.append(Paragraph(
            f"Only the newest {MAX_RECORDS:,} of {total:,} records are printed. Narrow the period, "
            "or download the Excel file for the complete list.", st["note"],
        ))

    els.append(Spacer(1, 22))
    els.append(KeepTogether([
        Paragraph(
            "I certify that the records above are a true extract of the incidents received through the "
            "Ziren system for the stated period.", st["note"],
        ),
        Spacer(1, 10),
        _signatures(W, st, prepared_by, role_label),
    ]))

    buf = io.BytesIO()
    doc = SimpleDocTemplate(
        buf, pagesize=landscape(letter),
        leftMargin=0.5 * inch, rightMargin=0.5 * inch, topMargin=0.62 * inch, bottomMargin=0.7 * inch,
        title="Incident Records Report", author="Ziren", subject=period,
    )
    canvas = _numbered_canvas(
        footer_left=f"Ziren Incident Reporting and Dispatch · Incident Records Report · Generated {generated}",
        header_right=f"Incident Records Report · {issuer['station']} · {period}",
    )
    doc.build(els, canvasmaker=canvas)
    return buf.getvalue()


# =============================================================================
# Narrative Reports bundle
# =============================================================================

def build_narrative_bundle(actor: dict, incident_ids: list[str]) -> tuple[bytes, str, str]:
    """A cover page listing the reports, then each Incident Record Form.

    An id the caller may not see raises (403) rather than being skipped: a
    bundle that silently drops a page is a document that lies about its own
    contents. An id with no report written yet is left out and the cover
    says so, because "not written yet" is a fact, not a permission.
    """
    ids = [i for i in dict.fromkeys(x.strip() for x in incident_ids) if i]
    if not ids:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Pick at least one narrative report.")
    if len(ids) > MAX_NARRATIVES:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"At most {MAX_NARRATIVES} narrative reports can be printed at once.",
        )

    db = get_supabase()
    loaded: list[tuple[dict, dict]] = []
    missing = 0
    for incident_id in ids:
        try:
            loaded.append(incident_narrative_service.load_for_print(db, incident_id, actor))
        except HTTPException as exc:
            if exc.status_code == status.HTTP_404_NOT_FOUND:
                missing += 1
                continue
            raise
    if not loaded:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="None of those incidents has a narrative report yet.")

    pdf = _narrative_bundle_pdf(actor, loaded, missing)
    return pdf, f"narrative_reports_{_now_ph().strftime('%Y-%m-%d')}.pdf", "application/pdf"


def _narrative_bundle_pdf(actor: dict, loaded: list[tuple[dict, dict]], missing: int) -> bytes:
    from reportlab.lib import colors
    from reportlab.lib.pagesizes import letter
    from reportlab.lib.units import inch
    from reportlab.platypus import PageBreak, Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

    st = _styles()
    issuer = _issuer(actor)
    W = 7.5 * inch
    generated = _now_ph().strftime("%B %d, %Y · %I:%M %p PHT").replace(" 0", " ")
    finalized = sum(1 for _, r in loaded if r.get("status") == "finalized")

    els: list = _letterhead(
        W, issuer, st, "NARRATIVE REPORTS",
        f"{len(loaded)} Incident Record Form{'s' if len(loaded) != 1 else ''}",
    )
    els.append(_meta_grid(W, [
        ("Reports in this set", f"{len(loaded)} ({finalized} finalized, {len(loaded) - finalized} draft)"),
        ("Prepared by", actor.get("full_name") or ""),
        ("Date generated", generated),
    ], st))
    els.append(Spacer(1, 12))

    head = [Paragraph(h, st["th"]) for h in ("#", "IRF Entry No.", "Record No.", "Type of Incident", "Date of Incident", "Place", "Status")]
    rows = [head]
    for n, (inc, rep) in enumerate(loaded, start=1):
        details = rep.get("details") if isinstance(rep.get("details"), dict) else {}
        kind = details.get("offense") or CATEGORY_LABEL.get(inc.get("incident_category") or "other", "Incident")
        rows.append([
            Paragraph(str(n), st["td"]),
            Paragraph(_esc(rep.get("reference_no")) or "—", st["tdb"]),
            Paragraph(_esc(inc.get("record_number")) or "—", st["td"]),
            Paragraph(_esc(kind), st["td"]),
            Paragraph(_esc(_stamp(rep.get("incident_occurred_at") or inc.get("created_at"))), st["td"]),
            Paragraph(_esc(rep.get("place_of_incident") or inc.get("location_address")) or "—", st["td"]),
            Paragraph("Finalized" if rep.get("status") == "finalized" else "Draft", st["td"]),
        ])
    toc = Table(rows, colWidths=[w * inch for w in (0.3, 1.05, 1.15, 1.35, 1.2, 1.7, 0.75)], repeatRows=1)
    toc.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor(HEAD)),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor(ZEBRA)]),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LINEBELOW", (0, 0), (-1, -1), 0.4, colors.HexColor(RULE)),
        ("BOX", (0, 0), (-1, -1), 0.6, colors.HexColor(RULE)),
        ("LEFTPADDING", (0, 0), (-1, -1), 4), ("RIGHTPADDING", (0, 0), (-1, -1), 4),
        ("TOPPADDING", (0, 0), (-1, -1), 4), ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
    ]))
    els.append(toc)
    if missing:
        plural = missing != 1
        els.append(Spacer(1, 6))
        els.append(Paragraph(
            f"{missing} selected incident{'s' if plural else ''} {'have' if plural else 'has'} no narrative "
            f"report written yet and {'are' if plural else 'is'} not included.",
            st["note"],
        ))

    for inc, rep in loaded:
        els.append(PageBreak())
        els.extend(incident_narrative_service.irf_flowables(inc, rep))

    buf = io.BytesIO()
    doc = SimpleDocTemplate(
        buf, pagesize=letter,
        leftMargin=0.5 * inch, rightMargin=0.5 * inch, topMargin=0.62 * inch, bottomMargin=0.7 * inch,
        title="Narrative Reports", author="Ziren",
    )
    canvas = _numbered_canvas(
        footer_left=f"Ziren Incident Reporting and Dispatch · Narrative Reports · Generated {generated}",
        header_right=f"Narrative Reports · {issuer['station']}",
    )
    doc.build(els, canvasmaker=canvas)
    return buf.getvalue()
