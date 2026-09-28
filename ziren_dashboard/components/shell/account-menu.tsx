'use client';

/**
 * AccountMenu — the dropdown shared by every place the signed-in operator
 * can act on their account: the top nav's avatar and the sidebar footer
 * row. One component so "Appearance" or "Sign out" can never drift between
 * the two depending on which trigger someone happened to click.
 */

import { ReactNode } from 'react';
import { LogOut, Monitor, Moon, Sun } from 'lucide-react';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/efferd/ui/dropdown-menu';
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from '@/components/efferd/ui/alert-dialog';
import { ZirenLogo } from '@/components/brand/ziren-logo';
import { useTheme, type ThemePreference } from '@/lib/theme/use-theme';
import type { SidebarUser } from './app-shell';

const THEME_OPTIONS: { value: ThemePreference; label: string; icon: typeof Sun }[] = [
  { value: 'light', label: 'Light', icon: Sun },
  { value: 'dark', label: 'Dark', icon: Moon },
  { value: 'system', label: 'System', icon: Monitor },
];

export function AccountMenu({
  user,
  align = 'end',
  children,
}: {
  user: SidebarUser;
  /** 'start' for the sidebar footer, so the menu doesn't overhang the rail
   *  the way an 'end'-aligned one would; 'end' for the top nav. */
  align?: 'start' | 'end';
  children: ReactNode;
}) {
  const { preference, setPreference, mounted } = useTheme();

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>{children}</DropdownMenuTrigger>
      <DropdownMenuContent align={align} className="w-56">
        <DropdownMenuLabel className="flex flex-col gap-0.5">
          <span className="truncate text-[13px] font-medium">{user.name}</span>
          <span className="truncate text-[11.5px] font-normal text-muted-foreground">
            {user.email}
          </span>
        </DropdownMenuLabel>
        <DropdownMenuSeparator />
        <DropdownMenuLabel className="text-[11px] font-normal text-muted-foreground">
          Appearance
        </DropdownMenuLabel>
        {/* `mounted` gates only which row reads as selected. Rendering the
            rows unconditionally keeps the menu correctly sized on first
            paint; the server cannot know the stored preference. */}
        <DropdownMenuRadioGroup
          onValueChange={v => setPreference(v as ThemePreference)}
          value={mounted ? preference : ''}
        >
          {THEME_OPTIONS.map(({ value, label, icon: Icon }) => (
            <DropdownMenuRadioItem key={value} value={value}>
              <Icon />
              {label}
            </DropdownMenuRadioItem>
          ))}
        </DropdownMenuRadioGroup>
        <DropdownMenuSeparator />
        <AlertDialog>
          <AlertDialogTrigger asChild>
            {/* onSelect is prevented so Radix doesn't close (and unmount)
                the dropdown before the alert dialog's own trigger click
                has a chance to open it. */}
            <DropdownMenuItem onSelect={e => e.preventDefault()}>
              <LogOut />
              Sign out
            </DropdownMenuItem>
          </AlertDialogTrigger>
          {/* Redesigned 2026-09-29: the product owner asked for bigger, more
              professional choices and the Ziren mark on it. Brand band with
              the logo, who is signing out, what stops when they do, then two
              full-width 48px buttons — Cancel as a quiet outline, Sign out as
              the one filled action. Orange, not red: signing out is a
              deliberate everyday action, and red is reserved for critical
              severity (globals.css). */}
          <AlertDialogContent className="max-w-[calc(100vw-2rem)]! gap-0 overflow-hidden p-0 sm:max-w-[420px]!">
            <div className="relative flex flex-col items-center gap-3 bg-[linear-gradient(180deg,var(--color-brand-subtle),transparent)] px-6 pb-2 pt-7">
              <span className="flex size-[72px] items-center justify-center rounded-2xl border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] shadow-[var(--shadow-md)]">
                <ZirenLogo alt="Ziren" size={52} />
              </span>
              <span className="text-[11px] font-bold uppercase tracking-[0.22em] text-muted-foreground">Ziren</span>
            </div>
            <AlertDialogHeader className="place-items-center! px-6 pt-2 text-center!">
              <AlertDialogTitle className="text-[20px] font-bold tracking-tight">Sign out of Ziren?</AlertDialogTitle>
              <AlertDialogDescription className="text-[13.5px] leading-relaxed">
                This screen will stop receiving new-report and assist alerts until you sign in again.
              </AlertDialogDescription>
            </AlertDialogHeader>
            <div className="mx-6 mt-4 flex items-center gap-3 rounded-xl border border-[var(--color-surface-border)] bg-[var(--color-surface-raised)] px-3.5 py-3">
              <span
                aria-hidden="true"
                className="flex size-10 shrink-0 items-center justify-center rounded-full text-[13px] font-bold"
                style={{ backgroundColor: 'var(--color-brand)', color: 'var(--color-text-inverse)' }}
              >
                {user.initials}
              </span>
              <span className="min-w-0 flex-1">
                <span className="block truncate text-[14px] font-semibold text-foreground">{user.name}</span>
                <span className="block truncate text-[12px] text-muted-foreground">{user.agencyName ?? user.roleLabel}</span>
              </span>
            </div>
            <AlertDialogFooter className="grid! grid-cols-2 gap-3 px-6 pb-6 pt-5">
              <AlertDialogCancel className="h-12! rounded-xl! text-[14px]! font-semibold">
                Cancel
              </AlertDialogCancel>
              <AlertDialogAction
                className="h-12! gap-2 rounded-xl! bg-[var(--color-brand)]! text-[14px]! font-bold text-white shadow-[0_6px_16px_-6px_color-mix(in_srgb,var(--color-brand)_70%,transparent)] hover:bg-[var(--color-brand)] hover:brightness-110"
                onClick={user.onSignOut}
              >
                <LogOut aria-hidden="true" className="size-[18px]" />
                Sign out
              </AlertDialogAction>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
