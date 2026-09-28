import { redirect } from 'next/navigation';

/**
 * /queue is now the Active view of /incidents.
 *
 * Kept as a redirect rather than deleted. This route was the post-login
 * landing page and is the target of "View on map" round trips, browser
 * bookmarks and anything a dispatcher pinned — a 404 for those would be a
 * worse outcome than one extra hop. Server-side, so it costs no client render.
 */
export default function QueueRedirect() {
  redirect('/incidents');
}
