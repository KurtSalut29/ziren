/**
 * The console's demos: for each page, the parts the mascot points at and what
 * it says about them, for Agency Admins and Provincial Admins.
 *
 * Same rule as help-content.ts: every line names a control that exists, with
 * the label it actually has. A step's `target` is a `data-demo` value on the
 * page (a DemoTarget or a data-demo attribute); when a page changes, change its
 * demo here and its targets there.
 *
 * A demo never presses anything: the tour covers the page, so the buttons it
 * points at cannot be clicked until it ends.
 */

import type { DemoScript, DemoStep } from './demo-types';

// ── Shared steps ────────────────────────────────────────────────────────────

const SHELL_TAIL: DemoStep[] = [
  {
    target: 'header:notifications',
    text: 'The bell holds your notifications. A number means unread ones; open it to read them or press "Mark all read".',
  },
  {
    target: 'header:theme',
    text: 'Light or dark mode, in one click.',
  },
  {
    target: 'header:account',
    text: 'Your account menu: Appearance (Light, Dark or System) and Sign out. The dot on it shows whether the console is connected.',
  },
  {
    pose: 'wink',
    text: 'Press Ctrl + K to search for an incident, a person or a page from anywhere. And whenever you need me, press my head at the bottom right.',
  },
];

const RECORDS_STEPS = (provincial: boolean): DemoStep[] => [
  {
    target: 'records:filters',
    text: provincial
      ? 'Incident Records is every report your agency type has received across Biliran, open or closed. Narrow it here by Period, Status, Severity, Station and Type.'
      : 'Incident Records is every report your station has received, open or closed. Narrow it here by Period, Status, Severity and Type.',
  },
  {
    target: 'records:period',
    text: 'Pick a period with the pills, or press Custom for exact dates.',
  },
  {
    target: 'records:summary',
    text: 'This line always says what the table holds: how many records, and how many are critical, resolved and cancelled.',
  },
  {
    target: 'records:search',
    text: 'Search every column of the records on this page — a barangay, a name, a record number.',
  },
  {
    target: 'records:table',
    text: provincial
      ? 'Click any row to read the full record. The Narrative report column opens the incident record form a station filed.'
      : 'Click any row to read the full record. The Narrative report column lets you write or open the incident record form for a resolved incident.',
  },
];

const ASSIST_STEPS = (provincial: boolean): DemoStep[] =>
  provincial
    ? [
        {
          target: 'assist:how',
          text: 'Assist Requests is help between stations: a station asks another for help, the asked station answers, and you oversee both.',
        },
        {
          target: 'assist:inbox',
          text: 'Every request involving your agency type, newest first: who asked whom, about what, and where it stands.',
        },
        {
          target: 'assist:search',
          text: 'Find one by station, place or record number.',
        },
        {
          target: 'assist:conversation',
          text: 'Pick a request to read the conversation between the two stations. Only the stations reply — you can read everything.',
        },
      ]
    : [
        {
          target: 'assist:how',
          text: 'Assist Requests is help between stations. From any incident, press "Request help" and pick stations anywhere in Biliran. The report stays yours.',
        },
        {
          target: 'assist:tabs',
          text: '"Needs attention" holds requests waiting for your answer and new replies. "Asked of us" are requests sent to you; "We asked" are yours.',
        },
        {
          target: 'assist:search',
          text: 'Find one by station, place or record number.',
        },
        {
          target: 'assist:inbox',
          text: 'A request marked "Needs your answer" is waiting on you — you also hear an alert when one arrives.',
        },
        {
          target: 'assist:conversation',
          text: 'Pick a request to read what happened and where, accept or decline it, and message the other station right here.',
        },
      ];

const NARRATIVE_STEPS = (provincial: boolean): DemoStep[] => [
  {
    target: 'narr:filters',
    text: 'Narrative Reports is the filing cabinet of incident record forms. Filter by when they were last saved and by status, or search them.',
  },
  ...(provincial
    ? []
    : [
        {
          target: 'narr:tabs',
          text: '"Reports" are the forms you have written. "Awaiting a report" lists resolved incidents that still need one — press "Write report" beside one to start.',
        } satisfies DemoStep,
      ]),
  {
    target: 'narr:types',
    text: 'The forms are filed by type of incident. Pick a type to see only those.',
  },
  {
    target: 'narr:list',
    text: provincial
      ? 'Press View to read a form, or download its PDF. The stations write them; you read the ones filed under your agency type.'
      : 'Press Open (or Continue for a draft) to edit a form, or download its PDF.',
  },
];

const MAP_STEPS: DemoStep[] = [
  {
    target: 'map:layers',
    text: 'The Incident Map, live. Choose what it shows: incidents, responders and stations — each with how many are drawn.',
  },
  {
    target: 'map:severity',
    text: 'Show or hide incidents by severity. Each chip says how many it would reveal.',
  },
  {
    target: 'map:agencies',
    text: 'Show the stations and responders of BFP, PNP or MDRRMO.',
  },
  {
    target: 'map:search',
    text: 'Search a place or landmark to fly the map there.',
  },
  {
    target: 'map:canvas',
    text: 'Click a pin to see the incident, and open it in full from there.',
  },
  {
    target: 'map:live',
    pose: 'ok',
    text: 'This badge says the map is live, and when it last refreshed.',
  },
];

const AREA_STEPS = (provincial: boolean): DemoStep[] => [
  {
    target: 'area:where',
    text: provincial
      ? 'Geographic Overview: one municipality at a time — its barangays, and the agencies present there.'
      : 'Operational Area: your municipality — its barangays, and the agencies present there.',
  },
  {
    target: 'area:filters',
    text: provincial
      ? 'Choose the Municipality, narrow to one Barangay, and pick the Period. Every figure below follows these.'
      : 'Narrow to one Barangay and pick the Period. Every figure below follows these.',
  },
  {
    target: 'area:tabs',
    text: provincial
      ? 'Overview, Map, Barangays, Response, Stations & crew, Agencies — and Compare, every municipality side by side.'
      : 'Overview, Map, Barangays, Response, Stations & crew, and Agencies — who else covers this area and how to reach them.',
  },
  {
    target: 'area:panel',
    text: 'The view you picked. Click an incident anywhere here to open it.',
  },
  {
    target: 'area:export',
    pose: 'ok',
    text: 'Export CSV downloads this screen’s figures as a spreadsheet.',
  },
];

const VERIFICATION_STEPS = (provincial: boolean): DemoStep[] => [
  {
    target: 'verify:tabs',
    text: provincial
      ? 'Verification has four jobs: ID review, Resident accounts, Agency Admins (access requests) and Responders (approvals).'
      : 'Two tabs: ID review, and Resident accounts — where verified residents go, and where you warn or suspend an account.',
  },
  {
    target: 'verify:purpose',
    text: 'This strip says what the tab decides, who may decide it, and what the decision changes. A verified mark never blocks anyone from reporting.',
  },
  {
    target: 'verify:stats',
    text: 'Who is waiting, the longest wait, and how many carry proof of residency or are missing evidence.',
  },
  {
    target: 'verify:priority',
    text: '"Needs a look" shows submissions carrying a signal first; "Everyone waiting" shows them all, oldest first.',
  },
  {
    target: 'verify:search',
    text: 'Find a resident in the waiting list.',
  },
  {
    target: 'verify:table',
    text: 'Open a resident to compare their ID with their selfie and with what they typed, then press "Verify resident", or "Does not match".',
  },
  {
    pose: 'thinking',
    text: 'In Resident accounts, a warning notifies the resident, and the third one suspends them. A suspended account cannot send reports until it ends or you lift it.',
  },
];

const REPORTS_STEPS = (provincial: boolean): DemoStep[] => [
  {
    target: 'rep:docs',
    text: 'Reports & Export prints two documents: Incident Records (PDF, Excel, CSV) and Narrative Reports (PDF). Pick one.',
  },
  {
    target: 'rep:options',
    text: provincial
      ? 'Choose what it covers — Period, Status and Severity — for every station of your agency in Biliran.'
      : 'Choose what it covers — Period, Status and Severity — for your station’s incidents.',
  },
  {
    target: 'rep:preview',
    text: 'The preview is the real document, rebuilt as you change anything. Each record includes the resident’s own report.',
  },
  {
    target: 'rep:actions',
    pose: 'ok',
    text: 'Print report, Download PDF, or export the same rows to Excel or CSV.',
  },
];

const SETTINGS_STEPS: DemoStep[] = [
  {
    target: 'set:search',
    text: 'Settings. Search for a setting by name — "password", "sound", "hotline" — to jump straight to it.',
  },
  {
    target: 'set:tabs',
    text: 'Your profile and security, preferences like appearance, notifications and the map, your agency’s information and alert rules, and support.',
  },
  {
    target: 'set:panel',
    text: 'The section you picked. Changes are kept until you save them.',
  },
  {
    target: 'set:saved',
    pose: 'ok',
    text: 'This corner says whether anything is unsaved — Save appears right here when it is.',
  },
];

// ── Agency Admin ────────────────────────────────────────────────────────────

const AGENCY: DemoScript[] = [
  {
    id: 'agency-dashboard',
    roles: 'agency',
    href: '/overview',
    title: 'Dashboard',
    summary: 'Your station at a glance, and how to get around.',
    steps: [
      {
        pose: 'excited',
        text: 'Hi! I’m Ziren. Let me show you around the console, starting with your Dashboard.',
      },
      {
        target: 'nav:/overview',
        text: 'Everything is in the sidebar, grouped as Overview, Monitoring, Management, Communication and Personal. A number beside an entry means something there is waiting for you.',
      },
      {
        target: 'overview:live',
        text: 'The live numbers: incidents in the last 14 days, what is active now, how many are critical, and how many still await triage.',
      },
      {
        target: 'overview:roster',
        text: 'Your agency’s roster: all your reports, your responders, who is on duty now, and who is awaiting your approval.',
      },
      {
        target: 'overview:volume',
        text: '"Reports received per day" — and beside it, "By agency".',
      },
      {
        target: 'overview:latency',
        text: '"Time to dispatch" shows how long reports waited for a crew.',
      },
      {
        target: 'overview:list',
        text: '"Needs attention": un-dispatched first, then by severity, then longest waiting. "Live queue" takes you to Incident Management.',
      },
      ...SHELL_TAIL,
    ],
  },
  {
    id: 'agency-queue',
    roles: 'agency',
    href: '/incidents',
    title: 'Incident Management',
    summary: 'The live queue: review, accept, dispatch, resolve.',
    dialog: 'incident',
    steps: [
      {
        pose: 'running',
        text: 'This is the live queue — where every report to your station is reviewed and handled. When a new one arrives, an alarm sounds and it opens over whatever you are doing.',
      },
      {
        target: 'queue:filters',
        text: 'Filter the queue by text, Agency and Status, and choose its Order — the working order, or newest first. The count on the right says how many are shown.',
      },
      {
        target: 'queue:stats',
        text: 'Awaiting dispatch, Critical waiting, Assigned / en route, and On scene — the life of a report, left to right.',
      },
      {
        target: 'queue:bands',
        text: 'The bands split the queue by stage; pick one to show only those. The next reports to handle are pinned here too.',
      },
      {
        target: 'queue:table',
        text: 'Click a report to open it. Let me open the first one, so you can see what is inside.',
      },
      {
        target: 'modal:header',
        dialog: true,
        text: 'This is the report. The top line says what happened, how severe it is and where it stands, with its record number — and the clock on the right shows how long it has waited.',
      },
      {
        target: 'modal:said',
        dialog: true,
        text: '"What the reporter said": the resident’s own words or voice note, and their answers. Warning chips above it flag anything unusual, and "Why this severity", further down, explains how the severity was set.',
      },
      {
        target: 'modal:where',
        dialog: true,
        text: '"Where it is": the address and the Landmark the resident gave. "Who reported it": their name, whether they are verified, and a number to call them.',
      },
      {
        target: 'modal:map',
        dialog: true,
        text: 'The map shows the scene and your station, with the distance and the estimated response time.',
      },
      {
        target: 'modal:nearby',
        dialog: true,
        text: '"Responders near this incident": who is on duty close by, how far, and what each is already on — so you can choose before you send anyone.',
      },
      {
        target: 'modal:timeline',
        dialog: true,
        text: 'The Timeline: every step of this report so far, and who took it. Scroll this column to read everything.',
      },
      {
        target: 'modal:assist',
        dialog: true,
        text: 'Need another station? "Request help from another station" alerts any station in Biliran — the report stays yours.',
      },
      {
        target: 'modal:actions',
        dialog: true,
        text: 'Everything you can do is in this bar. Accept, or Reject with a reason the resident is told. Chat to ask the reporter first. "Cancel incident" stops one that should not go on, and a misused SOS can be flagged with "Flag false SOS".',
      },
      {
        target: 'modal:actions',
        dialog: true,
        text: 'After accepting, press Dispatch and pick a responder — the nearest are listed first. When the crew is done, press Mark resolved and record what was found. Close takes you back to the queue.',
      },
      {
        target: 'queue:live',
        pose: 'ok',
        text: 'Auto refresh keeps the queue current. Pause it to hold the list still while you read, then press "Refresh now".',
      },
    ],
  },
  {
    id: 'agency-records',
    roles: 'agency',
    href: '/incident-history',
    title: 'Incident Records',
    summary: 'Every report your station received, open or closed.',
    steps: RECORDS_STEPS(false),
  },
  {
    id: 'agency-assist',
    roles: 'agency',
    href: '/assist-requests',
    title: 'Assist Requests',
    summary: 'Ask another station for help, and answer theirs.',
    steps: ASSIST_STEPS(false),
  },
  {
    id: 'agency-narrative',
    roles: 'agency',
    href: '/narrative-reports',
    title: 'Narrative Reports',
    summary: 'Write and file incident record forms.',
    steps: NARRATIVE_STEPS(false),
  },
  {
    id: 'agency-map',
    roles: 'agency',
    href: '/map',
    title: 'Incident Map',
    summary: 'Live incidents, responders and stations.',
    steps: MAP_STEPS,
  },
  {
    id: 'agency-area',
    roles: 'agency',
    href: '/geographic',
    title: 'Operational Area',
    summary: 'Your municipality: barangays, response and agencies.',
    steps: AREA_STEPS(false),
  },
  {
    id: 'agency-responders',
    roles: 'agency',
    href: '/responders',
    title: 'Responders',
    summary: 'Your crew, who is on duty, and new sign-ups.',
    steps: [
      {
        target: 'resp:stats',
        text: 'Your roster: how many responders, who is On duty, who is Awaiting approval, and who was Rejected.',
      },
      {
        target: 'resp:filters',
        text: 'Show Everyone, or only those Awaiting approval, Approved or Rejected.',
      },
      {
        target: 'resp:search',
        text: 'Find a responder by name.',
      },
      {
        target: 'resp:table',
        pose: 'ok',
        text: 'Approve or Reject a responder who registered for your station. "Revoke access" takes an approved one off the roster; "Approve again" brings them back.',
      },
    ],
  },
  {
    id: 'agency-verification',
    roles: 'agency',
    href: '/verification',
    title: 'Verification',
    summary: 'Residents’ ID checks and resident accounts.',
    steps: VERIFICATION_STEPS(false),
  },
  {
    id: 'agency-announcements',
    roles: 'agency',
    href: '/announcements',
    title: 'Announcements',
    summary: 'Alerts for your town, and residents who need help.',
    steps: [
      {
        target: 'ann:stats',
        text: 'Live safety alerts, residents Waiting for help, how many Residents answered, and what was Sent this week.',
      },
      {
        target: 'ann:waiting',
        pose: 'running',
        text: 'Waiting for help: every resident who answered "I need help" and has not been reached yet, with their number. Call them first.',
      },
      {
        target: 'ann:filters',
        text: 'Show Active, Safety alerts, Ended or All; pick a kind, or search by title or place.',
      },
      {
        target: 'ann:feed',
        pose: 'ok',
        text: 'Everything announced to your town. On an alert that asked residents if they are safe, press "See answers" for who needs help and who has not answered.',
      },
    ],
  },
  {
    id: 'agency-reports',
    roles: 'agency',
    href: '/reports',
    title: 'Reports & Export',
    summary: 'Print or export Incident Records and Narrative Reports.',
    steps: REPORTS_STEPS(false),
  },
  {
    id: 'agency-settings',
    roles: 'agency',
    href: '/settings',
    title: 'Settings',
    summary: 'Profile, preferences, and your agency’s hotlines.',
    steps: [
      ...SETTINGS_STEPS,
      {
        pose: 'thinking',
        text: 'Keep your hotline numbers current in Agency Information — residents with no internet see them as Call buttons in the app.',
      },
    ],
  },
];

// ── Provincial Admin ────────────────────────────────────────────────────────

const PROVINCIAL: DemoScript[] = [
  {
    id: 'prov-dashboard',
    roles: 'provincial',
    href: '/overview',
    title: 'Dashboard',
    summary: 'The province at a glance, and how to get around.',
    steps: [
      {
        pose: 'excited',
        text: 'Hi! I’m Ziren. Let me show you around the console. You oversee your agency type across Biliran — the stations dispatch.',
      },
      {
        target: 'nav:/overview',
        text: 'Everything is in the sidebar, grouped as Overview, Monitoring, Management, Communication and Personal. A number beside an entry means something there is waiting for you.',
      },
      {
        target: 'overview:live',
        text: 'Province-wide numbers: incidents in the last 14 days, what is active now, how many are critical, and how many still await triage.',
      },
      {
        target: 'overview:platform',
        text: 'The size of the system: reports by station, residents, responders, and stations — amber when an agency has no station.',
      },
      {
        target: 'overview:volume',
        text: '"Reports received per day" — and beside it, "By agency".',
      },
      {
        target: 'overview:list',
        text: '"Latest reports", newest first across your province. Open one to read it in full; "Incident Records" holds them all.',
      },
      ...SHELL_TAIL,
    ],
  },
  {
    id: 'prov-records',
    roles: 'provincial',
    href: '/incident-history',
    title: 'Incident Records',
    summary: 'Every report under your agency type, open or closed.',
    steps: RECORDS_STEPS(true),
  },
  {
    id: 'prov-assist',
    roles: 'provincial',
    href: '/assist-requests',
    title: 'Assist Requests',
    summary: 'Help between stations, for oversight.',
    steps: ASSIST_STEPS(true),
  },
  {
    id: 'prov-narrative',
    roles: 'provincial',
    href: '/narrative-reports',
    title: 'Narrative Reports',
    summary: 'The forms your stations filed.',
    steps: NARRATIVE_STEPS(true),
  },
  {
    id: 'prov-map',
    roles: 'provincial',
    href: '/map',
    title: 'Incident Map',
    summary: 'Live incidents, responders and stations.',
    steps: MAP_STEPS,
  },
  {
    id: 'prov-area',
    roles: 'provincial',
    href: '/geographic',
    title: 'Geographic Overview',
    summary: 'Any municipality, and all of them compared.',
    steps: AREA_STEPS(true),
  },
  {
    id: 'prov-accounts',
    roles: 'provincial',
    href: '/accounts',
    title: 'Accounts',
    summary: 'Access requests, agency admins, and every account.',
    steps: [
      {
        target: 'acc:tabs',
        text: 'Three views: Access requests (people asking to run an agency’s dashboard), Agency admins, and All accounts — every resident, responder and admin.',
      },
      {
        target: 'acc:content',
        text: 'Approve or reject a request here. In Agency admins, press "New agency admin" to give a station its dashboard account.',
      },
      {
        pose: 'ok',
        text: 'In All accounts, find anyone by name or email, and Suspend, Deactivate or Reactivate an account from its row.',
      },
    ],
  },
  {
    id: 'prov-agencies',
    roles: 'provincial',
    href: '/agencies',
    title: 'Agencies',
    summary: 'Stations, where they are, and their numbers.',
    steps: [
      {
        target: 'agn:stats',
        text: 'Your agencies and their active stations, and how many have their boundaries drawn.',
      },
      {
        target: 'agn:list',
        text: 'Each agency with its stations. Set location (or Move) puts a station on the map; Deactivate one that has closed, and Reactivate brings it back.',
      },
      {
        target: 'agn:add',
        pose: 'thinking',
        text: 'Add station creates a new one. Check every station has hotline numbers — residents call them when they have no internet.',
      },
    ],
  },
  {
    id: 'prov-verification',
    roles: 'provincial',
    href: '/verification',
    title: 'Verification',
    summary: 'ID checks, resident accounts, admins and responders.',
    steps: VERIFICATION_STEPS(true),
  },
  {
    id: 'prov-announcements',
    roles: 'provincial',
    href: '/announcements',
    title: 'Announcements',
    summary: 'Send safety alerts and see who needs help.',
    steps: [
      {
        target: 'ann:stats',
        text: 'Live safety alerts, residents Waiting for help, how many Residents answered, and what was Sent this week.',
      },
      {
        target: 'ann:send',
        text: 'Press "New announcement" and pick the kind — an evacuation order, a weather advisory, a hazard warning — or send one of these straight away.',
      },
      {
        pose: 'thinking',
        text: 'Fill in what that kind needs (an evacuation order asks where to go), then choose who gets it and where — a town or a few barangays. The button shows how many people it will reach.',
      },
      {
        target: 'ann:waiting',
        pose: 'running',
        text: 'Waiting for help: residents who answered "I need help" and have not been reached, with their numbers.',
      },
      {
        target: 'ann:feed',
        pose: 'ok',
        text: 'On an alert that asked residents if they are safe, press "See answers". When it is over, press "Send all clear".',
      },
    ],
  },
  {
    id: 'prov-reports',
    roles: 'provincial',
    href: '/reports',
    title: 'Reports & Export',
    summary: 'Province-wide records and narrative reports.',
    steps: REPORTS_STEPS(true),
  },
  {
    id: 'prov-settings',
    roles: 'provincial',
    href: '/settings',
    title: 'Settings',
    summary: 'Profile, preferences and system settings.',
    steps: SETTINGS_STEPS,
  },
];

export const ALL_DEMOS: DemoScript[] = [...AGENCY, ...PROVINCIAL];

export function demosFor(isProvincialAdmin: boolean): DemoScript[] {
  return isProvincialAdmin ? PROVINCIAL : AGENCY;
}

/** The demo for the page being looked at, if there is one. */
export function demoForPage(isProvincialAdmin: boolean, pathname: string): DemoScript | undefined {
  return demosFor(isProvincialAdmin).find(d => d.href === pathname);
}
