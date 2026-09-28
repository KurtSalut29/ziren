/**
 * Words, colours and icons for cross-agency assist requests, shared by the
 * request dialog, the Assist Requests page, the incident detail view and the
 * alert card, so a status never reads one way in one place and another way
 * in the next.
 *
 * The feature's own identity is the info blue, not brand orange: orange is
 * reserved for the button that does something (see globals.css), and red is
 * reserved for critical severity.
 */

import {
  Ambulance, CheckCircle2, Clock, Flame, LifeBuoy, ShieldAlert, TrafficCone, Users, XCircle,
} from 'lucide-react';
import type { AssistStatus } from '@/lib/api/assist-requests';

export const ASSIST_TINT = 'var(--color-system-info)';
export const ASSIST_TINT_BG = 'var(--color-system-info-bg)';

export const ASSIST_STATUS: Record<AssistStatus, {
  label: string;
  /** From the ASKING station's side. */
  outgoing: string;
  /** From the ASKED station's side. */
  incoming: string;
  icon: typeof Clock;
  fg: string;
  bg: string;
}> = {
  pending: {
    label: 'Waiting for reply',
    outgoing: 'Waiting for them to answer',
    incoming: 'Waiting for your answer',
    icon: Clock,
    fg: 'var(--color-system-warning)',
    bg: 'var(--color-system-warning-bg)',
  },
  acknowledged: {
    label: 'Responding',
    outgoing: 'They are responding',
    incoming: 'You accepted — responding',
    icon: CheckCircle2,
    fg: 'var(--color-system-success)',
    bg: 'var(--color-system-success-bg)',
  },
  declined: {
    label: 'Declined',
    outgoing: 'They can’t assist',
    incoming: 'You declined',
    icon: XCircle,
    fg: 'var(--color-text-secondary)',
    bg: 'var(--color-surface-raised)',
  },
};

/**
 * One-tap needs for the request message. Each adds a plain sentence the
 * other station can read without knowing Ziren, and the free-text box below
 * them is still there for anything specific.
 */
export const ASSIST_NEEDS: { key: string; label: string; sentence: string; icon: typeof Flame }[] = [
  { key: 'personnel', label: 'More personnel', sentence: 'We need additional personnel on scene.', icon: Users },
  { key: 'fire', label: 'Fire truck / suppression', sentence: 'We need a fire truck and fire suppression support.', icon: Flame },
  { key: 'medical', label: 'Ambulance / medical', sentence: 'We need an ambulance and medical responders.', icon: Ambulance },
  { key: 'security', label: 'Police / security', sentence: 'We need police presence for security.', icon: ShieldAlert },
  { key: 'traffic', label: 'Traffic & crowd control', sentence: 'We need traffic and crowd control.', icon: TrafficCone },
  { key: 'rescue', label: 'Search & rescue', sentence: 'We need search and rescue support.', icon: LifeBuoy },
];

/** "3 min ago" / "2 h ago" / "Sep 21" — short enough for a list row. */
export function ago(iso: string | null | undefined, now = Date.now()): string {
  if (!iso) return '';
  const t = new Date(iso).getTime();
  if (Number.isNaN(t)) return '';
  const s = Math.max(0, Math.round((now - t) / 1000));
  if (s < 45) return 'just now';
  const m = Math.round(s / 60);
  if (m < 60) return `${m} min ago`;
  const h = Math.round(m / 60);
  if (h < 24) return `${h} h ago`;
  return new Date(iso).toLocaleDateString('en-PH', { month: 'short', day: 'numeric' });
}

/** "Sep 29, 3:05 PM" in Philippine time. */
export function stamp(iso: string | null | undefined): string {
  if (!iso) return '—';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '—';
  return d.toLocaleString('en-PH', {
    timeZone: 'Asia/Manila', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit',
  });
}
