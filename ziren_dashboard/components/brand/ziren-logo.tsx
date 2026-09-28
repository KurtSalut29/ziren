/**
 * The Ziren mark, correct on any ground.
 *
 * WHY THIS IS A COMPONENT AND NOT AN <Image src="/ziren-logo.png">
 *
 * The old asset was a single monochrome PNG, and the five places that used it
 * each carried their own copy of the same CSS workaround —
 * `dark:brightness-0 dark:invert` — to keep it visible on the dark sidebar.
 * That trick works by destroying colour: it flattens the whole mark to solid
 * black and then flips it to solid white.
 *
 * The current logo is two-colour, a near-black monogram with one shape in
 * brand orange. Run through brightness-0 it becomes a white silhouette with
 * the brand colour gone. So the per-theme artwork is generated at build time
 * instead — see scripts/make-logo-assets.mjs, which knocks the white field out
 * to alpha and recolours ONLY the neutral ink, leaving the orange alone
 * because it already reads on both grounds.
 *
 * Which leaves one job for this component: pick the right file. Both are
 * rendered and one is hidden by the `dark:` variant, rather than reading the
 * theme in JS, because <html class="dark"> is set by a blocking script before
 * hydration. A JS read would render the light mark on the server, then swap it
 * on mount — a visible flash on every dark-mode page load, and a hydration
 * mismatch besides.
 *
 * VARIANTS
 *
 *   'mark'   — the ZR monogram alone. Anything at or under ~48px: sidebar,
 *              favicon, avatar slots. The wordmark set 40px wide is grey mush
 *              that also costs the monogram half its height.
 *   'lockup' — monogram plus the ZIREN wordmark. Auth screens and splashes,
 *              where it is read at 100px or more.
 *
 * Both files are square with even padding, so `size` is the box and the mark
 * fills it predictably.
 */

import Image from 'next/image';

type Variant = 'mark' | 'lockup';

const SOURCES: Record<Variant, { light: string; dark: string }> = {
  mark: { light: '/ziren-mark.png', dark: '/ziren-mark-on-dark.png' },
  lockup: { light: '/ziren-logo.png', dark: '/ziren-logo-on-dark.png' },
};

export function ZirenLogo({
  variant = 'mark',
  size = 32,
  className,
  priority = false,
  alt = '',
}: {
  variant?: Variant;
  /** Rendered box, in px. Both assets are square. */
  size?: number;
  className?: string;
  priority?: boolean;
  /** Leave empty when a visible "ZIREN" wordmark sits beside it. */
  alt?: string;
}) {
  const src = SOURCES[variant];
  // `alt` is passed explicitly at each call site below rather than through
  // this spread: jsx-a11y cannot see an alt that arrives inside an object, and
  // an accessibility rule that has to be silenced is worse than one satisfied.
  const common = {
    width: size,
    height: size,
    priority,
    // Explicit, because a parent with `display: flex` and no height would
    // otherwise let next/image's intrinsic sizing win and letterbox the mark.
    style: { width: size, height: size, objectFit: 'contain' as const },
  };

  return (
    <span
      className={['relative inline-flex shrink-0', className].filter(Boolean).join(' ')}
      style={{ width: size, height: size }}
    >
      <Image {...common} alt={alt} className="dark:hidden" src={src.light} />
      <Image {...common} alt={alt} className="hidden dark:block" src={src.dark} />
    </span>
  );
}

/**
 * The mark on a ground we control, rather than the page's.
 *
 * Used where the logo sits on a coloured or photographic panel — the invite
 * hero, for instance — and neither theme asset is the right answer, because
 * the ground is dark regardless of the reader's theme.
 */
export function ZirenLogoOnDark({
  variant = 'mark',
  size = 40,
  className,
  alt = 'Ziren',
}: {
  variant?: Variant;
  size?: number;
  className?: string;
  alt?: string;
}) {
  return (
    <Image
      alt={alt}
      className={className}
      height={size}
      priority
      src={SOURCES[variant].dark}
      style={{ width: size, height: size, objectFit: 'contain' }}
      width={size}
    />
  );
}
