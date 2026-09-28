'use client';

/**
 * AppShell — the application frame, rebuilt on the @efferd/dashboard-3 shell.
 *
 * Replaces the hand-built rounded-frame layout. The reference's structure is
 * SidebarProvider → Sidebar(variant="inset") → SidebarInset → header → scrolling
 * content, and the inset variant is what produces the floating-panel look:
 * the provider paints the ground, the sidebar sits on it as a rail, and the
 * inset is a rounded card with its own border.
 *
 * Everything the old frame did by hand — collapse persistence, the mobile
 * off-canvas drawer, the Escape handler, closing on route change — is handled
 * by the shadcn Sidebar primitive, so those ~60 lines are gone rather than
 * reimplemented alongside it. Collapse state persists in a cookie the provider
 * owns, which is why there is no localStorage effect here any more.
 *
 * `.shadcn-scope` wraps the tree: registry components assume base defaults
 * (a real border colour, a background/foreground ground) that Tailwind v4 does
 * not supply on its own — its default border-color is currentColor, so an
 * unstyled `border` would draw in the text colour. See the note in globals.css
 * for why that is scoped here rather than applied to `*` globally.
 */

import { createContext, useContext } from 'react';
import { SidebarInset, SidebarProvider } from '@/components/efferd/ui/sidebar';
import { TooltipProvider } from '@/components/efferd/ui/tooltip';
import { ZirenSidebar } from './ziren-sidebar';
import { ZirenHeader } from './ziren-header';
import type { NavRole } from '@/lib/nav/nav-config';

/**
 * Who is signed in, for anything rendered INSIDE the shell.
 *
 * The layout already resolves the display name and role label to build the
 * header's account menu. A page wanting to greet the operator by name would
 * otherwise re-fetch /users/me for values that are three components up the
 * tree, so the shell publishes them instead.
 */
const ShellUserContext = createContext<SidebarUser | null>(null);

/** Null outside the shell — every dashboard page is inside it. */
export function useShellUser(): SidebarUser | null {
  return useContext(ShellUserContext);
}

/**
 * Desktop-alert permission, published the same way.
 *
 * useIncidentAlerts already owns this state in the layout, and it must stay
 * the single owner: its requestPermission() does one thing the raw browser API
 * cannot, which is build the AudioContext during the permission click. That
 * click is the user gesture browsers require, and without it the chime never
 * plays no matter what the notification rules say. A settings page calling
 * Notification.requestPermission() directly would grant notifications and
 * silently leave the sound dead.
 */
export interface ShellAlerts {
  permission: NotificationPermission | 'unsupported';
  requestPermission: () => void;
  /** Whether the browser will let this page make a sound right now; null until known. */
  audioReady: boolean | null;
}

const ShellAlertsContext = createContext<ShellAlerts | null>(null);

export function useShellAlerts(): ShellAlerts | null {
  return useContext(ShellAlertsContext);
}

export interface SidebarUser {
  name: string;
  email: string;
  initials: string;
  roleLabel: string;
  /** BFP/PNP/MDRRMO, or null before hydration/for a role with no agency. */
  agencyType: string | null;
  /** The station's own name, e.g. "BFP Naval Station" — an Agency Admin's
   *  one station. Null for a Provincial Admin, who has no single station,
   *  and until the post-mount /users/me fetch resolves. */
  agencyName: string | null;
  isProvincialAdmin: boolean;
  onSignOut: () => void;
}

interface AppShellProps {
  role: NavRole;
  pathname: string;
  user: SidebarUser;
  title: string;
  section?: string;
  /** For the notification bell — null while the session hasn't hydrated yet. */
  token: string | null;
  alerts?: ShellAlerts;
  children: React.ReactNode;
}

export function AppShell({
  role,
  pathname,
  user,
  title,
  section,
  token,
  alerts,
  children,
}: AppShellProps) {


  return (
    <TooltipProvider>
      <ShellUserContext.Provider value={user}>
      <ShellAlertsContext.Provider value={alerts ?? null}>
      <div className="shadcn-scope overflow-hidden">
        <a className="skip-link" href="#main-content">
          Skip to main content
        </a>
        <SidebarProvider className="relative h-svh">
          <ZirenSidebar pathname={pathname} role={role} user={user} />
          {/* The frame interior, not --background. The inset variant's whole
              point is a panel floating on the sidebar's ground, and in light
              both were #FAFAFA — the panel existed but was the same colour as
              what it floated on. --color-frame is the token this codebase
              already keeps for exactly this surface (#FFFFFF / #141414). */}
          <SidebarInset className="overflow-hidden bg-[var(--color-frame)]">
            <ZirenHeader
              section={section}
              title={title}
              token={token}
              user={user}
            />
            {/* tabIndex -1 so the skip link can actually move focus here.
                Without it the browser scrolls to the anchor but focus stays in
                the nav, and the next Tab drops the user back into it.

                `relative` is load-bearing. Every box from here to <html> is
                position: static, so an absolutely positioned descendant would
                resolve its containing block to the initial containing block and
                escape this pane's overflow — Tailwind's .sr-only is exactly
                such a box, and one visually-hidden label deep in a table was
                once enough to give the app a phantom second scrollbar. */}
            <main
              className="scroll-slim relative min-h-0 flex-1 overflow-y-auto outline-none"
              id="main-content"
              tabIndex={-1}
            >
              {children}
            </main>
          </SidebarInset>
        </SidebarProvider>
      </div>
      </ShellAlertsContext.Provider>
      </ShellUserContext.Provider>
    </TooltipProvider>
  );
}
