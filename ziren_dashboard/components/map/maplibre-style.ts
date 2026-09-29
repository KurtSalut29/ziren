/**
 * The one map style every dashboard map draws from, and the loader that
 * brings MapLibre in.
 *
 * WHY MAPLIBRE, AND WHY THESE TILES
 *
 * The dashboard's maps were Leaflet over raster tiles fetched from CARTO,
 * OpenStreetMap and Esri on every pan. A dispatch console whose map goes blank
 * when someone else's tile server is slow — or rate-limits us, as
 * tile.openstreetmap.org's usage policy allows it to — is a console that
 * fails exactly when it is needed. So the street map now comes from OUR copy
 * of Biliran: the same OpenStreetMap extract the mobile app ships
 * (ziren_mobile/assets/map/biliran.mbtiles), converted to a single PMTiles
 * file in public/map/ and drawn in the browser by MapLibre GL. Labels use
 * fonts served from public/map/fonts, not a glyph server. Nothing in the
 * street map touches a third party.
 *
 * Satellite imagery is the one thing we cannot host: Esri World Imagery,
 * exactly as before. It is drawn OVER the street map rather than instead of
 * it, so if Esri is slow or unreachable the dispatcher sees our street map
 * underneath instead of a grey void, and our own labels are drawn on top of
 * the photography (replacing CARTO's labels layer).
 *
 * The extract covers Biliran and its waters (bounds below). Everything
 * outside is painted as sea — Biliran is an island, so the map reads as one.
 */

import type {
  ExpressionSpecification,
  LayerSpecification,
  StyleSpecification,
} from 'maplibre-gl';

export type Basemap = 'satellite' | 'streets';
type MapLibre = typeof import('maplibre-gl');

/** [lng, lat] — MapLibre's order, the opposite of Leaflet's. */
export const BILIRAN_CENTER: [number, number] = [124.408, 11.583];
export const BILIRAN_ZOOM = 10.6;
/** How far the map may be panned: Biliran with room to breathe. */
export const BILIRAN_MAX_BOUNDS: [[number, number], [number, number]] = [[123.95, 11.25], [124.85, 11.95]];
/** Esri's real imagery over Biliran stops here; past it they send a grey placeholder. */
const SATELLITE_MAX_ZOOM = 18;
export const MAX_ZOOM = 19;

// ── Loader ────────────────────────────────────────────────────────────────

let loader: Promise<MapLibre> | null = null;

/**
 * MapLibre, with the pmtiles:// protocol registered — once per page, however
 * many maps ask. Imported dynamically: it touches `window` at module load and
 * is ~800 KB, which only map screens should pay for.
 */
export function loadMapLibre(): Promise<MapLibre> {
  if (!loader) {
    loader = Promise.all([import('maplibre-gl'), import('pmtiles')]).then(([ml, pm]) => {
      const maplibre = ((ml as unknown as { default?: MapLibre }).default ?? ml) as MapLibre;
      const protocol = new pm.Protocol();
      maplibre.addProtocol('pmtiles', protocol.tile);
      return maplibre;
    });
    loader.catch(() => { loader = null; });
  }
  return loader;
}

// ── Palette ───────────────────────────────────────────────────────────────

interface Palette {
  sea: string;
  land: string;
  wood: string;
  grass: string;
  residential: string;
  park: string;
  building: string;
  buildingLine: string;
  roadCasing: string;
  roadMajor: string;
  roadMinor: string;
  path: string;
  boundary: string;
  text: string;
  textMuted: string;
  halo: string;
  waterText: string;
}

const LIGHT: Palette = {
  sea: '#aad3df',
  land: '#f2efe9',
  wood: '#cfe3c1',
  grass: '#dcebcf',
  residential: '#ebe6dc',
  park: '#c8e3bc',
  building: '#dcd4c6',
  buildingLine: '#c9bfae',
  roadCasing: '#d3c9b8',
  roadMajor: '#fcd69a',
  roadMinor: '#ffffff',
  path: '#b8ab95',
  boundary: '#9c8fb4',
  text: '#2b2b2b',
  textMuted: '#5c5c5c',
  halo: 'rgba(255,255,255,0.92)',
  waterText: '#3f6f86',
};

const DARK: Palette = {
  sea: '#0f2533',
  land: '#1b1d20',
  wood: '#1f2a20',
  grass: '#212a22',
  residential: '#23252a',
  park: '#1e2b20',
  building: '#2c2f35',
  buildingLine: '#3a3e45',
  roadCasing: '#111214',
  roadMajor: '#6b5a3c',
  roadMinor: '#3b3e44',
  path: '#4a4d52',
  boundary: '#7b6f96',
  text: '#e8e6e1',
  textMuted: '#b3b0a8',
  halo: 'rgba(12,12,14,0.9)',
  waterText: '#8fb7cc',
};

// ── Layers ────────────────────────────────────────────────────────────────

const SRC = 'biliran';
const OUTSIDE = 'outside-extract';

/** The extract's own bounds (biliran.mbtiles metadata): inside is real data. */
const EXTRACT: [number, number, number, number] = [124.2, 11.4, 124.7, 11.86];
const REGULAR = ['Noto Sans Regular'];
const MEDIUM = ['Noto Sans Medium'];
const ITALIC = ['Noto Sans Italic'];

/** Every label is the Latin-script name: the only glyph ranges we host. */
const NAME: ExpressionSpecification = ['coalesce', ['get', 'name:latin'], ['get', 'name']];

const MAJOR = ['motorway', 'trunk', 'primary', 'secondary'];
const MID = ['tertiary', 'minor'];

/** Road width by zoom, so a highway reads as one from the island view down to a street. */
function roadWidth(base: number, extra = 0): ExpressionSpecification {
  return ['interpolate', ['exponential', 1.5], ['zoom'], 10, base * 0.4 + extra, 14, base * 2 + extra, 18, base * 9 + extra];
}

/** Filling layers: land, water, the shapes of things. Shared by both basemaps. */
function baseLayers(p: Palette): LayerSpecification[] {
  return [
    // Land is the background: OpenMapTiles has no land polygons, only water
    // (the sea included), so land is simply "wherever there is no water".
    { id: 'background', type: 'background', paint: { 'background-color': p.land } },
    // …which would make everything OUTSIDE the extract land too. This paints
    // the world beyond the extract's bounds as sea, so Biliran reads as the
    // island it is instead of sitting in an endless beige continent.
    { id: 'outside', type: 'fill', source: OUTSIDE, paint: { 'fill-color': p.sea } },
    {
      id: 'landcover-wood', type: 'fill', source: SRC, 'source-layer': 'landcover',
      filter: ['in', ['get', 'class'], ['literal', ['wood', 'forest']]],
      paint: { 'fill-color': p.wood, 'fill-opacity': 0.8 },
    },
    {
      id: 'landcover-grass', type: 'fill', source: SRC, 'source-layer': 'landcover',
      filter: ['in', ['get', 'class'], ['literal', ['grass', 'farmland', 'scrub', 'wetland']]],
      paint: { 'fill-color': p.grass, 'fill-opacity': 0.8 },
    },
    {
      id: 'landuse-residential', type: 'fill', source: SRC, 'source-layer': 'landuse',
      filter: ['in', ['get', 'class'], ['literal', ['residential', 'suburb', 'neighbourhood', 'commercial', 'retail', 'industrial']]],
      paint: { 'fill-color': p.residential, 'fill-opacity': 0.9 },
    },
    {
      id: 'landuse-other', type: 'fill', source: SRC, 'source-layer': 'landuse',
      filter: ['!', ['in', ['get', 'class'], ['literal', ['residential', 'suburb', 'neighbourhood', 'commercial', 'retail', 'industrial']]]],
      paint: { 'fill-color': p.park, 'fill-opacity': 0.45 },
    },
    { id: 'park', type: 'fill', source: SRC, 'source-layer': 'park', paint: { 'fill-color': p.park, 'fill-opacity': 0.7 } },
    { id: 'water', type: 'fill', source: SRC, 'source-layer': 'water', paint: { 'fill-color': p.sea } },
    {
      id: 'waterway', type: 'line', source: SRC, 'source-layer': 'waterway',
      paint: { 'line-color': p.sea, 'line-width': ['interpolate', ['linear'], ['zoom'], 10, 0.6, 16, 3] },
    },
    {
      id: 'aeroway', type: 'fill', source: SRC, 'source-layer': 'aeroway',
      filter: ['==', ['geometry-type'], 'Polygon'],
      paint: { 'fill-color': p.residential, 'fill-opacity': 0.9 },
    },
    {
      id: 'building', type: 'fill', source: SRC, 'source-layer': 'building', minzoom: 14,
      paint: { 'fill-color': p.building, 'fill-outline-color': p.buildingLine },
    },
  ];
}

/** Roads, drawn casing-then-fill so junctions merge cleanly. */
function roadLayers(p: Palette, opacity = 1): LayerSpecification[] {
  const line = (id: string, classes: string[], color: string, base: number, casing = false): LayerSpecification => ({
    id, type: 'line', source: SRC, 'source-layer': 'transportation',
    filter: ['all', ['==', ['geometry-type'], 'LineString'], ['in', ['get', 'class'], ['literal', classes]]],
    layout: { 'line-cap': 'round', 'line-join': 'round' },
    paint: {
      'line-color': color,
      // The casing is the same line 1.5px wider, drawn first.
      'line-width': roadWidth(base, casing ? 1.5 : 0),
      'line-opacity': opacity,
    },
  });
  return [
    {
      id: 'road-path', type: 'line', source: SRC, 'source-layer': 'transportation', minzoom: 13,
      filter: ['in', ['get', 'class'], ['literal', ['path', 'track']]],
      paint: { 'line-color': p.path, 'line-width': 1, 'line-dasharray': [2, 1.5], 'line-opacity': opacity },
    },
    line('road-minor-casing', ['service', ...MID], p.roadCasing, 1.1, true),
    line('road-major-casing', MAJOR, p.roadCasing, 1.7, true),
    line('road-minor', ['service', ...MID], p.roadMinor, 1.1),
    line('road-major', MAJOR, p.roadMajor, 1.7),
    {
      id: 'boundary', type: 'line', source: SRC, 'source-layer': 'boundary',
      filter: ['all', ['<=', ['get', 'admin_level'], 8], ['!=', ['get', 'maritime'], 1]],
      paint: { 'line-color': p.boundary, 'line-width': 1, 'line-dasharray': [3, 2], 'line-opacity': 0.7 * opacity },
    },
  ];
}

/** Landmarks a dispatcher sends a crew by — seen from furthest out. */
export const POI_EMERGENCY = ['hospital', 'doctors', 'police', 'fire_station', 'town_hall', 'ferry_terminal'];
/**
 * A landmark's name, or, when OpenStreetMap has none, what it is
 * ("Police Station", "Basketball Court"), so no icon is ever drawn bare.
 */
const POI_LABEL: ExpressionSpecification = ['coalesce', ['get', 'name:latin'], ['get', 'name'],
  ['match', ['get', 'subclass'],
    'basketball', 'Basketball Court', 'multi', 'Multi-purpose Court', 'volleyball', 'Volleyball Court', 'tennis', 'Tennis Court',
    'athletics', 'Track Oval', 'swimming_pool', 'Swimming Pool', 'community_centre', 'Barangay Hall', 'grave_yard', 'Cemetery',
    'viewpoint', 'Viewpoint', 'government', 'Government Office', 'food_court', 'Food Court', 'artwork', 'Monument',
    'convenience', 'Store', 'general', 'Store', 'confectionery', 'Bakery',
    ['match', ['get', 'class'],
      'hospital', 'Hospital', 'doctors', 'Health Center', 'police', 'Police Station', 'fire_station', 'Fire Station',
      'town_hall', 'Town Hall', 'ferry_terminal', 'Port', 'pitch', 'Court', 'basketball', 'Basketball Court',
      'multi', 'Multi-purpose Court', 'athletics', 'Track Oval', 'running', 'Track Oval', 'sports_centre', 'Sports Center',
      'swimming_pool', 'Swimming Pool', 'cemetery', 'Cemetery', 'place_of_worship', 'Church', 'shelter', 'Shelter',
      'gate', 'Gate', 'park', 'Park', 'playground', 'Playground', 'picnic_site', 'Picnic Area',
      'campsite', 'Campsite', 'attraction', 'Tourist Spot', 'school', 'School', 'library', 'Library',
      'post', 'Post Office', 'office', 'Office', 'restaurant', 'Restaurant', 'cafe', 'Cafe',
      'fast_food', 'Eatery', 'bakery', 'Bakery', 'shop', 'Store', 'clothing_store', 'Clothing Store',
      'pharmacy', 'Pharmacy', 'bank', 'Bank', 'atm', 'ATM', 'fuel', 'Gas Station',
      'lodging', 'Lodging', 'parking', 'Parking', 'toilets', 'Restroom', 'reservoir', 'Reservoir',
      'art_gallery', 'Monument',
      'Landmark'],
  ]];

/** Public places people give directions by. */
const POI_CIVIC = [
  'school', 'college', 'kindergarten', 'university', 'place_of_worship', 'post', 'library', 'office',
  'cemetery', 'information', 'shelter', 'bus', 'fuel', 'bank', 'atm', 'pharmacy',
];

/** OpenMapTiles poi class → sprite icon (scripts/make-map-assets.mjs). */
const POI_ICON: ExpressionSpecification = [
  'match', ['get', 'class'],
  'hospital', 'poi-hospital',
  'doctors', 'poi-doctors',
  'police', 'poi-police',
  'fire_station', 'poi-fire_station',
  'town_hall', 'poi-town_hall',
  'ferry_terminal', 'poi-ferry',
  ['school', 'college', 'kindergarten', 'university'], 'poi-school',
  'place_of_worship', 'poi-worship',
  'post', 'poi-post',
  'library', 'poi-library',
  'office', 'poi-office',
  'cemetery', 'poi-cemetery',
  'information', 'poi-info',
  'shelter', 'poi-shelter',
  'bus', 'poi-bus',
  'fuel', 'poi-fuel',
  ['bank', 'atm'], 'poi-bank',
  'pharmacy', 'poi-pharmacy',
  ['shop', 'grocery', 'clothing_store', 'multi', 'hardware', 'convenience', 'mobile_phone', 'furniture'], 'poi-shop',
  ['fast_food', 'restaurant', 'bakery', 'bar', 'beer', 'ice_cream'], 'poi-food',
  'cafe', 'poi-cafe',
  'lodging', 'poi-lodging',
  ['attraction', 'castle', 'art_gallery', 'museum', 'monument'], 'poi-attraction',
  ['park', 'campsite', 'garden', 'playground'], 'poi-park',
  ['pitch', 'sports_centre', 'swimming_pool', 'basketball', 'stadium'], 'poi-sports',
  'poi-generic',
];

function poiLayer(
  id: string,
  filter: ExpressionSpecification,
  minzoom: number,
  p: Palette,
  emergency: boolean,
): LayerSpecification {
  return {
    // Every landmark carries a label: its name, or what it is (POI_LABEL).
    id, type: 'symbol', source: SRC, 'source-layer': 'poi', minzoom, filter,
    layout: {
      'icon-image': POI_ICON,
      'icon-size': emergency ? ['interpolate', ['linear'], ['zoom'], 11.5, 0.75, 15, 1] : 1,
      // A hospital or fire station is always drawn, never dropped because
      // something else sits on the same spot. There are only ~20; place
      // names step around them (see the place layers' variable anchors).
      'icon-allow-overlap': emergency,
      // The name shows whenever the icon does, and looks for room on any
      // side of it before giving up. An ordinary landmark whose name finds no
      // room is dropped whole — never an icon with no name. An emergency
      // facility always keeps its icon (icon-allow-overlap), name or not.
      'text-field': POI_LABEL,
      'text-font': emergency ? MEDIUM : REGULAR,
      'text-size': emergency ? 11.5 : 10.5,
      'text-variable-anchor': ['top', 'bottom', 'right', 'left'],
      'text-radial-offset': emergency ? 1.1 : 0.9,
      'text-justify': 'auto',
      'text-max-width': 9,
      'text-optional': emergency,
    },
    paint: {
      'text-color': emergency ? p.text : p.textMuted,
      'text-halo-color': p.halo,
      'text-halo-width': 1.4,
    },
  };
}

/** Names: water, roads, places, and the points a dispatcher navigates by. */
function labelLayers(p: Palette): LayerSpecification[] {
  return [
    {
      id: 'water-name', type: 'symbol', source: SRC, 'source-layer': 'water_name',
      layout: { 'text-field': NAME, 'text-font': ITALIC, 'text-size': 12 },
      paint: { 'text-color': p.waterText, 'text-halo-color': p.halo, 'text-halo-width': 1.2 },
    },
    {
      id: 'road-name', type: 'symbol', source: SRC, 'source-layer': 'transportation_name', minzoom: 13,
      layout: {
        'symbol-placement': 'line', 'text-field': NAME, 'text-font': REGULAR,
        'text-size': ['interpolate', ['linear'], ['zoom'], 13, 10, 17, 13],
        'text-max-angle': 30,
      },
      paint: { 'text-color': p.textMuted, 'text-halo-color': p.halo, 'text-halo-width': 1.5 },
    },
    // Every landmark in the extract, with its icon (public/map/sprite, made by
    // scripts/make-map-assets.mjs). Three layers by how soon they appear:
    // emergency facilities from the district view, civic ones (schools,
    // churches, offices) from the town view, the rest from the street view.
    // Drawn in reverse priority: MapLibre places the LAST layer's symbols
    // first, so a hospital wins a collision with a sari-sari store.
    // Unnamed courts, chapels, sheds: labelled by what they are ("Basketball
    // Court"), street view only, and first to give way in a collision.
    poiLayer('poi-unnamed', ['all', ['!', ['has', 'name']], ['!', ['in', ['get', 'class'], ['literal', POI_EMERGENCY]]]], 16, p, false),
    poiLayer('poi-other', ['all', ['has', 'name'], ['!', ['in', ['get', 'class'], ['literal', [...POI_EMERGENCY, ...POI_CIVIC]]]]], 15.5, p, false),
    poiLayer('poi-civic', ['all', ['has', 'name'], ['in', ['get', 'class'], ['literal', POI_CIVIC]]], 14, p, false),
    {
      id: 'place-small', type: 'symbol', source: SRC, 'source-layer': 'place', minzoom: 12,
      filter: ['in', ['get', 'class'], ['literal', ['village', 'hamlet', 'suburb', 'neighbourhood', 'isolated_dwelling']]],
      layout: { 'text-variable-anchor': ['center', 'top', 'bottom', 'left', 'right'], 'text-radial-offset': 0.9, 'text-field': NAME, 'text-font': REGULAR, 'text-size': ['interpolate', ['linear'], ['zoom'], 12, 10.5, 16, 13], 'text-max-width': 8 },
      paint: { 'text-color': p.text, 'text-halo-color': p.halo, 'text-halo-width': 1.5 },
    },
    {
      id: 'place-town', type: 'symbol', source: SRC, 'source-layer': 'place',
      filter: ['in', ['get', 'class'], ['literal', ['city', 'town']]],
      layout: { 'text-variable-anchor': ['center', 'top', 'bottom', 'left', 'right'], 'text-radial-offset': 0.9, 'text-field': NAME, 'text-font': MEDIUM, 'text-size': ['interpolate', ['linear'], ['zoom'], 9, 12, 14, 17], 'text-max-width': 8 },
      paint: { 'text-color': p.text, 'text-halo-color': p.halo, 'text-halo-width': 1.8 },
    },
    // Last, so it is PLACED first: town names then move around these
    // icons (text-variable-anchor) instead of sitting on top of them.
    poiLayer('poi-emergency', ['in', ['get', 'class'], ['literal', POI_EMERGENCY]], 11.5, p, true),
  ];
}

/**
 * The full style for one basemap and theme.
 *
 * `origin` is the page's own origin: tile and font URLs must be absolute for
 * MapLibre's workers, which do not resolve a path against the page.
 */
export function buildMapStyle(kind: Basemap, dark: boolean, origin: string): StyleSpecification {
  const p = kind === 'satellite' ? LIGHT : dark ? DARK : LIGHT;
  const onPhoto: Palette = { ...LIGHT, text: '#ffffff', textMuted: '#f1f1f1', halo: 'rgba(0,0,0,0.75)', waterText: '#dbeef7' };

  const layers: LayerSpecification[] = kind === 'streets'
    ? [...baseLayers(p), ...roadLayers(p), ...labelLayers(p)]
    : [
        // Our street map first, then the photography over it: if Esri does not
        // answer, the dispatcher still has a map. Then faint roads and our own
        // labels over the photo.
        ...baseLayers(LIGHT),
        ...roadLayers(LIGHT),
        { id: 'satellite', type: 'raster', source: 'satellite' },
        ...roadLayers(LIGHT, 0.35).map(l => ({ ...l, id: `photo-${l.id}` }) as LayerSpecification),
        ...labelLayers(onPhoto),
      ];

  return {
    version: 8,
    name: `Ziren ${kind}${dark ? ' dark' : ''}`,
    glyphs: `${origin}/map/fonts/{fontstack}/{range}.pbf`,
    sprite: `${origin}/map/sprite`,
    sources: {
      [OUTSIDE]: {
        type: 'geojson',
        data: {
          type: 'Feature',
          properties: {},
          geometry: {
            type: 'Polygon',
            // The world, with the extract cut out of it (hole wound the other way).
            coordinates: [
              [[-180, -85], [180, -85], [180, 85], [-180, 85], [-180, -85]],
              [[EXTRACT[0], EXTRACT[1]], [EXTRACT[0], EXTRACT[3]], [EXTRACT[2], EXTRACT[3]], [EXTRACT[2], EXTRACT[1]], [EXTRACT[0], EXTRACT[1]]],
            ],
          },
        },
      },
      [SRC]: {
        type: 'vector',
        url: `pmtiles://${origin}/map/biliran.pmtiles`,
        attribution: '© <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noreferrer">OpenStreetMap</a> contributors · © OpenMapTiles',
      },
      ...(kind === 'satellite'
        ? {
            satellite: {
              type: 'raster' as const,
              tiles: ['https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'],
              tileSize: 256,
              maxzoom: SATELLITE_MAX_ZOOM,
              attribution: 'Imagery © Esri, Maxar, Earthstar Geographics',
            },
          }
        : {}),
    },
    layers,
  };
}

/** The page's current theme, read off <html class="dark">. */
export function isDarkTheme(): boolean {
  return typeof document !== 'undefined' && document.documentElement.classList.contains('dark');
}
