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
  AlertDialogMedia,
  AlertDialogTitle,
  AlertDialogTrigger,
} from '@/components/efferd/ui/alert-dialog';
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
          <AlertDialogContent>
            <AlertDialogHeader>
              <AlertDialogMedia tone="neutral"><LogOut /></AlertDialogMedia>
              <AlertDialogTitle>Sign Out?</AlertDialogTitle>
              <AlertDialogDescription>
                Are you sure you want to sign out of your Ziren account?
              </AlertDialogDescription>
            </AlertDialogHeader>
            <AlertDialogFooter>
              <AlertDialogCancel>Cancel</AlertDialogCancel>
              <AlertDialogAction onClick={user.onSignOut}>Sign Out</AlertDialogAction>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
