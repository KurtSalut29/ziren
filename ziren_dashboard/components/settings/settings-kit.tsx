'use client';

/**
 * Compatibility layer over the Settings kit (kit.tsx).
 *
 * A few older panels — AI & NLP, Incident Categories, and the
 * link-outs to pages that already own their content — were written against
 * these names. Rather than rewrite each, the names are kept and drawn with the
 * new kit, so every panel in Settings has one look.
 *
 * What is NOT here any more, deliberately: PlaceholderPanel and ComingSoonBadge,
 * which drew a disabled switch beside a "Not available yet" badge. A control
 * that cannot be used does not belong on a settings screen; where a feature
 * does not exist, the panel now says so in words and offers what does.
 */

import Link from 'next/link';
import { ArrowRight } from 'lucide-react';
import type { LucideIcon } from 'lucide-react';
import { Card, PanelHeader, Row, RowList } from '@/components/settings/kit';
import { cn } from '@/lib/utils';

/** A section's heading, description and body. */
export function SettingsPanel({
  icon,
  title,
  description,
  children,
}: {
  icon?: LucideIcon;
  title: string;
  description?: React.ReactNode;
  children: React.ReactNode;
}) {
  // Imported lazily to keep this file's own icon optional: the older panels
  // did not always pass one.
  return (
    <div className="flex flex-col gap-6">
      <PanelHeader description={description} icon={icon ?? ArrowRight} title={title} />
      {children}
    </div>
  );
}

/** A list of rows, in a card. */
export function SettingsRowGroup({ children }: { children: React.ReactNode }) {
  return (
    <Card flush>
      <RowList>{children}</RowList>
    </Card>
  );
}

/** One setting: what it is on the left, its control on the right. */
export function SettingsRow({
  icon,
  label,
  description,
  htmlFor,
  children,
}: {
  icon?: LucideIcon;
  label: string;
  description?: string;
  htmlFor?: string;
  children?: React.ReactNode;
}) {
  return (
    <Row description={description} htmlFor={htmlFor} icon={icon} label={label}>
      {children}
    </Row>
  );
}

/** Several inputs that are genuinely one form. */
export function SettingsFieldGroup({
  children,
  className,
}: {
  children: React.ReactNode;
  className?: string;
}) {
  return <Card className={cn(className)}>{children}</Card>;
}

/**
 * A settings item whose real content lives on a page that already exists —
 * Agencies, Users & Roles, Severity Rules, Audit Logs, System Status. Rebuilding
 * any of those here would mean two places maintaining the same list, so this
 * points at the one that already does.
 */
export function LinkOutPanel({
  icon,
  title,
  description,
  href,
  cta = 'Open',
}: {
  icon?: LucideIcon;
  title: string;
  description: string;
  href: string;
  cta?: string;
}) {
  return (
    <div className="flex flex-col gap-6">
      <PanelHeader description={description} icon={icon ?? ArrowRight} title={title} />
      <Card>
        <div className="flex flex-wrap items-center justify-between gap-3">
          <p className="max-w-[54ch] text-[13px] leading-relaxed text-[var(--color-text-secondary)]">
            This is managed on its own page, so there is one list to keep correct instead of two.
          </p>
          <Link
            className="inline-flex items-center gap-1.5 rounded-lg bg-[var(--color-brand)] px-3.5 py-2 text-[13px] font-semibold text-white transition-opacity hover:opacity-90"
            href={href}
          >
            {cta} <ArrowRight className="size-3.5" />
          </Link>
        </div>
      </Card>
    </div>
  );
}
