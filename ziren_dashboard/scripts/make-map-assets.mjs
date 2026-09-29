/**
 * make-map-assets.mjs — the landmark icons and the landmark search index,
 * generated from the same Biliran extract every Ziren map draws.
 *
 *   node scripts/make-map-assets.mjs
 *
 * Writes:
 *   public/map/sprite.json, sprite.png, sprite@2x.png      (dashboard)
 *   ../ziren_mobile/assets/map/sprite/sprite*.{json,png}    (mobile, served by
 *                                                           OfflineMapService)
 *   public/map/places.json                                  (search index)
 *   ../ziren_mobile/assets/map/places.json                  (same, for the app)
 *   ../ziren_mobile/assets/map/unnamed_landmarks.json       (app only: courts,
 *                                                           halls … with no name)
 *
 * WHY A GENERATED SPRITE
 *
 * A MapLibre style names its icons from a "sprite" — one PNG sheet and a JSON
 * table of where each icon sits. The public sprites belong to someone else's
 * server, which is exactly the dependency the self-hosted map removed. So the
 * icons are drawn here from Lucide glyphs (ISC licence, the icon set the
 * dashboard already uses) and rasterised with sharp.
 *
 * Two tiers, by what a dispatcher needs first:
 *   emergency — hospital, doctors, police, fire station, town hall, ferry
 *               terminal: a dark rounded square, seen from further out.
 *   everything else — a small white circle with a grey glyph.
 * Deliberately neutral colours: on this console red means critical severity
 * and the agency hues mean BFP/PNP/MDRRMO; a landmark must not borrow either.
 *
 * `sharp` resolves out of Next.js's own dependencies — see make-logo-assets.mjs.
 */

import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { DatabaseSync } from 'node:sqlite';
import { gunzipSync } from 'node:zlib';
import sharp from 'sharp';
import { VectorTile } from '@mapbox/vector-tile';
import Pbf from 'pbf';

const HERE = dirname(fileURLToPath(import.meta.url));
const DASH = resolve(HERE, '..');
const MOBILE = resolve(DASH, '..', 'ziren_mobile');
const MBTILES = resolve(MOBILE, 'assets', 'map', 'biliran.mbtiles');

/** Icon name → [lucide glyph, tier]. The style maps OpenMapTiles poi classes onto these. */
const ICONS = {
  hospital: ['hospital', 'emergency'],
  doctors: ['stethoscope', 'emergency'],
  police: ['shield', 'emergency'],
  fire_station: ['flame', 'emergency'],
  town_hall: ['landmark', 'emergency'],
  ferry: ['ship', 'emergency'],
  school: ['graduation-cap', 'civic'],
  worship: ['church', 'civic'],
  post: ['mail', 'civic'],
  library: ['book-open', 'civic'],
  office: ['building-2', 'civic'],
  cemetery: ['cross', 'civic'],
  info: ['info', 'civic'],
  shelter: ['tent', 'civic'],
  bus: ['bus', 'civic'],
  fuel: ['fuel', 'civic'],
  bank: ['banknote', 'civic'],
  pharmacy: ['pill', 'civic'],
  shop: ['shopping-bag', 'civic'],
  food: ['utensils', 'civic'],
  cafe: ['coffee', 'civic'],
  lodging: ['bed', 'civic'],
  attraction: ['castle', 'civic'],
  park: ['trees', 'civic'],
  sports: ['trophy', 'civic'],
  generic: ['map-pin', 'civic'],
};

async function lucideSvg(name) {
  const src = await readFile(resolve(DASH, 'node_modules', 'lucide-react', 'dist', 'esm', 'icons', `${name}.mjs`), 'utf8');
  const node = src.slice(src.indexOf('const __iconNode = ') + 'const __iconNode = '.length, src.indexOf('];\nconst') + 1);
  // The icon node is plain JS data: [tag, {attrs}] pairs. Evaluated as data.
  const parts = Function(`return ${node}`)();
  return parts.map(([tag, attrs]) => {
    const a = Object.entries(attrs).filter(([k]) => k !== 'key').map(([k, v]) => `${k}="${v}"`).join(' ');
    return `<${tag} ${a}/>`;
  }).join('');
}

function badgeSvg(glyph, tier, px) {
  if (tier === 'emergency') {
    const s = 26 * px;
    return `<svg xmlns="http://www.w3.org/2000/svg" width="${s}" height="${s}" viewBox="0 0 26 26">
      <rect x="1" y="1" width="24" height="24" rx="7" fill="#2b2f36" stroke="#ffffff" stroke-width="2"/>
      <g transform="translate(5 5) scale(0.6667)" fill="none" stroke="#ffffff" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round">${glyph}</g>
    </svg>`;
  }
  const s = 20 * px;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${s}" height="${s}" viewBox="0 0 20 20">
    <circle cx="10" cy="10" r="9" fill="#ffffff" stroke="#8a8f98" stroke-width="1.2"/>
    <g transform="translate(4.5 4.5) scale(0.4583)" fill="none" stroke="#4b5563" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round">${glyph}</g>
  </svg>`;
}

/**
 * The two pin shapes the mobile app draws its own marks with (`circle-15` for
 * incidents, `marker-15` for a destination) — names from the public Maki set
 * the app was written against, which no Ziren style ever carried, so those
 * pins drew nothing. Signed-distance-field icons ("sdf": true), so the app's
 * per-pin `iconColor` (severity colours) actually tints them.
 */
const SDF_ICONS = { 'circle-15': 'circle', 'marker-15': 'marker' };

/** Signed distance (units, + outside) from p to a convex polygon. */
function polygonDistance(px, py, pts) {
  let inside = true;
  let best = Infinity;
  for (let i = 0; i < pts.length; i++) {
    const [ax, ay] = pts[i];
    const [bx, by] = pts[(i + 1) % pts.length];
    const ex = bx - ax, ey = by - ay;
    const t = Math.max(0, Math.min(1, ((px - ax) * ex + (py - ay) * ey) / (ex * ex + ey * ey)));
    best = Math.min(best, Math.hypot(px - ax - t * ex, py - ay - t * ey));
    if (ex * (py - ay) - ey * (px - ax) < 0) inside = false;
  }
  return inside ? -best : best;
}

function shapeDistance(shape, x, y) {
  if (shape === 'circle') return Math.hypot(x - 7.5, y - 7.5) - 5.5;
  // A map pin: round head over a point, tip at the bottom centre.
  const head = Math.hypot(x - 7.5, y - 5.6) - 4.9;
  const point = polygonDistance(x, y, [[3.2, 7.6], [11.8, 7.6], [7.5, 14.6]]);
  return Math.min(head, point);
}

async function sdfPng(shape, px) {
  const buffer = 3; // units of SDF falloff around the 15-unit shape
  const size = (15 + 2 * buffer) * px;
  const raw = Buffer.alloc(size * size * 4);
  for (let j = 0; j < size; j++) {
    for (let i = 0; i < size; i++) {
      const d = shapeDistance(shape, (i + 0.5) / px - buffer, (j + 0.5) / px - buffer) * px;
      // MapLibre's SDF convention (TinySDF): 0.75 at the edge, falling 1/8 per pixel outward.
      const a = Math.round(255 * Math.max(0, Math.min(1, 0.75 - d / 8)));
      raw.set([255, 255, 255, a], (j * size + i) * 4);
    }
  }
  return sharp(raw, { raw: { width: size, height: size, channels: 4 } }).png().toBuffer();
}

async function buildSprite(px) {
  const entries = [];
  let x = 0;
  let height = 0;
  const images = [];
  for (const [name, [glyphName, tier]] of Object.entries(ICONS)) {
    const png = await sharp(Buffer.from(badgeSvg(await lucideSvg(glyphName), tier, px))).png().toBuffer();
    const meta = await sharp(png).metadata();
    images.push({ input: png, left: x, top: 0 });
    entries.push([`poi-${name}`, { x, y: 0, width: meta.width, height: meta.height, pixelRatio: px }]);
    x += meta.width + 2 * px;
    height = Math.max(height, meta.height);
  }
  for (const [name, shape] of Object.entries(SDF_ICONS)) {
    const png = await sdfPng(shape, px);
    const meta = await sharp(png).metadata();
    images.push({ input: png, left: x, top: 0 });
    entries.push([name, { x, y: 0, width: meta.width, height: meta.height, pixelRatio: px, sdf: true }]);
    x += meta.width + 2 * px;
    height = Math.max(height, meta.height);
  }
  const sheet = await sharp({ create: { width: x, height, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } } })
    .composite(images).png().toBuffer();
  return { json: Object.fromEntries(entries), png: sheet };
}

async function writeSprites() {
  const outs = [resolve(DASH, 'public', 'map'), resolve(MOBILE, 'assets', 'map', 'sprite')];
  for (const px of [1, 2]) {
    const { json, png } = await buildSprite(px);
    const suffix = px === 2 ? '@2x' : '';
    for (const dir of outs) {
      await mkdir(dir, { recursive: true });
      await writeFile(resolve(dir, `sprite${suffix}.json`), JSON.stringify(json));
      await writeFile(resolve(dir, `sprite${suffix}.png`), png);
    }
  }
  console.log(`sprite: ${Object.keys(ICONS).length + Object.keys(SDF_ICONS).length} icons ->`, outs.join(', '));
}

/**
 * Every named landmark and place in the extract, for the map's search box:
 * name, kind, and where. Read at zoom 14, where the extract carries every
 * POI; a place (town, barangay) is taken at its own label point.
 */
async function writePlaces() {
  const db = new DatabaseSync(MBTILES, { readOnly: true });
  const rows = db.prepare('SELECT tile_column AS x, tile_row AS row, tile_data AS data FROM tiles WHERE zoom_level = 14').all();
  const seen = new Map();
  const unnamed = new Map();
  for (const { x, row, data } of rows) {
    const y = (1 << 14) - 1 - row;
    const tile = new VectorTile(new Pbf(gunzipSync(Buffer.from(data))));
    for (const [layerName, kind] of [['poi', 'poi'], ['place', 'place']]) {
      const layer = tile.layers[layerName];
      if (!layer) continue;
      for (let i = 0; i < layer.length; i++) {
        const f = layer.feature(i);
        const p = f.properties;
        const name = p['name:latin'] || p.name;
        const g = f.toGeoJSON(x, y, 14).geometry;
        const [lng, lat] = g.type === 'Point' ? g.coordinates : g.coordinates[0];
        if (!name) {
          // A landmark nobody named still marks the spot: the map labels it by
          // what it is (maplibre-style.ts POI_LABEL), and so does the app.
          const label = kind === 'poi' ? unnamedLabel(p) : null;
          if (label) {
            const key = `${label}|${lat.toFixed(5)}|${lng.toFixed(5)}`;
            if (!unnamed.has(key)) unnamed.set(key, { n: label, c: String(p.class), lat: +lat.toFixed(6), lng: +lng.toFixed(6) });
          }
          continue;
        }
        const cls = String(p.class ?? kind);
        const key = `${name}|${cls}`;
        if (!seen.has(key)) seen.set(key, { n: name, c: cls, k: kind, lat: +lat.toFixed(6), lng: +lng.toFixed(6) });
      }
    }
  }
  const places = [...seen.values()].sort((a, b) => a.n.localeCompare(b.n));
  await writeFile(resolve(DASH, 'public', 'map', 'places.json'), JSON.stringify(places));
  // The app reads the same list offline: nearest landmark to a report, and
  // place search when a resident puts an incident somewhere else on the map.
  await writeFile(resolve(MOBILE, 'assets', 'map', 'places.json'), JSON.stringify(places));
  console.log(`places: ${places.length} named landmarks and places`);
  // Only the app wants these: the landmark nearest a report may be the
  // basketball court across the road, which has no name. Kept out of
  // places.json so place search is not flooded with "Store".
  const nameless = [...unnamed.values()].sort((a, b) => a.lat - b.lat || a.lng - b.lng);
  await writeFile(resolve(MOBILE, 'assets', 'map', 'unnamed_landmarks.json'), JSON.stringify(nameless));
  console.log(`unnamed landmarks: ${nameless.length}`);
}

/** Same generic words as POI_LABEL in components/map/maplibre-style.ts. */
const UNNAMED_BY_SUBCLASS = {
  basketball: 'Basketball Court', multi: 'Multi-purpose Court', volleyball: 'Volleyball Court', tennis: 'Tennis Court',
  athletics: 'Track Oval', swimming_pool: 'Swimming Pool', community_centre: 'Barangay Hall', grave_yard: 'Cemetery',
  viewpoint: 'Viewpoint', government: 'Government Office', food_court: 'Food Court', artwork: 'Monument',
  convenience: 'Store', general: 'Store', confectionery: 'Bakery',
};
const UNNAMED_BY_CLASS = {
  hospital: 'Hospital', doctors: 'Health Center', police: 'Police Station', fire_station: 'Fire Station',
  town_hall: 'Town Hall', ferry_terminal: 'Port', pitch: 'Court', basketball: 'Basketball Court',
  multi: 'Multi-purpose Court', athletics: 'Track Oval', running: 'Track Oval', sports_centre: 'Sports Center',
  swimming_pool: 'Swimming Pool', cemetery: 'Cemetery', place_of_worship: 'Church', shelter: 'Shelter',
  gate: 'Gate', park: 'Park', playground: 'Playground', picnic_site: 'Picnic Area',
  campsite: 'Campsite', attraction: 'Tourist Spot', school: 'School', library: 'Library',
  post: 'Post Office', office: 'Office', restaurant: 'Restaurant', cafe: 'Cafe',
  fast_food: 'Eatery', bakery: 'Bakery', shop: 'Store', clothing_store: 'Clothing Store',
  pharmacy: 'Pharmacy', bank: 'Bank', atm: 'ATM', fuel: 'Gas Station',
  lodging: 'Lodging', art_gallery: 'Monument',
};
function unnamedLabel(p) {
  return UNNAMED_BY_SUBCLASS[p.subclass] ?? UNNAMED_BY_CLASS[p.class] ?? null;
}

await writeSprites();
await writePlaces();
