'use client';

import { useEffect, useState } from 'react';
import {
  Accessibility, Contrast, Focus, Link2, MousePointerClick, TextCursorInput,
  Wind,
} from 'lucide-react';
import {
  accessibilityPrefs, type AccessibilityPrefs, type FontScale,
} from '@/lib/prefs/definitions';
import {
  Callout, Card, PanelHeader, Row, RowList, SavedFlash, Segmented, ToggleRow,
} from '@/components/settings/kit';
import { Button } from '@/components/efferd/ui/button';
import { cn } from '@/lib/utils';

const SIZES: { value: FontScale; label: string; sample: string; hint: string }[] = [
  { value: 'small', label: 'Small', sample: '13px', hint: '90%' },
  { value: 'normal', label: 'Default', sample: '15px', hint: '100%' },
  { value: 'large', label: 'Large', sample: '17px', hint: '115%' },
  { value: 'extra-large', label: 'Extra large', sample: '20px', hint: '130%' },
];

export function AccessibilityPanel() {
  const prefs = accessibilityPrefs.use();
  const set = (patch: Partial<AccessibilityPrefs>) => accessibilityPrefs.set(patch);

  // The operating system's own reduced-motion request, which Ziren also honours
  // on its own. Shown so the reader knows why animations may already be off.
  const [osReduced, setOsReduced] = useState(false);
  useEffect(() => {
    const mq = window.matchMedia?.('(prefers-reduced-motion: reduce)');
    if (!mq) return;
    setOsReduced(mq.matches);
    const on = (e: MediaQueryListEvent) => setOsReduced(e.matches);
    mq.addEventListener('change', on);
    return () => mq.removeEventListener('change', on);
  }, []);

  return (
    <div className="flex flex-col gap-6">
      <PanelHeader
        description="Make the console easier to read and operate. Every choice applies on every page, straight away, and stays on this browser."
        icon={Accessibility}
        meta={<SavedFlash signal={JSON.stringify(prefs)} />}
        scope="browser"
        title="Accessibility"
      />

      <Card
        description="Scales the whole console — text, spacing and controls together — so nothing ends up larger than the space made for it."
        title="Interface size"
      >
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4" role="radiogroup" aria-label="Interface size">
          {SIZES.map(s => {
            const active = prefs.fontScale === s.value;
            return (
              <button
                aria-checked={active}
                className={cn(
                  'flex flex-col items-start gap-1 rounded-[12px] border px-4 py-3 text-left transition-colors',
                  active
                    ? 'border-[var(--color-brand)] bg-[var(--color-brand-subtle)]'
                    : 'border-[var(--color-surface-border)] hover:bg-[var(--color-surface-raised)]',
                )}
                key={s.value}
                onClick={() => set({ fontScale: s.value })}
                role="radio"
                type="button"
              >
                {/* The sample is set at its own size in a fixed unit so the card
                    itself does not resize under the reader as they choose. */}
                <span className="font-bold leading-none text-foreground" style={{ fontSize: s.sample }}>Aa</span>
                <span className="text-[13px] font-semibold text-foreground">{s.label}</span>
                <span className="text-[12px] text-muted-foreground">{s.hint}</span>
              </button>
            );
          })}
        </div>
      </Card>

      <Card title="Reading">
        <RowList>
          <ToggleRow
            checked={prefs.highContrast}
            description="Darker secondary text and stronger borders. Severity, status and agency colours are deliberately left as they are — they carry meaning, and changing them would change what an alert says."
            icon={Contrast}
            id="a11y-contrast"
            label="High contrast"
            onChange={v => set({ highContrast: v })}
          />
          <Row
            description="Adds room between letters and words, which helps with dyslexia and low vision."
            icon={TextCursorInput}
            label="Text spacing"
          >
            <Segmented
              ariaLabel="Text spacing"
              onChange={v => set({ textSpacing: v })}
              options={[
                { value: 'normal', label: 'Default' },
                { value: 'relaxed', label: 'Relaxed' },
                { value: 'wide', label: 'Wide' },
              ]}
              value={prefs.textSpacing}
            />
          </Row>
          <ToggleRow
            checked={prefs.underlineLinks}
            description="Underlines every link, so a link is never told apart from text by colour alone."
            icon={Link2}
            id="a11y-underline"
            label="Underline links"
            onChange={v => set({ underlineLinks: v })}
          />
        </RowList>
      </Card>

      <Card title="Moving around">
        <RowList>
          <ToggleRow
            checked={prefs.largerControls}
            description="Makes buttons, fields and selects at least 44 pixels tall — the recommended minimum for a finger or an unsteady hand."
            icon={MousePointerClick}
            id="a11y-larger"
            label="Larger controls"
            onChange={v => set({ largerControls: v })}
          />
          <ToggleRow
            checked={prefs.strongFocus}
            description="A thick outline around whatever the keyboard has selected, so you can always find the cursor on a busy table."
            icon={Focus}
            id="a11y-focus"
            label="Strong keyboard focus"
            onChange={v => set({ strongFocus: v })}
          />
          <ToggleRow
            badge={
              osReduced && (
                <span className="rounded-full bg-[var(--color-surface-raised)] px-2 py-0.5 text-[11px] font-medium text-muted-foreground">
                  Your device already asks for this
                </span>
              )
            }
            checked={prefs.reducedMotion}
            description="Turns off animation and transitions across the console."
            icon={Wind}
            id="a11y-motion"
            label="Reduce motion"
            onChange={v => set({ reducedMotion: v })}
          />
        </RowList>
      </Card>

      <Callout title="Already built in" tone="info">
        Severity is always written as a word as well as a colour, status always carries a
        label, every control can be reached with Tab and shows a focus ring, and there is a
        “Skip to main content” link at the very top of each page. A new-report alert opens
        as an alert dialog, which screen readers announce when it appears.
      </Callout>

      <div className="flex justify-end">
        <Button onClick={() => accessibilityPrefs.reset()} size="sm" variant="ghost">
          Reset accessibility settings
        </Button>
      </div>
    </div>
  );
}
