/**
 * The tone vocabulary shared by DialogMedia and AlertDialogMedia — the tinted
 * icon badge a confirm dialog uses to signal what kind of action it is,
 * before anyone reads a word of the title.
 *
 * Deliberately the same six names the mobile app's ZirenTone enum uses
 * (lib/shared/widgets/ziren_dialogs.dart) and the same rule: the tone always
 * matches the dialog's primary action button, never decided independently of
 * it. "danger" is red because the button it sits above is red — pick a tone
 * that disagrees with the action and the icon reads as a mismatched bug, not
 * a design choice.
 *
 * `brand` and `danger` ride the shadcn --primary/--destructive bridge so they
 * stay correct if that bridge is ever repointed; the other four read the raw
 * --color-system-* custom properties directly (see globals.css) because
 * shadcn's theme never defined warning/info/success tokens of its own.
 *
 * Split into background and foreground maps (rather than one combined class
 * string) because MediaBadge paints the tint on two stacked shape layers and
 * the icon color on a third — a single "bg-x text-y" string can't address
 * that separately.
 */
export type DialogTone = "brand" | "danger" | "success" | "info" | "warning" | "neutral"

export const TONE_BG: Record<DialogTone, string> = {
  brand: "bg-primary/10",
  danger: "bg-destructive/10",
  success: "bg-[var(--color-system-success-bg)]",
  info: "bg-[var(--color-system-info-bg)]",
  warning: "bg-[var(--color-system-warning-bg)]",
  neutral: "bg-muted",
}

export const TONE_FG: Record<DialogTone, string> = {
  brand: "text-primary",
  danger: "text-destructive",
  success: "text-[var(--color-system-success)]",
  info: "text-[var(--color-system-info)]",
  warning: "text-[var(--color-system-warning)]",
  neutral: "text-muted-foreground",
}
