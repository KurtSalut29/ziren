'use client';

/**
 * ConnectivityDot — presence indicator on the account avatar.
 *
 * Replaces the old sidebar-footer ConnectivityCard's permanent three-line
 * text block with the same colored-dot-on-an-avatar pattern Gmail/Google
 * Chat use for presence: quiet by default, the full sentence only on
 * hover/focus. The underlying question ("is this queue live or stale?")
 * still matters just as much — see useConnectivity — it just no longer
 * needs a standing slot of its own to say so.
 *
 * Positioned absolutely by the caller (relative parent around the Avatar);
 * this component only draws the dot and its tooltip.
 */

import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from '@/components/efferd/ui/tooltip';
import { useConnectivity } from '@/lib/hooks/useConnectivity';

export function ConnectivityDot() {
  const { label, detail, color } = useConnectivity();

  return (
    <Tooltip>
      <TooltipTrigger asChild>
        {/* The ring is the surface colour, not a border — it's what keeps
            the dot legible sitting on top of the avatar's own fill. */}
        <span
          aria-label={`Connection: ${label} — ${detail}`}
          className="absolute -bottom-0.5 -right-0.5 block size-2.5 rounded-full"
          role="status"
          style={{ backgroundColor: color, boxShadow: '0 0 0 2px var(--color-surface-card)' }}
        />
      </TooltipTrigger>
      <TooltipContent>
        {label} — {detail}
      </TooltipContent>
    </Tooltip>
  );
}
