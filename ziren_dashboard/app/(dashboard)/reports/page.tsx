'use client';

/**
 * Reports & Export — spec Section 16.
 *
 * Every report type is its own card, not one option buried in a dropdown —
 * the dropdown version left six of the seven reports invisible unless
 * someone happened to open it. Generation happens server-side
 * (report_service.py); this page is the picker plus the authenticated-
 * fetch-then-blob download dance GET /reports/{type} needs (see
 * lib/api/reports.ts for why a plain link can't be used here).
 */

import { useMemo, useState } from 'react';
import {
  BarChart3, Building2, CalendarRange, ClipboardCheck, Download, Eye,
  FileDown, Flag, Gauge, Map, MapPin, PieChart, ShieldCheck, Users,
} from 'lucide-react';
import { signOut, useAuth } from '@/lib/hooks/useAuth';
import { ApiError } from '@/lib/api/client';
import {
  AGENCY_ADMIN_REPORT_TYPES, downloadReport, REPORT_TYPES,
  type ReportDateRange, type ReportFormat, type ReportType,
} from '@/lib/api/reports';
import { Alert } from '@/components/ui/alert';
import { Button } from '@/components/efferd/ui/button';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/efferd/ui/select';
import {
  Card, CardContent, CardDescription, CardHeader, CardTitle,
} from '@/components/efferd/ui/card';
import { PeriodPicker } from '@/components/ui/period-picker';
import { phToday, resolvePeriod, type Range } from '@/components/ui/period';
import { ReportPreviewModal } from '@/components/reports/report-preview-modal';

const FORMATS: { value: ReportFormat; label: string }[] = [
  { value: 'csv', label: 'CSV' },
  { value: 'xlsx', label: 'Excel (.xlsx)' },
  { value: 'pdf', label: 'PDF' },
];

/**
 * One glance says what a card is before anyone reads its title, and the
 * colour groups the seven into the three things they actually answer —
 * incident data, agency/crew performance, or resident adoption — without
 * restructuring the grid into literal sections. Colour never stands alone:
 * every card still prints its category as a word, right above the title.
 */
const REPORT_META: Record<ReportType, { icon: typeof BarChart3; color: string; category: string }> = {
  monthly_incidents:      { icon: BarChart3,      color: 'var(--color-system-info, #0ea5e9)',  category: 'Incident' },
  municipality_incidents: { icon: Map,            color: 'var(--color-system-info, #0ea5e9)',  category: 'Incident' },
  barangay_incidents:     { icon: MapPin,         color: 'var(--color-system-info, #0ea5e9)',  category: 'Incident' },
  incident_resolution:    { icon: ClipboardCheck, color: 'var(--color-system-info, #0ea5e9)',  category: 'Incident' },
  severity_breakdown:     { icon: PieChart,       color: 'var(--color-system-info, #0ea5e9)',  category: 'Incident' },
  agency_performance:     { icon: Building2,      color: 'var(--color-brand)',                 category: 'Operational' },
  responders:             { icon: ShieldCheck,    color: 'var(--color-brand)',                 category: 'Operational' },
  sla_compliance:         { icon: Gauge,          color: 'var(--color-brand)',                 category: 'Operational' },
  resident_registrations: { icon: Users,          color: 'var(--color-system-success)',        category: 'Registration' },
  flagged_reports:        { icon: Flag,           color: 'var(--color-system-warning)',         category: 'Accountability' },
};

export default function ReportsPage() {
  const { token, isAgencyAdmin } = useAuth();
  const reportTypes = useMemo(
    () => isAgencyAdmin
      ? REPORT_TYPES.filter(r => (AGENCY_ADMIN_REPORT_TYPES as string[]).includes(r.value))
      : REPORT_TYPES,
    [isAgencyAdmin],
  );
  const [formats, setFormats] = useState<Record<ReportType, ReportFormat>>(
    () => Object.fromEntries(REPORT_TYPES.map(r => [r.value, 'csv'])) as Record<ReportType, ReportFormat>,
  );
  const [generating, setGenerating] = useState<ReportType | null>(null);
  const [error, setError] = useState<string | null>(null);
  // Which card's Preview is open — null closes the dialog. Format rides
  // along so the preview reflects whatever format is currently picked on
  // that card, not whatever it was when the dialog first opened.
  const [previewing, setPreviewing] = useState<ReportType | null>(null);
  // One shared period for every card, not a picker per report — a period
  // like "August 2026" is something a person sets once for the whole session
  // of pulling reports, not a fact that changes report to report. Same
  // segmented pills + Custom dialog as every other date-range filter in the
  // dashboard; /reports only ever understood exact dates, not a rolling
  // "last N days" window, so a chosen preset is resolved to concrete dates
  // right here rather than sent as `days`.
  const [days, setDays] = useState(0);
  const [customRange, setCustomRange] = useState<Range | null>(null);
  const [today] = useState(() => phToday());
  const resolved = resolvePeriod(days, customRange, today);
  const range: ReportDateRange = {
    startDate: resolved?.from,
    endDate: resolved?.to,
  };

  async function generate(type: ReportType) {
    if (!token) return;
    setGenerating(type);
    setError(null);
    try {
      await downloadReport(token, type, formats[type], range);
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) { signOut(); return; }
      setError(e instanceof Error ? e.message : 'Failed to generate report.');
    } finally {
      setGenerating(null);
    }
  }

  return (
    <div className="flex flex-col gap-4 px-6 py-5 md:px-7">
      {error && <Alert variant="error" message={error} />}

      <div className="flex items-start gap-3 rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-raised)] px-4 py-3">
        <span
          className="flex size-7 shrink-0 items-center justify-center rounded-full"
          style={{ backgroundColor: 'var(--color-brand-subtle)', color: 'var(--color-brand)' }}
        >
          <FileDown aria-hidden="true" size={14} />
        </span>
        <p className="text-meta pt-0.5 leading-relaxed text-[var(--color-text-secondary)]">
          <span className="font-semibold text-foreground">Always live. </span>
          Every report below is built from live data at the moment you download it —
          there is no cached or scheduled version, and nothing is emailed.
          {isAgencyAdmin && ' Figures are scoped to your own agency only.'}
        </p>
      </div>

      {/* One period for every card below, not a picker per report — see this
          state's own comment. All time is the default, unchanged from before
          this control existed, so nothing about the page's prior behaviour
          changes until someone actually picks something else. */}
      <div className="flex flex-wrap items-center gap-3 rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] px-4 py-3">
        <span className="flex shrink-0 items-center gap-2 text-[13px] font-semibold text-foreground">
          <CalendarRange aria-hidden="true" size={15} className="text-muted-foreground" />
          Reporting period
        </span>
        {/* Grows to fill the room the label leaves, capped so the pills don't stretch
            absurdly wide on an ultra-wide screen — same idea as Operational Area's
            filter row, just a single field rather than several sharing it. */}
        <div className="min-w-[380px] max-w-[560px] flex-1">
          <PeriodPicker days={days} onDays={setDays} onRange={setCustomRange} range={customRange} size="sm" today={today} />
        </div>
      </div>

      <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-3">
        {reportTypes.map(r => {
          const meta = REPORT_META[r.value];
          const Icon = meta.icon;
          return (
            <Card className="flex flex-col" key={r.value}>
              <CardHeader className="gap-1">
                {/* Icon + category + title as one unit, not title alone.
                    Seven cards read as a list of near-identical sentences at
                    this density ("X Report", "Y Report") — the icon is what
                    a scanning eye locks onto first, and the category word
                    above the title is what lets "these three are about
                    incidents, that one's about residents" register without
                    the page being split into literal sections. */}
                <div className="flex items-center gap-2.5">
                  <span
                    className="flex size-8 shrink-0 items-center justify-center rounded-[var(--radius-md)]"
                    style={{
                      backgroundColor: `color-mix(in srgb, ${meta.color} 14%, transparent)`,
                      color: meta.color,
                    }}
                  >
                    <Icon aria-hidden="true" size={16} strokeWidth={2} />
                  </span>
                  <div className="min-w-0">
                    <span
                      className="block text-[10px] font-bold uppercase tracking-wide"
                      style={{ color: meta.color }}
                    >
                      {meta.category}
                    </span>
                    <CardTitle className="text-[14.5px] leading-tight">{r.label}</CardTitle>
                  </div>
                </div>
                <CardDescription className="leading-relaxed">{r.description}</CardDescription>
              </CardHeader>
              <CardContent className="mt-auto flex flex-col gap-3">
                {/* One line, not a row of wrapping pills. The pills cost
                    two or three lines per card and said nothing a plain
                    "Columns: A · B · C" doesn't say faster — the wrapping
                    was competing with the actions below for the card's
                    height, which is what made three controls in one row
                    feel forced into no room. */}
                <p className="text-[11.5px] leading-relaxed text-muted-foreground">
                  <span className="font-semibold text-[var(--color-text-secondary)]">Columns </span>
                  {r.columns.join(' · ')}
                </p>

                {/* A rule, then the whole action area gets its own block —
                    format above, Preview/Download below as a real
                    two-button row instead of three controls sharing one. */}
                <div className="flex flex-col gap-2 border-t border-[var(--color-surface-border)] pt-3">
                  <div className="flex items-center gap-2">
                    <span className="shrink-0 text-[11.5px] font-semibold text-muted-foreground">
                      Format
                    </span>
                    <Select
                      onValueChange={v => setFormats(f => ({ ...f, [r.value]: v as ReportFormat }))}
                      value={formats[r.value]}
                    >
                      <SelectTrigger className="h-7 flex-1" size="sm"><SelectValue /></SelectTrigger>
                      <SelectContent>
                        {FORMATS.map(f => <SelectItem key={f.value} value={f.value}>{f.label}</SelectItem>)}
                      </SelectContent>
                    </Select>
                  </div>
                  <div className="flex gap-2">
                    <Button
                      className="flex-1"
                      onClick={() => setPreviewing(r.value)}
                      size="sm"
                      variant="outline"
                    >
                      <Eye data-icon="inline-start" />
                      Preview
                    </Button>
                    <Button
                      className="flex-1"
                      disabled={generating === r.value}
                      onClick={() => generate(r.value)}
                      size="sm"
                    >
                      <Download data-icon="inline-start" />
                      {generating === r.value ? 'Generating…' : 'Download'}
                    </Button>
                  </div>
                </div>
              </CardContent>
            </Card>
          );
        })}
      </div>

      {previewing && token && (
        <ReportPreviewModal
          format={formats[previewing]}
          label={reportTypes.find(r => r.value === previewing)?.label ?? 'Report'}
          onClose={() => setPreviewing(null)}
          range={range}
          token={token}
          type={previewing}
        />
      )}
    </div>
  );
}
