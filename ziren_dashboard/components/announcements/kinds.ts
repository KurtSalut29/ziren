/**
 * Every kind of announcement: its name, look, what it asks for, and a
 * starting text. One table, read by the composer, the list and the preview,
 * so a kind can never be called two things.
 *
 * COLOUR. Red stays reserved for critical severity: an evacuation order (and
 * the legacy "emergency") is the one kind that is a life-safety order, so it
 * is the only red one. A hazard warning is severity-high amber; a weather
 * advisory is information blue; the all clear is green.
 */

import {
  Bell, BellRing, CloudLightning, Construction, DoorOpen, HeartPulse, Megaphone, Package,
  PlugZap, ShieldCheck, Siren, Sparkles, TriangleAlert, UserSearch, WifiOff, Wrench,
  type LucideIcon,
} from 'lucide-react';
import type { AnnouncementCategory, AnnouncementDetails, AnnouncementTarget } from '@/lib/api/announcements';

export type KindGroup = 'safety' | 'info';

export interface Kind {
  key: AnnouncementCategory;
  label: string;
  /** One line under the name in the picker. */
  blurb: string;
  group: KindGroup;
  Icon: LucideIcon;
  color: string;
  /** Residents can be asked "safe / need help". */
  canAsk: boolean;
  /** The ask switch starts on. */
  askByDefault: boolean;
  /** Who it usually goes to. */
  defaultTarget: AnnouncementTarget;
  /** Offered in the picker (the legacy ones stay readable but are not offered). */
  offered: boolean;
  template: { title: string; body: string };
}

export const KINDS: Record<AnnouncementCategory, Kind> = {
  evacuation: {
    key: 'evacuation', label: 'Evacuation order', group: 'safety',
    blurb: 'Tell people in an area to leave, and where to go.',
    Icon: DoorOpen, color: 'var(--color-severity-critical)',
    canAsk: true, askByDefault: true, defaultTarget: 'resident', offered: true,
    template: {
      title: 'Evacuation order',
      body: 'Ipinag-uutos ang paglikas sa inyong lugar. Pumunta agad sa itinakdang evacuation center. Dalhin ang go-bag, gamot at mahahalagang dokumento. Sagutin sa app kung ligtas ka o kailangan mo ng tulong.',
    },
  },
  weather: {
    key: 'weather', label: 'Weather advisory', group: 'safety',
    blurb: 'A typhoon signal or a rainfall warning.',
    Icon: CloudLightning, color: 'var(--color-system-info)',
    canAsk: true, askByDefault: false, defaultTarget: 'all', offered: true,
    template: {
      title: 'Weather advisory',
      body: 'Maghanda sa malakas na hangin at ulan. Iwasan ang paglabas kung hindi kailangan, i-charge ang cellphone, at makinig sa susunod na abiso.',
    },
  },
  hazard: {
    key: 'hazard', label: 'Hazard warning', group: 'safety',
    blurb: 'Flood, landslide, storm surge, earthquake, tsunami.',
    Icon: TriangleAlert, color: 'var(--color-severity-high)',
    canAsk: true, askByDefault: true, defaultTarget: 'resident', offered: true,
    template: {
      title: 'Hazard warning',
      body: 'May panganib sa inyong lugar. Lumayo sa ilog, dalampasigan at mga dalisdis. Maghanda sa posibleng paglikas at sagutin sa app kung ligtas ka.',
    },
  },
  road_closure: {
    key: 'road_closure', label: 'Road closure', group: 'safety',
    blurb: 'A road or bridge that cannot be used, and the way around.',
    Icon: Construction, color: 'var(--color-system-warning)',
    canAsk: false, askByDefault: false, defaultTarget: 'all', offered: true,
    template: {
      title: 'Road closure',
      body: 'Sarado muna ang daan. Gumamit ng ibang ruta at sundin ang mga nakabantay sa lugar.',
    },
  },
  missing_person: {
    key: 'missing_person', label: 'Missing person', group: 'safety',
    blurb: 'Ask the public to look out for someone.',
    Icon: UserSearch, color: 'var(--color-agency-pnp)',
    canAsk: false, askByDefault: false, defaultTarget: 'all', offered: true,
    template: {
      title: 'Missing person',
      body: 'Kung may nakakita o may impormasyon, tumawag agad sa numerong nakalista. Huwag magpakalat ng hindi kumpirmadong balita.',
    },
  },
  all_clear: {
    key: 'all_clear', label: 'All clear', group: 'safety',
    blurb: 'End a warning: it is safe again.',
    Icon: ShieldCheck, color: 'var(--color-system-success)',
    canAsk: false, askByDefault: false, defaultTarget: 'all', offered: false,
    template: {
      title: 'All clear',
      body: 'Ligtas na po. Maaari nang bumalik sa inyong mga tahanan. Mag-ingat pa rin sa mga natumbang puno, putol na kawad at baha sa daan.',
    },
  },
  emergency: {
    key: 'emergency', label: 'Emergency', group: 'safety',
    blurb: 'Any other urgent safety notice.',
    Icon: Siren, color: 'var(--color-severity-critical)',
    canAsk: true, askByDefault: false, defaultTarget: 'all', offered: true,
    template: { title: 'Emergency notice', body: '' },
  },
  relief: {
    key: 'relief', label: 'Relief distribution', group: 'info',
    blurb: 'Where and when aid is given out, and what to bring.',
    Icon: Package, color: 'var(--color-agency-mdrrmo)',
    canAsk: false, askByDefault: false, defaultTarget: 'resident', offered: true,
    template: {
      title: 'Relief distribution',
      body: 'Magkakaroon ng pamamahagi ng relief goods. Magdala ng valid ID at sundin ang pila. Isang kinatawan lamang bawat pamilya.',
    },
  },
  health: {
    key: 'health', label: 'Health advisory', group: 'info',
    blurb: 'Dengue, an outbreak, a vaccination schedule.',
    Icon: HeartPulse, color: 'var(--color-status-processing)',
    canAsk: false, askByDefault: false, defaultTarget: 'resident', offered: true,
    template: { title: 'Health advisory', body: '' },
  },
  drill: {
    key: 'drill', label: 'Drill', group: 'info',
    blurb: 'An earthquake or fire drill - so it is not reported as real.',
    Icon: BellRing, color: 'var(--color-text-secondary)',
    canAsk: false, askByDefault: false, defaultTarget: 'all', offered: true,
    template: {
      title: 'Drill schedule',
      body: 'Magkakaroon ng drill. Huwag mabahala sa maririnig na sirena - ito ay pagsasanay lamang.',
    },
  },
  utility: {
    key: 'utility', label: 'Power / water interruption', group: 'info',
    blurb: 'A scheduled or unplanned outage.',
    Icon: PlugZap, color: 'var(--color-system-warning)',
    canAsk: false, askByDefault: false, defaultTarget: 'all', offered: true,
    template: {
      title: 'Power interruption',
      body: 'Mawawalan ng kuryente sa mga apektadong lugar. I-charge nang maaga ang cellphone at power bank.',
    },
  },
  service_interruption: {
    key: 'service_interruption', label: 'Ziren service interruption', group: 'info',
    blurb: 'The app itself will be down - and what to do instead.',
    Icon: WifiOff, color: 'var(--color-system-warning)',
    canAsk: false, askByDefault: false, defaultTarget: 'all', offered: true,
    template: {
      title: 'Ziren will be unavailable',
      body: 'Habang hindi gumagana ang app, tumawag sa 911 o sa hotline ng inyong istasyon para mag-report.',
    },
  },
  maintenance: {
    key: 'maintenance', label: 'Maintenance', group: 'info',
    blurb: 'Planned work on the system.',
    Icon: Wrench, color: 'var(--color-status-processing)',
    canAsk: false, askByDefault: false, defaultTarget: 'all', offered: false,
    template: { title: 'Maintenance', body: '' },
  },
  feature: {
    key: 'feature', label: 'New feature', group: 'info',
    blurb: 'Something new in Ziren.',
    Icon: Sparkles, color: 'var(--color-brand)',
    canAsk: false, askByDefault: false, defaultTarget: 'all', offered: false,
    template: { title: 'New in Ziren', body: '' },
  },
  reminder: {
    key: 'reminder', label: 'Reminder', group: 'info',
    blurb: 'A reminder to a group.',
    Icon: Bell, color: 'var(--color-status-dispatched)',
    canAsk: false, askByDefault: false, defaultTarget: 'all', offered: true,
    template: { title: 'Reminder', body: '' },
  },
  general: {
    key: 'general', label: 'General', group: 'info',
    blurb: 'Anything else.',
    Icon: Megaphone, color: 'var(--color-text-muted)',
    canAsk: false, askByDefault: false, defaultTarget: 'all', offered: true,
    template: { title: '', body: '' },
  },
};

/**
 * Who issues which kind - mirrors announcement_service.KIND_OWNERS, which is
 * what actually enforces it. MDRRMO declares evacuations and weather/hazard
 * warnings and runs relief; PNP handles missing persons; the rest are open to
 * all three provincial offices.
 */
export const KIND_OWNERS: Partial<Record<AnnouncementCategory, string[]>> = {
  evacuation: ['MDRRMO'],
  weather: ['MDRRMO'],
  hazard: ['MDRRMO'],
  relief: ['MDRRMO'],
  missing_person: ['PNP'],
};

export const mayIssue = (key: AnnouncementCategory, agencyType: string | null | undefined) => {
  const owners = KIND_OWNERS[key];
  return !owners || owners.includes((agencyType ?? '').toUpperCase());
};

/** Only the office that issued an alert ends it or takes it down. An old one with no issuer on record: anyone. */
export const mayEnd = (issuer: string | null | undefined, agencyType: string | null | undefined) =>
  !issuer || issuer.toUpperCase() === (agencyType ?? '').toUpperCase();

export const kindOf = (key: string | null | undefined): Kind =>
  KINDS[(key ?? 'general') as AnnouncementCategory] ?? KINDS.general;

export const isSafety = (key: string | null | undefined) => kindOf(key).group === 'safety';

export const MUNICIPALITIES = ['Almeria', 'Biliran', 'Cabucgayan', 'Caibiran', 'Culaba', 'Kawayan', 'Maripipi', 'Naval'] as const;

export const TARGET_LABEL: Record<AnnouncementTarget, string> = {
  all: 'Everyone',
  resident: 'Residents',
  responder: 'Responders',
  agency_admin: 'Agency admins',
  agency: 'One agency',
};

export const HAZARD_LABEL: Record<NonNullable<AnnouncementDetails['hazard']>, string> = {
  flood: 'Flood', landslide: 'Landslide', storm_surge: 'Storm surge', earthquake: 'Earthquake',
  tsunami: 'Tsunami', volcanic: 'Volcanic activity', fire: 'Fire', other: 'Other hazard',
};

export const RAINFALL_LABEL: Record<NonNullable<AnnouncementDetails['rainfall']>, string> = {
  yellow: 'Yellow rainfall', orange: 'Orange rainfall', red: 'Red rainfall',
};

/** Rainfall warnings use PAGASA's own colours - that is what people know them by. */
export const RAINFALL_COLOR: Record<NonNullable<AnnouncementDetails['rainfall']>, string> = {
  yellow: '#CA8A04', orange: '#EA580C', red: 'var(--color-severity-critical)',
};

/** "Naval · Atipolo, Caraycaray; Almeria" - or "Whole province". */
export function placeLine(
  towns: string[] | null | undefined,
  barangays: { name: string; municipality: string }[] | null | undefined,
): string {
  if (!towns || towns.length === 0) return 'Whole province';
  return towns.map(t => {
    const picked = (barangays ?? []).filter(b => b.municipality === t).map(b => b.name);
    return picked.length ? `${t} · ${picked.join(', ')}` : t;
  }).join('; ');
}

/** The short facts a card shows under the title, e.g. "Signal No. 3", "Flood". */
export function factChips(category: string, d: AnnouncementDetails | null | undefined): { label: string; color?: string }[] {
  if (!d) return [];
  const out: { label: string; color?: string }[] = [];
  if (category === 'weather') {
    if (d.signal) out.push({ label: `Signal No. ${d.signal}`, color: d.signal >= 3 ? 'var(--color-severity-high)' : undefined });
    if (d.rainfall) out.push({ label: RAINFALL_LABEL[d.rainfall], color: RAINFALL_COLOR[d.rainfall] });
    if (d.storm_name) out.push({ label: d.storm_name });
  }
  if (category === 'hazard' && d.hazard) out.push({ label: HAZARD_LABEL[d.hazard] });
  if (category === 'evacuation') {
    if (d.kind) out.push({ label: d.kind === 'forced' ? 'Forced' : 'Pre-emptive', color: d.kind === 'forced' ? 'var(--color-severity-critical)' : undefined });
    if (d.centers?.length) out.push({ label: `${d.centers.length} evacuation centre${d.centers.length === 1 ? '' : 's'}` });
  }
  if (category === 'road_closure' && d.reopens) out.push({ label: `Reopens ${d.reopens}` });
  if (category === 'missing_person' && d.age != null) out.push({ label: `Age ${d.age}` });
  if ((category === 'relief' || category === 'drill' || category === 'health' || category === 'utility') && d.when) out.push({ label: d.when });
  return out;
}
