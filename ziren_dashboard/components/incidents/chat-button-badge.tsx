/**
 * The little count on the Chat button: how many replies from the resident the
 * agency has not opened yet. Nothing at zero - a button that always carries a
 * badge teaches people to stop reading it.
 */
export function ChatButtonBadge({ count }: { count: number }) {
  if (count <= 0) return null;
  return (
    <span
      aria-label={`${count} unread ${count === 1 ? 'reply' : 'replies'}`}
      className="ml-1.5 inline-flex min-w-[18px] items-center justify-center rounded-full px-1.5 text-[10.5px] font-bold leading-[18px]"
      data-chat-unread={count}
      style={{ backgroundColor: 'var(--color-system-warning)', color: '#fff' }}
    >
      {count > 9 ? '9+' : count}
    </span>
  );
}
