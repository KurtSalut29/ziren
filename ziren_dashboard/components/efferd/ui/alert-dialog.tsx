"use client"

import * as React from "react"
import { AlertDialog as AlertDialogPrimitive } from "radix-ui"

import { cn } from "@/lib/utils"
import { Button } from "@/components/efferd/ui/button"
import { MediaBadge } from "@/components/efferd/ui/media-badge"
import { type DialogTone } from "@/components/efferd/ui/tone"

function AlertDialog({
  ...props
}: React.ComponentProps<typeof AlertDialogPrimitive.Root>) {
  return <AlertDialogPrimitive.Root data-slot="alert-dialog" {...props} />
}

function AlertDialogTrigger({
  ...props
}: React.ComponentProps<typeof AlertDialogPrimitive.Trigger>) {
  return (
    <AlertDialogPrimitive.Trigger data-slot="alert-dialog-trigger" {...props} />
  )
}

function AlertDialogPortal({
  ...props
}: React.ComponentProps<typeof AlertDialogPrimitive.Portal>) {
  return (
    <AlertDialogPrimitive.Portal data-slot="alert-dialog-portal" {...props} />
  )
}

function AlertDialogOverlay({
  className,
  ...props
}: React.ComponentProps<typeof AlertDialogPrimitive.Overlay>) {
  return (
    <AlertDialogPrimitive.Overlay
      data-slot="alert-dialog-overlay"
      className={cn(
        // z-[1100]: comfortably above the map overlay panels (z-[999]/z-[1000] —
        // ZirenMap.tsx, incident-location-panel.tsx), which are themselves that
        // high only to clear Leaflet's own internal pane z-indices. A dialog
        // must always sit above page content, maps included. Below the
        // incident-interrupt alert (z-[2000]), which must break through
        // anything, dialogs included.
        "fixed inset-0 z-[1100] bg-black/45 duration-200 supports-backdrop-filter:backdrop-blur-sm data-open:animate-in data-open:fade-in-0 data-closed:animate-out data-closed:fade-out-0",
        className
      )}
      {...props}
    />
  )
}

function AlertDialogContent({
  className,
  size = "default",
  ...props
}: React.ComponentProps<typeof AlertDialogPrimitive.Content> & {
  size?: "default" | "sm"
}) {
  return (
    <AlertDialogPortal>
      <AlertDialogOverlay />
      <AlertDialogPrimitive.Content
        data-slot="alert-dialog-content"
        data-size={size}
        className={cn(
          // shadow-[var(--shadow-modal)]: see dialog.tsx — the dialog is the
          // highest, most attention-demanding surface in the app.
          "group/alert-dialog-content fixed top-1/2 left-1/2 z-[1100] grid w-full -translate-x-1/2 -translate-y-1/2 gap-5 rounded-2xl bg-popover p-6 text-popover-foreground ring-1 ring-foreground/10 shadow-[var(--shadow-modal)] duration-200 outline-none data-[size=default]:max-w-xs data-[size=sm]:max-w-xs data-[size=default]:sm:max-w-sm data-open:animate-in data-open:fade-in-0 data-open:zoom-in-95 data-open:slide-in-from-bottom-2 data-closed:animate-out data-closed:fade-out-0 data-closed:zoom-out-95",
          className
        )}
        {...props}
      />
    </AlertDialogPortal>
  )
}

function AlertDialogHeader({
  className,
  ...props
}: React.ComponentProps<"div">) {
  return (
    <div
      data-slot="alert-dialog-header"
      className={cn(
        "grid grid-rows-[auto_1fr] place-items-center gap-1.5 text-center has-data-[slot=alert-dialog-media]:grid-rows-[auto_auto_1fr] has-data-[slot=alert-dialog-media]:gap-x-4 sm:group-data-[size=default]/alert-dialog-content:place-items-start sm:group-data-[size=default]/alert-dialog-content:text-left sm:group-data-[size=default]/alert-dialog-content:has-data-[slot=alert-dialog-media]:grid-rows-[auto_1fr]",
        className
      )}
      {...props}
    />
  )
}

/** No band: buttons float on the same surface as the rest of the dialog,
 *  separated only by the grid's own gap-5 — see dialog.tsx's DialogFooter for
 *  the same call. */
function AlertDialogFooter({
  className,
  ...props
}: React.ComponentProps<"div">) {
  return (
    <div
      data-slot="alert-dialog-footer"
      className={cn(
        "flex flex-col-reverse gap-2 group-data-[size=sm]/alert-dialog-content:grid group-data-[size=sm]/alert-dialog-content:grid-cols-2 sm:flex-row sm:justify-end",
        className
      )}
      {...props}
    />
  )
}

/** The tinted icon badge naming what kind of action this confirm dialog is,
 *  before anyone reads the title. See tone.ts for the tone/action-colour
 *  contract and media-badge.tsx for the scalloped shape itself. This div (not
 *  MediaBadge directly) is what AlertDialogHeader's has-data-[slot=…] rules
 *  key off to switch into the icon-left, text-right layout — keep the slot
 *  name even though the visuals now live one level down. */
function AlertDialogMedia({
  className,
  tone = "neutral",
  children,
}: { className?: string; tone?: DialogTone; children: React.ReactNode }) {
  return (
    <div
      data-slot="alert-dialog-media"
      className={cn("mb-2 sm:group-data-[size=default]/alert-dialog-content:row-span-2", className)}
    >
      <MediaBadge tone={tone} className="size-16">{children}</MediaBadge>
    </div>
  )
}

function AlertDialogTitle({
  className,
  ...props
}: React.ComponentProps<typeof AlertDialogPrimitive.Title>) {
  return (
    <AlertDialogPrimitive.Title
      data-slot="alert-dialog-title"
      className={cn(
        "font-heading text-lg font-semibold leading-tight sm:group-data-[size=default]/alert-dialog-content:group-has-data-[slot=alert-dialog-media]/alert-dialog-content:col-start-2",
        className
      )}
      {...props}
    />
  )
}

function AlertDialogDescription({
  className,
  ...props
}: React.ComponentProps<typeof AlertDialogPrimitive.Description>) {
  return (
    <AlertDialogPrimitive.Description
      data-slot="alert-dialog-description"
      className={cn(
        "text-sm text-balance text-muted-foreground md:text-pretty *:[a]:underline *:[a]:underline-offset-3 *:[a]:hover:text-foreground",
        className
      )}
      {...props}
    />
  )
}

// rounded-full on both: TailAdmin's own alert-style modals (Danger Alert,
// Success Alert on nextjs-demo.tailadmin.com/modals) use a pill button for
// their single centred action, not the app's usual rounded-lg. Scoped to
// AlertDialog specifically — the confirm/alert primitive — rather than to
// Button itself, which every ordinary form and toolbar in the app still
// uses at rounded-lg. Passed through Button's own className (not the inner
// primitive's) so buttonVariants' tailwind-merge is what resolves the
// rounded-lg → rounded-full override, not raw class-string concatenation.

function AlertDialogAction({
  className,
  variant = "default",
  size = "default",
  ...props
}: React.ComponentProps<typeof AlertDialogPrimitive.Action> &
  Pick<React.ComponentProps<typeof Button>, "variant" | "size">) {
  return (
    <Button variant={variant} size={size} className="rounded-full" asChild>
      <AlertDialogPrimitive.Action
        data-slot="alert-dialog-action"
        className={cn(className)}
        {...props}
      />
    </Button>
  )
}

function AlertDialogCancel({
  className,
  variant = "outline",
  size = "default",
  ...props
}: React.ComponentProps<typeof AlertDialogPrimitive.Cancel> &
  Pick<React.ComponentProps<typeof Button>, "variant" | "size">) {
  return (
    <Button variant={variant} size={size} className="rounded-full" asChild>
      <AlertDialogPrimitive.Cancel
        data-slot="alert-dialog-cancel"
        className={cn(className)}
        {...props}
      />
    </Button>
  )
}

export {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogMedia,
  AlertDialogOverlay,
  AlertDialogPortal,
  AlertDialogTitle,
  AlertDialogTrigger,
}
