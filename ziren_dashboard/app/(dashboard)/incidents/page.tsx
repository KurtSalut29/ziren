'use client';

/**
 * Incidents — the live, open queue. Agency Admin only.
 *
 * History used to be a tab on this same page (toggled via ?view=history)
 * rather than its own sidebar entry; it is now /incident-history, and the two
 * still don't share a component: Active polls on a timer, groups by severity
 * band, and filters client-side over the whole open set; History has no poll,
 * is a flat list, and pages server-side over a date window.
 *
 * A Provincial Admin has no queue to work and no Incident Monitoring page, so
 * an old link or bookmark to this address sends them to the Dashboard. Nothing
 * is fetched for them here, and nothing renders until the role is known, so an Agency Admin never sees a flash of a redirect and a
 * Provincial Admin never triggers a queue load they will not use.
 */

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/lib/hooks/useAuth';
import { ActiveIncidentsView } from '@/components/incidents/active-view';

export default function IncidentsPage() {
  const router = useRouter();
  const { hydrated, isProvincialAdmin } = useAuth();

  useEffect(() => {
    if (hydrated && isProvincialAdmin) router.replace('/overview');
  }, [hydrated, isProvincialAdmin, router]);

  if (!hydrated || isProvincialAdmin) return null;
  return <ActiveIncidentsView />;
}
