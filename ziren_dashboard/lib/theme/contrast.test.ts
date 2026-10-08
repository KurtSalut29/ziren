import { readFileSync } from 'node:fs';
import path from 'node:path';
import { describe, expect, it } from 'vitest';

// Week 9 plan item (2026-10-01): "a contrast test that fails when a dashboard
// colour token falls below its WCAG minimum, so a value like #3A3A3A is caught
// by a check instead of by a person."
//
// It reads app/globals.css itself - the values the browser gets - and measures
// every colour this console uses for TEXT against every ground that text sits
// on, in both themes. Its first run (2026-10-08) failed 12 light-mode tokens,
// all four severities among them, while their comments claimed 4.6-5.9:1.

const css = readFileSync(path.resolve(__dirname, '../../app/globals.css'), 'utf-8');

/** The body of the first `{ ... }` block after `start`. */
function block(start: RegExp): string {
  const m = start.exec(css);
  if (!m) throw new Error(`no block for ${start}`);
  let depth = 1;
  let i = m.index + m[0].length;
  const from = i;
  while (depth > 0 && i < css.length) {
    if (css[i] === '{') depth++;
    else if (css[i] === '}') depth--;
    i++;
  }
  return css.slice(from, i - 1);
}

const rgb = (hex: string) => [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16));
const toHex = (c: number[]) => '#' + c.map(v => Math.round(v).toString(16).padStart(2, '0')).join('').toUpperCase();

/** `#RRGGBB` as is; `rgba(r, g, b, a)` (dark mode's tints) laid over `under`. */
function tokens(text: string, under?: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const m of text.matchAll(/(--color-[a-z0-9-]+):\s*(#[0-9A-Fa-f]{6})\s*;/g)) out[m[1]] = m[2];
  const card = out['--color-surface-card'] ?? under;
  for (const m of text.matchAll(/(--color-[a-z0-9-]+):\s*rgba\(\s*(\d+),\s*(\d+),\s*(\d+),\s*([\d.]+)\s*\)\s*;/g)) {
    if (!card) continue;
    const a = Number(m[5]);
    const base = rgb(card);
    out[m[1]] = toHex([m[2], m[3], m[4]].map((v, i) => Number(v) * a + base[i] * (1 - a)));
  }
  return out;
}

const LIGHT = tokens(block(/@theme[^{]*\{/));
// Dark only overrides what changes; anything it leaves alone is the light value.
const DARK = { ...LIGHT, ...tokens(block(/\n\.dark\s*\{/)) };

/** WCAG 2.x relative luminance. */
function luminance(hex: string): number {
  const [r, g, b] = rgb(hex).map(c => {
    const s = c / 255;
    return s <= 0.04045 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

export function contrast(a: string, b: string): number {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
}

/** `color-mix(in srgb, fg p%, bg)` - how the chips tint their own background. */
function mix(fg: string, bg: string, p: number): string {
  const a = rgb(fg);
  const b = rgb(bg);
  return '#' + a.map((v, i) => Math.round(v * p + b[i] * (1 - p)).toString(16).padStart(2, '0')).join('');
}

/** WCAG 1.4.3: body-size text. Every token below is used at 10.5-14px. */
const TEXT_MIN = 4.5;

/** Colours this console draws text in, with the tinted ground each one sits
 *  on in a pill or banner (its `-bg` token), if it has one. */
const TEXT_TOKENS: [string, string | null][] = [
  ['text-primary', null], ['text-secondary', null], ['text-muted', null], ['text-tertiary', null],
  ['severity-critical', 'severity-critical-bg'], ['severity-high', 'severity-high-bg'],
  ['severity-medium', 'severity-medium-bg'], ['severity-low', 'severity-low-bg'],
  ['status-received', 'status-received-bg'], ['status-processing', 'status-processing-bg'],
  ['status-dispatched', 'status-dispatched-bg'], ['status-resolved', 'status-resolved-bg'],
  ['status-cancelled', 'status-cancelled-bg'],
  ['system-success', 'system-success-bg'], ['system-warning', 'system-warning-bg'],
  ['system-error', 'system-error-bg'], ['system-info', 'system-info-bg'],
  ['ai-suggested', 'ai-suggested-bg'],
];

const GROUNDS = ['surface-base', 'surface-card', 'surface-raised'];

for (const [theme, t] of [['light', LIGHT], ['dark', DARK]] as const) {
  describe(`${theme} theme: text colours meet ${TEXT_MIN}:1`, () => {
    for (const [name, own] of TEXT_TOKENS) {
      it(name, () => {
        const fg = t[`--color-${name}`];
        expect(fg, `--color-${name} is not defined`).toBeDefined();
        const grounds: Record<string, string> = Object.fromEntries(GROUNDS.map(g => [g, t[`--color-${g}`]]));
        if (own && t[`--color-${own}`]) grounds[own] = t[`--color-${own}`];
        // SeverityChip and its kin: the colour at 10% over a card.
        grounds['10% chip tint'] = mix(fg, t['--color-surface-card'], 0.1);
        const failing = Object.entries(grounds)
          .map(([g, bg]) => ({ g, ratio: Math.round(contrast(fg, bg) * 100) / 100 }))
          .filter(r => r.ratio < TEXT_MIN);
        expect(failing, `${name} ${fg}`).toEqual([]);
      });
    }
  });
}

describe('the measurement itself', () => {
  it('matches the WCAG reference values', () => {
    expect(contrast('#000000', '#FFFFFF')).toBeCloseTo(21, 5);
    expect(contrast('#FFFFFF', '#FFFFFF')).toBeCloseTo(1, 5);
    // #767676 on white is the well-known 4.54:1 grey.
    expect(contrast('#767676', '#FFFFFF')).toBeCloseTo(4.54, 2);
  });

  it('read the tokens from the stylesheet, not an empty block', () => {
    expect(Object.keys(LIGHT).length).toBeGreaterThan(50);
    expect(LIGHT['--color-surface-card']).not.toBe(DARK['--color-surface-card']);
  });
});
