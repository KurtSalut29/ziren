"use client"

import * as React from "react"

import { cn } from "@/lib/utils"
import { TONE_BG, TONE_FG, type DialogTone } from "@/components/efferd/ui/tone"

/**
 * The icon badge a confirm dialog leads with — a scalloped "flower" instead
 * of a plain tinted circle (spotted 2026-09-25 on TailAdmin's own /modals
 * showcase, nextjs-demo.tailadmin.com).
 *
 * Built from two identical rounded squares of the same tint, one rotated 45°
 * over the other, rather than an SVG path — cheap and it inherits the tone
 * system for free. The radius is the whole trick: much above ~30% and the
 * two squares are already too close to circles for a 45° spin to change the
 * silhouette at all (a circle has no corners to rotate); much below ~15% and
 * the points read as a sharp ninja-star instead of a soft bloom. 18% is where
 * the lobes read clearly at the ~56px this actually renders at — a size this
 * checked matters: the same shape at 24% looked like a plain rounded square
 * until tested at 4x its real size, because eight gentle lobes on a 48px
 * badge is a handful of pixels each, not a shape a glance can name.
 */
export function MediaBadge({
  tone,
  className,
  children,
}: {
  tone: DialogTone
  className?: string
  children: React.ReactNode
}) {
  return (
    <div
      data-slot="media-badge"
      className={cn("relative inline-flex size-14 shrink-0 items-center justify-center", className)}
    >
      <span aria-hidden="true" className={cn("absolute inset-0 rounded-[18%]", TONE_BG[tone])} />
      <span aria-hidden="true" className={cn("absolute inset-0 rounded-[18%] rotate-45", TONE_BG[tone])} />
      <span className={cn("relative *:[svg:not([class*='size-'])]:size-7", TONE_FG[tone])}>
        {children}
      </span>
    </div>
  )
}
