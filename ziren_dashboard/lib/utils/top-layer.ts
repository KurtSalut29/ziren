/**
 * The two things that must stay usable while a Radix dialog is open.
 *
 * A modal Radix dialog treats every pointer-down outside its own content as
 * "the user clicked away" and closes. The incident alert and the toasts are
 * deliberately outside it - they have to appear over whatever is on screen -
 * so a click on "Dismiss" or on a toast's close button used to also close the
 * incident the dispatcher was reading, or (because the dialog sets
 * pointer-events: none on <body>) do nothing at all.
 *
 * Dialog content passes this to onInteractOutside so those clicks are ignored
 * by the dialog. The elements themselves opt back in to pointer events.
 */
export const TOP_LAYER_SELECTOR = '[data-incident-interrupt], [data-toaster]';

export function isTopLayerTarget(target: EventTarget | null | undefined): boolean {
  return target instanceof Element && target.closest(TOP_LAYER_SELECTOR) !== null;
}
