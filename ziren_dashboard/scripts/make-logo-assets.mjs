/**
 * Build every Ziren logo asset from the single authored source, zirenlogo.png.
 *
 *   node scripts/make-logo-assets.mjs        (from ziren_dashboard/)
 *
 * WHY THIS EXISTS
 *
 * The authored artwork is a 1254x1254 PNG with no alpha channel: a near-black
 * "ZR" monogram and "ZIREN" wordmark, with one shape in brand orange, sitting
 * on a near-white field. Shipping that file directly fails three ways:
 *
 *   1. The white is opaque, so the mark carries a white card everywhere it is
 *      placed. On the dark sidebar that is a bright rectangle, not a logo.
 *   2. The ink is #101010. On the dark theme's #0A0A0A surface that is an
 *      invisible smudge — 1.05:1.
 *   3. The ink occupies 727x610 of a 1254x1254 canvas. Rendered with
 *      object-fit:contain into a 32px box, the mark is ~19px with 40% of the
 *      box spent on margin the artwork brought with it.
 *
 * The dashboard already had a workaround for (2): `dark:brightness-0
 * dark:invert`, which flattens the mark to solid black and then flips it to
 * solid white. That was correct for the OLD logo, which was monochrome. This
 * one is not — brightness-0 destroys the orange, and the two-colour mark
 * becomes a white silhouette. So the recolouring has to happen per pixel, at
 * build time, with knowledge of which pixels are neutral and which are brand.
 *
 * WHAT IT DOES
 *
 * White knock-out: alpha = 1 - min(r,g,b)/255, then the colour is
 * unpremultiplied back off white. Using the MINIMUM channel rather than
 * luminance is what saves the orange: #FC5A05 has a blue channel of 5, so it
 * reads as ~98% opaque instead of the ~55% a luminance test would give it.
 * Unpremultiplying then recovers the authored hue exactly rather than a washed
 * version of it. Alpha is stretched so the near-white field (253-255) lands on
 * a true 0 and solid ink on a true 1; antialiased edges keep their ramp.
 *
 * Dark-mode recolour: ONLY the neutral ink is flipped, from #1A1A1A to
 * #FAFAFA. The orange is left exactly as authored, because it already clears
 * the 3:1 WCAG bar for graphical objects against both grounds — 3.05:1 on the
 * light #FAFAFA and 6.22:1 on the dark #0A0A0A. Flipping it too would produce
 * a logo in the wrong brand colour to solve a contrast problem it does not
 * have. Pixels are classified by HSV saturation and BLENDED across the
 * boundary, so the antialiased seam where black meets orange stays smooth
 * instead of turning into a stair-stepped edge.
 *
 * Two crops, because the lockup and the mark have different jobs:
 *   - the full lockup keeps the wordmark, for auth screens and splashes where
 *     it is read at 100px or more;
 *   - the mark drops it, for the 24-32px sidebar square and the favicon, where
 *     "ZIREN" set 60px wide is illegible noise that costs the monogram half
 *     its height.
 *
 * Sources: zirenlogo.png at the repo root. Outputs are committed, so this
 * script only needs re-running when the artwork changes.
 *
 * `sharp` is not declared in package.json — it resolves out of Next.js's own
 * dependency tree, which is where the image optimiser gets it. That is fine
 * while it holds and is worth knowing when it stops: if a future Next release
 * drops it, this script fails at the import with a module-not-found and the
 * fix is `npm i -D sharp`, not a code change. It is deliberately NOT a
 * runtime dependency — nothing the dashboard serves uses it.
 */

import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, '..', '..');
const SOURCE = resolve(REPO, 'zirenlogo.png');

const DASHBOARD_PUBLIC = resolve(REPO, 'ziren_dashboard', 'public');
const MOBILE_IMAGES = resolve(REPO, 'ziren_mobile', 'assets', 'images');
const ANDROID_RES = resolve(REPO, 'ziren_mobile', 'android', 'app', 'src', 'main', 'res');

/**
 * Android launcher densities. Standard adaptive-icon-less sizes.
 *
 * There is no drawable-night companion for the splash mark on purpose:
 * values-night/styles.xml deliberately keeps the LaunchTheme light even when
 * the device is dark, so that the recents thumbnail stays white. A dark-ink
 * variant would only ever render on a light ground.
 */
const LAUNCHER_DENSITIES = [
  ['mipmap-mdpi', 48], ['mipmap-hdpi', 72], ['mipmap-xhdpi', 96],
  ['mipmap-xxhdpi', 144], ['mipmap-xxxhdpi', 192],
];

/** Neutral ink on a light ground. Matches --color-text-primary. */
const INK_LIGHT = [0x1a, 0x1a, 0x1a];
/** Neutral ink on a dark ground. Matches --color-text-primary in .dark. */
const INK_DARK = [0xfa, 0xfa, 0xfa];

/**
 * The alpha a fully-inked pixel produces under the min-channel rule.
 * The artwork's solid black is #101010, so 1 - 16/255. Everything is divided
 * through by this so solid ink lands on a true 1.0 rather than 0.937 — without
 * it, a solid black mark would let 6% of the background through.
 */
const INK_ALPHA = 1 - 16 / 255;
/** The alpha the near-white field produces. Anything under this is background. */
const FIELD_ALPHA = 2 / 255;

/**
 * Where a pixel stops being neutral ink and starts being brand orange.
 *
 * Measured as the channel spread (max - min) of the ORIGINAL pixel, divided by
 * its alpha so a half-covered orange edge scores the same as a solid one.
 *
 * The obvious test — HSV saturation of the unpremultiplied colour — is wrong
 * here, and wrong in a way that looks like a rendering fault rather than a
 * classification one. Unpremultiplying a near-black pixel divides tiny channel
 * differences by a number close to 1 and then measures them against a maximum
 * close to 0: a source pixel of (20,18,25), which is black with a few units of
 * encoder noise, comes out as (2,0,8) and scores a saturation of 1.0. Every
 * such pixel was classified as brand and left black — so the dark-mode mark
 * rendered as white ink shot through with black speckle.
 *
 * SPREAD_FLOOR is the second half of the guard. Near the outer edge of the
 * mark, alpha is ~0.03 and dividing by it amplifies two units of noise into a
 * spread of 100. The floor rejects those on the absolute spread before the
 * division ever happens.
 */
const SPREAD_NEUTRAL = 60;
const SPREAD_BRAND = 140;
const SPREAD_FLOOR = 12;

const clamp01 = (v) => (v < 0 ? 0 : v > 1 ? 1 : v);

/**
 * Knock the white field out to transparency and, optionally, recolour the
 * neutral ink for a dark ground. Returns a raw RGBA buffer.
 */
function knockOut(data, width, height, ink) {
  const out = Buffer.alloc(width * height * 4);
  for (let i = 0; i < width * height; i++) {
    const s = i * 4;
    const r = data[s], g = data[s + 1], b = data[s + 2];

    const rawAlpha = 1 - Math.min(r, g, b) / 255;
    const alpha = clamp01((rawAlpha - FIELD_ALPHA) / (INK_ALPHA - FIELD_ALPHA));

    if (alpha <= 0) {
      // Fully transparent. Zero the colour too: a stray colour under alpha 0
      // survives some resamplers as a fringe.
      out[s] = out[s + 1] = out[s + 2] = out[s + 3] = 0;
      continue;
    }

    // Unpremultiply off white to recover the authored ink colour.
    const un = (c) => clamp01((c / 255 - (1 - rawAlpha)) / rawAlpha) * 255;
    const cr = un(r), cg = un(g), cb = un(b);

    // 0 = neutral ink, 1 = brand orange, ramped across the antialiased seam so
    // the boundary between the black and orange shapes stays smooth.
    const spread = Math.max(r, g, b) - Math.min(r, g, b);
    const brand = spread < SPREAD_FLOOR
      ? 0
      : clamp01((spread / rawAlpha - SPREAD_NEUTRAL) / (SPREAD_BRAND - SPREAD_NEUTRAL));

    out[s]     = Math.round(ink[0] * (1 - brand) + cr * brand);
    out[s + 1] = Math.round(ink[1] * (1 - brand) + cg * brand);
    out[s + 2] = Math.round(ink[2] * (1 - brand) + cb * brand);
    out[s + 3] = Math.round(alpha * 255);
  }
  return out;
}

/** Tight bounding box of anything with alpha, within a row range. */
function inkBox(rgba, width, height, top = 0, bottom = height - 1) {
  let minX = width, minY = height, maxX = -1, maxY = -1;
  for (let y = top; y <= bottom; y++) {
    for (let x = 0; x < width; x++) {
      if (rgba[(y * width + x) * 4 + 3] > 8) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  if (maxX < 0) throw new Error('no ink found in the requested band');
  return { left: minX, top: minY, width: maxX - minX + 1, height: maxY - minY + 1 };
}

/** Rows that contain ink, as [start, end] bands — used to find the wordmark. */
function inkBands(rgba, width, height) {
  const bands = [];
  let start = -1;
  for (let y = 0; y < height; y++) {
    let hasInk = false;
    for (let x = 0; x < width && !hasInk; x++) {
      if (rgba[(y * width + x) * 4 + 3] > 8) hasInk = true;
    }
    if (hasInk && start < 0) start = y;
    if (!hasInk && start >= 0) { bands.push([start, y - 1]); start = -1; }
  }
  if (start >= 0) bands.push([start, height - 1]);
  return bands;
}

/**
 * Crop to the ink, pad evenly, and write at [size] px on the long edge.
 *
 * The padding is deliberate and small (6%). With zero padding a logo butts
 * against the edge of whatever rounded box it sits in; with the artwork's own
 * 40% margin it renders too small to read. This re-centres it so the caller's
 * box size means what it says.
 */
async function emit(rgba, width, height, box, file, size) {
  const pad = Math.round(Math.max(box.width, box.height) * 0.06);
  const side = Math.max(box.width, box.height) + pad * 2;

  // TWO PIPELINES, AND THAT IS THE FIX.
  //
  // sharp does NOT run operations in the order they are chained. It has a
  // fixed internal order, and `extend` happens AFTER `resize` no matter where
  // it appears in the chain. So the single chain this replaces —
  // extract → extend → resize — actually executed as extract → resize →
  // extend: the ink was resized to a square and the padding was then added
  // AROUND that square, making the result rectangular again.
  //
  // The mark came out 344x589 instead of 256x256, an aspect of 0.58. Every
  // consumer draws it with object-fit/BoxFit.contain into a square box, so a
  // 0.58 image fits by HEIGHT and the visible monogram rendered at 58% of the
  // width it was given — the logo looked small on the mobile auth screens, on
  // the dashboard sign-in, and in the sidebar, and no amount of raising `size`
  // at the call sites would have fixed the cause.
  //
  // Padding first, in its own pipeline, then resizing the finished square is
  // the only ordering that survives sharp's reordering.
  const padded = await sharp(rgba, { raw: { width, height, channels: 4 } })
    .extract(box)
    .extend({
      // Centre the mark in a square canvas so every consumer can use one
      // aspect ratio and object-fit:contain without guessing.
      top: Math.round((side - box.height) / 2),
      bottom: side - box.height - Math.round((side - box.height) / 2),
      left: Math.round((side - box.width) / 2),
      right: side - box.width - Math.round((side - box.width) / 2),
      background: { r: 0, g: 0, b: 0, alpha: 0 },
    })
    .png()
    .toBuffer();

  const png = await sharp(padded)
    .resize(size, size, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .png({ compressionLevel: 9 })
    .toBuffer();

  // Reported from the FILE, not from the size we asked for. The old log said
  // "256x256" for a 344x589 image, which is why the bug above shipped: the
  // one place that could have caught it was printing the intention instead of
  // the result.
  const actual = await sharp(png).metadata();
  if (actual.width !== size || actual.height !== size) {
    throw new Error(
      `${file}: expected ${size}x${size}, got ${actual.width}x${actual.height}. ` +
      'Something reordered the pipeline again — see the note in emit().',
    );
  }

  await mkdir(dirname(file), { recursive: true });
  await writeFile(file, png);
  console.log(
    `  ${file.replace(REPO, '.')}  ${actual.width}x${actual.height}  ` +
    `${(png.length / 1024).toFixed(1)} KB`,
  );
}

/**
 * The favicon / launcher icon: the on-dark mark on its own opaque tile.
 *
 * Everything else on this page ships transparent and lets the surface show
 * through, which is right when we control the surface. A favicon sits on a
 * surface we do not control and cannot query: Chrome's tab strip is near-white
 * in light mode and #292A2D in dark, and it does not honour the
 * prefers-color-scheme media attribute on <link rel=icon> that Safari and
 * Firefox do. A transparent mark there is a coin flip — and the losing side is
 * a near-black monogram on a near-black tab.
 *
 * So the icon brings its own ground. #141414 is darker than every browser
 * chrome in circulation, light or dark, so the tile is always distinguishable,
 * and the white-and-orange artwork on it is always legible. One asset, no
 * media queries, no fallback path that silently renders an invisible tab.
 */
async function emitIcon(rgba, width, height, box, file, size) {
  const inset = Math.round(size * 0.16);
  const mark = await sharp(rgba, { raw: { width, height, channels: 4 } })
    .extract(box)
    .resize(size - inset * 2, size - inset * 2, {
      fit: 'contain',
      background: { r: 0, g: 0, b: 0, alpha: 0 },
    })
    .png()
    .toBuffer();

  const radius = Math.round(size * 0.22);
  const mask = Buffer.from(
    `<svg width="${size}" height="${size}"><rect width="${size}" height="${size}" ` +
    `rx="${radius}" ry="${radius}" fill="#141414"/></svg>`,
  );

  const png = await sharp(mask)
    .composite([{ input: mark, gravity: 'centre' }])
    .png({ compressionLevel: 9 })
    .toBuffer();

  await mkdir(dirname(file), { recursive: true });
  await writeFile(file, png);
  console.log(`  ${file.replace(REPO, '.')}  ${size}x${size}  ${(png.length / 1024).toFixed(1)} KB  (tiled)`);
}

// ensureAlpha, not removeAlpha. The source PNG has no alpha channel, so
// removeAlpha() leaves raw() emitting three bytes per pixel while every loop
// below walks it four at a time — every row lands progressively further out of
// phase and the mark comes out smeared into four ghosted copies of itself.
// ensureAlpha() pads to a fixed RGBA stride so the arithmetic is honest.
const { data, info } = await sharp(SOURCE).ensureAlpha().raw()
  .toBuffer({ resolveWithObject: true });
const { width, height } = info;
if (info.channels !== 4) {
  throw new Error(`expected 4 channels after ensureAlpha, got ${info.channels}`);
}

// Bands are found once, off the light version — the geometry is identical in
// both, and finding them twice would risk the two variants cropping
// differently and jittering when the theme is switched.
const light = knockOut(data, width, height, INK_LIGHT);
const dark = knockOut(data, width, height, INK_DARK);

const bands = inkBands(light, width, height);
if (bands.length < 2) {
  throw new Error(
    `expected a monogram band and a wordmark band, found ${bands.length}. ` +
    'If the artwork changed shape, the mark/lockup split below needs revisiting.',
  );
}
const monogramBand = bands[0];
console.log(`source ${width}x${height}, ink bands ${JSON.stringify(bands)}`);

const lockupBox = inkBox(light, width, height);
const markBox = inkBox(light, width, height, monogramBand[0], monogramBand[1]);

const targets = [
  // Full lockup — auth screens, splash, anywhere it is read above ~100px.
  { box: lockupBox, size: 512, name: 'ziren-logo.png',         rgba: light, dir: DASHBOARD_PUBLIC },
  { box: lockupBox, size: 512, name: 'ziren-logo-on-dark.png', rgba: dark,  dir: DASHBOARD_PUBLIC },
  // Monogram only — sidebar square, favicon, avatar slots.
  { box: markBox,   size: 256, name: 'ziren-mark.png',         rgba: light, dir: DASHBOARD_PUBLIC },
  { box: markBox,   size: 256, name: 'ziren-mark-on-dark.png', rgba: dark,  dir: DASHBOARD_PUBLIC },
  // Mobile is themeMode.light only today, but the dark lockup ships anyway:
  // the splash and the SOS screens are dark surfaces regardless of theme.
  { box: lockupBox, size: 512, name: 'ziren_logo.png',         rgba: light, dir: MOBILE_IMAGES },
  { box: lockupBox, size: 512, name: 'ziren_logo_on_dark.png', rgba: dark,  dir: MOBILE_IMAGES },
  { box: markBox,   size: 256, name: 'ziren_mark.png',         rgba: light, dir: MOBILE_IMAGES },
  { box: markBox,   size: 256, name: 'ziren_mark_on_dark.png', rgba: dark,  dir: MOBILE_IMAGES },
];

console.log('writing:');
for (const t of targets) {
  await emit(t.rgba, width, height, t.box, resolve(t.dir, t.name), t.size);
}
await emitIcon(dark, width, height, markBox, resolve(DASHBOARD_PUBLIC, 'ziren-icon.png'), 512);
await emitIcon(dark, width, height, markBox, resolve(MOBILE_IMAGES, 'ziren_icon.png'), 512);

// Android native launch screen. drawable/ziren_logo is composited over
// @color/zirenBackground (#FAFAFA), so it takes the light-ink mark. It is
// drawn 1:1 by the bitmap item — no scaling — so 192px is the sensible size
// rather than the 512 the Flutter-side assets use.
await emit(light, width, height, markBox,
  resolve(ANDROID_RES, 'drawable', 'ziren_logo.png'), 192);

for (const [dir, px] of LAUNCHER_DENSITIES) {
  await emitIcon(dark, width, height, markBox,
    resolve(ANDROID_RES, dir, 'ic_launcher.png'), px);
}
console.log('done.');
