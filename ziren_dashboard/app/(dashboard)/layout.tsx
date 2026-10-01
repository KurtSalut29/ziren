'use client';

import { useEffect, useRef, useState } from 'react';
import { useRouter, usePathname } from 'next/navigation';
import { useAuth, signOut } from '@/lib/hooks/useAuth';
import { DistressBanner } from '@/components/incidents/distress-banner';
import { apiClient } from '@/lib/api/client';
import { AppShell } from '@/components/shell/app-shell';
import { PrefsApplier } from '@/components/shell/prefs-applier';
import { AlertSoundNudge } from '@/components/ui/incident-alerts';
import { IncidentInterrupt } from '@/components/ui/incident-interrupt';
import { AlertDemoTrigger } from '@/components/ui/alert-demo-trigger';
import { IncidentDetailModal } from '@/components/incidents/incident-detail-modal';
import { useIncidentAlerts } from '@/lib/hooks/useIncidentAlerts';
import { useAssistInbox } from '@/lib/hooks/useAssistInbox';
import { AssistInboxProvider } from '@/components/assist/assist-context';
import { AssistAlerts } from '@/components/assist/assist-alerts';
import { ZirenHelp } from '@/components/help/ziren-help';
import { DemoProvider } from '@/components/help/demo-tour';
import { getRouteMeta } from '@/lib/utils/route-meta';

export default function DashboardLayout({ children }: { children: React.ReactNode }) {
  const { token, email, isAdmin, isAgencyAdmin, isProvincialAdmin, agencyType, hydrated } = useAuth();
  const router   = useRouter();
  const pathname = usePathname();

  const [mounted, setMounted]   = useState(false);
  const [fullName, setFullName] = useState<string | null>(null);
  // The station/agency's own name, e.g. "BFP Naval Station" — an Agency
  // Admin's one station, denormalised onto /users/me from the agencies
  // join (see UserProfile.model_validate in the backend). Null for a
  // Provincial Admin, who has no single station.
  const [agencyName, setAgencyName] = useState<string | null>(null);

  useEffect(() => { setMounted(true); }, []);

  // Still fetched for full_name (not stored at login, unlike role/agency_type)
  // — agency_type itself now comes straight from useAuth()/sessionStorage,
  // available immediately instead of waiting on this post-mount call.
  useEffect(() => {
    if (!token) return;
    apiClient.get<{ full_name: string | null; agency_name?: string | null }>('/users/me', token)
      .then(me => {
        setFullName(me.full_name);
        setAgencyName(me.agency_name ?? null);
      })
      .catch(() => {});
  }, [token]);

  useEffect(() => {
    if (!hydrated) return;
    if (!token || !isAdmin) router.replace('/login');
  }, [hydrated, token, isAdmin, router]);

  // The incident detail route, if that is where we are. Read from the path
  // rather than passed down, because the alert hook lives here in the layout
  // and the page that knows the id is a child of it. Still relevant for a
  // deep link (Incident Records, a bookmarked URL) — the alert flow below no
  // longer navigates here at all, see openAlertId.
  const viewingIncidentId =
    pathname?.match(/^\/incidents\/([^/]+)$/)?.[1] ?? null;

  // The report currently open in the shared detail dialog below, when it was
  // opened FROM an alert (the spotlight card or a tray row) rather than from
  // a page's own table. One dialog, usable from any page, so "Open incident"
  // never has to leave wherever the dispatcher already was.
  //
  // Deliberately NOT acknowledged the moment this is set — see
  // incident-interrupt.tsx's file comment on why a report leaves the tray on
  // CLOSE, not on open.
  const [openAlertId, setOpenAlertId] = useState<string | null>(null);

  // Incident alerting must also be called before any early return, otherwise
  // the hook order changes between the loading and loaded renders and React
  // throws "Rendered more hooks than during the previous render."
  const {
    pending: pendingAlerts,
    acknowledge: acknowledgeAlert,
    acknowledgeAll: acknowledgeAllAlerts,
    simulate: simulateAlerts,
    permission: notifPermission,
    requestPermission: enableNotifications,
    audioReady,
    enableSound,
  } = useIncidentAlerts({
    token,
    isProvincialAdmin,
    // Agency Admins only. The interrupt is for whoever dispatches a crew; a
    // Provincial Admin oversees, dispatches nothing, and reads new reports on the
    // dashboard and in Incident Records. A blocking, looping alarm for reports
    // they cannot act on is noise at best.
    enabled: Boolean(token && isAdmin && hydrated && !isProvincialAdmin),
    // Never interrupt someone with the report already on their screen.
    viewingIncidentId: viewingIncidentId,
  });

  // Cross-agency assist requests: one poll for the whole console, shared by
  // the Assist Requests page, the sidebar badge and the alert card below. A
  // station that is asked for help is alerted on whatever page it is on —
  // the report itself stays with the station that asked. Provincial Admins
  // read the same list for oversight but are never alerted: they answer
  // nothing. Called before the early return for the same hook-order reason
  // as the incident alerts above.
  const assistInbox = useAssistInbox({
    token,
    enabled: Boolean(token && isAdmin && hydrated),
    isProvincialAdmin,
    alerting: Boolean(token && isAgencyAdmin && hydrated),
  });

  // The alert's detail dialog lives here, above every page, so a link inside
  // it (an assist request, "Open Assist Requests") changes the page UNDER a
  // dialog that stays open. Leaving the page closes it — and, as closing it
  // any other way does, acknowledges that report's alert.
  const lastPath = useRef(pathname);
  useEffect(() => {
    if (lastPath.current === pathname) return;
    lastPath.current = pathname;
    if (openAlertId) {
      acknowledgeAlert(openAlertId);
      setOpenAlertId(null);
    }
    // Only a change of page should close it, not the dialog opening.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pathname]);

  if (!mounted || !hydrated) return <_LoadingSkeleton />;
  if (!token || !isAdmin)    return null;

  const displayName = fullName ?? (email ? email.split('@')[0] : '?');
  const initials = displayName
    .split(/[\s._-]+/)
    .filter(Boolean)
    .slice(0, 2)
    .map(p => p[0].toUpperCase())
    .join('') || '?';

  const roleLabel = isProvincialAdmin
    ? `${agencyType} Provincial Admin`
    : agencyType ? `${agencyType} Agency Admin` : 'Agency Admin';

  const routeMeta = getRouteMeta(pathname ?? '', isProvincialAdmin, agencyType);

  // The assist cards shown bottom-right, worked out once: the help mascot
  // shares that corner and steps aside while any of them is up.
  const assistCards = !isAgencyAdmin
    ? []
    : pathname === '/assist-requests'
      // Already on the page: only a request card for something not
      // currently open still needs to break through.
      ? assistInbox.alerts.filter(a => a.kind === 'request')
      : assistInbox.alerts;

  return (
    <DemoProvider>
    <>
      {/* Applies the saved display and accessibility preferences on EVERY page
          — see the note in that component for why it lives here and not in the
          settings hook that used to own it. */}
      <PrefsApplier />

      <AssistInboxProvider value={assistInbox}>
      <AppShell
        badges={{ '/assist-requests': assistInbox.attention }}
        // Settings needs these to tell the operator whether the browser will
        // actually deliver the alerts its toggles promise.
        alerts={{ permission: notifPermission, requestPermission: enableNotifications, audioReady }}
        role={{ isProvincialAdmin, isAgencyAdmin }}
        pathname={pathname ?? ''}
        title={routeMeta.title}
        section={routeMeta.section}
        token={token}
        user={{
          name: displayName,
          // The user card shows the email, per the reference design. Falling
          // back to the role label keeps the second line from collapsing for
          // an account whose email hasn't hydrated yet.
          email: email ?? roleLabel,
          initials,
          roleLabel,
          agencyType,
          agencyName,
          isProvincialAdmin,
          onSignOut: signOut,
        }}
      >
        {/* The alert-sound bar appears ONLY while the browser is really keeping
            this page silent, and clears itself on the first click or key press
            anywhere - see incident-alerts.tsx. Agency Admins only: a Provincial
            Admin gets no alarm. */}
        {!isProvincialAdmin && (
          <AlertSoundNudge audioReady={audioReady} onEnable={enableSound} />
        )}

        {/* A responder in danger outranks whatever page is open, so this
            sits above the routed content on every screen rather than only on
            the queue. It renders nothing at all when there is nothing to
            report, so it costs no space on an ordinary shift. */}
        <DistressBanner token={token} />

        {children}
      </AppShell>
      </AssistInboxProvider>

      {/* Bottom-right, on every page — see assist-alerts.tsx for why it does
          not share the incident alert's corner. Outside the shell frame for
          the same clipping reason as the incident alerts below. */}
      {isAgencyAdmin && (
        <AssistAlerts
          alerts={assistCards}
          onDismiss={assistInbox.dismissAlert}
          onOpen={assistInbox.markRead}
        />
      )}

      {/* "Ask Ziren for help": the mascot's head, bottom-right on every page,
          for both admin roles — each gets its own topics. Outside the shell
          frame for the same clipping reason as the alerts. */}
      <ZirenHelp
        hidden={assistCards.length > 0}
        isProvincialAdmin={Boolean(isProvincialAdmin)}
        pageTitle={routeMeta.title}
        pathname={pathname ?? ''}
      />

      {/* Live incident alerts — driven by the agency's notification_rules.
          Deliberately OUTSIDE the shell frame: these are viewport-fixed
          overlays, and nesting them inside the frame's overflow-hidden clip
          would cut them off at the rounded corner.
          Mounted for BOTH admin types, not just `!isProvincialAdmin` — a
          Provincial Admin still never gets a REAL automatic alarm (the poll
          itself stays off for them: `enabled` above already excludes
          isProvincialAdmin, unchanged), but with the mount gated out
          entirely they could not even use the Demo trigger below to preview
          the feature — clicking it filled `pending` with nothing on screen
          to show it. This only widens who can look, not who gets
          interrupted. */}
      {isAdmin && (
        <>
          <IncidentInterrupt
            onAcknowledge={acknowledgeAlert}
            onAcknowledgeAll={acknowledgeAllAlerts}
            onOpen={setOpenAlertId}
            openIncidentId={openAlertId}
            pending={pendingAlerts}
          />
          {/* One dialog, shared by every page, opened only from an alert.
              Closing it — however the dispatcher got there, an action taken
              or just the X — is what acknowledges the alert and lets the
              next-worst report take the spotlight. See incident-interrupt's
              file comment. otherPendingCount tells it how many OTHER alerts
              are still waiting, so it can confirm before dropping an
              unfinished report back into the queue — see that prop's own
              doc comment. */}
          <IncidentDetailModal
            fromAlert
            incidentId={openAlertId}
            onClose={() => {
              if (openAlertId) acknowledgeAlert(openAlertId);
              setOpenAlertId(null);
            }}
            otherPendingCount={pendingAlerts.filter(a => a.id !== openAlertId).length}
          />
          {/* Renders only when NEXT_PUBLIC_ENABLE_ALERT_DEMO=true — see the component. */}
          <AlertDemoTrigger onSimulate={simulateAlerts} />
        </>
      )}
    </>
    </DemoProvider>
  );
}

// ── Loading skeleton ──────────────────────────────────────────────────────────
// Mirrors the shell's frame geometry so the layout doesn't jump when auth
// resolves — same canvas padding, same radius, same sidebar width.
function _LoadingSkeleton() {
  return (
    <div className="h-screen overflow-hidden bg-[var(--color-canvas)] p-0 md:p-4">
      <div className="flex h-full overflow-hidden rounded-none border border-[var(--color-surface-border)] bg-[var(--color-frame)] md:rounded-[var(--radius-frame)]">
        <aside className="hidden w-[236px] shrink-0 flex-col border-r border-[var(--color-surface-border)] bg-[var(--color-sidebar)] md:flex">
          <div className="flex h-[60px] items-center gap-2.5 px-4">
            <div className="h-8 w-8 animate-pulse rounded-[var(--radius-md)] bg-[var(--color-surface-raised)]" />
            <div className="h-3 w-16 animate-pulse rounded bg-[var(--color-surface-raised)]" />
          </div>
          <div className="px-3 pb-3">
            <div className="h-9 animate-pulse rounded-[var(--radius-control)] bg-[var(--color-surface-raised)]" />
          </div>
          <div className="flex flex-col gap-1 px-3">
            {Array.from({ length: 6 }).map((_, i) => (
              <div
                key={i}
                className="h-[38px] animate-pulse rounded-[var(--radius-md)] bg-[var(--color-surface-raised)]"
              />
            ))}
          </div>
        </aside>
        <div className="flex min-w-0 flex-1 flex-col">
          <div className="h-[56px] shrink-0 border-b border-[var(--color-surface-border)]" />
          <div className="flex flex-col gap-4 p-6">
            {Array.from({ length: 3 }).map((_, i) => (
              <div
                key={i}
                className="h-24 animate-pulse rounded-[var(--radius-card)] bg-[var(--color-surface-raised)]"
              />
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
