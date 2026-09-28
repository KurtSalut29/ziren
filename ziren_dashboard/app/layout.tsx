import type { Metadata } from 'next';
import { Inter, JetBrains_Mono } from 'next/font/google';
import './globals.css';
import { THEME_BOOTSTRAP_SCRIPT } from '@/lib/theme/theme-script';
import { MotionProvider } from '@/components/motion-provider';
import { Toaster } from '@/components/ui/toaster';


// Inter — the dashboard is a dense data console (13.5px table rows, tabular
// figures, 11px section labels), and Inter's narrower advance width and taller
// x-height hold up at those sizes better than the geometric Plus Jakarta Sans
// it replaces here. Confirmed switch: 2026-08-08 restyle.
//
// This is a WEB-ONLY divergence. ziren_mobile keeps its own face — see the
// typography note in globals.css before "syncing" app_tokens.dart to match.
const inter = Inter({
  subsets: ['latin'],
  variable: '--font-inter',
  weight: ['400', '500', '600', '700'],
  display: 'swap',
});

// JetBrains Mono — the face for operational figures (see .fig in globals.css).
//
// --font-mono in globals.css has always NAMED 'JetBrains Mono' in its stack,
// but nothing ever loaded it, so every `.text-mono` and `font-mono` in the app
// was silently falling through to whatever ui-monospace resolves to on the
// operator's machine — Consolas on Windows, SF Mono on macOS. The token was
// making a promise the app did not keep, and figures rendered in a different
// face per workstation. Loading it here makes --font-mono honest.
//
// Two weights only. These are counts and clock values, not code listings.
const jetbrainsMono = JetBrains_Mono({
  subsets: ['latin'],
  variable: '--font-mono-face',
  weight: ['500', '600'],
  display: 'swap',
});

export const metadata: Metadata = {
  title: 'Ziren — Emergency Response Dashboard',
  description: 'Agency Admin and Provincial Admin dispatch portal for Ziren.',
  // ziren-icon.png, not ziren-mark.png. The mark ships transparent, which is
  // right everywhere we own the surface and wrong here: a browser tab strip is
  // near-white in light mode and #292A2D in dark, and Chrome ignores the
  // prefers-color-scheme media attribute on <link rel=icon>. The icon variant
  // carries its own dark tile so it reads on either. See
  // scripts/make-logo-assets.mjs.
  icons: {
    icon: '/ziren-icon.png',
    shortcut: '/ziren-icon.png',
    apple: '/ziren-icon.png',
  },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html
      lang="en"
      className={`${inter.variable} ${jetbrainsMono.variable}`}
      suppressHydrationWarning
    >
      <head>
        {/*
          Applies the stored theme before the browser paints anything.

          This has to be a blocking inline script in <head>, not an effect.
          React resolves the theme only after hydration, so a dark-mode user
          would get a full white flash on every navigation and reload — on a
          screen someone stares at through a night shift, that is not a
          cosmetic detail.

          `suppressHydrationWarning` on <html> above is required and not a
          papering-over: this script mutates the class list on purpose, so
          the server's markup and the client's DOM legitimately differ, and
          React would otherwise warn about the mismatch it was told to
          expect.
        */}
        <script
          // A compile-time constant, never user data.
          // eslint-disable-next-line react/no-danger
          dangerouslySetInnerHTML={{ __html: THEME_BOOTSTRAP_SCRIPT }}
        />
      </head>
      <body className="antialiased h-full">
        <MotionProvider>{children}</MotionProvider>
        {/* Every toast in the app renders here - see lib/toast.ts. */}
        <Toaster />
      </body>
    </html>
  );
}
