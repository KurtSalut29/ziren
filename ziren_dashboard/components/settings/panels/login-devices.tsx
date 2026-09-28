'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { useRouter } from 'next/navigation';
import {
  Clock, History, Laptop, LogOut, MonitorSmartphone, Smartphone, Timer,
} from 'lucide-react';
import { ApiError } from '@/lib/api/client';
import {
  describeAction, fetchMyActivity, revokeSessions, type ActivityItem,
} from '@/lib/api/account';
import { signOut } from '@/lib/hooks/useAuth';
import { describeDevice, readSessionTiming, timeAgo } from '@/lib/utils/device';
import { displayPrefs, privacyPrefs, type PrivacyPrefs } from '@/lib/prefs/definitions';
import { formatDateTime } from '@/lib/format/datetime';
import { Button } from '@/components/efferd/ui/button';
import { Skeleton } from '@/components/efferd/ui/skeleton';
import {
  Callout, Card, PanelHeader, Row, RowList, SavedFlash, Segmented, StatusDot,
} from '@/components/settings/kit';
import { useNotice } from '@/lib/toast';

export function LoginDevicesPanel({ token }: { token: string }) {
  const router = useRouter();
  const display = displayPrefs.use();
  const privacy = privacyPrefs.use();

  // Read once: the device and the token do not change while this panel is open.
  const device = useMemo(
    () => describeDevice(typeof navigator === 'undefined' ? '' : navigator.userAgent),
    [],
  );
  const timing = useMemo(() => readSessionTiming(token), [token]);

  const [history, setHistory] = useState<ActivityItem[] | null>(null);
  const [historyFailed, setHistoryFailed] = useState(false);
  const [busy, setBusy] = useState<'others' | 'global' | null>(null);
  const setNotice = useNotice();

  const loadHistory = useCallback(() => {
    fetchMyActivity(token, { kind: 'auth', limit: 30 })
      .then(r => setHistory(r.items))
      .catch((e: unknown) => {
        if (e instanceof ApiError && e.status === 401) { signOut(); return; }
        setHistoryFailed(true);
      });
  }, [token]);

  useEffect(() => { loadHistory(); }, [loadHistory]);

  async function end(scope: 'others' | 'global') {
    setBusy(scope);
    setNotice(null);
    try {
      const r = await revokeSessions(token, scope);
      if (scope === 'global') {
        // This session is gone too; leave cleanly instead of waiting for the
        // next request to fail.
        signOut();
        router.replace('/login');
        return;
      }
      setNotice({ tone: 'success', text: r.message });
      loadHistory();
    } catch (e) {
      setNotice({ tone: 'danger', text: e instanceof Error ? e.message : 'Could not end the sessions.' });
    } finally {
      setBusy(null);
    }
  }

  const DeviceIcon = device.mobile ? Smartphone : Laptop;
  const setPrivacy = (patch: Partial<PrivacyPrefs>) => privacyPrefs.set(patch);

  return (
    <div className="flex flex-col gap-6">
      <PanelHeader
        description="See how your account is signed in, end sessions you do not recognise, and have this browser sign itself out when it is left alone."
        icon={MonitorSmartphone}
        meta={<SavedFlash signal={privacy.idleMinutes} />}
        scope={['account', 'browser']}
        title="Login & Devices"
      />


      <Card title="This device">
        <div className="flex flex-wrap items-center gap-4">
          <span
            aria-hidden="true"
            className="flex size-12 shrink-0 items-center justify-center rounded-[14px] bg-[var(--color-surface-raised)] text-[var(--color-text-secondary)]"
          >
            <DeviceIcon className="size-6" />
          </span>
          <div className="min-w-0 flex-1">
            <p className="flex items-center gap-2 text-[15px] font-semibold text-foreground">
              {device.label}
              <StatusDot tone="success">This session</StatusDot>
            </p>
            <p className="mt-0.5 text-[12.5px] text-muted-foreground">
              {timing.issuedAt
                ? `Current sign-in renewed ${timeAgo(timing.issuedAt)} · ${formatDateTime(new Date(timing.issuedAt), display)}`
                : 'Signed in on this browser.'}
            </p>
          </div>
          <Button
            onClick={() => { signOut(); router.replace('/login'); }}
            size="sm"
            variant="outline"
          >
            <LogOut data-icon="inline-start" />
            Sign out of this device
          </Button>
        </div>
        <p className="mt-4 border-t border-[var(--color-surface-border)] pt-3 text-[12.5px] leading-relaxed text-muted-foreground">
          You stay signed in only while this tab is open — closing it signs you out. While it
          is open, the sign-in renews itself about every half hour
          {timing.expiresAt ? ` (this one is good until ${formatDateTime(new Date(timing.expiresAt), display)})` : ''}.
        </p>
      </Card>

      <Card
        description="If you signed in on a shared computer, lost a device or see a sign-in below you do not recognise, end those sessions now."
        title="Other devices"
      >
        <RowList>
          <Row
            description="Ends every session on your account except this one. Those devices can no longer renew their sign-in, and drop out at the latest within about half an hour."
            icon={LogOut}
            label="Sign out of every other device"
          >
            <Button disabled={busy !== null} onClick={() => end('others')} size="sm" variant="outline">
              <LogOut data-icon="inline-start" />
              {busy === 'others' ? 'Working…' : 'Sign out others'}
            </Button>
          </Row>
          <Row
            description="Ends every session, including this one, and returns you to the sign-in page."
            icon={LogOut}
            label="Sign out everywhere"
          >
            <Button disabled={busy !== null} onClick={() => end('global')} size="sm" variant="outline">
              <LogOut data-icon="inline-start" />
              {busy === 'global' ? 'Working…' : 'Sign out everywhere'}
            </Button>
          </Row>
        </RowList>
      </Card>

      <Card
        description="Sign-ins to your admin account, newest first. Recording began when this feature was added, so earlier sign-ins are not listed."
        flush
        title="Sign-in history"
      >
        {historyFailed ? (
          <div className="px-5 py-4">
            <Callout title="Could not load your sign-in history" tone="warning" />
          </div>
        ) : history === null ? (
          <div className="flex flex-col gap-2 px-5 py-4">
            <Skeleton className="h-10 rounded-lg" />
            <Skeleton className="h-10 rounded-lg" />
            <Skeleton className="h-10 rounded-lg" />
          </div>
        ) : history.length === 0 ? (
          <div className="flex flex-col items-center gap-2 px-5 py-10 text-center">
            <History aria-hidden="true" className="size-7 text-muted-foreground" />
            <p className="text-[13.5px] font-medium text-foreground">No sign-ins recorded yet</p>
            <p className="max-w-[46ch] text-[12.5px] text-muted-foreground">
              From now on, each time you sign in it will be listed here with the device it came from.
            </p>
          </div>
        ) : (
          <ul className="divide-y divide-[var(--color-surface-border)]">
            {history.map(item => {
              const d = describeDevice(item.metadata?.user_agent);
              const isSignIn = item.action === 'auth.login';
              const ItemIcon = d.mobile ? Smartphone : Laptop;
              return (
                <li className="flex flex-wrap items-center gap-x-4 gap-y-1 px-5 py-3" key={item.id}>
                  <ItemIcon aria-hidden="true" className="size-4 shrink-0 text-muted-foreground" />
                  <span className="min-w-0 flex-1">
                    <span className="block text-[13.5px] font-medium text-foreground">
                      {describeAction(item.action)}
                      {isSignIn && (
                        <span className="ml-2 font-normal text-muted-foreground">· {d.label}</span>
                      )}
                    </span>
                    <span className="block text-[12px] text-muted-foreground">
                      {item.metadata?.ip ? `From ${item.metadata.ip}` : 'Address not recorded'}
                      {!isSignIn && item.target_label ? ` · ${item.target_label}` : ''}
                    </span>
                  </span>
                  <span className="shrink-0 text-right">
                    <span className="block font-mono text-[12.5px] tabular-nums text-foreground">
                      {formatDateTime(item.created_at, display)}
                    </span>
                    <span className="block text-[11.5px] text-muted-foreground">
                      {timeAgo(new Date(item.created_at).getTime())}
                    </span>
                  </span>
                </li>
              );
            })}
          </ul>
        )}
      </Card>

      <Card title="Automatic sign-out">
        <RowList>
          <Row
            description={
              privacy.idleMinutes === 0
                ? 'This browser stays signed in as long as the tab is open, however long it sits untouched.'
                : `After ${privacy.idleMinutes} minutes with no mouse or keyboard input, this browser signs itself out — with a 60-second warning first.`
            }
            icon={Timer}
            label="Sign out when idle"
          >
            <Segmented
              ariaLabel="Sign out when idle"
              onChange={v => setPrivacy({ idleMinutes: v })}
              options={[
                { value: 0, label: 'Never' },
                { value: 15, label: '15 min' },
                { value: 30, label: '30 min' },
                { value: 60, label: '1 hour' },
                { value: 120, label: '2 hours' },
              ]}
              value={privacy.idleMinutes}
            />
          </Row>
        </RowList>
        <div className="mt-4">
          <Callout icon={Clock} title="Leave this off on a wall display" tone="info">
            A screen that watches the live queue is supposed to sit untouched for hours, and
            signing it out would blind it. Use this on a desk computer that people walk away
            from, not on the dispatch board.
          </Callout>
        </div>
      </Card>
    </div>
  );
}
