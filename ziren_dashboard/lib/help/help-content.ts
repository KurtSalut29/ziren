/**
 * "How to use Ziren" for the dashboard — one set of topics per role.
 *
 * Every step names a page or button by the label it actually has on screen
 * (sidebar entries from lib/nav/nav-config.ts, actions from the incident
 * panel). When a screen changes, change its topic here: help that describes
 * a button nobody can find is worse than none.
 */

export interface HelpTopic {
  id: string;
  title: string;
  summary: string;
  steps: string[];
  tip?: string;
  /** A page to open from the topic. */
  href?: string;
  hrefLabel?: string;
}

export interface HelpGroup {
  label: string;
  topics: HelpTopic[];
}

const GETTING_AROUND: HelpTopic = {
  id: 'getting-around',
  title: 'Getting around',
  summary: 'The sidebar, search and shortcuts.',
  steps: [
    'Everything is in the sidebar on the left, grouped as Overview, Monitoring, Management, Communication and Personal.',
    'Press Ctrl + K to search for an incident, a person or a page from anywhere.',
    'Press Ctrl + B to show or hide the sidebar; Esc closes any panel, menu or dialog.',
    'A number beside a sidebar entry means something there is waiting for you.',
  ],
};

const RESIDENT_SIDE: HelpTopic = {
  id: 'resident-side',
  title: 'What residents see and send',
  summary: 'Landmarks, reports placed elsewhere, and calling your station offline.',
  steps: [
    'Every report now carries a landmark — the app fills in the nearest one from the map, and the resident corrects it. It is shown as "Landmark" under Where it is.',
    'A resident can report an incident they are not at by placing it on the map. You then see "Reported from somewhere else", with where the caller was and how far that is from the incident.',
    'The address and map pin are always the incident itself — call the reporter to confirm the spot before dispatching.',
    'With no internet the app shows your station\'s hotline numbers as Call buttons, so expect phone calls from residents who could not send a report.',
  ],
  tip: 'Your hotline numbers are the ones in Settings → Agency Information. Keep them current — residents call them offline.',
  href: '/settings?tab=agency',
  hrefLabel: 'Open Agency Information',
};

const AGENCY_ADMIN: HelpGroup[] = [
  {
    label: 'Start here',
    topics: [GETTING_AROUND, RESIDENT_SIDE],
  },
  {
    label: 'Handling a report',
    topics: [
      {
        id: 'new-report',
        title: 'When a new report arrives',
        summary: 'An alarm sounds and the report opens over whatever you are doing.',
        steps: [
          'Open it from the alert, or from Incident Management in the sidebar.',
          'Read the category, the resident\'s own words and the severity with its reason.',
          'Check Where it is: the address, the Landmark, and the map beside it. Look for "Reported from somewhere else".',
          'Use the chat button to ask the reporter something before you decide.',
        ],
        href: '/incidents',
        hrefLabel: 'Open Incident Management',
      },
      {
        id: 'accept-reject',
        title: 'Accept or reject',
        summary: 'Every report is reviewed by a person before anyone is sent.',
        steps: [
          'Press Accept when the report is genuine and yours to handle.',
          'Press Reject and give the reason when it is not — the resident is told.',
          'A false SOS can be marked with Flag false SOS; repeated ones suspend the account.',
        ],
      },
      {
        id: 'dispatch',
        title: 'Dispatch a responder',
        summary: 'Send the crew, then follow them to the scene.',
        steps: [
          'After accepting, press Dispatch and pick a responder. The ones nearest the incident are listed first.',
          'The crew answers in their app; the panel shows "Accepted by crew" and then their progress (on the way, on scene).',
          'When the crew is done, press Mark resolved and record what was found, injured, fatalities and transported.',
          'Cancel incident closes a report that needs no response.',
        ],
      },
      {
        id: 'assist',
        title: 'Ask another station for help',
        summary: 'Any station in Biliran, from inside the incident.',
        steps: [
          'In the incident, press "Request help from another station" and choose who to ask — any station in the province.',
          'The station you ask is alerted with an alarm. The report stays yours.',
          'Follow the conversation, and answer requests sent to you, in Assist Requests.',
        ],
        href: '/assist-requests',
        hrefLabel: 'Open Assist Requests',
      },
    ],
  },
  {
    label: 'Records and paperwork',
    topics: [
      {
        id: 'records',
        title: 'Find a past incident',
        summary: 'Incident Records holds everything, open or closed.',
        steps: [
          'Open Incident Records, pick a period, and filter by status, severity or type.',
          'Open any row to see the full record.',
        ],
        href: '/incident-history',
        hrefLabel: 'Open Incident Records',
      },
      {
        id: 'narrative',
        title: 'Write a narrative report',
        summary: 'The incident record form, filed by type of incident.',
        steps: [
          'Open Narrative Reports. Resolved incidents still waiting for a report are listed there.',
          'Press Write report beside the incident, fill in the sections of the form, and save.',
          'It is filed under its type of incident, where you can open it again later.',
        ],
        href: '/narrative-reports',
        hrefLabel: 'Open Narrative Reports',
      },
      {
        id: 'export',
        title: 'Print or export',
        summary: 'Incident Records and Narrative Reports as clean PDFs.',
        steps: [
          'Open Reports & Export and pick Incident Records or Narrative Reports.',
          'Set the period and filters; the preview updates.',
          'Print, download the PDF, or export to Excel or CSV.',
        ],
        href: '/reports',
        hrefLabel: 'Open Reports & Export',
      },
    ],
  },
  {
    label: 'Your station',
    topics: [
      {
        id: 'responders',
        title: 'Responders',
        summary: 'Your crew, who is on duty, and new sign-ups.',
        steps: [
          'Open Responders to see your crew and who is on duty.',
          'Approve or Reject responders who registered for your station.',
        ],
        href: '/responders',
        hrefLabel: 'Open Responders',
      },
      {
        id: 'map-area',
        title: 'Incident Map and Operational Area',
        summary: 'Where things are happening, and your area at a glance.',
        steps: [
          'Incident Map shows reports as pins; search a barangay or landmark from the box on the map.',
          'Operational Area summarises your municipality: barangays, stations and other agencies\' numbers.',
        ],
        href: '/map',
        hrefLabel: 'Open Incident Map',
      },
      {
        id: 'hotlines',
        title: 'Your hotline numbers',
        summary: 'What residents call when they have no internet.',
        steps: [
          'Open Settings → Agency Information.',
          'Under Hotline numbers, list every line, separated by ";" — for example Globe: 0955-723-6300; Smart: 0948-024-3466.',
          'Save. Residents see each number as its own Call button in the app.',
        ],
        href: '/settings?tab=agency',
        hrefLabel: 'Open Agency Information',
      },
    ],
  },
];

const PROVINCIAL_ADMIN: HelpGroup[] = [
  {
    label: 'Start here',
    topics: [
      GETTING_AROUND,
      {
        id: 'province-view',
        title: 'Watching the province',
        summary: 'You oversee your agency type across Biliran; stations dispatch.',
        steps: [
          'Dashboard shows what is open right now across your agency type.',
          'Incident Records lists every report, open or closed; open one to read it in full.',
          'Incident Map and Geographic Overview show where things are happening.',
          'Dispatching is done by each station — you see every step they take.',
        ],
        href: '/overview',
        hrefLabel: 'Open Dashboard',
      },
      RESIDENT_SIDE,
    ],
  },
  {
    label: 'Management',
    topics: [
      {
        id: 'accounts',
        title: 'Accounts',
        summary: 'Station admins and everyone else, in one directory.',
        steps: [
          'Open Accounts to find anyone by name or email.',
          'Use New agency admin to give a station its dashboard account.',
          'Suspend, Deactivate or Reactivate an account from its row.',
        ],
        href: '/accounts',
        hrefLabel: 'Open Accounts',
      },
      {
        id: 'agencies',
        title: 'Agencies and stations',
        summary: 'Your agency type\'s stations, where they are, and their numbers.',
        steps: [
          'Open Agencies. Use Add station for a new one, and Set location to put it on the map.',
          'Deactivate a station that has closed; Reactivate brings it back.',
          'Check each station has hotline numbers — residents call them offline.',
        ],
        href: '/agencies',
        hrefLabel: 'Open Agencies',
      },
      {
        id: 'verification',
        title: 'Verification',
        summary: 'Residents\' ID checks.',
        steps: ['Open Verification to review IDs residents submitted and approve or refuse them.'],
        href: '/verification',
        hrefLabel: 'Open Verification',
      },
    ],
  },
  {
    label: 'Communication',
    topics: [
      {
        id: 'announcements',
        title: 'Announcements',
        summary: 'Safety alerts and notices, aimed at a town or a few barangays.',
        steps: [
          'Open Announcements and press New announcement, then pick the kind (evacuation order, weather advisory, hazard warning…).',
          'Fill in what that kind needs - an evacuation order asks where to go - then choose who gets it and where. The button shows how many people it will reach.',
          'On an alert that asked residents if they are safe, press See answers for who needs help, who has not answered, and their numbers. When it is over, press Send all clear.',
        ],
        href: '/announcements',
        hrefLabel: 'Open Announcements',
      },
      {
        id: 'assist-oversight',
        title: 'Help between stations',
        summary: 'Every assist request under your agency type.',
        steps: ['Open Assist Requests to follow which stations asked for help and how it was answered.'],
        href: '/assist-requests',
        hrefLabel: 'Open Assist Requests',
      },
      {
        id: 'export-prov',
        title: 'Print or export',
        summary: 'Province-wide records and narrative reports as PDFs.',
        steps: [
          'Open Reports & Export and pick Incident Records or Narrative Reports.',
          'Set the period and filters, then print, download the PDF, or export to Excel or CSV.',
        ],
        href: '/reports',
        hrefLabel: 'Open Reports & Export',
      },
    ],
  },
];

export function helpFor(isProvincialAdmin: boolean): HelpGroup[] {
  return isProvincialAdmin ? PROVINCIAL_ADMIN : AGENCY_ADMIN;
}
