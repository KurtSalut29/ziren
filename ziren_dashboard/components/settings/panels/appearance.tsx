'use client';

import { Clock, Monitor, Moon, Palette, Rows3, Sun } from 'lucide-react';
import { useTheme, type ThemePreference } from '@/lib/theme/use-theme';
import { displayPrefs, type DisplayPrefs } from '@/lib/prefs/definitions';
import { formatDate, formatTime, zoneLabel } from '@/lib/format/datetime';
import {
  Callout, Card, ChoiceOption, OptionCards, PanelHeader, Row, RowList,
  SavedFlash, Segmented,
} from '@/components/settings/kit';

const THEMES: ChoiceOption<ThemePreference>[] = [
  { value: 'light',  label: 'Light',  icon: Sun,     hint: 'Best in a bright room or a day shift.' },
  { value: 'dark',   label: 'Dark',   icon: Moon,    hint: 'Easier on the eyes on a night shift.' },
  { value: 'system', label: 'System', icon: Monitor, hint: 'Follow this device, and switch with it at sunset.' },
];

/** A fixed example instant, so the previews below never change under the reader. */
const SAMPLE = new Date('2026-03-08T15:48:00+08:00');

export function AppearancePanel() {
  const { preference, setPreference, mounted } = useTheme();
  const prefs = displayPrefs.use();
  const set = (patch: Partial<DisplayPrefs>) => displayPrefs.set(patch);

  return (
    <div className="flex flex-col gap-6">
      <PanelHeader
        description="How the console looks and how it writes dates and times. Applies to this browser only, so a shared dispatch terminal can keep its own look."
        icon={Palette}
        meta={<SavedFlash signal={`${preference}${JSON.stringify(prefs)}`} />}
        scope="browser"
        title="Appearance"
      />

      <Card
        description="The severity palette is re-tuned between the two themes so every level stays legible in each."
        title="Theme"
      >
        {/* `mounted` gates the selected state: the server cannot know which theme
            the bootstrap script chose, and marking one before the first client
            read would emit markup the client immediately contradicts. */}
        <OptionCards
          ariaLabel="Theme"
          onChange={setPreference}
          options={THEMES}
          value={(mounted ? preference : 'system') as ThemePreference}
        />
      </Card>

      <Card
        description="How much room each row in a table takes. Compact fits about a third more records on the screen."
        title="Table density"
      >
        <div className="flex flex-col items-start gap-4">
          <Segmented
            ariaLabel="Table density"
            onChange={v => set({ density: v })}
            options={[
              { value: 'comfortable', label: 'Comfortable' },
              { value: 'compact', label: 'Compact' },
            ]}
            value={prefs.density}
          />
          <DensityPreview compact={prefs.density === 'compact'} />
        </div>
      </Card>

      <Card
        description="Used wherever the console shows a moment in time: Incident Records, the record panel and its timeline."
        title="Dates and times"
      >
        <RowList>
          <Row
            description={`Example: ${formatDate(SAMPLE, { ...prefs })}`}
            icon={Rows3}
            label="Date style"
          >
            <Segmented
              ariaLabel="Date style"
              onChange={v => set({ dateStyle: v })}
              options={[
                { value: 'iso', label: '2026-03-08', hint: 'Year, month, day — sorts correctly' },
                { value: 'medium', label: '8 Mar 2026' },
                { value: 'dmy', label: '08/03/2026' },
              ]}
              value={prefs.dateStyle}
            />
          </Row>
          <Row description={`Example: ${formatTime(SAMPLE, prefs)}`} icon={Clock} label="Time format">
            <Segmented
              ariaLabel="Time format"
              onChange={v => set({ timeFormat: v })}
              options={[
                { value: '24h', label: '24-hour' },
                { value: '12h', label: '12-hour' },
              ]}
              value={prefs.timeFormat}
            />
          </Row>
          <Row
            description={
              prefs.timeZone === 'browser'
                ? `Following this computer's clock (${zoneLabel(prefs)}). Two offices in different zones would see the same record at different times.`
                : 'Every time is shown in Philippine Time (UTC+8), whatever this computer is set to — so every office reads the same record at the same hour.'
            }
            label="Time zone"
          >
            <Segmented
              ariaLabel="Time zone"
              onChange={v => set({ timeZone: v })}
              options={[
                { value: 'browser', label: 'This device' },
                { value: 'Asia/Manila', label: 'Philippine Time' },
              ]}
              value={prefs.timeZone}
            />
          </Row>
        </RowList>
      </Card>

      <Callout title="What cannot be changed" tone="info">
        Colours that carry meaning — red for critical, the fixed hue of each agency, the
        status colours — are the same for everyone on purpose. A dispatcher moving between
        screens must read an alert the same way on every one, so there is no colour
        customisation here. For stronger contrast, use High contrast under Accessibility.
      </Callout>
    </div>
  );
}

function DensityPreview({ compact }: { compact: boolean }) {
  const rows = [
    ['ZIR-2026-000131', 'Fire', 'Critical'],
    ['ZIR-2026-000130', 'Vehicular', 'High'],
    ['ZIR-2026-000129', 'Medical / trauma', 'Medium'],
  ];
  return (
    <div className="w-full overflow-hidden rounded-[10px] border border-[var(--color-surface-border)]">
      <table className="w-full border-separate border-spacing-0 text-left text-[12.5px]">
        <tbody>
          {rows.map(([id, type, sev]) => (
            <tr key={id}>
              {/* Padding written inline, not through the global compact rule: this
                  preview must show the density being CHOSEN, and that rule
                  reflects the density already saved. */}
              <td
                className="border-b border-[var(--color-surface-border)] px-3 font-mono font-semibold last:border-b-0"
                style={{ paddingBlock: compact ? '0.375rem' : '0.75rem' }}
              >
                {id}
              </td>
              <td
                className="border-b border-[var(--color-surface-border)] px-3 text-[var(--color-text-secondary)]"
                style={{ paddingBlock: compact ? '0.375rem' : '0.75rem' }}
              >
                {type}
              </td>
              <td
                className="border-b border-[var(--color-surface-border)] px-3 text-right font-semibold"
                style={{ paddingBlock: compact ? '0.375rem' : '0.75rem' }}
              >
                {sev}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
