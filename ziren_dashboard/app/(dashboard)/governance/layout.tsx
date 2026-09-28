'use client';

/**
 * System Governance — spec Section 11.
 *
 * Five tabs, sub-routed (not client-side tab state) so each one has its own
 * shareable URL and the Severity Configuration tab keeps working exactly as
 * /rubric always did — it's the same page, same component, just re-hosted at
 * /governance/severity. Agency Admin sees only that one tab: the other four
 * are Super-Admin-only governance surfaces the spec never gives an Agency
 * Admin a reason to open.
 */

import { usePathname } from 'next/navigation';
import {
  BrainCircuit, ClipboardList, Scale, ShieldCheck, Siren,
} from 'lucide-react';
import { useAuth } from '@/lib/hooks/useAuth';
import { NavTabs } from '@/components/ui/nav-tabs';

const TABS = [
  { href: '/governance/severity', label: 'Severity Configuration', icon: Scale, provincialAdminOnly: false },
  { href: '/governance/incident-configuration', label: 'Incident Configuration', icon: Siren, provincialAdminOnly: true },
  { href: '/governance/account-policies', label: 'Account Policies', icon: ShieldCheck, provincialAdminOnly: true },
  { href: '/governance/notification-policies', label: 'Notification Policies', icon: BrainCircuit, provincialAdminOnly: true },
  { href: '/governance/configuration-history', label: 'Configuration History', icon: ClipboardList, provincialAdminOnly: true },
] as const;

export default function GovernanceLayout({ children }: { children: React.ReactNode }) {
  const { isProvincialAdmin } = useAuth();
  const pathname = usePathname() ?? '';
  const tabs = TABS.filter(t => !t.provincialAdminOnly || isProvincialAdmin);

  return (
    <div className="min-h-full">
      {tabs.length > 1 && (
        <div className="sticky top-0 z-30 bg-[var(--color-surface-card)]">
          <NavTabs
            activeKey={tabs.find(t => pathname === t.href || pathname.startsWith(t.href + '/'))?.href ?? tabs[0].href}
            ariaLabel="System Governance sections"
            idPrefix="governance-tab"
            tabs={tabs.map(t => ({ key: t.href, label: t.label, icon: t.icon, href: t.href }))}
          />
        </div>
      )}
      {children}
    </div>
  );
}
