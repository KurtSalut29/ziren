/**
 * Reports & Export — the two printable documents: the Incident Records
 * Report and the Narrative Reports bundle. Both are built server-side
 * (ziren_backend/app/services/printable_reports.py) and fetched here as a
 * blob, because a plain <a href> can't attach the Authorization header the
 * API requires.
 */

import { ApiError, httpErrorMessage, networkErrorMessage } from './client';

const API_BASE_URL = process.env.NEXT_PUBLIC_API_BASE_URL ?? 'http://localhost:8000';

export type RecordsFormat = 'pdf' | 'xlsx' | 'csv';
export type RecordsStatus = 'open' | 'resolved' | 'cancelled';
export type RecordsSeverity = 'critical' | 'high' | 'medium' | 'low';

export interface RecordsFilter {
  /** Bare YYYY-MM-DD dates, both inclusive. Omitted means all time. */
  startDate?: string;
  endDate?: string;
  status?: RecordsStatus | null;
  severity?: RecordsSeverity | null;
}

export interface ReportFile {
  blob: Blob;
  filename: string;
}

async function fetchFile(path: string, token: string, fallbackName: string): Promise<ReportFile> {
  let response: Response;
  try {
    response = await fetch(`${API_BASE_URL}${path}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
  } catch (cause) {
    throw new ApiError(networkErrorMessage(path, cause), 0);
  }
  if (!response.ok) {
    const body = await response.json().catch(() => null);
    throw new ApiError(httpErrorMessage(response.status, body), response.status);
  }
  const blob = await response.blob();
  const match = (response.headers.get('content-disposition') ?? '').match(/filename="([^"]+)"/);
  return { blob, filename: match ? match[1] : fallbackName };
}

/** The Incident Records Report — PDF to read and print, Excel/CSV to work with. */
export function fetchIncidentRecords(token: string, format: RecordsFormat, f: RecordsFilter): Promise<ReportFile> {
  const params = new URLSearchParams({ format });
  if (f.startDate) params.set('start_date', f.startDate);
  if (f.endDate) params.set('end_date', f.endDate);
  if (f.status) params.set('status', f.status);
  if (f.severity) params.set('severity', f.severity);
  return fetchFile(`/reports/incident_records?${params}`, token, `incident_records.${format}`);
}

/** The chosen narrative reports as one PDF: a cover page, then each Incident Record Form. */
export function fetchNarrativeBundle(token: string, incidentIds: string[]): Promise<ReportFile> {
  const params = new URLSearchParams({ ids: incidentIds.join(',') });
  return fetchFile(`/reports/narrative_reports?${params}`, token, 'narrative_reports.pdf');
}

/** Save a fetched report under its own name. */
export function saveFile({ blob, filename }: ReportFile): void {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  // Revoked on the next tick: some browsers start the download after click()
  // returns, and a URL revoked synchronously can abort it.
  window.setTimeout(() => URL.revokeObjectURL(url), 1000);
}

/**
 * Open the browser's print dialog for a PDF, without leaving the page.
 *
 * The PDF is loaded into a hidden iframe and printed from there. If the
 * browser will not print a PDF frame (some block it), the file opens in a new
 * tab instead, where the viewer's own Print button does the same job.
 */
export function printPdf(blob: Blob): void {
  const url = URL.createObjectURL(blob);
  const frame = document.createElement('iframe');
  frame.style.cssText = 'position:fixed;right:0;bottom:0;width:0;height:0;border:0;visibility:hidden';
  frame.src = url;
  const cleanup = () => window.setTimeout(() => { frame.remove(); URL.revokeObjectURL(url); }, 60_000);
  frame.onload = () => {
    try {
      frame.contentWindow?.focus();
      frame.contentWindow?.print();
    } catch {
      window.open(url, '_blank', 'noopener');
    }
    cleanup();
  };
  document.body.appendChild(frame);
}
