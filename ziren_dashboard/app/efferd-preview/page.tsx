/**
 * Reference preview — @efferd/dashboard-3, as shipped.
 *
 * Deliberately outside the (dashboard) route group, so it inherits neither the
 * Ziren shell nor its auth gate: this is a design reference to look at, not a
 * console page. Nothing in the live app imports anything from here.
 *
 * `.shadcn-scope` supplies the base defaults the registry components assume —
 * the background/foreground ground and a real border colour. Tailwind v4
 * defaults border-color to currentColor, so without it every `border` in the
 * block would draw in the text colour. The shadcn `@layer base` that normally
 * provides this applies to `*` and `body`, which would have repainted the
 * whole console; see the note in globals.css.
 *
 * Delete this route once the parts worth keeping have been adapted.
 */

import { Dashboard } from '@/components/efferd/dashboard';
import { AppShell } from '@/components/efferd/app-shell';
import { TooltipProvider } from '@/components/efferd/ui/tooltip';

export const metadata = { title: 'efferd dashboard-3 — reference' };

export default function EfferdPreviewPage() {
  return (
    // TooltipProvider is required by the block's sidebar and charts — the CLI
    // says to put it in the root layout, which would push a Radix context over
    // the entire live console for the sake of a reference page. Scoped here
    // instead; move it up only if registry components ever ship for real.
    <TooltipProvider>
      <div className="shadcn-scope">
        <AppShell>
          <Dashboard />
        </AppShell>
      </div>
    </TooltipProvider>
  );
}
