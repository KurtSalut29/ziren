'use client';

/**
 * ZirenSidebar — the console's navigation column, built on the
 * @efferd/dashboard-3 sidebar structure the product owner adopted.
 *
 * Structure taken from the reference, verbatim in shape:
 *   header (mark + wordmark) → primary action + search → labelled nav groups
 *   with collapsible sub-trees → quiet footer links → user.
 *
 * Content is Ziren's. The nav comes from lib/nav/nav-config.ts, which is still
 * the single place role gating is expressed — this file renders whatever
 * getNavGroups() returns and performs no permission checks of its own.
 *
 * One departure from the reference: its "New Conversation" primary button
 * and the search control beside it are dropped rather than re-pointed. Both
 * duplicated something already on screen — Live Queue is a nav row two
 * items below, and the button only focused the header's search field — and
 * a primary action that repeats a nav item spends the loudest colour on the
 * sidebar saying nothing new.
 *
 * The reference's footer marketing card is gone; the connectivity state it
 * used to carry lives as a dot on the account avatar instead (see
 * ConnectivityDot) — still operational information, not chrome, but it no
 * longer needs a permanent slot to say so. What DOES take that slot now is
 * the reference's own "user" row (SidebarUserFooter): avatar, name, email,
 * a chevron that opens the same account menu the top nav's avatar does.
 */

import Link from 'next/link';
import { ChevronRight } from 'lucide-react';
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from '@/components/efferd/ui/collapsible';
import {
  Sidebar,
  SidebarContent,
  SidebarGroup,
  SidebarGroupLabel,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarMenuSub,
  SidebarMenuSubButton,
  SidebarMenuSubItem,
} from '@/components/efferd/ui/sidebar';
import {
  getNavGroups,
  isItemActive,
  isItemExpanded,
  type NavRole,
} from '@/lib/nav/nav-config';
import { ZirenLogo } from '@/components/brand/ziren-logo';
import { SidebarUserFooter } from './sidebar-user';
import type { SidebarUser } from './app-shell';

export function ZirenSidebar({
  role,
  pathname,
  user,
}: {
  role: NavRole;
  pathname: string;
  user: SidebarUser;
}) {
  const groups = getNavGroups(role);

  return (
    <Sidebar collapsible="icon" variant="inset">
      <SidebarHeader className="h-16 justify-center">
        <SidebarMenuButton asChild>
          <Link href="/overview">
            {/* ZirenLogo carries both the object-contain (the mark is not
                square inside its box, and `fill` would crop it) and the
                per-theme asset swap that replaced the old
                `dark:brightness-0 dark:invert` — that pair works by discarding
                colour, and the logo now has brand orange in it.
                size=32 (up from 24): the spec calls the previous mark too
                small for "sufficient visual identity" in the sidebar. Header
                bumped to h-16 alongside it so the larger mark doesn't crowd
                the wordmark next to it or the collapse toggle above. */}
            <ZirenLogo priority size={32} />
            {/* Set as a logotype, not as a word. Wide tracking on a short
                uppercase string is what separates a wordmark from a heading —
                at the default tracking it read as body copy that happened to
                be capitalised. */}
            <span className="text-[15px] font-bold leading-none tracking-[0.2em]">
              ZIREN
            </span>
          </Link>
        </SidebarMenuButton>
      </SidebarHeader>

      <SidebarContent>
        {groups.map(group => (
          <SidebarGroup key={group.label}>
            <SidebarGroupLabel>{group.label}</SidebarGroupLabel>
            <SidebarMenu className="gap-1.5">
              {group.items.map(item => {
                const active = isItemActive(item, pathname);
                const Icon = item.icon;

                // The efferd base gives an active row only a background tint
                // plus bold text — both close enough to the hover/default
                // look that "you are here" reads as "your cursor was near
                // here". The pre-efferd sidebar (components/shell/sidebar.tsx,
                // no longer rendered) put the actual identifying colour on the
                // ICON instead, precisely because brand orange as label text
                // on its own tint measures 4.1:1 — under the floor for text,
                // fine for an icon. That treatment never carried over when
                // this file replaced it; restoring it here, not inventing it.
                const iconStyle = active
                  ? { color: 'var(--color-nav-active-icon)' }
                  : undefined;

                // A left rail, on top of the tint + icon colour above rather
                // than instead of them — the rail is the shape a glance
                // catches first (it doesn't need to be read as colour at
                // all), the icon confirms it. SidebarMenuItem is already
                // `relative` (see sidebar.tsx), so this only needs to be
                // absolutely positioned, not given its own stacking context.
                const activeRail = active && (
                  <span
                    aria-hidden="true"
                    className="absolute left-0 top-1/2 h-5 w-[3px] -translate-y-1/2 rounded-r-full"
                    style={{ backgroundColor: 'var(--color-nav-active-icon)' }}
                  />
                );

                if (!item.children?.length) {
                  return (
                    <SidebarMenuItem key={item.href + item.label}>
                      {activeRail}
                      <SidebarMenuButton
                        asChild
                        isActive={active}
                        tooltip={item.label}
                      >
                        <Link href={item.href}>
                          <Icon strokeWidth={active ? 2.25 : 2} style={iconStyle} />
                          <span>{item.label}</span>
                        </Link>
                      </SidebarMenuButton>
                    </SidebarMenuItem>
                  );
                }

                return (
                  <Collapsible
                    asChild
                    className="group/collapsible"
                    defaultOpen={isItemExpanded(item, pathname)}
                    key={item.href + item.label}
                  >
                    <SidebarMenuItem>
                      {activeRail}
                      <CollapsibleTrigger asChild>
                        <SidebarMenuButton isActive={active} tooltip={item.label}>
                          <Icon strokeWidth={active ? 2.25 : 2} style={iconStyle} />
                          <span>{item.label}</span>
                          <ChevronRight className="ml-auto transition-transform duration-200 group-data-[state=open]/collapsible:rotate-90" />
                        </SidebarMenuButton>
                      </CollapsibleTrigger>
                      <CollapsibleContent>
                        <SidebarMenuSub>
                          {item.children.map(child => (
                            <SidebarMenuSubItem key={child.href}>
                              <SidebarMenuSubButton
                                asChild
                                isActive={isItemActive(child, pathname)}
                              >
                                <Link href={child.href}>
                                  <span>{child.label}</span>
                                </Link>
                              </SidebarMenuSubButton>
                            </SidebarMenuSubItem>
                          ))}
                        </SidebarMenuSub>
                      </CollapsibleContent>
                    </SidebarMenuItem>
                  </Collapsible>
                );
              })}
            </SidebarMenu>
          </SidebarGroup>
        ))}
      </SidebarContent>

      <SidebarUserFooter user={user} />
    </Sidebar>
  );
}
