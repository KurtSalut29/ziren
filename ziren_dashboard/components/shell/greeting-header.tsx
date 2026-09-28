'use client';

/**
 * GreetingHeader — what now opens the Overview.
 *
 * Replaces the status sentence ("9 active incidents across 3 agencies…") and
 * its refresh meta line. Those restated, in prose, numbers the stat cards
 * directly below already carry — the reader met every figure twice before
 * reaching a chart.
 *
 * What a greeting adds that the sentence did not: WHO you are signed in as.
 * A provincial admin sees every station's incidents for their own agency_type;
 * an agency admin sees only their own. Those two people used to read an
 * identical-looking page and would have had to open the account menu to find
 * out which one they are, because the difference changes what every figure
 * on the page means.
 *
 * The identity badge is coloured by the signed-in admin's own agency_type
 * (the same fixed BFP/PNP/MDRRMO hues used everywhere else in the app —
 * see incident-vocabulary.ts) instead of the generic brand tint every role
 * used to share. Provincial Admin additionally gets a "Province-wide" chip:
 * the one piece of scope information that isn't already implied by
 * roleLabel for an Agency Admin, who is always exactly one station.
 *
 * The clock is deliberately coarse. It ticks once a minute, not once a second:
 * nothing here is to-the-second information, and a per-second interval on a
 * page that already polls the queue is wasted work.
 */

import { useEffect, useState } from 'react';
import { useShellUser } from './app-shell';
import { AG_COLOR, AG_BG } from '@/components/incidents/incident-vocabulary';

/**
 * Local hours, not UTC — the operator is in Biliran and the greeting is about
 * their morning. Boundaries chosen to match ordinary Philippine usage rather
 * than an even three-way split: "good evening" starts at 6pm, not 4pm.
 */
function greetingFor(hour: number): string {
  if (hour < 12) return 'Good morning';
  if (hour < 18) return 'Good afternoon';
  return 'Good evening';
}

export function GreetingHeader() {
  const user = useShellUser();

  // null until mounted: the server has no clock in the reader's timezone, and
  // rendering a guessed greeting would swap under them on hydration.
  const [now, setNow] = useState<Date | null>(null);

  useEffect(() => {
    setNow(new Date());
    const id = setInterval(() => setNow(new Date()), 60_000);
    return () => clearInterval(id);
  }, []);

  // The station, not the person. An Agency Admin's console is read as "the
  // desk for this station", and greeting it by the signed-in individual's
  // first name framed the whole page around whoever happened to be logged
  // in that shift rather than the station itself. Falls back to first name
  // for a Provincial Admin, who has no single station to be greeted as.
  const firstName = user?.name?.trim().split(/\s+/)[0] ?? null;
  const greetName = user?.agencyName?.trim() || firstName;

  return (
    <header className="flex flex-wrap items-end justify-between gap-x-6 gap-y-2 px-6 pb-1 pt-5 md:px-7">
      <div className="min-w-0">
        <h1 className="text-page-title truncate text-foreground">
          {now ? greetingFor(now.getHours()) : 'Welcome back'}
          {greetName ? `, ${greetName}` : ''}
        </h1>
        <p className="mt-1 text-meta text-muted-foreground">
          {now
            ? now.toLocaleDateString(undefined, {
                weekday: 'long',
                day: 'numeric',
                month: 'long',
              })
            : ' '}
        </p>
      </div>

      {user?.roleLabel ? (
        <div className="flex shrink-0 flex-wrap items-center gap-2">
          <span
            className="rounded-full px-2.5 py-1 text-meta font-medium"
            style={{
              // Colored by the admin's own agency_type when known — identity,
              // not a status or a severity, but the same fixed hue everyone
              // already reads that agency as everywhere else in the app (see
              // incident-vocabulary.ts). Falls back to the neutral brand tint
              // for a role with no agency_type (there isn't one today, but a
              // resident/responder viewing this component should never crash
              // on an undefined color).
              backgroundColor: user.agencyType ? AG_BG[user.agencyType] : 'var(--color-brand-subtle)',
              color: user.agencyType ? AG_COLOR[user.agencyType] : 'var(--color-brand-active)',
            }}
          >
            Signed in as {user.roleLabel}
          </span>
          {user.isProvincialAdmin && (
            <span
              className="rounded-full px-2.5 py-1 text-meta font-medium"
              style={{
                backgroundColor: 'var(--color-surface-raised)',
                color: 'var(--color-text-secondary)',
              }}
            >
              Province-wide
            </span>
          )}
        </div>
      ) : null}
    </header>
  );
}
