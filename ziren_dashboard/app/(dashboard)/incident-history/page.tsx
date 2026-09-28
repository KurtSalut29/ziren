'use client';

/**
 * Incident Records — every report, including resolved and cancelled, as a
 * table of records. (Formerly "Incident History"; the route keeps that name
 * so existing links and bookmarks still work.)
 *
 * Its own sidebar entry rather than a tab on Incident Monitoring — see
 * app/(dashboard)/incidents/page.tsx for the earlier tab-shell version and
 * why it existed. Kept as a thin wrapper around the same IncidentHistoryView
 * used before, on the same /dispatch/history endpoint (paged, server-side
 * filtered, no live poll) — none of that changed, only how a dispatcher
 * reaches it.
 */

import { Suspense } from 'react';
import { useSearchParams } from 'next/navigation';
import { IncidentHistoryView } from '@/components/incidents/history-view';

/**
 * Reads ?status= reactively and hands it down — see IncidentHistoryView for why
 * the address is not read inside the view itself. Keyed on the value, so a link
 * to a different status opens a fresh view rather than a half-updated one.
 */
function RecordsWithLink() {
  const status = useSearchParams().get('status');
  return <IncidentHistoryView initialStatus={status} key={status ?? 'none'} />;
}

export default function IncidentHistoryPage() {
  // useSearchParams needs a Suspense boundary above it or the page cannot be
  // prerendered; there is nothing to show in the fallback, the view has its own skeleton.
  return (
    <Suspense fallback={null}>
      <RecordsWithLink />
    </Suspense>
  );
}
