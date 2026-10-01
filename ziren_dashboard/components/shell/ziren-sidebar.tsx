'use client';

/**
 * ZirenSidebar — the console's navigation column, built on the
 * @efferd/dashboard-3 sidebar structure the product owner adopted.
 *
 * Structure taken from the reference, verbatim in shape:
 *   header (mark + wordmark) → labelled nav groups with collapsible
 *   sub-trees → user.
 *
 * Content is Ziren's. The nav comes from lib/nav/nav-config.ts, which is still
 * the single place role gating is expressed — this file renders whatever
 * getNavGroups() returns and performs no permission checks of its own.
 *
 * THE ACTIVE ROW
 *
 * Redesigned 2026-09-29 at the product owner's request ("pagandahin pa, lalo
 * na ang active state"). The earlier row was a pale tint, an orange icon and a
 * thin left rail — three quiet signals that together still read as "hovered".
 * Now the ICON sits in a solid brand-orange chip with a soft orange glow, on a
 * tinted row with a hairline orange ring, and the label turns bold. The label
 * stays in the primary text colour rather than white-on-orange: brand orange
 * under white small text measures 3.0:1, and a nav label is read at a glance
 * all shift long. The chip carries the colour; the text carries the words.
 * Brand orange here is within the colour rules (globals.css): CTAs and the
 * active nav item are exactly what it is reserved for.
 *
 * THE COLLAPSED RAIL
 *
 * Collapsed, the rail used to be 3rem, which left a 16px box for a 32px logo:
 * the mark was cut in half. The rail is 3.5rem now (see SIDEBAR_WIDTH_ICON)
 * and the header button drops its padding when collapsed, so the whole mark
 * shows, centred, at the same size as the icon chips beneath it.
 *
 * BADGES
 *
 * `badges` maps an href to a count (the layout sets one for Assist Requests).
 * Expanded, it is a pill at the row's end; collapsed, a dot on the icon, so
 * the rail still says "something here needs you".
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
  type ResolvedNavItem,
} from '@/lib/nav/nav-config';
import { ZirenLogo } from '@/components/brand/ziren-logo';
import { cn } from '@/lib/utils';
import { SidebarUserFooter } from './sidebar-user';
import type { SidebarUser } from './app-shell';

/**
 * Row geometry and states, layered over the efferd base. The base's own
 * `data-active:bg-sidebar-accent` is kept (it IS the tint); what is added is
 * the ring, the weight and the collapsed centring.
 */
const ROW = cn(
  'h-10 gap-3 rounded-xl px-2 text-[13.5px] font-medium text-[var(--color-text-secondary)]',
  'transition-[background-color,color,box-shadow] duration-150',
  'hover:bg-[var(--color-surface-hover)] hover:text-foreground',
  'data-active:font-semibold data-active:text-[var(--color-text-primary)]',
  'data-active:shadow-[inset_0_0_0_1px_color-mix(in_srgb,var(--color-brand)_22%,transparent)]',
  'data-active:hover:bg-sidebar-accent',
  'group-data-[collapsible=icon]:size-10! group-data-[collapsible=icon]:justify-center group-data-[collapsible=icon]:p-0!',
);

function IconChip({ item, active, badge }: { item: ResolvedNavItem; active: boolean; badge: number }) {
  const Icon = item.icon;
  return (
    <span
      className={cn(
        'relative flex size-7 shrink-0 items-center justify-center rounded-lg transition-[background-color,color,box-shadow] duration-150',
        active
          ? 'bg-[var(--color-brand)] text-white shadow-[0_4px_12px_-3px_color-mix(in_srgb,var(--color-brand)_65%,transparent)]'
          : 'text-[var(--color-text-tertiary)] group-hover/menu-button:bg-[var(--color-surface-raised)] group-hover/menu-button:text-foreground',
      )}
    >
      <Icon strokeWidth={active ? 2.4 : 2} />
      {badge > 0 && (
        <span
          aria-hidden="true"
          className="absolute -right-1 -top-1 hidden size-2.5 rounded-full border-2 border-[var(--color-sidebar)] bg-[var(--color-brand)] group-data-[collapsible=icon]:block"
        />
      )}
    </span>
  );
}

function CountPill({ count, active }: { count: number; active: boolean }) {
  if (count <= 0) return null;
  return (
    <span
      className={cn(
        'ml-auto flex h-5 min-w-5 shrink-0 items-center justify-center rounded-full px-1.5 text-[11px] font-bold tabular-nums group-data-[collapsible=icon]:hidden',
        active ? 'bg-[var(--color-surface-card)] text-[var(--color-brand)]' : 'bg-[var(--color-brand)] text-white',
      )}
    >
      {count > 99 ? '99+' : count}
    </span>
  );
}

export function ZirenSidebar({
  role,
  pathname,
  user,
  badges,
}: {
  role: NavRole;
  pathname: string;
  user: SidebarUser;
  badges?: Record<string, number>;
}) {
  const groups = getNavGroups(role);

  return (
    <Sidebar collapsible="icon" variant="inset">
      <SidebarHeader className="h-16 justify-center group-data-[collapsible=icon]:items-center">
        <SidebarMenuButton
          asChild
          className="h-11 gap-2.5 rounded-xl px-1.5 hover:bg-transparent group-data-[collapsible=icon]:size-10! group-data-[collapsible=icon]:justify-center group-data-[collapsible=icon]:p-1!"
          tooltip="Ziren — Dashboard"
        >
          <Link href="/overview">
            {/* ZirenLogo carries both the object-contain (the mark is not
                square inside its box, and `fill` would crop it) and the
                per-theme asset swap. 32px: the same box as the collapsed
                button's content area, so collapsing never crops it. */}
            <ZirenLogo priority size={32} />
            {/* Set as a logotype, not as a word — wide tracking on a short
                uppercase string is what separates a wordmark from a heading. */}
            <span className="flex flex-col leading-none group-data-[collapsible=icon]:hidden">
              <span className="text-[15px] font-bold tracking-[0.2em] text-foreground">ZIREN</span>
              <span className="mt-1 text-[10px] font-semibold uppercase tracking-[0.14em] text-muted-foreground">Dispatch console</span>
            </span>
          </Link>
        </SidebarMenuButton>
      </SidebarHeader>

      <SidebarContent className="scroll-slim">
        {groups.map(group => (
          <SidebarGroup className="py-1.5" key={group.label}>
            <SidebarGroupLabel className="h-7 px-2.5 text-[10.5px] font-bold uppercase tracking-[0.12em] text-[var(--color-text-tertiary)]">
              {group.label}
            </SidebarGroupLabel>
            <SidebarMenu className="gap-1">
              {group.items.map(item => {
                const active = isItemActive(item, pathname);
                const badge = badges?.[item.href] ?? 0;
                const tooltip = badge > 0 ? `${item.label} · ${badge} need${badge === 1 ? 's' : ''} attention` : item.label;

                if (!item.children?.length) {
                  return (
                    <SidebarMenuItem key={item.href + item.label}>
                      <SidebarMenuButton
                        asChild
                        className={ROW}
                        isActive={active}
                        tooltip={tooltip}
                      >
                        <Link aria-current={active ? 'page' : undefined} data-demo={`nav:${item.href}`} href={item.href}>
                          <IconChip active={active} badge={badge} item={item} />
                          <span className="group-data-[collapsible=icon]:hidden">{item.label}</span>
                          <CountPill active={active} count={badge} />
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
                      <CollapsibleTrigger asChild>
                        <SidebarMenuButton className={ROW} isActive={active} tooltip={item.label}>
                          <IconChip active={active} badge={0} item={item} />
                          <span className="group-data-[collapsible=icon]:hidden">{item.label}</span>
                          <ChevronRight className="ml-auto group-data-[collapsible=icon]:hidden transition-transform duration-200 group-data-[state=open]/collapsible:rotate-90" />
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
