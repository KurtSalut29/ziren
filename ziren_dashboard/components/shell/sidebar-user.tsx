'use client';

/**
 * SidebarUserFooter — the account row at the bottom of the nav column.
 *
 * The shadcn "NavUser" shape the @efferd/dashboard-3 reference ships —
 * avatar, name over email, a chevron marking it opens a menu — which Ziren
 * had never wired up; the sidebar footer carried the connectivity card
 * instead (see ConnectivityDot for where that moved).
 *
 * Opens the same AccountMenu the top nav's avatar does, so Appearance and
 * Sign out live in exactly one place regardless of which trigger someone
 * clicks. Collapses to just the avatar when the sidebar is in icon-rail
 * mode, matching every other row in this column.
 */

import { ChevronsUpDown } from 'lucide-react';
import {
  Avatar,
  AvatarFallback,
} from '@/components/efferd/ui/avatar';
import {
  SidebarFooter,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
} from '@/components/efferd/ui/sidebar';
import { AccountMenu } from './account-menu';
import type { SidebarUser as SidebarUserData } from './app-shell';

export function SidebarUserFooter({ user }: { user: SidebarUserData }) {
  return (
    <SidebarFooter>
      <SidebarMenu>
        <SidebarMenuItem>
          <AccountMenu align="start" user={user}>
            <SidebarMenuButton
              className="data-[state=open]:bg-sidebar-accent data-[state=open]:text-sidebar-accent-foreground"
              size="lg"
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
              <div className="grid flex-1 text-left leading-tight">
                <span className="truncate text-[13px] font-medium">{user.name}</span>
                <span className="truncate text-[11.5px] text-muted-foreground">
                  {user.email}
                </span>
              </div>
              <ChevronsUpDown className="ml-auto size-4 text-muted-foreground" />
            </SidebarMenuButton>
          </AccountMenu>
        </SidebarMenuItem>
      </SidebarMenu>
    </SidebarFooter>
  );
}
