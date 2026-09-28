/**
 * Builds the Android 12+ splash icon from the transparent Ziren mark.
 *
 * WHY THIS EXISTS
 *
 * From Android 12 the system draws the splash itself, and it ignores
 * `windowBackground`. Unless the app supplies `windowSplashScreenAnimatedIcon`
 * it falls back to the launcher icon — and ours is a legacy (non-adaptive)
 * bitmap of a BLACK rounded square, which the platform then centres inside its
 * own WHITE rounded container. That is the two nested boxes on the launch
 * screen: the white one is the system's, the black one is our icon.
 *
 * Supplying a transparent-background icon removes both. The system draws our
 * mark straight onto the splash colour with nothing behind it.
 *
 * THE GEOMETRY IS NOT ARBITRARY
 *
 * Android masks the splash icon to a circle. With no icon background the
 * canvas is 288dp and only the inner 192dp is guaranteed visible — two thirds.
 * The authored mark is a tall transparent canvas (the artwork sits in the
 * middle of a 344x589 box), so handing it over as-is would scale the whole
 * canvas to fit and leave the monogram tiny inside a mostly-empty circle.
 *
 * So it is trimmed to the ink, then padded back out to a square whose side is
 * 1.5x the artwork — putting the visible mark at exactly the two-thirds mark
 * the platform guarantees.
 */
import sharp from 'sharp';
import { mkdir } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';

const REPO = resolve(import.meta.dirname, '..', '..');
const SOURCE = resolve(REPO, 'ziren_mobile/assets/images/ziren_mark.png');
const OUT = resolve(
  REPO,
  'ziren_mobile/android/app/src/main/res/drawable/ziren_splash_mark.png',
);

/** Side of the square canvas, in pixels. Generous: it is downscaled to 288dp. */
const CANVAS = 960;

/** Fraction of the canvas the artwork may occupy. See the note above. */
const SAFE = 2 / 3;

const trimmed = await sharp(SOURCE)
  // Trim against a fully transparent reference so the tall empty canvas goes
  // and only the monogram is left to measure.
  .trim({ background: { r: 0, g: 0, b: 0, alpha: 0 }, threshold: 0 })
  .toBuffer({ resolveWithObject: true });

const { width, height } = trimmed.info;
const scale = (CANVAS * SAFE) / Math.max(width, height);
const drawWidth = Math.round(width * scale);
const drawHeight = Math.round(height * scale);

const art = await sharp(trimmed.data)
  .resize(drawWidth, drawHeight, { fit: 'fill' })
  .toBuffer();

await mkdir(dirname(OUT), { recursive: true });
await sharp({
  create: {
    width: CANVAS,
    height: CANVAS,
    channels: 4,
    background: { r: 0, g: 0, b: 0, alpha: 0 },
  },
})
  .composite([
    {
      input: art,
      left: Math.round((CANVAS - drawWidth) / 2),
      top: Math.round((CANVAS - drawHeight) / 2),
    },
  ])
  .png()
  .toFile(OUT);

console.log(
  `splash icon: trimmed ${width}x${height} -> ${drawWidth}x${drawHeight} ` +
    `centred on ${CANVAS}x${CANVAS} transparent\n  ${OUT}`,
);
