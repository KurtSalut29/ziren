'use client';

/**
 * The view switcher of the Operational Area — the shared NavTabs, sitting on the
 * foot of the header card so "where am I", "what am I looking at" and "where can
 * I go" read as one object instead of three stacked ones.
 *
 * All the behaviour (centring, the underline on the rule, hover, edge fades,
 * arrow keys) lives in components/ui/nav-tabs.tsx, so this screen's navigation
 * is the same object as Accounts', Verification's and Governance's. This file
 * only keeps the names the Operational Area already imports.
 */

import { NavTabs, type NavTabItem } from '@/components/ui/nav-tabs';

export type AreaTabItem = Omit<NavTabItem, 'badge'> & {
  /** A count worth a glance, drawn as an amber pill after the label. */
  attention?: number;
};

export const AREA_PANEL_ID = 'area-tabpanel';
export const areaTabId = (key: string) => `area-tab-${key}`;

export function AreaTabs({
  tabs,
  activeKey,
  onSelect,
  ariaLabel,
}: {
  tabs: AreaTabItem[];
  activeKey: string;
  onSelect: (key: string) => void;
  ariaLabel: string;
}) {
  return (
    <NavTabs
      ariaLabel={ariaLabel}
      activeKey={activeKey}
      // The card's own bottom edge is the rule; a second one would double it.
      framed={false}
      idPrefix="area-tab"
      onSelect={onSelect}
      panelId={AREA_PANEL_ID}
      tabs={tabs.map(({ attention, ...t }) => ({ ...t, badge: attention }))}
      className="border-t border-[var(--color-surface-border)]"
    />
  );
}
