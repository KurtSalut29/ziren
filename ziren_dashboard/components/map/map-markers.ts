/**
 * The marker artwork and the labels that go under it.
 *
 * THE PROBLEM THIS SOLVES
 *
 * There are three station icons and twenty-one stations. Biliran has seven
 * municipalities with a BFP, a PNP and an MDRRMO in each, so the icon alone
 * says what KIND of station a pin is and never WHICH one — and in Naval the
 * three sit a couple of hundred metres apart, close enough that at province
 * zoom they read as one smudge.
 *
 * So every station pin carries its name in text: "BFP Naval", "PNP Almeria".
 * The icon gives the kind at a glance and the label resolves it, which is the
 * same division of labour the console uses for severity — colour for speed,
 * a word so the colour is never load-bearing on its own.
 *
 * WHY THE LABELS DISAPPEAR WHEN YOU ZOOM OUT
 *
 * Twenty-one labels on a view of the whole island is not information, it is
 * a wall of text with a map behind it. Below LABEL_MIN_ZOOM only the icons
 * draw; the labels come back as soon as there is room for them. Nothing is
 * hidden that the viewer could have read anyway.
 */

import type { AgencyType, MapStation } from '@/lib/api/map';

/**
 * Marker art — the actual station icons provided for the project
 * (BFPIcon.png / PNPIcon.png / MDRRMOIcon.png), one per agency type. Twenty-
 * one stations share three icons; see stationLabel() below for how a pin
 * says WHICH station on top of what kind it is.
 */
export const AGENCY_MARKER: Record<AgencyType, string> = {
  BFP:    '/markers/bfp.png',
  PNP:    '/markers/pnp.png',
  MDRRMO: '/markers/mdrrmo.png',
};

export const RESPONDER_MARKER = '/markers/responder.png';
export const RESIDENT_MARKER  = '/markers/resident.png';

/**
 * Drawn size of a station pin, and where its point is.
 *
 * TIP_RATIO is measured from the artwork, not guessed: scanning down the
 * centre column of each PNG, the solid pin's opaque pixels stop and the soft
 * drop-shadow ellipse begins at ~83-85% of the image height (measured
 * separately per file — bfp.png at 0.830, pnp.png at 0.852, mdrrmo.png at
 * 0.854 — close enough to share one constant at the marker's drawn size of a
 * few dozen pixels). Anchoring at the bottom of the image instead would
 * float every station a few pixels north of where it actually is, into the
 * shadow rather than the point.
 */
export const PIN_W = 24;
export const PIN_H = 36;
export const PIN_TIP_RATIO = 0.84;

/** The person markers stand on a glow ring; its centre is the position. */
export const PERSON_W = 24;
export const PERSON_H = 34;
export const PERSON_TIP_RATIO = 0.87;

/** Below this zoom, pins draw without their labels. */
export const LABEL_MIN_ZOOM = 13;

/**
 * Marker stacking order for incidents, worst on top.
 *
 * Leaflet's default is by latitude, which decides overlaps by an accident of
 * geography. Reports cluster in town centres, so overlaps are the normal case
 * and not an edge one.
 */
export const SEVERITY_STACK: Record<string, number> = {
  critical: 400,
  high:     300,
  medium:   200,
  low:      100,
  unscored: 50,
};

/**
 * What a station pin says under it: "BFP Naval".
 *
 * Agency type plus municipality, not the full `name`. The seeded names are
 * "BFP Naval Main Station" and "MDRRMO Naval Office" — inconsistent in form
 * and too long to sit under a 24px pin without colliding with its neighbour.
 * The full name is still one hover away in the tooltip.
 */
export function stationLabel(st: {
  agency_type: AgencyType | null;
  municipality: string | null;
  name: string;
}): string {
  if (st.agency_type && st.municipality) {
    return `${st.agency_type} ${st.municipality}`;
  }
  // An agency row without a municipality is a data gap, not a reason to draw
  // an unlabelled pin — fall back to whatever name it does have.
  return st.agency_type ?? st.name;
}

/** The full description, for the hover tooltip. */
export function stationTooltip(st: MapStation): string {
  const parts = [st.name];
  if (st.address) parts.push(st.address);
  return parts.join(' · ');
}

/**
 * Escape text bound for innerHTML.
 *
 * NOT optional. Leaflet's `divIcon({ html })` and `bindTooltip(string)` both
 * assign to innerHTML, and every string interpolated into them here comes out
 * of the database: station names and addresses are typed by agency admins,
 * and responder names come from user registration. Before this, a station
 * named `<img src=x onerror=...>` executed in the browser of every dispatcher
 * who opened the map.
 */
export function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/**
 * The inner HTML of a pin: the artwork, with a label chip under it.
 *
 * `alt` is empty on purpose. The image is decoration in the accessibility
 * sense — the label beside it already carries the same words, and a screen
 * reader announcing "BFP Naval, image, BFP Naval" is worse than silent art.
 */
export function markerHtml(opts: {
  src: string;
  w: number;
  h: number;
  label: string;
  labelColor: string;
  /** Fill the chip with this colour and print the label on it in white. */
  labelBg?: string;
  /**
   * Keep the label at every zoom, exempt from LABEL_MIN_ZOOM.
   *
   * Only incidents get this. There are twenty-one stations and they are fixed
   * infrastructure a dispatcher already knows the position of; there are a
   * handful of open incidents and their severity is the single most urgent
   * fact on the map. Hiding "CRITICAL" when you zoom out to see the whole
   * island would hide it exactly when the widest view is being used to decide
   * where to send people.
   */
  alwaysLabel?: boolean;
}): string {
  // The size goes in an INLINE STYLE, not just the width/height attributes.
  //
  // Presentational attributes sit at the bottom of the cascade, and both
  // Tailwind's preflight (`img { height: auto }`) and Leaflet's own
  // `.leaflet-container img { max-width: none !important }` outrank them. With
  // attributes alone every pin drew at the artwork's natural 86x128 inside a
  // 24x36 box: markers four times too big, overflowing their own anchor, and
  // covering the incidents they were supposed to sit beside.
  const chipStyle = opts.labelBg
    ? `background:${opts.labelBg};border-color:${opts.labelBg};color:#fff`
    : `color:${opts.labelColor}`;
  const chipClass = opts.alwaysLabel ? 'zmk-label zmk-label-keep' : 'zmk-label';

  return [
    '<div class="zmk">',
    `<img class="zmk-art" src="${opts.src}" alt=""`,
    ` width="${opts.w}" height="${opts.h}"`,
    ` style="width:${opts.w}px;height:${opts.h}px">`,
    `<span class="${chipClass}" style="${chipStyle}">`,
    escapeHtml(opts.label),
    '</span>',
    '</div>',
  ].join('');
}
