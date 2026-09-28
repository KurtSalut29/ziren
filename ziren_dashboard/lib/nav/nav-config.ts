/**
 * Sidebar navigation model.
 *
 * Restructured per the original Super Admin feature plan
 * (docs/superpowers/plans/2026-09-09-super-admin-features.md), later
 * repointed to Provincial Admin (one per agency_type) when that role
 * replaced Super Admin entirely. Provincial Admin and Agency Admin see
 * different subsets of the same tree — a Provincial Admin monitors their own
 * agency_type province-wide, an Agency Admin dispatches within their own
 * agency — rather than two separate nav trees, so there is exactly one place
 * role gating is expressed.
 *
 * /coverage is retired (Coverage Areas → Agency Management + Geographic
 * Overview). The former Governance group (System Governance, AI &
 * Classification, Audit Logs, System Status) and System Analytics were
 * removed from Provincial Admin's nav at the user's request — the pages
 * themselves and their backend routes are untouched, only the sidebar
 * entries that reached them are gone, so this is reversible without a
 * backend change if that scope comes back.
 *
 * Role gating is expressed as a `visible` predicate over the flags useAuth
 * already computes. The Sidebar renders whatever this function returns and
 * performs no role checks of its own, so there is exactly one place to audit
 * when permissions change.
 */

/**
 * Icon set — chosen for what each destination actually is, not for a generic
 * category. See the original restyle's note (kept relevant): Radar/Siren/
 * Radio came from the dispatch room itself. New icons follow the same rule:
 * Globe2 for province-wide geography (not a pin, which is reserved for the
 * live map), Building2 for the agency/station hierarchy, Megaphone for
 * outbound broadcast, FileDown for exportable output.
 */
import {
  Building2,
  FileDown,
  Globe2,
  History,
  MapPinned,
  Megaphone,
  NotebookText,
  Radar,
  ScanFace,
  Settings,
  Siren,
  UserCog,
  Users,
} from 'lucide-react';
import type { LucideIcon } from 'lucide-react';

export interface NavRole {
  isProvincialAdmin: boolean;
  isAgencyAdmin: boolean;
}

export interface NavItem {
  href: string;
  /** Either a fixed string, or resolved per-role (e.g. /governance's title differs by role). */
  label: string | ((role: NavRole) => string);
  icon: LucideIcon;
  /** Omit for items every admin can see. */
  visible?: (role: NavRole) => boolean;
  /** Rendered as an indented tree under the parent, no icons. */
  children?: NavItem[];
  /**
   * Treat descendant paths as active too.
   *
   * Deliberately absent on /incidents. The pre-restyle sidebar carried an
   * explicit `href !== '/incidents'` carve-out for exactly this, because
   * /incidents/[id] is reached from the Live Queue at least as often as from
   * the history list — highlighting "Incident History" for someone who drilled
   * in from the queue tells them they are somewhere they aren't. Preserved
   * rather than quietly normalised away.
   */
  matchNested?: boolean;
}

export interface NavGroup {
  /** Uppercase section heading. Not clickable, not focusable. */
  label: string;
  items: NavItem[];
}

/** A resolved NavItem, with `label` always a plain string. */
export type ResolvedNavItem = Omit<NavItem, 'label' | 'children'> & {
  label: string;
  children?: ResolvedNavItem[];
};

export interface ResolvedNavGroup {
  label: string;
  items: ResolvedNavItem[];
}

const NAV: NavGroup[] = [
  {
    label: 'Overview',
    items: [
      { href: '/overview', label: 'Dashboard', icon: Radar },
    ],
  },
  {
    label: 'Monitoring',
    items: [
      // matchNested keeps this lit on /incidents/[id] as well — a dispatcher
      // who drilled into a report from the queue is still looking at this
      // page, not Incident History, even though the URL is now nested one
      // level under it.
      //
      //
      // Agency Admin only. This is the live dispatch queue, and a Provincial
      // Admin dispatches nothing: what they need from it — what is open right
      // now, and where it stands — is Incident Records with its "Open now"
      // status, the Dashboard's live counts, and the map. A page that existed
      // only to be watched, with its auto-refresh removed, was a second copy
      // of those. A Provincial Admin who reaches /incidents by an old link is
      // sent to the Dashboard.
      {
        href: '/incidents',
        label: 'Incident Management',
        icon: Siren,
        matchNested: true,
        visible: r => r.isAgencyAdmin,
      },
      // Its own entry rather than a tab on Incident Monitoring — was merged
      // into one page with an Active/History toggle earlier; split back out
      // to its own sidebar item at the user's request. A separate top-level
      // path (not /incidents/history) on purpose: /incidents already uses
      // matchNested, which would otherwise light up "Incident Monitoring" for
      // this route too since it shares the same prefix.
      // Label is "Incident Records"; the path keeps its old name so existing
      // links and bookmarks still resolve.
      { href: '/incident-history', label: 'Incident Records', icon: History },
      // The filing cabinet for narrative reports - every one an agency has
      // written, organised by kind of incident. Both roles: an Agency Admin
      // writes them, a Provincial Admin reads the ones filed under their agency
      // type. matchNested keeps it lit on /narrative-reports/[id], the editor.
      { href: '/narrative-reports', label: 'Narrative Reports', icon: NotebookText, matchNested: true },
      { href: '/map', label: 'Incident Map', icon: MapPinned },
      {
        // Same page for both roles — Agency Admin's Operational Area (spec
        // Section 16) reuses it locked to their own agency's municipality;
        // see /geographic's router for the server-side enforcement.
        href: '/geographic',
        label: r => (r.isProvincialAdmin ? 'Geographic Overview' : 'Operational Area'),
        icon: Globe2,
      },
    ],
  },
  {
    label: 'Management',
    items: [
      {
        href: '/accounts',
        label: 'Accounts',
        icon: UserCog,
        matchNested: true,
        visible: r => r.isProvincialAdmin,
      },
      {
        href: '/agencies',
        label: 'Agencies',
        icon: Building2,
        matchNested: true,
        visible: r => r.isProvincialAdmin,
      },
      {
        href: '/responders',
        label: 'Responders',
        icon: Users,
        matchNested: true,
        visible: r => r.isAgencyAdmin,
      },
      {
        href: '/verification',
        label: 'Verification',
        icon: ScanFace,
        matchNested: true,
        visible: r => r.isAgencyAdmin || r.isProvincialAdmin,
      },
    ],
  },
  {
    label: 'Communication',
    items: [
      {
        // Publishing is Provincial-Admin-only (enforced server-side and by the
        // page's own UI), but an Agency Admin is a real audience for these —
        // announcements can target "agency_admin" or their specific agency —
        // so unlike every other Communication item, both roles see this one.
        href: '/announcements',
        label: 'Announcements',
        icon: Megaphone,
      },
      {
        // Agency Admin's Agency Reports (spec Section 14) reuse this same
        // page — REPORT_TYPES is filtered client-side to the four types
        // that have a per-agency cut, and every download is scoped
        // server-side to their own agency.
        href: '/reports',
        label: 'Reports & Export',
        icon: FileDown,
      },
    ],
  },
  {
    label: 'Personal',
    items: [
      { href: '/settings', label: 'Settings', icon: Settings },
    ],
  },
];

function resolveLabel(item: NavItem, role: NavRole): string {
  return typeof item.label === 'function' ? item.label(role) : item.label;
}

/** Resolve one item (and its children, if any) for the given role. */
function resolveItem(item: NavItem, role: NavRole): ResolvedNavItem {
  return {
    ...item,
    label: resolveLabel(item, role),
    children: item.children
      ?.filter(c => !c.visible || c.visible(role))
      .map(c => resolveItem(c, role)),
  };
}

/** Resolve the groups visible to the given role, dropping anything empty. */
export function getNavGroups(role: NavRole): ResolvedNavGroup[] {
  return NAV
    .map(group => ({
      ...group,
      items: group.items
        .filter(item => !item.visible || item.visible(role))
        .map(item => resolveItem(item, role)),
    }))
    .filter(group => group.items.length > 0);
}

/** True when `pathname` should light up `item`. */
export function isItemActive(item: ResolvedNavItem, pathname: string): boolean {
  if (item.children?.length) {
    return item.children.some(child => isItemActive(child, pathname));
  }
  if (pathname === item.href) return true;
  return Boolean(item.matchNested && pathname.startsWith(item.href + '/'));
}

/**
 * Whether an expandable item should start open.
 *
 * Looser than isItemActive on purpose. On /incidents/[id] no child is
 * *highlighted* (see matchNested above), but the group must still be *open* —
 * otherwise opening an incident from the queue silently collapses the section
 * the user is standing in, and the sidebar appears to lose its place.
 */
export function isItemExpanded(item: ResolvedNavItem, pathname: string): boolean {
  if (!item.children?.length) return false;
  return item.children.some(
    child => pathname === child.href || pathname.startsWith(child.href + '/'),
  );
}
