'use client';

/**
 * ZirenHeader — the top bar, on the @efferd/dashboard-3 header structure.
 *
 * Reference shape, kept: sidebar trigger → vertical rule → breadcrumbs on the
 * left; outline icon buttons → vertical rule → user menu on the right. Sticky,
 * h-14, bordered underneath.
 *
 * Ziren content in the slots: the notification bell with its unread count,
 * a one-click theme toggle, settings, and a user menu carrying the full
 * Light/Dark/System choice and sign-out. The reference's send-message
 * button has no counterpart here and is dropped rather than given an
 * invented job.
 *
 * The account avatar also carries a small connectivity dot (bottom-right
 * corner) — see ConnectivityDot. It replaced a permanent sidebar-footer
 * card with the same colored-dot-on-avatar convention Gmail/Google Chat
 * use for presence.
 */

import Link from 'next/link';
import { Moon, Settings, Sun } from 'lucide-react';
import { AccountMenu } from './account-menu';
import { ConnectivityDot } from './connectivity-dot';
import { Button } from '@/components/efferd/ui/button';
import { Separator } from '@/components/efferd/ui/separator';
import { SidebarTrigger } from '@/components/efferd/ui/sidebar';
import {
  Breadcrumb,
  BreadcrumbItem,
  BreadcrumbList,
  BreadcrumbPage,
  BreadcrumbSeparator,
} from '@/components/efferd/ui/breadcrumb';
import {
  Avatar,
  AvatarFallback,
} from '@/components/efferd/ui/avatar';
import { useTheme } from '@/lib/theme/use-theme';
import { NotificationCenter } from './notification-center';
import type { SidebarUser } from './app-shell';

export function ZirenHeader({
  title,
  section,
  token,
  user,
}: {
  title: string;
  section?: string;
  token: string | null;
  user: SidebarUser;
}) {
  const { theme, toggle, mounted } = useTheme();

  return (
    <header className="sticky top-0 z-50 flex h-14 shrink-0 items-center justify-between gap-2 border-b bg-background px-4 md:px-6">
      <div className="flex min-w-0 items-center gap-3">
        <SidebarTrigger />
        <Separator
          className="mr-1 h-4 data-[orientation=vertical]:self-center"
          orientation="vertical"
        />
        {/* No fixed root crumb. It read "Overview" while the page it pointed
            at is called "Dashboard", so /overview rendered "Overview >
            Dashboard" — the same destination named twice, differently. A
            crumb trail should only contain places, and the one place above a
            section page is the section. */}
        <Breadcrumb>
          <BreadcrumbList>
            {section ? (
              <>
                <BreadcrumbItem className="hidden md:block">
                  {section}
                </BreadcrumbItem>
                <BreadcrumbSeparator className="hidden md:block" />
              </>
            ) : null}
            <BreadcrumbItem>
              <BreadcrumbPage>{title}</BreadcrumbPage>
            </BreadcrumbItem>
          </BreadcrumbList>
        </Breadcrumb>
      </div>

      <div className="flex shrink-0 items-center gap-2 md:gap-3">
        <NotificationCenter token={token} />
        {/* One click, not a menu — the dropdown's own Light/Dark/System
            radio group stays for the person who wants "System" specifically;
            this is for everyone else, who just wants the lights off. Mirrors
            `mounted` the same way the dropdown's selected row does, so the
            icon doesn't paint a guess before the stored preference loads. */}
        <Button
          aria-label={mounted && theme === 'dark' ? 'Switch to light mode' : 'Switch to dark mode'}
          onClick={toggle}
          size="icon-sm"
          type="button"
          variant="outline"
        >
          {mounted && theme === 'dark' ? <Moon /> : <Sun />}
        </Button>
        <Button aria-label="Settings" asChild size="icon-sm" variant="outline">
          <Link href="/settings">
            <Settings />
          </Link>
        </Button>
        <Separator
          className="hidden h-4 data-[orientation=vertical]:self-center sm:block"
          orientation="vertical"
        />

        <AccountMenu user={user}>
          <button
            aria-label={`Account menu, signed in as ${user.name}`}
            className="relative rounded-full outline-none focus-visible:ring-2 focus-visible:ring-ring"
            type="button"
          >
            <Avatar className="size-8">
              <AvatarFallback
                className="text-[11px] font-semibold"
                style={{
                  backgroundColor: 'var(--color-brand)',
                  color: 'var(--color-text-inverse)',
                }}
              >
                {user.initials}
              </AvatarFallback>
            </Avatar>
            <ConnectivityDot />
          </button>
        </AccountMenu>
      </div>
    </header>
  );
}
