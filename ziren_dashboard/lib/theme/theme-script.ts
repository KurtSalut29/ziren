/**
 * The inline theme bootstrap, kept as a string so both the <head> script tag
 * and the React hook below it agree on one storage key and one resolution
 * rule. Injected by app/layout.tsx.
 *
 * Resolution order:
 *   1. an explicit choice the user made (localStorage)
 *   2. otherwise the OS preference (prefers-color-scheme)
 *
 * The whole thing is wrapped in try/catch because localStorage throws — not
 * returns null, throws — when cookies are blocked or the page is opened in a
 * hardened privacy context. An uncaught throw here runs before hydration and
 * takes the entire page down with it. Losing the theme preference is an
 * acceptable failure; a blank dashboard is not.
 */

export const THEME_STORAGE_KEY = 'ziren-theme';

export type Theme = 'light' | 'dark';
export type ThemePreference = Theme | 'system';

export const THEME_BOOTSTRAP_SCRIPT = `
(function () {
  try {
    var stored = localStorage.getItem('${THEME_STORAGE_KEY}');
    var prefersDark =
      window.matchMedia &&
      window.matchMedia('(prefers-color-scheme: dark)').matches;
    var resolved =
      stored === 'light' || stored === 'dark'
        ? stored
        : prefersDark ? 'dark' : 'light';
    var root = document.documentElement;
    root.classList.toggle('dark', resolved === 'dark');
    root.style.colorScheme = resolved;
  } catch (e) {}
})();
`.trim();
