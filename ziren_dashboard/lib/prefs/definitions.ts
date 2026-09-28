/**
 * Every per-browser preference the console offers, in one place.
 *
 * This file is the contract between Settings (which edits these) and the
 * screens that obey them. A preference belongs here only if something reads it:
 * a control that saves a value nothing consumes is worse than no control at
 * all, because it tells the operator the console changed when it did not. The
 * "Read by" note on each group says where the value takes effect.
 *
 * Everything here is per BROWSER (see store.ts). Account and agency facts —
 * profile, agency contact details, which severities interrupt the agency's
 * dispatchers — live on the server and are edited through the API.
 */

import { clamp, createPrefStore, oneOf } from './store';

// ── Display ──────────────────────────────────────────────────────────────

/**
 * Read by: PrefsApplier (density), lib/format/datetime.ts and every screen
 * that formats a date or time through it (Incident Records, the record panel).
 */
export interface DisplayPrefs {
  /** Row height in every table. Compact fits roughly a third more on screen. */
  density: 'comfortable' | 'compact';
  /** 2026-09-19, 19 Sep 2026, or 19/09/2026. */
  dateStyle: 'iso' | 'medium' | 'dmy';
  timeFormat: '24h' | '12h';
  /** Whose clock dates and times are shown in. `browser` is this machine's. */
  timeZone: 'browser' | 'Asia/Manila';
  /** Month names and number grouping. */
  locale: 'en-PH' | 'fil-PH' | 'en-US';
}

export const DISPLAY_DEFAULTS: DisplayPrefs = {
  density: 'comfortable',
  dateStyle: 'iso',
  timeFormat: '24h',
  timeZone: 'browser',
  locale: 'en-PH',
};

export const displayPrefs = createPrefStore<DisplayPrefs>(
  'ziren-display-prefs',
  DISPLAY_DEFAULTS,
  v => ({
    density: oneOf(v.density, ['comfortable', 'compact'], 'comfortable'),
    dateStyle: oneOf(v.dateStyle, ['iso', 'medium', 'dmy'], 'iso'),
    timeFormat: oneOf(v.timeFormat, ['24h', '12h'], '24h'),
    timeZone: oneOf(v.timeZone, ['browser', 'Asia/Manila'], 'browser'),
    locale: oneOf(v.locale, ['en-PH', 'fil-PH', 'en-US'], 'en-PH'),
  }),
);

// ── Alerts ───────────────────────────────────────────────────────────────

/**
 * Read by: useIncidentAlerts — the poll cadence, the alarm's sound and level,
 * the desktop notification and the flashing tab title.
 *
 * WHICH SEVERITIES interrupt is NOT here. That is an agency rule, stored on the
 * agency record and shared by every dispatcher in it (Settings → Alerts). These
 * are only how THIS browser delivers what the agency decided.
 */
export interface AlertPrefs {
  /** `critical` sounds only for a critical report; `off` is silent. */
  soundMode: 'all' | 'critical' | 'off';
  /** Alarm level, 0.2 to 1. Never fully silent here: silence is `soundMode: off`,
   *  a separate and deliberate choice, so a slider can't be dragged there by
   *  accident. */
  volume: number;
  /** Raise a desktop notification (still needs the browser's permission). */
  desktop: boolean;
  /** Flash "(2) NEW REPORTS" in the tab title so a hidden tab still shouts. */
  flashTitle: boolean;
  /** Seconds between checks for a new report. */
  pollSeconds: 5 | 10 | 15 | 30;
}

export const ALERT_DEFAULTS: AlertPrefs = {
  soundMode: 'all',
  volume: 1,
  desktop: true,
  flashTitle: true,
  pollSeconds: 10,
};

export const alertPrefs = createPrefStore<AlertPrefs>(
  'ziren-alert-prefs',
  ALERT_DEFAULTS,
  v => ({
    soundMode: oneOf(v.soundMode, ['all', 'critical', 'off'], 'all'),
    volume: clamp(v.volume, 0.2, 1, 1),
    desktop: v.desktop,
    flashTitle: v.flashTitle,
    pollSeconds: oneOf(v.pollSeconds, [5, 10, 15, 30], 10),
  }),
);

// ── Map ──────────────────────────────────────────────────────────────────

/**
 * Read by: the Incident Map page (which layers open switched on), ZirenMap
 * (basemap, label behaviour), useMapData (refresh), and lib/format/geo.ts
 * (units and coordinate style, used by the record panel and the map).
 */
export interface MapPrefs {
  basemap: 'satellite' | 'streets';
  /** Which layers are on when the map opens. */
  layerIncidents: boolean;
  layerResponders: boolean;
  layerStations: boolean;
  /** Show place labels at every zoom, not only when zoomed in. */
  alwaysLabels: boolean;
  units: 'km' | 'mi';
  coordFormat: 'decimal' | 'dms';
  /** Seconds between map data refreshes. */
  refreshSeconds: 15 | 30 | 60 | 120;
}

export const MAP_DEFAULTS: MapPrefs = {
  basemap: 'satellite',
  layerIncidents: true,
  layerResponders: true,
  layerStations: true,
  alwaysLabels: false,
  units: 'km',
  coordFormat: 'decimal',
  refreshSeconds: 30,
};

export const mapPrefs = createPrefStore<MapPrefs>(
  'ziren-map-prefs',
  MAP_DEFAULTS,
  v => ({
    basemap: oneOf(v.basemap, ['satellite', 'streets'], 'satellite'),
    layerIncidents: v.layerIncidents,
    layerResponders: v.layerResponders,
    layerStations: v.layerStations,
    alwaysLabels: v.alwaysLabels,
    units: oneOf(v.units, ['km', 'mi'], 'km'),
    coordFormat: oneOf(v.coordFormat, ['decimal', 'dms'], 'decimal'),
    refreshSeconds: oneOf(v.refreshSeconds, [15, 30, 60, 120], 30),
  }),
);

// ── Incidents ────────────────────────────────────────────────────────────

/**
 * Read by: the live queue (refresh), Incident Records (window and page size),
 * and the record panel (which sections it shows).
 *
 * The `show…` switches hide DISPLAY only. Nothing here changes what is stored,
 * scored or sent to a crew — turning off the AI suggestion does not stop the
 * rubric running, it stops it being drawn on this screen.
 */
export interface IncidentPrefs {
  /** Live queue refresh, seconds. */
  refreshSeconds: 5 | 15 | 30 | 60;
  /** How far back Incident Records opens, in days. */
  historyDays: 7 | 30 | 90 | 365;
  /** Rows per page in Incident Records. */
  recordsPerPage: 25 | 50 | 100;
  showAiSuggestion: boolean;
  showWizardAnswers: boolean;
  showLocationDetail: boolean;
  showRecording: boolean;
}

export const INCIDENT_DEFAULTS: IncidentPrefs = {
  refreshSeconds: 15,
  historyDays: 30,
  recordsPerPage: 100,
  showAiSuggestion: true,
  showWizardAnswers: true,
  showLocationDetail: true,
  showRecording: true,
};

export const incidentPrefs = createPrefStore<IncidentPrefs>(
  'ziren-incident-prefs',
  INCIDENT_DEFAULTS,
  v => ({
    refreshSeconds: oneOf(v.refreshSeconds, [5, 15, 30, 60], 15),
    historyDays: oneOf(v.historyDays, [7, 30, 90, 365], 30),
    recordsPerPage: oneOf(v.recordsPerPage, [25, 50, 100], 100),
    showAiSuggestion: v.showAiSuggestion,
    showWizardAnswers: v.showWizardAnswers,
    showLocationDetail: v.showLocationDetail,
    showRecording: v.showRecording,
  }),
);

// ── Privacy ──────────────────────────────────────────────────────────────

/**
 * Read by: the record panel (masking) and IdleGuard (auto sign-out).
 */
export interface PrivacyPrefs {
  /** Show reporter and emergency-contact numbers masked until clicked. */
  maskContacts: boolean;
  /** Sign this browser out after this many idle minutes. 0 is never. */
  idleMinutes: 0 | 15 | 30 | 60 | 120;
}

export const PRIVACY_DEFAULTS: PrivacyPrefs = {
  maskContacts: false,
  idleMinutes: 0,
};

export const privacyPrefs = createPrefStore<PrivacyPrefs>(
  'ziren-privacy-prefs',
  PRIVACY_DEFAULTS,
  v => ({
    maskContacts: v.maskContacts,
    idleMinutes: oneOf(v.idleMinutes, [0, 15, 30, 60, 120], 0),
  }),
);

// ── Accessibility ────────────────────────────────────────────────────────

export type FontScale = 'small' | 'normal' | 'large' | 'extra-large';

/**
 * Read by: PrefsApplier, which writes them to <html> on every page. They used
 * to be applied by a hook mounted only on the Settings page, so they worked
 * there and nowhere else — see the note in store.ts.
 *
 * Same storage key as before, so anyone who already chose a font size or high
 * contrast keeps it.
 */
export interface AccessibilityPrefs {
  fontScale: FontScale;
  highContrast: boolean;
  reducedMotion: boolean;
  largerControls: boolean;
  /** A thick, high-visibility focus outline instead of the default ring. */
  strongFocus: boolean;
  underlineLinks: boolean;
  textSpacing: 'normal' | 'relaxed' | 'wide';
}

export const A11Y_DEFAULTS: AccessibilityPrefs = {
  fontScale: 'normal',
  highContrast: false,
  reducedMotion: false,
  largerControls: false,
  strongFocus: false,
  underlineLinks: false,
  textSpacing: 'normal',
};

export const FONT_SCALE_VALUES: Record<FontScale, number> = {
  small: 0.9,
  normal: 1,
  large: 1.15,
  'extra-large': 1.3,
};

export const accessibilityPrefs = createPrefStore<AccessibilityPrefs>(
  'ziren-accessibility-prefs',
  A11Y_DEFAULTS,
  v => ({
    fontScale: oneOf(v.fontScale, ['small', 'normal', 'large', 'extra-large'], 'normal'),
    highContrast: v.highContrast,
    reducedMotion: v.reducedMotion,
    largerControls: v.largerControls,
    strongFocus: v.strongFocus,
    underlineLinks: v.underlineLinks,
    textSpacing: oneOf(v.textSpacing, ['normal', 'relaxed', 'wide'], 'normal'),
  }),
);

// ── All of them, for export / import / reset ─────────────────────────────

export const ALL_PREF_STORES = [
  displayPrefs,
  alertPrefs,
  mapPrefs,
  incidentPrefs,
  privacyPrefs,
  accessibilityPrefs,
] as const;
