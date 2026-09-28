'use client';

/**
 * TopBar — persistent header bar across the full dashboard shell.
 *
 * Contains:
 *   - Page title (derived from route via props, set per-page via the
 *     <TopBarTitle> pattern or passed directly)
 *   - Connectivity status pill — online / offline / syncing
 *     Uses navigator.onLine + online/offline events. Syncing state is
 *     shown for 2s after reconnecting to give the page time to re-fetch.
 *   - Notification bell — badge shown when unread count > 0
 *     (static placeholder for Phase 4 — wire to real data then)
 *   - Global search — controlled input, onSearch callback
 *
 * Used inside DashboardLayout. Not a Server Component because it reads
 * navigator.onLine (browser-only API) and tracks interactive state.
 */

import { useEffect, useState } from 'react';
import { SearchInput } from '@/components/ui/search-input';
import { Bell, ChevronRight, LogOut, Wifi, WifiOff, RefreshCw } from 'lucide-react';

// ── Connectivity pill ─────────────────────────────────────────────────────────

type ConnectivityState = 'online' | 'offline' | 'syncing';

function ConnectivityPill() {
  const [state, setState] = useState<ConnectivityState>('online');

  useEffect(() => {
    // Initialise from current browser state
    setState(navigator.onLine ? 'online' : 'offline');

    let syncTimer: ReturnType<typeof setTimeout> | null = null;

    const handleOnline = () => {
      setState('syncing');
      syncTimer = setTimeout(() => setState('online'), 2000);
    };
    const handleOffline = () => {
      if (syncTimer) clearTimeout(syncTimer);
      setState('offline');
    };

    window.addEventListener('online',  handleOnline);
    window.addEventListener('offline', handleOffline);
    return () => {
      window.removeEventListener('online',  handleOnline);
      window.removeEventListener('offline', handleOffline);
      if (syncTimer) clearTimeout(syncTimer);
    };
  }, []);

  const config: Record<ConnectivityState, {
    icon: React.ReactNode;
    label: string;
    pill: string;
  }> = {
    online: {
      icon: <Wifi size={11} strokeWidth={2.5} />,
      label: 'Online',
      pill: 'bg-[var(--color-system-success-bg)] text-[var(--color-connectivity-online)]',
    },
    offline: {
      icon: <WifiOff size={11} strokeWidth={2.5} />,
      label: 'Offline',
      pill: 'bg-[var(--color-status-cancelled-bg)] text-[var(--color-connectivity-offline)]',
    },
    syncing: {
      icon: <RefreshCw size={11} strokeWidth={2.5} className="animate-spin" />,
      label: 'Syncing',
      pill: 'bg-[var(--color-system-warning-bg)] text-[var(--color-connectivity-sms)]',
    },
  };

  const { icon, label, pill } = config[state];

  return (
    <span
      className={[
        'inline-flex items-center gap-1.5 px-2.5 py-1',
        'rounded-[var(--radius-full)]',
        'text-[11px] font-semibold leading-none',
        'select-none',
        pill,
      ].join(' ')}
      title={`Connection status: ${label}`}
    >
      {icon}
      {label}
    </span>
  );
}

// ── Notification bell ─────────────────────────────────────────────────────────

function NotificationBell({ unread = 0 }: { unread?: number }) {
  return (
    <button
      className={[
        'relative flex items-center justify-center',
        'w-10 h-10 rounded-full',
        'border border-[var(--color-surface-border)]',
        'text-[var(--color-text-secondary)]',
        'hover:bg-[var(--color-surface-raised)]',
        'hover:text-[var(--color-text-primary)]',
        'transition-colors',
      ].join(' ')}
      aria-label={unread > 0 ? `${unread} unread notifications` : 'Notifications'}
    >
      <Bell size={17} strokeWidth={1.8} />
      {unread > 0 && (
        <span
          aria-hidden="true"
          className={[
            'absolute top-2 right-2.5',
            'w-2 h-2 rounded-full',
            'bg-[var(--color-severity-critical)]',
            'ring-2 ring-[var(--color-surface-card)]',
          ].join(' ')}
        />
      )}
    </button>
  );
}

// ── Search bar ────────────────────────────────────────────────────────────────

function SearchBar({
  value,
  onChange,
}: {
  value: string;
  onChange: (v: string) => void;
}) {
  return (
    <SearchInput
      className="w-[260px] xl:w-[340px]"
      label="Search"
      onValueChange={onChange}
      placeholder="Search"
      size="lg"
      value={value}
    />
  );
}

// ── Breadcrumb ────────────────────────────────────────────────────────────────

function Breadcrumb({ section, title }: { section?: string; title: string }) {
  return (
    <div className="flex items-center gap-2 min-w-0 text-[14px] leading-tight">
      <span className="font-medium text-[var(--color-text-muted)] shrink-0">Dashboard</span>
      {section && (
        <>
          <ChevronRight size={14} strokeWidth={2.5} className="text-[var(--color-text-muted)] shrink-0" />
          <span className="font-medium text-[var(--color-text-muted)] truncate hidden md:inline">{section}</span>
        </>
      )}
      <ChevronRight size={14} strokeWidth={2.5} className="text-[var(--color-text-muted)] shrink-0 hidden md:inline" />
      <span className="font-bold text-[var(--color-text-primary)] truncate">{title}</span>
    </div>
  );
}

// ── Avatar ────────────────────────────────────────────────────────────────────

interface AvatarInfo {
  initials: string;
  name: string;
  roleLabel: string;
  onSignOut: () => void;
}

function AvatarMenu({ avatar }: { avatar: AvatarInfo }) {
  const [open, setOpen] = useState(false);

  return (
    <div className="relative">
      <button
        onClick={() => setOpen(o => !o)}
        className="flex items-center transition-opacity hover:opacity-85"
        aria-haspopup="true"
        aria-expanded={open}
        title={`${avatar.name} · ${avatar.roleLabel}`}
      >
        <span
          className="flex h-10 w-10 shrink-0 select-none items-center justify-center rounded-full text-[12.5px] font-bold text-white ring-2 ring-[var(--color-surface-card)]"
          style={{ backgroundColor: 'var(--color-brand)' }}
        >
          {avatar.initials}
        </span>
      </button>

      {open && (
        <>
          <button
            aria-hidden="true"
            tabIndex={-1}
            className="fixed inset-0 z-10 cursor-default"
            onClick={() => setOpen(false)}
          />
          <div
            className="absolute right-0 top-[calc(100%+8px)] z-20 w-52 overflow-hidden rounded-[14px] border py-1 shadow-[var(--shadow-lg)]"
            style={{ borderColor: 'var(--color-surface-border)', backgroundColor: 'var(--color-surface-overlay)' }}
          >
            <div className="border-b px-3.5 py-2.5" style={{ borderColor: 'var(--color-surface-border)' }}>
              <p className="truncate text-[13px] font-semibold text-[var(--color-text-primary)]">{avatar.name}</p>
              <p className="truncate text-[11px] text-[var(--color-text-muted)]">{avatar.roleLabel}</p>
            </div>
            <button
              onClick={avatar.onSignOut}
              className="flex w-full items-center gap-2 px-3.5 py-2.5 text-[13px] font-semibold text-[var(--color-text-secondary)] transition-colors hover:bg-[var(--color-surface-raised)] hover:text-[var(--color-text-primary)]"
            >
              <LogOut size={14} strokeWidth={2} />
              Sign out
            </button>
          </div>
        </>
      )}
    </div>
  );
}

// ── Main TopBar ───────────────────────────────────────────────────────────────

interface TopBarProps {
  /** Current page title — the final breadcrumb segment */
  title: string;
  /** Nav-group label shown as the breadcrumb segment before the title */
  section?: string;
  /** Unread notification count — pass 0 for no badge */
  unreadCount?: number;
  /** Search value (controlled) — omit to hide the search bar */
  searchValue?: string;
  onSearchChange?: (v: string) => void;
  /** Account avatar shown on the right — omit while auth state is loading */
  avatar?: AvatarInfo;
}

export function TopBar({
  title,
  section,
  unreadCount = 0,
  searchValue,
  onSearchChange,
  avatar,
}: TopBarProps) {
  return (
    <header
      className={[
        'sticky top-0 z-10',
        'flex items-center justify-between',
        'h-[72px] px-7 gap-4',
        'bg-[var(--color-surface-card)]/90 backdrop-blur-md',
        'border-b border-[var(--color-surface-border)]',
        'shrink-0',
      ].join(' ')}
    >
      {/* Left — breadcrumb */}
      <Breadcrumb section={section} title={title} />

      {/* Right — search + controls */}
      <div className="flex items-center gap-3 shrink-0">
        {onSearchChange && (
          <SearchBar value={searchValue ?? ''} onChange={onSearchChange} />
        )}

        <ConnectivityPill />
        <NotificationBell unread={unreadCount} />
        {avatar && <AvatarMenu avatar={avatar} />}
      </div>
    </header>
  );
}
