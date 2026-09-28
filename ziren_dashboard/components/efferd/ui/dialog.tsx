"use client"

import * as React from "react"
import { Dialog as DialogPrimitive } from "radix-ui"

import { cn } from "@/lib/utils"
import { isTopLayerTarget } from "@/lib/utils/top-layer"
import { Button } from "@/components/efferd/ui/button"
import { MediaBadge } from "@/components/efferd/ui/media-badge"
import { type DialogTone } from "@/components/efferd/ui/tone"
import { XIcon } from "lucide-react"

function Dialog({
  ...props
}: React.ComponentProps<typeof DialogPrimitive.Root>) {
  return <DialogPrimitive.Root data-slot="dialog" {...props} />
}

function DialogTrigger({
  ...props
}: React.ComponentProps<typeof DialogPrimitive.Trigger>) {
  return <DialogPrimitive.Trigger data-slot="dialog-trigger" {...props} />
}

function DialogPortal({
  ...props
}: React.ComponentProps<typeof DialogPrimitive.Portal>) {
  return <DialogPrimitive.Portal data-slot="dialog-portal" {...props} />
}

function DialogClose({
  ...props
}: React.ComponentProps<typeof DialogPrimitive.Close>) {
  return <DialogPrimitive.Close data-slot="dialog-close" {...props} />
}

function DialogOverlay({
  className,
  ...props
}: React.ComponentProps<typeof DialogPrimitive.Overlay>) {
  return (
    <DialogPrimitive.Overlay
      data-slot="dialog-overlay"
      className={cn(
        // See alert-dialog.tsx for why this is 1100, not 50: it must clear the
        // map overlay panels' z-[999]/z-[1000].
        "fixed inset-0 isolate z-[1100] bg-black/45 duration-200 supports-backdrop-filter:backdrop-blur-sm data-open:animate-in data-open:fade-in-0 data-closed:animate-out data-closed:fade-out-0",
        className
      )}
      {...props}
    />
  )
}

function DialogContent({
  className,
  children,
  showCloseButton = true,
  ...props
}: React.ComponentProps<typeof DialogPrimitive.Content> & {
  showCloseButton?: boolean
}) {
  return (
    <DialogPortal>
      <DialogOverlay />
      <DialogPrimitive.Content
        data-slot="dialog-content"
        className={cn(
          // shadow-[var(--shadow-modal)]: the dialog is the highest,
          // most attention-demanding surface in the app — see globals.css.
          "fixed top-1/2 left-1/2 z-[1100] grid w-full max-w-[calc(100%-2rem)] -translate-x-1/2 -translate-y-1/2 gap-5 rounded-2xl bg-popover p-6 text-sm text-popover-foreground ring-1 ring-foreground/10 shadow-[var(--shadow-modal)] duration-200 outline-none sm:max-w-sm data-open:animate-in data-open:fade-in-0 data-open:zoom-in-95 data-open:slide-in-from-bottom-2 data-closed:animate-out data-closed:fade-out-0 data-closed:zoom-out-95",
          className
        )}
        {...props}
        // The incident alert and the toasts sit outside every dialog on purpose;
        // clicking them must not count as clicking away. See lib/utils/top-layer.
        onInteractOutside={(event) => {
          if (isTopLayerTarget(event.target)) event.preventDefault()
          props.onInteractOutside?.(event)
        }}
      >
        {children}
        {showCloseButton && (
          <DialogPrimitive.Close data-slot="dialog-close" asChild>
            <Button
              variant="ghost"
              className="absolute top-3 right-3"
              size="icon-sm"
            >
              <XIcon
              />
              <span className="sr-only">Close</span>
            </Button>
          </DialogPrimitive.Close>
        )}
      </DialogPrimitive.Content>
    </DialogPortal>
  )
}

function DialogHeader({ className, ...props }: React.ComponentProps<"div">) {
  return (
    <div
      data-slot="dialog-header"
      className={cn("flex flex-col gap-2", className)}
      {...props}
    />
  )
}

/** A tone-tinted icon circle for a DialogHeader — the same "what kind of
 *  action is this" signal AlertDialogMedia gives a confirm dialog, and the
 *  mobile app's ZirenDialog gives every one of its dialogs. Opt-in: most
 *  Dialogs (forms, editors, pickers) have no single action to badge and stay
 *  plain-text. Wrap it with DialogTitle yourself (see DispatchModal) — the
 *  two don't need to sit in a fixed relationship the way the centred
 *  AlertDialogMedia/Title pair does. */
function DialogMedia({
  className,
  tone = "brand",
  children,
}: { className?: string; tone?: DialogTone; children: React.ReactNode }) {
  return (
    <MediaBadge tone={tone} className={cn("size-12", className)}>
      {children}
    </MediaBadge>
  )
}

/** No band: buttons float on the same surface as the rest of the dialog,
 *  separated only by the grid's own gap-5 — TailAdmin's own confirm dialogs
 *  (nextjs-demo.tailadmin.com/modals) don't box the footer off either, and a
 *  border-topped muted strip was reading as a second, unrelated card glued
 *  to the bottom of the first. */
function DialogFooter({
  className,
  showCloseButton = false,
  children,
  ...props
}: React.ComponentProps<"div"> & {
  showCloseButton?: boolean
}) {
  return (
    <div
      data-slot="dialog-footer"
      className={cn("flex flex-col-reverse gap-2 sm:flex-row sm:justify-end", className)}
      {...props}
    >
      {children}
      {showCloseButton && (
        <DialogPrimitive.Close asChild>
          <Button variant="outline">Close</Button>
        </DialogPrimitive.Close>
      )}
    </div>
  )
}

function DialogTitle({
  className,
  ...props
}: React.ComponentProps<typeof DialogPrimitive.Title>) {
  return (
    <DialogPrimitive.Title
      data-slot="dialog-title"
      className={cn(
        "font-heading text-lg leading-tight font-semibold",
        className
      )}
      {...props}
    />
  )
}

function DialogDescription({
  className,
  ...props
}: React.ComponentProps<typeof DialogPrimitive.Description>) {
  return (
    <DialogPrimitive.Description
      data-slot="dialog-description"
      className={cn(
        "text-sm text-muted-foreground *:[a]:underline *:[a]:underline-offset-3 *:[a]:hover:text-foreground",
        className
      )}
      {...props}
    />
  )
}

export {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogMedia,
  DialogOverlay,
  DialogPortal,
  DialogTitle,
  DialogTrigger,
}
