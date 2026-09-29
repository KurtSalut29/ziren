/**
 * Route metadata — maps dashboard pathnames to display titles and subtitles.
 *
 * Used by DashboardLayout to populate the TopBar title without requiring
 * each page to pass it up through props. Add entries here when new routes
 * are created.
 *
 * Restructured for the original Super Admin feature plan
 * (docs/superpowers/plans/2026-09-09-super-admin-features.md), later
 * repointed to Provincial Admin (one per agency_type) when that role
 * replaced Super Admin entirely. Section labels now match
 * lib/nav/nav-config.ts's groups (Overview / Monitoring / Management /
 * Governance / Communication / Personal), /coverage is retired, and /rubric
 * is renamed to /governance. A couple of entries are role-dependent
 * (Incident Management/Monitoring's title split, Governance's narrower
 * Agency Admin title) — see getRouteMeta's `isProvincialAdmin` param.
 */

export interface RouteMeta {
  title: string;
  subtitle?: string;
  /** Nav-group label — shown as the breadcrumb segment before the title in TopBar */
  section?: string;
}

// `section` is the breadcrumb's OPTIONAL middle segment. It is set only where
// the route genuinely sits under a parent the user navigated through, not for
// every sidebar group — the crumb trail already begins with a fixed "Overview"
// root, so echoing the group label back produced trails that read
// "Overview › Main Navigation › Dashboard", where the middle segment carried
// no information and pushed the part that matters to third place.
//
// Where it IS set, it must match the sidebar group label in
// lib/nav/nav-config.ts, because the crumb is a claim about where the user is.
const ROUTE_META: Record<string, RouteMeta> = {
  '/overview':   { title: 'Dashboard',            subtitle: 'Live operational summary' },
  // /queue survives only as a server-side redirect to /incidents; the entry
  // stays so the crumb is right for the instant before it resolves.
  '/queue':      { title: 'Incidents',            subtitle: 'Open work and full history' },
  '/incidents':  { title: 'Incidents',            subtitle: 'Open work and full history', section: 'Monitoring' },
  '/map':        { title: 'Incident Map',         subtitle: 'Live geospatial view',            section: 'Monitoring' },
  '/assist-requests': { title: 'Assist Requests', subtitle: 'Help between stations', section: 'Monitoring' },
  '/narrative-reports': { title: 'Narrative Reports', subtitle: 'Every report your agency has written, by type of incident', section: 'Monitoring' },

  '/accounts':   { title: 'Accounts',             subtitle: 'Cross-agency user directory',     section: 'Management' },
  '/agencies':   { title: 'Agencies',             subtitle: 'Stations, admins, and personnel', section: 'Management' },
  '/responders': { title: 'Responders',           subtitle: 'Field personnel roster',          section: 'Management' },
  '/verification': { title: 'Verification',       subtitle: 'Account registration review',     section: 'Management' },

  '/governance/incident-configuration':  { title: 'Incident Configuration',  subtitle: 'Categories and statuses (read-only)', section: 'Governance' },
  '/governance/account-policies':        { title: 'Account Policies',        subtitle: 'Verification and suspension defaults', section: 'Governance' },
  '/governance/notification-policies':   { title: 'Notification Policies',   subtitle: 'System-wide notification categories', section: 'Governance' },
  '/governance/configuration-history':   { title: 'Configuration History',   subtitle: 'Every critical config change',        section: 'Governance' },
  '/ai-classification': { title: 'AI & Classification',  subtitle: 'Model monitoring',          section: 'Governance' },
  '/audit-logs':        { title: 'Audit Logs',            subtitle: 'Administrative action trail', section: 'Governance' },
  '/system-status':     { title: 'System Status',         subtitle: 'Service health',            section: 'Governance' },

  '/announcements': { title: 'Announcements',     subtitle: 'System-wide broadcasts',          section: 'Communication' },
  '/reports':       { title: 'Reports & Export',  subtitle: 'Print incident records and narrative reports', section: 'Communication' },

  '/settings':   { title: 'Settings',             subtitle: 'Profile & preferences' },
  '/help':       { title: 'Help',                 subtitle: 'How to use Ziren' },
};

/**
 * Resolve RouteMeta for a given pathname.
 *
 * `isProvincialAdmin` disambiguates the couple of routes whose title
 * genuinely differs by role (Task 6 / Task 13 of the plan above) — every
 * other route's meta is role-independent, so the param defaults to false
 * rather than being required everywhere. `agencyType` (BFP/PNP/MDRRMO) is
 * used only by /incidents' Provincial Admin subtitle, which names the
 * signed-in admin's own agency rather than speaking generically.
 *
 * Handles dynamic segments — e.g. /incidents/[id] → "Incident Detail",
 * /governance/[agency] → "BFP Severity Configuration".
 */
export function getRouteMeta(
  pathname: string,
  isProvincialAdmin = false,
  agencyType: string | null = null,
): RouteMeta {
  if (pathname === '/incidents') {
    // Agency Admin only (they act on these reports). A Provincial Admin has no
    // such page: /incidents sends them to the Dashboard before this is read.
    return isProvincialAdmin
      ? { title: 'Dashboard', subtitle: 'Province-wide overview', section: 'Monitoring' }
      : {
          title: 'Incident Management',
          subtitle: 'Manage and coordinate incidents at your station',
          section: 'Monitoring',
        };
  }

  // Split out of /incidents' Active/History toggle into its own sidebar
  // entry — see app/(dashboard)/incident-history/page.tsx. Renamed "Incident
  // Records" when the page stopped being a monitoring list and became the
  // archive: a table of every incident, each with a citable record number.
  // The URL kept its old name so existing links and bookmarks still work.
  // The title is the same for both roles (both are reading the record), but
  // the subtitle states the SCOPE, same as /incidents' split above — one
  // station vs. every station of one agency_type — so the two roles don't
  // read as showing identical data.
  if (pathname === '/incident-history') {
    return {
      title: 'Incident Records',
      subtitle: isProvincialAdmin
        ? agencyType
          ? `The record of every incident across all ${agencyType} stations`
          : 'The record of every incident across your agency’s stations'
        : 'The record of every incident handled at your station',
      section: 'Monitoring',
    };
  }

  // Same page, same two endpoints, scoped server-side for Agency Admin's
  // Agency Analytics (Agency Admin spec Section 13) — see nav-config.ts's
  // matching label swap for why this isn't a separate route.
  if (pathname === '/analytics') {
    return {
      title: isProvincialAdmin ? 'System Analytics' : 'Agency Analytics',
      subtitle: isProvincialAdmin ? 'Incident, user, and agency trends' : 'Your agency’s incident and responder trends',
      section: 'Monitoring',
    };
  }

  // Agency Admin's Operational Area (Agency Admin spec Section 16) reuses
  // this same page, locked server-side to their own agency's municipality.
  if (pathname === '/geographic') {
    return {
      title: isProvincialAdmin ? 'Geographic Overview' : 'Operational Area',
      subtitle: isProvincialAdmin ? 'Province-wide coverage by area' : 'Where your agency operates',
      section: 'Monitoring',
    };
  }

  // Bare /governance redirects client-side to /governance/severity — this
  // title is visible only for the instant before that redirect resolves.
  if (pathname === '/governance') {
    return { title: 'System Governance', subtitle: 'Redirecting…', section: 'Governance' };
  }

  // /governance/severity is the exact page /rubric used to be — same title
  // logic that page always had (agency picker for Provincial Admin, one
  // agency's rubric for Agency Admin), just re-hosted.
  if (pathname === '/governance/severity') {
    return isProvincialAdmin
      ? { title: 'Severity Configuration', subtitle: 'Choose an agency', section: 'Governance' }
      : { title: 'Severity Configuration', subtitle: 'Your agency’s rubric rules', section: 'Governance' };
  }

  // Exact match
  if (ROUTE_META[pathname]) return ROUTE_META[pathname];

  // /narrative-reports/[id] - the Incident Record Form editor
  if (/^\/narrative-reports\/[^/]+$/.test(pathname)) {
    return { title: 'Narrative Report', subtitle: 'The full Incident Record Form', section: 'Monitoring' };
  }

  // /incidents/[id] — detail drill-down
  if (/^\/incidents\/[^/]+$/.test(pathname)) {
    return { title: 'Incident Detail', subtitle: 'Report · signals · dispatch log', section: 'Monitoring' };
  }

  // /agencies/[stationId] — station detail drill-down
  if (/^\/agencies\/[^/]+$/.test(pathname)) {
    return { title: 'Station Detail', subtitle: 'Info · personnel · activity · coverage', section: 'Management' };
  }

  // /governance/severity/[agency] — the ONLY governance sub-route with a
  // dynamic segment. Matched narrowly (severity/ required) so this can never
  // catch a sibling tab like /governance/account-policies and misread its
  // slug as an agency name.
  const severityAgencyMatch = pathname.match(/^\/governance\/severity\/([^/]+)$/);
  if (severityAgencyMatch) {
    // decodeURIComponent because the segment reaches us percent-encoded and
    // would otherwise render as e.g. "BFP%20Biliran Severity Configuration"
    // in the breadcrumb for any agency whose slug contains a space.
    const agency = decodeURIComponent(severityAgencyMatch[1]);
    return {
      title: `${agency} Severity Configuration`,
      subtitle: 'Severity rule set',
      section: 'Governance',
    };
  }

  // Prefix fallback — /responders/... etc.
  for (const [route, meta] of Object.entries(ROUTE_META)) {
    if (pathname.startsWith(route + '/')) return meta;
  }

  return { title: 'Ziren Dashboard' };
}
