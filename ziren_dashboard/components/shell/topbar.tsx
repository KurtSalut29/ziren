'use client';

/**
 * Topbar — the fixed strip along the top of the content area.
 *
 * Breadcrumb on the left; search, connectivity, notification and settings on
 * the right.
 *
 * Search sits here rather than in the sidebar because the sidebar collapses to
 * a 68px rail, and a field that disappears at one of its two widths is not a
 * place to put the app's only search. The topbar keeps a fixed geometry on
 * every route and every collapse state. Below md it hands the field back to
 * the nav drawer — see ShellSearch — since the breadcrumb and three controls
 * already fill a phone-width bar.
 *
 * The connectivity pill is not in the reference design and is kept anyway:
 * this is a dispatch console, and whether the operator is looking at live data
 * or a stale cache is operational information, not chrome. Removing it to
 * match a support-desk mockup would be a regression dressed as a restyle.
 */

import { useEffect, useState } from 'react';
import Link from 'next/link';
import {
  Bell,
  ChevronRight,
  LayoutGrid,
  Menu,
  RefreshCw,
  Settings,
  Wifi,
  WifiOff,
} from 'lucide-react';
import { ShellSearch } from './shell-search';

type ConnectivityState = 'online' | 'offline' | 'syncing';

export interface TopbarProps {
  /** Final breadcrumb segment — the page the user is on. */
  title: string;
  /** Optional ancestor segment, rendered muted before the title. */
  section?: string;
  unreadCount?: number;
  /** Opens the off-canvas nav. Rendered below md only. */
  onOpenDrawer: () => void;
  searchValue: string;
  onSearchChange: (v: string) => void;
}

export function Topbar({
  title,
  section,
  unreadCount = 0,
  onOpenDrawer,
  searchValue,
  onSearchChange,
}: TopbarProps) {
  return (
    <header
      className={[
        'flex h-[56px] shrink-0 items-center justify-between gap-3',
        'border-b border-[var(--color-surface-border)]',
        'bg-[var(--color-frame)] px-4 md:px-6',
      ].join(' ')}
    >
      <div className="flex min-w-0 items-center gap-2">
        <button
          type="button"
          onClick={onOpenDrawer}
          aria-label="Open navigation"
          className="-ml-1 flex h-8 w-8 shrink-0 items-center justify-center rounded-[var(--radius-md)] text-[var(--color-text-tertiary)] transition-colors hover:bg-[var(--color-surface-hover)] hover:text-[var(--color-text-primary)] md:hidden"
        >
          <Menu size={17} strokeWidth={1.9} />
        </button>

        <Breadcrumb section={section} title={title} />
      </div>

      <div className="flex shrink-0 items-center gap-1.5">
        {/* Hidden below md, where the drawer carries it instead. `hidden` on
            the wrapper rather than a narrower field: a search box that shrinks
            past its own placeholder reads as broken, not responsive. */}
        <ShellSearch
          value={searchValue}
          onChange={onSearchChange}
          className="mr-1.5 hidden w-[200px] md:block lg:w-[260px]"
        />
        <ConnectivityPill />
        <IconButton
          icon={<Bell size={16} strokeWidth={1.8} />}
          label={unreadCount > 0 ? `Notifications, ${unreadCount} unread` : 'Notifications'}
          badge={unreadCount > 0}
        />
        <IconButton
          icon={<Settings size={16} strokeWidth={1.8} />}
          label="Settings"
          href="/settings"
        />
      </div>
    </header>
  );
}

// ── Breadcrumb ────────────────────────────────────────────────────────────────

function Breadcrumb({ section, title }: { section?: string; title: string }) {
  return (
    <nav aria-label="Breadcrumb" className="min-w-0">
      <ol className="flex min-w-0 items-center gap-1.5 text-[13px] leading-tight">
        <li className="flex shrink-0 items-center gap-1.5 text-[var(--color-text-tertiary)]">
          <LayoutGrid size={14} strokeWidth={1.9} aria-hidden="true" />
          <span className="hidden sm:inline">Overview</span>
        </li>
        {section && (
          <li className="hidden min-w-0 items-center gap-1.5 md:flex">
            <ChevronRight
              size={13}
              strokeWidth={2}
              aria-hidden="true"
              className="shrink-0 text-[var(--color-text-muted)]"
            />
            <span className="truncate text-[var(--color-text-tertiary)]">{section}</span>
          </li>
        )}
        <li className="flex min-w-0 items-center gap-1.5">
          <ChevronRight
            size={13}
            strokeWidth={2}
            aria-hidden="true"
            className="shrink-0 text-[var(--color-text-muted)]"
          />
          {/* aria-current="page" marks the terminal crumb so a screen reader
              announces which segment is the current location. */}
          <span
            aria-current="page"
            className="truncate font-medium text-[var(--color-text-primary)]"
          >
            {title}
          </span>
        </li>
      </ol>
    </nav>
  );
}

// ── Icon button ───────────────────────────────────────────────────────────────

function IconButton({
  icon,
  label,
  href,
  badge = false,
}: {
  icon: React.ReactNode;
  label: string;
  href?: string;
  badge?: boolean;
}) {
  const className =
    'relative flex h-8 w-8 items-center justify-center rounded-[var(--radius-md)] text-[var(--color-text-tertiary)] transition-colors hover:bg-[var(--color-surface-hover)] hover:text-[var(--color-text-primary)]';

  const content = (
    <>
      <span aria-hidden="true">{icon}</span>
      {badge && (
        <span
          aria-hidden="true"
          className="absolute right-1.5 top-1.5 h-1.5 w-1.5 rounded-full ring-2 ring-[var(--color-frame)]"
          style={{ backgroundColor: 'var(--color-severity-critical)' }}
        />
      )}
    </>
  );

  if (href) {
    return (
      <Link href={href} aria-label={label} className={className}>
        {content}
      </Link>
    );
  }

  return (
    <button type="button" aria-label={label} className={className}>
      {content}
    </button>
  );
}

// ── Connectivity ──────────────────────────────────────────────────────────────

function ConnectivityPill() {
  const [state, setState] = useState<ConnectivityState>('online');

  useEffect(() => {
    setState(navigator.onLine ? 'online' : 'offline');

    let syncTimer: ReturnType<typeof setTimeout> | null = null;

    const handleOnline = () => {
      // Hold "syncing" briefly so the pages behind this bar have a moment to
      // re-fetch — flipping straight to "Online" would claim the data is
      // current a couple of seconds before it actually is.
      setState('syncing');
      syncTimer = setTimeout(() => setState('online'), 2000);
    };
    const handleOffline = () => {
      if (syncTimer) clearTimeout(syncTimer);
      setState('offline');
    };

    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);
    return () => {
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
      if (syncTimer) clearTimeout(syncTimer);
    };
  }, []);

  const config: Record<
    ConnectivityState,
    { icon: React.ReactNode; label: string; color: string }
  > = {
    online: {
      icon: <Wifi size={11} strokeWidth={2.4} />,
      label: 'Online',
      color: 'var(--color-connectivity-online)',
    },
    offline: {
      icon: <WifiOff size={11} strokeWidth={2.4} />,
      label: 'Offline',
      color: 'var(--color-connectivity-offline)',
    },
    syncing: {
      icon: <RefreshCw size={11} strokeWidth={2.4} className="animate-spin" />,
      label: 'Syncing',
      color: 'var(--color-connectivity-sms)',
    },
  };

  const { icon, label, color } = config[state];

  return (
    // role="status" so a change is announced without stealing focus. Going
    // offline mid-shift is exactly the kind of thing a non-sighted operator
    // must not have to discover by noticing a colour changed.
    <span
      role="status"
      className="mr-1 hidden items-center gap-1.5 rounded-[var(--radius-control)] border border-[var(--color-surface-border)] px-2.5 py-1 text-[11.5px] font-medium leading-none sm:inline-flex"
      style={{ color }}
    >
      <span aria-hidden="true">{icon}</span>
      {label}
    </span>
  );
}
