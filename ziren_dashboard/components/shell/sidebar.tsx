'use client';

/**
 * Sidebar — fixed navigation column inside the app frame.
 *
 * Structure, top to bottom: logo row with collapse control, labelled nav
 * groups with expandable items and an indented sub-item tree, and a bordered
 * user card pinned to the bottom.
 *
 * Search moved to the topbar. It survives here only below md, where this panel
 * is the off-canvas drawer and the topbar has no room for a field — dropping
 * it outright would have taken search off mobile rather than relocating it.
 *
 * Contains no role logic. It renders the groups getNavGroups() hands it, so
 * permissions are auditable in one file instead of being spread through markup.
 */

import { useEffect, useId, useState } from 'react';
import Link from 'next/link';
import {
  ChevronDown,
  ChevronsLeft,
  ChevronsRight,
  LogOut,
  Monitor,
  Moon,
  Sun,
  X,
} from 'lucide-react';
import {
  getNavGroups,
  isItemActive,
  isItemExpanded,
  type ResolvedNavItem,
  type NavRole,
} from '@/lib/nav/nav-config';
import { ZirenLogo } from '@/components/brand/ziren-logo';
import { useTheme, type ThemePreference } from '@/lib/theme/use-theme';
import { ShellSearch } from './shell-search';

export interface SidebarUser {
  name: string;
  email: string;
  initials: string;
  roleLabel: string;
  onSignOut: () => void;
}

interface SidebarProps {
  role: NavRole;
  pathname: string;
  user: SidebarUser;
  collapsed: boolean;
  onToggleCollapsed: () => void;
  /** Mobile drawer state — ignored at >=768px, where the sidebar is static. */
  drawerOpen: boolean;
  onCloseDrawer: () => void;
  searchValue: string;
  onSearchChange: (v: string) => void;
}

export function Sidebar({
  role,
  pathname,
  user,
  collapsed,
  onToggleCollapsed,
  drawerOpen,
  onCloseDrawer,
  searchValue,
  onSearchChange,
}: SidebarProps) {
  const groups = getNavGroups(role);

  return (
    <>
      {/* Scrim — mobile only. Closing on click is the expected gesture, and
          the drawer is also Escape-closable from AppShell. */}
      {drawerOpen && (
        <div
          className="fixed inset-0 z-30 bg-black/40 md:hidden"
          onClick={onCloseDrawer}
          aria-hidden="true"
        />
      )}

      <aside
        aria-label="Main navigation"
        className={[
          'z-40 flex shrink-0 flex-col',
          'border-r border-[var(--color-surface-border)]',
          'bg-[var(--color-sidebar)]',
          'transition-[width,transform] duration-200',
          collapsed ? 'w-[68px]' : 'w-[236px]',
          // Below md the sidebar leaves the flow entirely and slides in as an
          // off-canvas drawer, so the content area gets the full width.
          'fixed inset-y-0 left-0 md:static md:translate-x-0',
          drawerOpen ? 'translate-x-0' : '-translate-x-full',
        ].join(' ')}
      >
        {/* ── Logo row ─────────────────────────────────────── */}
        <div className="flex h-[60px] shrink-0 items-center gap-2.5 px-4">
          <Link
            href="/overview"
            className="flex min-w-0 items-center gap-2.5 rounded-[var(--radius-md)]"
            aria-label="Ziren — go to overview"
          >
            {/*
              Monogram, not the full lockup: the visible "ZIREN" beside it
              already carries the name, and the wordmark inside a 32px square
              is illegible at any weight.

              The per-theme swap lives in ZirenLogo. This used to be
              `dark:brightness-0 dark:invert` on a single asset, which worked
              only while the mark was monochrome — it flattens colour by
              design, and the current logo has brand orange in it.
            */}
            <ZirenLogo priority size={32} />
            {!collapsed && (
              <span className="truncate text-[16px] font-bold tracking-tight text-[var(--color-text-primary)]">
                ZIREN
              </span>
            )}
          </Link>

          {!collapsed && (
            <button
              type="button"
              onClick={onToggleCollapsed}
              aria-label="Collapse sidebar"
              className="ml-auto hidden h-7 w-7 shrink-0 items-center justify-center rounded-[var(--radius-md)] text-[var(--color-text-tertiary)] transition-colors hover:bg-[var(--color-surface-hover)] hover:text-[var(--color-text-primary)] md:flex"
            >
              <ChevronsLeft size={16} strokeWidth={1.9} />
            </button>
          )}

          {/* Drawer close — mobile only, where the collapse control is
              meaningless because the whole panel slides away instead. */}
          <button
            type="button"
            onClick={onCloseDrawer}
            aria-label="Close navigation"
            className="ml-auto flex h-7 w-7 shrink-0 items-center justify-center rounded-[var(--radius-md)] text-[var(--color-text-tertiary)] transition-colors hover:bg-[var(--color-surface-hover)] hover:text-[var(--color-text-primary)] md:hidden"
          >
            <X size={16} strokeWidth={1.9} />
          </button>
        </div>

        {collapsed && (
          <button
            type="button"
            onClick={onToggleCollapsed}
            aria-label="Expand sidebar"
            className="mx-auto mb-2 hidden h-7 w-7 items-center justify-center rounded-[var(--radius-md)] text-[var(--color-text-tertiary)] transition-colors hover:bg-[var(--color-surface-hover)] hover:text-[var(--color-text-primary)] md:flex"
          >
            <ChevronsRight size={16} strokeWidth={1.9} />
          </button>
        )}

        {/* ── Search — drawer only ─────────────────────────── */}
        {/* md:hidden, not `!collapsed`: above md this is the static sidebar
            and the topbar owns the field. Rendering both would put two search
            boxes on screen at desktop width. */}
        <div className="shrink-0 px-3 pb-3 md:hidden">
          <ShellSearch value={searchValue} onChange={onSearchChange} />
        </div>

        {/* ── Nav groups ───────────────────────────────────── */}
        <nav className="min-h-0 flex-1 overflow-y-auto px-3 pb-3">
          {groups.map(group => (
            <div key={group.label} className="mb-5 last:mb-0">
              {!collapsed && (
                <p className="px-3 pb-2 text-section-label text-[var(--color-text-tertiary)]">
                  {group.label}
                </p>
              )}
              <ul className="flex flex-col gap-0.5">
                {group.items.map(item => (
                  <li key={item.href + item.label}>
                    <NavRow
                      item={item}
                      pathname={pathname}
                      collapsed={collapsed}
                      onNavigate={onCloseDrawer}
                    />
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </nav>

        {/* ── User card ────────────────────────────────────── */}
        <div className="shrink-0 p-3">
          <UserCard user={user} collapsed={collapsed} />
        </div>
      </aside>
    </>
  );
}

// ── Nav row ───────────────────────────────────────────────────────────────────

function NavRow({
  item,
  pathname,
  collapsed,
  onNavigate,
}: {
  item: ResolvedNavItem;
  pathname: string;
  collapsed: boolean;
  onNavigate: () => void;
}) {
  const active = isItemActive(item, pathname);
  const hasChildren = Boolean(item.children?.length);
  const submenuId = useId();

  // Route-driven, but user-overridable: the initial value follows the URL, and
  // the effect re-opens the group when navigation moves into it. It does not
  // force it closed again, so a group the user opened by hand stays open.
  const [open, setOpen] = useState(() => isItemExpanded(item, pathname));
  useEffect(() => {
    if (isItemExpanded(item, pathname)) setOpen(true);
  }, [item, pathname]);

  const Icon = item.icon;

  /* The active row wears the brand tint, not the grey hover fill it used
     to share with every other row. "You are here" and "your cursor is
     here" were previously the same pixel colour, which made the sidebar
     unreadable at a glance and spent nothing on the one place the colour
     rules actually reserve brand orange for.

     Hue lands on the fill and the icon; the label stays on a text token.
     Brand orange as 13.5px label text on its own tint is 4.1:1, under the
     floor — and the icon beside it already carries the identity. */
  const rowClass = [
    'group flex w-full items-center gap-2.5 rounded-[var(--radius-md)] px-3',
    'text-[13.5px] transition-colors',
    collapsed ? 'justify-center px-0' : '',
    active
      ? 'bg-[var(--color-nav-active-bg)] font-medium text-[var(--color-text-primary)]'
      : 'font-normal text-[var(--color-text-tertiary)] hover:bg-[var(--color-surface-hover)] hover:text-[var(--color-text-primary)]',
  ].join(' ');

  /* Inline rather than a class: the icon has to break out of the row's
     inherited text colour, and only when active. */
  const iconStyle = active ? { color: 'var(--color-nav-active-icon)' } : undefined;

  if (hasChildren && !collapsed) {
    return (
      <>
        <button
          type="button"
          onClick={() => setOpen(o => !o)}
          aria-expanded={open}
          aria-controls={submenuId}
          className={rowClass}
          style={{ height: '38px' }}
        >
          <Icon
            size={16}
            strokeWidth={active ? 2 : 1.75}
            className="shrink-0"
            style={iconStyle}
          />
          <span className="truncate">{item.label}</span>
          <ChevronDown
            size={14}
            strokeWidth={2}
            aria-hidden="true"
            className={[
              'ml-auto shrink-0 transition-transform duration-200',
              open ? 'rotate-180' : 'rotate-0',
            ].join(' ')}
          />
        </button>

        {open && (
          <ul id={submenuId} className="relative mt-0.5 ml-[21px] flex flex-col gap-0.5 pl-3.5">
            {/* Tree spine. aria-hidden: it is a drawn line, and the list
                already conveys the parent/child relationship semantically. */}
            <span
              aria-hidden="true"
              className="absolute left-0 top-1 bottom-3 w-px bg-[var(--color-surface-border)]"
            />
            {item.children!.map(child => {
              const childActive = isItemActive(child, pathname);
              return (
                <li key={child.href} className="relative">
                  <span
                    aria-hidden="true"
                    className="absolute left-[-14px] top-1/2 h-px w-2.5 bg-[var(--color-surface-border)]"
                  />
                  <Link
                    href={child.href}
                    onClick={onNavigate}
                    aria-current={childActive ? 'page' : undefined}
                    className={[
                      'flex items-center rounded-[var(--radius-md)] px-2.5 text-[13px] transition-colors',
                      childActive
                        ? 'bg-[var(--color-nav-active-bg)] font-medium text-[var(--color-text-primary)]'
                        : 'text-[var(--color-text-tertiary)] hover:bg-[var(--color-surface-hover)] hover:text-[var(--color-text-primary)]',
                    ].join(' ')}
                    style={{ height: '32px' }}
                  >
                    <span className="truncate">{child.label}</span>
                  </Link>
                </li>
              );
            })}
          </ul>
        )}
      </>
    );
  }

  // Collapsed rail, or a leaf item. A collapsed expandable row navigates to its
  // own href rather than expanding — there is no room to show a subtree.
  return (
    <Link
      href={item.href}
      onClick={onNavigate}
      aria-current={active ? 'page' : undefined}
      title={collapsed ? item.label : undefined}
      className={rowClass}
      style={{ height: '38px' }}
    >
      <Icon
        size={16}
        strokeWidth={active ? 2 : 1.75}
        className="shrink-0"
        style={iconStyle}
      />
      {!collapsed && <span className="truncate">{item.label}</span>}
    </Link>
  );
}

// ── User card ─────────────────────────────────────────────────────────────────

const THEME_OPTIONS: { value: ThemePreference; label: string; icon: typeof Sun }[] = [
  { value: 'light', label: 'Light', icon: Sun },
  { value: 'dark', label: 'Dark', icon: Moon },
  { value: 'system', label: 'System', icon: Monitor },
];

function UserCard({ user, collapsed }: { user: SidebarUser; collapsed: boolean }) {
  const [open, setOpen] = useState(false);
  const { preference, setPreference, mounted } = useTheme();
  const menuId = useId();

  useEffect(() => {
    if (!open) return;
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setOpen(false);
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [open]);

  if (collapsed) {
    return (
      <button
        type="button"
        onClick={user.onSignOut}
        title={`Sign out — ${user.name}`}
        aria-label={`Sign out, signed in as ${user.name}`}
        className="mx-auto flex h-9 w-9 select-none items-center justify-center rounded-full text-[11px] font-semibold text-[var(--color-text-inverse)]"
        style={{ backgroundColor: 'var(--color-brand)' }}
      >
        {user.initials}
      </button>
    );
  }

  return (
    <div className="relative">
      {open && (
        <>
          <button
            aria-hidden="true"
            tabIndex={-1}
            className="fixed inset-0 z-10 cursor-default"
            onClick={() => setOpen(false)}
          />
          <div
            id={menuId}
            role="menu"
            className="absolute bottom-[calc(100%+8px)] left-0 right-0 z-20 overflow-hidden rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-overlay)] py-1 shadow-[var(--shadow-lg)]"
          >
            <p className="px-3 pb-1.5 pt-2 text-section-label text-[var(--color-text-tertiary)]">
              Appearance
            </p>
            {THEME_OPTIONS.map(({ value, label, icon: Icon }) => {
              // `mounted` gates the checkmark only. Rendering the rows
              // unconditionally keeps the menu usable and correctly sized
              // during the first paint; only which one is *selected* has to
              // wait for the client, because the server cannot know it.
              const selected = mounted && preference === value;
              return (
                <button
                  key={value}
                  role="menuitemradio"
                  aria-checked={selected}
                  onClick={() => {
                    setPreference(value);
                    setOpen(false);
                  }}
                  className={[
                    'flex w-full items-center gap-2.5 px-3 py-2 text-[13px] transition-colors',
                    'hover:bg-[var(--color-surface-hover)]',
                    selected
                      ? 'font-medium text-[var(--color-text-primary)]'
                      : 'text-[var(--color-text-tertiary)]',
                  ].join(' ')}
                >
                  <Icon size={14} strokeWidth={1.9} aria-hidden="true" />
                  {label}
                  {selected && (
                    <span
                      aria-hidden="true"
                      className="ml-auto h-1.5 w-1.5 rounded-full"
                      style={{ backgroundColor: 'var(--color-brand)' }}
                    />
                  )}
                </button>
              );
            })}

            <div className="my-1 h-px bg-[var(--color-surface-border)]" />

            <button
              role="menuitem"
              onClick={user.onSignOut}
              className="flex w-full items-center gap-2.5 px-3 py-2 text-[13px] font-medium text-[var(--color-text-tertiary)] transition-colors hover:bg-[var(--color-surface-hover)] hover:text-[var(--color-text-primary)]"
            >
              <LogOut size={14} strokeWidth={1.9} aria-hidden="true" />
              Sign out
            </button>
          </div>
        </>
      )}

      <button
        type="button"
        onClick={() => setOpen(o => !o)}
        aria-haspopup="menu"
        aria-expanded={open}
        aria-controls={open ? menuId : undefined}
        className="flex w-full items-center gap-2.5 rounded-[var(--radius-control)] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] p-2.5 text-left transition-colors hover:bg-[var(--color-surface-hover)]"
      >
        <span
          aria-hidden="true"
          className="flex h-8 w-8 shrink-0 select-none items-center justify-center rounded-full text-[11px] font-semibold text-[var(--color-text-inverse)]"
          style={{ backgroundColor: 'var(--color-brand)' }}
        >
          {user.initials}
        </span>
        <span className="min-w-0 flex-1">
          <span className="block truncate text-[13px] font-medium leading-tight text-[var(--color-text-primary)]">
            {user.name}
          </span>
          <span className="mt-0.5 block truncate text-[11.5px] leading-tight text-[var(--color-text-muted)]">
            {user.email}
          </span>
        </span>
        <ChevronDown
          size={14}
          strokeWidth={2}
          aria-hidden="true"
          className={[
            'shrink-0 text-[var(--color-text-muted)] transition-transform duration-200',
            open ? 'rotate-180' : 'rotate-0',
          ].join(' ')}
        />
      </button>
    </div>
  );
}
