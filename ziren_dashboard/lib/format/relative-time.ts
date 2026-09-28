/**
 * "just now", "5m ago", "3h ago", "2d ago" from an ISO timestamp.
 *
 * `absoluteAfterDays` switches to a short calendar date ("Sep 3") once the
 * moment is that many days old, for lists where "40d ago" reads worse than a date.
 */
export function relativeTime(
  iso: string,
  now: number = Date.now(),
  opts: { absoluteAfterDays?: number } = {},
): string {
  const mins = Math.floor((now - new Date(iso).getTime()) / 60_000);
  if (mins < 1) return 'just now';
  if (mins < 60) return `${mins}m ago`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  if (opts.absoluteAfterDays !== undefined && days >= opts.absoluteAfterDays) {
    return new Date(iso).toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
  }
  return `${days}d ago`;
}
