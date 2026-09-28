const API_BASE_URL = process.env.NEXT_PUBLIC_API_BASE_URL ?? 'http://localhost:8000';

export type ReportType =
  | 'monthly_incidents' | 'agency_performance' | 'municipality_incidents'
  | 'barangay_incidents' | 'resident_registrations' | 'responders' | 'incident_resolution'
  | 'severity_breakdown' | 'sla_compliance' | 'flagged_reports';
export type ReportFormat = 'csv' | 'xlsx' | 'pdf';

/** Bare 'YYYY-MM-DD' strings from an <input type="date">. Either or both may be omitted for all-time. */
export interface ReportDateRange {
  startDate?: string;
  endDate?: string;
}

export const REPORT_TYPES: { value: ReportType; label: string; description: string; columns: string[] }[] = [
  {
    value: 'monthly_incidents', label: 'Monthly Incident Report',
    description: 'Incident counts by month, province-wide.',
    columns: ['Month', 'Incident Count'],
  },
  {
    value: 'agency_performance', label: 'Agency Performance Report',
    description: 'Per-agency handled/resolved/cancelled counts, resolution rate, and average response and resolution time.',
    columns: ['Agency', 'Handled', 'Resolved', 'Cancelled', 'Resolution Rate', 'Avg Response', 'Avg Resolution'],
  },
  {
    value: 'municipality_incidents', label: 'Municipality Incident Report',
    description: 'Incident counts by municipality, attributed by the station that handled each one.',
    columns: ['Municipality', 'Incident Count'],
  },
  {
    value: 'barangay_incidents', label: 'Barangay Incident Report',
    description: 'Incident counts by barangay, attributed by the reporting resident’s registered address.',
    columns: ['Barangay', 'Incident Count'],
  },
  {
    value: 'resident_registrations', label: 'Resident Registration Report',
    description: 'Registered resident counts by barangay — useful for spotting low-adoption areas.',
    columns: ['Barangay', 'Registered Residents'],
  },
  {
    value: 'responders', label: 'Responder Report',
    description: 'Every responder account: agency, badge ID, approval status, and current availability.',
    columns: ['Name', 'Badge ID', 'Agency', 'Approval Status', 'Availability'],
  },
  {
    value: 'incident_resolution', label: 'Incident Resolution Report',
    description: 'Every resolved incident with reported/resolved timestamps and total resolution time.',
    columns: ['Incident ID', 'Agency', 'Reported At', 'Resolved At', 'Resolution Time'],
  },
  {
    value: 'severity_breakdown', label: 'Severity Breakdown Report',
    description: 'Incident counts by severity — the distribution the triage rubric actually produced. Reports never dispatched count as Untriaged.',
    columns: ['Severity', 'Incident Count', 'Share of Total'],
  },
  {
    value: 'sla_compliance', label: 'SLA Compliance Report',
    description: 'How often each severity was dispatched within its target response window, per the dispatch-target minutes the live queue itself is measured against.',
    columns: ['Severity', 'Target', 'On Time', 'Late', 'Still Awaiting Dispatch', 'Compliance Rate'],
  },
  {
    value: 'flagged_reports', label: 'Flagged Reports (False SOS & Rejected)',
    description: 'Rejected reports and SOS reports filed by a reporter with a prior false-alarm warning — the accountability side of the queue.',
    columns: ['Incident ID', 'Type', 'Reason', 'Reporter', 'Agency', 'Date'],
  },
];

/**
 * Agency Admin's Agency Reports (Agency Admin spec Section 14) reuse the
 * same endpoints and the same report types below, scoped server-side
 * to the caller's own agency — the three left out (municipality/barangay
 * incidents, resident registrations) have no per-agency cut.
 */
export const AGENCY_ADMIN_REPORT_TYPES: ReportType[] = [
  'monthly_incidents', 'agency_performance', 'responders', 'incident_resolution',
  'severity_breakdown', 'sla_compliance', 'flagged_reports',
];

/**
 * The authenticated fetch every report action shares — a plain <a href>
 * can't attach the Authorization header the API requires. GET /reports/{type}
 * accepts both admin roles; an Agency Admin's request is scoped server-side
 * to their own agency rather than exposing province-wide data.
 */
async function fetchReport(
  token: string, type: ReportType, format: ReportFormat, range?: ReportDateRange,
): Promise<{ blob: Blob; filename: string }> {
  const params = new URLSearchParams({ format });
  if (range?.startDate) params.set('start_date', range.startDate);
  if (range?.endDate) params.set('end_date', range.endDate);
  const response = await fetch(`${API_BASE_URL}/reports/${type}?${params}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!response.ok) {
    const body = await response.json().catch(() => ({ detail: `HTTP ${response.status}` }));
    throw new Error(body.detail ?? `HTTP ${response.status}`);
  }
  const blob = await response.blob();
  const disposition = response.headers.get('content-disposition') ?? '';
  const match = disposition.match(/filename="([^"]+)"/);
  const filename = match ? match[1] : `${type}.${format}`;
  return { blob, filename };
}

/** Downloads happen as fetch + blob — see fetchReport's own doc comment. */
export async function downloadReport(
  token: string, type: ReportType, format: ReportFormat, range?: ReportDateRange,
): Promise<void> {
  const { blob, filename } = await fetchReport(token, type, format, range);
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

/**
 * A look at what a report actually contains before committing to a download.
 *
 * PDF renders in the browser's own viewer (an object URL in an <iframe>) —
 * the one format where layout, not just data, IS the format, so it is the
 * one previewed pixel-for-pixel as the real file. CSV and XLSX are always
 * previewed via the CSV variant regardless of which of the two was picked:
 * both come from the exact same (headers, rows) on the backend (see
 * report_service.py's docstring), so CSV is a faithful stand-in for XLSX's
 * data without pulling in a spreadsheet-parsing library just to render a
 * table the CSV text already gives for free.
 */
export async function previewReport(
  token: string, type: ReportType, format: ReportFormat, range?: ReportDateRange,
): Promise<
  | { kind: 'pdf'; objectUrl: string }
  | { kind: 'table'; headers: string[]; rows: string[][] }
> {
  if (format === 'pdf') {
    const { blob } = await fetchReport(token, type, 'pdf', range);
    return { kind: 'pdf', objectUrl: URL.createObjectURL(blob) };
  }
  const { blob } = await fetchReport(token, type, 'csv', range);
  const text = await blob.text();
  const [headers, ...rows] = parseCsv(text);
  return { kind: 'table', headers: headers ?? [], rows };
}

/**
 * A small RFC 4180 parser, not a split(','). Every report's numbers are
 * rendered through Python's csv.writer (report_service.py's _to_csv), which
 * quotes any field containing a comma, quote or newline — a field like
 * `"Naval, Biliran"` would otherwise split into two columns and misalign
 * every column after it.
 */
function parseCsv(text: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [];
  let field = '';
  let inQuotes = false;

  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (inQuotes) {
      if (c === '"') {
        if (text[i + 1] === '"') { field += '"'; i++; }
        else inQuotes = false;
      } else {
        field += c;
      }
    } else if (c === '"') {
      inQuotes = true;
    } else if (c === ',') {
      row.push(field);
      field = '';
    } else if (c === '\r') {
      // swallowed; \r\n's \n below closes the row
    } else if (c === '\n') {
      row.push(field);
      field = '';
      rows.push(row);
      row = [];
    } else {
      field += c;
    }
  }
  // Final field/row — csv.writer always trails a newline, so this only
  // fires on genuinely malformed input, but a value dropped silently here
  // would still be wrong data shown as though it were complete.
  if (field.length > 0 || row.length > 0) {
    row.push(field);
    rows.push(row);
  }
  return rows.filter(r => !(r.length === 1 && r[0] === ''));
}
