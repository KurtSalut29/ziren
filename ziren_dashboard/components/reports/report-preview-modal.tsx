'use client';

/**
 * ReportPreviewModal — what the download will actually contain, before it downloads.
 *
 * PDF renders in the browser's own viewer, pixel-for-pixel the real file — the
 * one format where layout IS part of "the format", not just the data. CSV and
 * XLSX both preview as an HTML table built from the CSV variant regardless of
 * which of the two is selected (see lib/api/reports.ts's previewReport):
 * both formats come from the exact same rows on the backend, so the table is
 * a faithful stand-in for XLSX without a spreadsheet-parsing dependency.
 */

import { useEffect, useState } from 'react';
import { Download, Loader2 } from 'lucide-react';
import {
  downloadReport, previewReport,
  type ReportDateRange, type ReportFormat, type ReportType,
} from '@/lib/api/reports';
import { Button } from '@/components/efferd/ui/button';
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from '@/components/efferd/ui/dialog';
import { Alert } from '@/components/ui/alert';

type PreviewState =
  | { status: 'loading' }
  | { status: 'error'; message: string }
  | { status: 'pdf'; objectUrl: string }
  | { status: 'table'; headers: string[]; rows: string[][] };

export function ReportPreviewModal({
  type,
  format,
  label,
  token,
  range,
  onClose,
}: {
  type: ReportType;
  format: ReportFormat;
  label: string;
  token: string;
  range?: ReportDateRange;
  onClose: () => void;
}) {
  const [state, setState] = useState<PreviewState>({ status: 'loading' });
  const [downloading, setDownloading] = useState(false);
  const [downloadError, setDownloadError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    let objectUrl: string | null = null;
    setState({ status: 'loading' });

    previewReport(token, type, format, range)
      .then(result => {
        if (cancelled) return;
        if (result.kind === 'pdf') {
          objectUrl = result.objectUrl;
          setState({ status: 'pdf', objectUrl: result.objectUrl });
        } else {
          setState({ status: 'table', headers: result.headers, rows: result.rows });
        }
      })
      .catch((e: unknown) => {
        if (cancelled) return;
        setState({
          status: 'error',
          message: e instanceof Error ? e.message : 'Could not load a preview.',
        });
      });

    return () => {
      cancelled = true;
      // The PDF preview's object URL is a real in-memory reference to the
      // blob — without this it leaks for the rest of the tab's life every
      // time someone previews a PDF report and closes the dialog.
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    };
    // range is an object literal from the caller, recreated every render —
    // its two string fields are the only part that should retrigger this
    // effect, not its identity.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [token, type, format, range?.startDate, range?.endDate]);

  async function handleDownload() {
    setDownloading(true);
    setDownloadError(null);
    try {
      await downloadReport(token, type, format, range);
    } catch (e) {
      setDownloadError(e instanceof Error ? e.message : 'Failed to download report.');
    } finally {
      setDownloading(false);
    }
  }

  const canDownload = state.status === 'pdf' || state.status === 'table';
  const periodLabel =
    range?.startDate && range?.endDate ? `${range.startDate} through ${range.endDate}`
    : range?.startDate ? `From ${range.startDate} onward`
    : range?.endDate ? `Through ${range.endDate}`
    : 'all-time';

  return (
    <Dialog onOpenChange={open => { if (!open && !downloading) onClose(); }} open>
      <DialogContent className="flex max-h-[85vh] flex-col gap-0 overflow-hidden p-0 sm:max-w-[900px]">
        <DialogHeader className="shrink-0 border-b border-[var(--color-surface-border)] px-6 py-4 text-left">
          <DialogTitle>{label}</DialogTitle>
          <DialogDescription>
            {format === 'pdf'
              ? `Exactly what the PDF will look like — ${periodLabel}, built from live data.`
              : `Shown as a table for ${periodLabel}. The ${format.toUpperCase()} file downloads with these same rows.`}
          </DialogDescription>
        </DialogHeader>

        <div className="scroll-slim min-h-0 flex-1 overflow-auto">
          {state.status === 'loading' && (
            <div className="flex h-64 items-center justify-center gap-2 text-[13px] text-muted-foreground">
              <Loader2 className="animate-spin" size={16} />
              Building the preview from live data…
            </div>
          )}

          {state.status === 'error' && (
            <div className="p-6">
              <Alert message={state.message} variant="error" />
            </div>
          )}

          {state.status === 'pdf' && (
            <iframe
              className="h-[70vh] w-full"
              src={state.objectUrl}
              title={`${label} preview`}
            />
          )}

          {state.status === 'table' && (
            state.rows.length === 0 ? (
              <p className="p-6 text-[13px] text-muted-foreground">
                Nothing to show yet — the report would download with just the
                column headers below, no rows.
              </p>
            ) : (
              <table className="w-full min-w-max border-collapse text-left text-[13px]">
                <thead>
                  <tr>
                    {state.headers.map((h, i) => (
                      <th
                        className="sticky top-0 z-10 whitespace-nowrap border-b border-[var(--color-surface-border)] bg-[var(--color-surface-card)] px-3 py-2 font-semibold text-muted-foreground"
                        key={i}
                      >
                        {h}
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {state.rows.map((row, ri) => (
                    <tr
                      className="border-b border-[var(--color-surface-border)] last:border-b-0"
                      key={ri}
                    >
                      {row.map((cell, ci) => (
                        <td className="whitespace-nowrap px-3 py-2 text-foreground" key={ci}>
                          {cell}
                        </td>
                      ))}
                    </tr>
                  ))}
                </tbody>
              </table>
            )
          )}
        </div>

        {downloadError && (
          <div className="shrink-0 px-6 pt-3">
            <Alert message={downloadError} variant="error" />
          </div>
        )}

        <DialogFooter className="mb-0 shrink-0 border-t border-[var(--color-surface-border)] px-6 py-3">
          <Button disabled={downloading} onClick={onClose} size="sm" variant="outline">
            Close
          </Button>
          <Button disabled={!canDownload || downloading} onClick={handleDownload} size="sm">
            <Download data-icon="inline-start" />
            {downloading ? 'Downloading…' : `Download ${format.toUpperCase()}`}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
