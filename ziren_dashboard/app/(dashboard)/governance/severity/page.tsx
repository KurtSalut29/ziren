'use client';

/**
 * Rubric Configuration — which agency's severity rules to look at.
 *
 * A Provincial Admin picks among every agency of their own agency_type; an
 * Agency Admin has exactly one and is sent straight to it. The cards report
 * what each agency is actually running,
 * because "which of these has a real config and which is still on the bundled
 * seed" is the only question this page can answer that the sidebar cannot.
 */

import { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { AlertTriangle, ArrowRight, CheckCircle2, Flame, Shield, Trees } from 'lucide-react';
import { useAuth } from '@/lib/hooks/useAuth';
import { apiClient } from '@/lib/api/client';
import { getActiveConfig, type AgencyType } from '@/lib/api/rubric';
import { Alert } from '@/components/ui/alert';
import { Fig } from '@/components/ui/fig';
import { Skeleton } from '@/components/efferd/ui/skeleton';
import {
  Card, CardContent, CardDescription, CardHeader, CardTitle,
} from '@/components/efferd/ui/card';

/**
 * Agency identity.
 *
 * `color` is the token, with NO hex fallback. The fallbacks that used to sit
 * here — #E53E3E, #3182CE, #38A169 — were a different red, blue and green from
 * the tokens they claimed to back up (#EF4444 / #0EA5E9 / #10B981), so the one
 * place they DID take effect, the `color-mix()` tile ground, mixed a hue this
 * console does not use. The icon and the ground behind it were literally
 * different colours. A token that is missing should look broken, not
 * plausible.
 */
const AGENCIES: {
  type: AgencyType;
  label: string;
  icon: typeof Flame;
  color: string;
  bg: string;
  description: string;
}[] = [
  {
    type: 'BFP',
    label: 'Bureau of Fire Protection',
    icon: Flame,
    color: 'var(--color-agency-bfp)',
    bg: 'var(--color-agency-bfp-bg)',
    description: 'Severity rules for fire, HAZMAT, and structure emergencies.',
  },
  {
    type: 'PNP',
    label: 'Philippine National Police',
    icon: Shield,
    color: 'var(--color-agency-pnp)',
    bg: 'var(--color-agency-pnp-bg)',
    description: 'Severity rules for crime, domestic disputes, and public safety incidents.',
  },
  {
    type: 'MDRRMO',
    label: 'Municipal DRRMO',
    icon: Trees,
    color: 'var(--color-agency-mdrrmo)',
    bg: 'var(--color-agency-mdrrmo-bg)',
    description: 'Severity rules for floods, landslides, calamities, and mass-casualty events.',
  },
];

/** What an agency is currently running. Null version = bundled seed. */
interface RubricStatus {
  version: string | null;
  ruleCount: number | null;
}

export default function RubricLandingPage() {
  const { token, isAgencyAdmin } = useAuth();
  const router = useRouter();

  /**
   * Whether the Agency Admin redirect is still in flight.
   *
   * The page used to do `if (isAgencyAdmin) return null` unconditionally, on
   * the assumption that the redirect always lands. Both of its own comments
   * said otherwise — "if agency_type is null … stay on this page" and
   * "redirect failed silently — fall through to show the selector" — and
   * neither was reachable past that early return. An Agency Admin whose
   * /users/me call failed, or whose account has no agency_type, got a
   * permanently blank page with no error and nothing to click.
   *
   * Now the return is gated on this flag, which the catch clears.
   */
  const [redirecting, setRedirecting] = useState(isAgencyAdmin);

  useEffect(() => {
    if (!isAgencyAdmin || !token) {
      setRedirecting(false);
      return;
    }
    let cancelled = false;
    apiClient
      .get<{ agency_type: string | null }>('/users/me', token)
      .then(me => {
        if (cancelled) return;
        if (me.agency_type) router.replace(`/governance/severity/${me.agency_type}`);
        else setRedirecting(false);   // no agency on the account — show the selector
      })
      .catch(() => { if (!cancelled) setRedirecting(false); });
    return () => { cancelled = true; };
  }, [isAgencyAdmin, token, router]);

  // ── What each agency is running ─────────────────────────────
  const [status, setStatus] = useState<Partial<Record<AgencyType, RubricStatus>>>({});
  const [statusLoading, setStatusLoading] = useState(true);

  const loadStatus = useCallback(async () => {
    if (!token) return;
    setStatusLoading(true);
    // Settled, not all: one agency's endpoint failing must not blank the other
    // two cards, which are independent reads of independent configs.
    const results = await Promise.allSettled(
      AGENCIES.map(a => getActiveConfig(a.type, token)),
    );
    const next: Partial<Record<AgencyType, RubricStatus>> = {};
    results.forEach((r, i) => {
      if (r.status !== 'fulfilled') return;
      next[AGENCIES[i].type] = r.value
        ? { version: r.value.version, ruleCount: r.value.rules.filter(x => x.active).length }
        : { version: null, ruleCount: null };
    });
    setStatus(next);
    setStatusLoading(false);
  }, [token]);

  useEffect(() => {
    if (redirecting) return;   // an Agency Admin is about to leave this page
    void loadStatus();
  }, [redirecting, loadStatus]);

  if (redirecting) return null;

  return (
    <div className="flex flex-col gap-4 px-6 py-5 md:px-7">
      {isAgencyAdmin && (
        <Alert
          variant="warning"
          message={
            'Your account has no agency type set, so it could not be sent to a ' +
            'single rubric. Pick one below to read it — saving changes still ' +
            'requires an agency. Ask a Provincial Admin to set your agency.'
          }
        />
      )}

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {AGENCIES.map(agency => {
          const Icon = agency.icon;
          const s = status[agency.type];
          return (
            <Link className="group" href={`/governance/severity/${agency.type}`} key={agency.type}>
              <Card className="h-full transition-[border-color,box-shadow] hover:border-[var(--color-brand)] hover:shadow-[var(--shadow-md)]">
                <CardHeader className="gap-2">
                  <span
                    aria-hidden="true"
                    className="flex size-11 items-center justify-center rounded-full"
                    style={{ backgroundColor: agency.bg, color: agency.color }}
                  >
                    <Icon className="size-5" />
                  </span>
                  <CardTitle className="flex flex-wrap items-center gap-2 text-[14px]">
                    <span className="font-bold" style={{ color: agency.color }}>
                      {agency.type}
                    </span>
                    <span className="text-foreground">{agency.label}</span>
                  </CardTitle>
                  <CardDescription>{agency.description}</CardDescription>
                </CardHeader>

                <CardContent className="flex items-center justify-between gap-3">
                  {/* What this agency is actually running. The old cards were
                      three identical links — nothing on them distinguished an
                      agency with a live config from one still on the seed, so
                      the only way to find out was to open all three. */}
                  {statusLoading && !s ? (
                    <Skeleton className="h-5 w-32" />
                  ) : s === undefined ? (
                    <span className="text-meta text-muted-foreground">
                      Status unavailable
                    </span>
                  ) : s.version ? (
                    <span className="flex items-center gap-1.5 text-meta text-[var(--color-system-success)]">
                      <CheckCircle2 className="size-3.5 shrink-0" />
                      v{s.version} active ·{' '}
                      <Fig className="text-[12px] font-semibold">{s.ruleCount}</Fig> rules
                    </span>
                  ) : (
                    <span className="flex items-center gap-1.5 text-meta text-[var(--color-system-warning)]">
                      <AlertTriangle className="size-3.5 shrink-0" />
                      Bundled seed
                    </span>
                  )}
                  <ArrowRight className="size-4 shrink-0 text-[var(--color-brand)] transition-transform group-hover:translate-x-0.5" />
                </CardContent>
              </Card>
            </Link>
          );
        })}
      </div>

      <Card>
        <CardContent className="py-4">
          <p className="text-meta leading-relaxed text-[var(--color-text-secondary)]">
            <span className="font-semibold">How the rubric engine works:</span> each
            agency has a versioned decision table. When a report arrives, the
            engine checks the signals extracted from it against every active
            rule for the relevant agency, and the highest severity any triggered
            rule contributes becomes the suggested severity.{' '}
            <span className="font-semibold">
              A dispatcher always has the final override.
            </span>{' '}
            Configs are versioned, and every upload and activation is written to
            an audit log.
          </p>
        </CardContent>
      </Card>
    </div>
  );
}
