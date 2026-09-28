'use client';

import { useCallback, useEffect, useState } from 'react';
import {
  Bell, BellOff, BellRing, CheckCheck, Inbox, MonitorSmartphone, Play, Send, Timer,
  Volume2, VolumeX,
} from 'lucide-react';
import { alertPrefs, type AlertPrefs } from '@/lib/prefs/definitions';
import { useShellAlerts } from '@/components/shell/app-shell';
import {
  fetchUnreadCount, markAllNotificationsRead,
} from '@/lib/api/notifications';
import { Button } from '@/components/efferd/ui/button';
import {
  Callout, Card, PanelHeader, RangeControl, Row, RowList, SavedFlash,
  Segmented, StatusDot, ToggleRow,
} from '@/components/settings/kit';

/**
 * Notifications — how THIS browser delivers an alert.
 *
 * Which severities interrupt is the agency's decision and lives under Alerts.
 * This panel is the other half: given that a report has earned an interruption,
 * how loud, how fast and through which layers does this screen deliver it. The
 * two are kept apart because they have different owners — one belongs to the
 * agency, the other to whoever is sitting at this screen — and mixing them made
 * a per-screen volume look like an agency policy.
 */
export function NotificationsPanel({
  token,
  onOpen,
  isProvincialAdmin = false,
}: {
  token: string;
  /** A Provincial Admin gets no live report alerts, so only the inbox is theirs. */
  isProvincialAdmin?: boolean;
  /** Jump to another Settings section. */
  onOpen: (key: string) => void;
}) {
  const prefs = alertPrefs.use();
  const set = (patch: Partial<AlertPrefs>) => alertPrefs.set(patch);
  const shell = useShellAlerts();
  const permission = shell?.permission ?? 'default';

  if (isProvincialAdmin) {
    return (
      <div className="flex flex-col gap-6">
        <PanelHeader
          description="Messages the system has sent you. A Provincial Admin oversees and does not dispatch, so new reports do not interrupt you with a sound or a pop-up; they appear on the dashboard and in Incident Records."
          icon={Bell}
          scope="account"
          title="Notifications"
        />
        <InboxCard token={token} />
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-6">
      <PanelHeader
        description="How this screen delivers an alert once a report has earned one: the sound, the desktop pop-up, the flashing tab and how quickly it looks for new reports."
        icon={Bell}
        meta={<SavedFlash signal={JSON.stringify(prefs)} />}
        scope="browser"
        title="Notifications"
      />

      <DeliveryCard onEnable={shell?.requestPermission} permission={permission} />

      <SoundStatusCard audioReady={shell?.audioReady ?? null} />

      <Card
        description="The alarm sounds for as long as a new report is waiting to be seen, and stops when someone opens it or dismisses it."
        title="Sound"
      >
        <RowList>
          <Row
            description="“Critical only” keeps this screen quiet for everything else. Whatever you choose, the on-screen alert, the flashing tab and the desktop pop-up still appear."
            icon={prefs.soundMode === 'off' ? VolumeX : Volume2}
            label="Play the alarm for"
          >
            <Segmented
              ariaLabel="When to play the alarm"
              onChange={v => set({ soundMode: v })}
              options={[
                { value: 'all', label: 'All alerts' },
                { value: 'critical', label: 'Critical only' },
                { value: 'off', label: 'Off' },
              ]}
              value={prefs.soundMode}
            />
          </Row>

          <Row
            description="Applies at once, even to an alarm that is already sounding. It cannot go fully silent from here — choose Off above for that."
            label="Volume"
          >
            <div className="flex flex-wrap items-center gap-3">
              <RangeControl
                ariaLabel="Alarm volume"
                format={v => `${Math.round(v * 100)}%`}
                id="alert-volume"
                max={1}
                min={0.2}
                onChange={v => set({ volume: v })}
                step={0.05}
                value={prefs.volume}
              />
              <TestSound volume={prefs.volume} />
            </div>
          </Row>
        </RowList>
      </Card>

      {prefs.soundMode === 'off' && (
        <Callout title="This screen will not make a sound" tone="warning">
          A report can arrive and wait unseen if nobody is looking at the screen. Keep the
          flashing tab title on, and use this only on a screen that is always watched.
        </Callout>
      )}

      <Card title="Other ways to be told">
        <RowList>
          <ToggleRow
            checked={prefs.desktop}
            description={
              permission === 'granted'
                ? 'A pop-up outside the browser window, so a report reaches you even while you work in another program.'
                : permission === 'denied'
                  ? 'The browser is blocking notifications, so this switch has no effect until that is lifted — see the panel above.'
                  : 'Needs the browser’s permission first — use “Turn on desktop alerts” above.'
            }
            icon={MonitorSmartphone}
            id="alert-desktop"
            label="Desktop pop-up"
            onChange={v => set({ desktop: v })}
          />
          <ToggleRow
            checked={prefs.flashTitle}
            description="Flashes “(2) NEW REPORTS” in the browser tab, the one layer that reaches a background tab without asking for any permission."
            icon={BellRing}
            id="alert-flash"
            label="Flash the tab title"
            onChange={v => set({ flashTitle: v })}
          />
        </RowList>
      </Card>

      <Card
        description="How often this screen asks the server whether a new report has come in. This is the longest a report can sit before the alert starts."
        title="Checking for new reports"
      >
        <RowList>
          <Row
            description={`Currently every ${prefs.pollSeconds} seconds. Faster is safer and costs the server nothing noticeable — a province files a handful of reports an hour.`}
            icon={Timer}
            label="Check every"
          >
            <Segmented
              ariaLabel="How often to check for new reports"
              onChange={v => set({ pollSeconds: v })}
              options={[
                { value: 5, label: '5 s' },
                { value: 10, label: '10 s' },
                { value: 15, label: '15 s' },
                { value: 30, label: '30 s' },
              ]}
              value={prefs.pollSeconds}
            />
          </Row>
        </RowList>
      </Card>

      <Card
        description="Which severities interrupt is decided once for the whole agency, not per screen."
        title="Which reports earn an alert"
      >
        <div className="flex flex-wrap items-center justify-between gap-3">
          <p className="max-w-[52ch] text-[13px] leading-relaxed text-[var(--color-text-secondary)]">
            Critical and High interrupt by default. A report the system could not score
            always interrupts, whatever the rules say.
          </p>
          <Button onClick={() => onOpen('alerts')} size="sm" variant="outline">
            <Bell data-icon="inline-start" />
            Open agency alert rules
          </Button>
        </div>
      </Card>

      <InboxCard token={token} />
    </div>
  );
}

// ── Delivery status ──────────────────────────────────────────────────────

/**
 * Whether the browser will actually deliver what the switches promise.
 *
 * Desktop pop-ups and the chime both depend on a permission the console asks
 * for exactly once. Deny or dismiss it and nothing anywhere says so again, so a
 * dispatcher can believe they will be interrupted and be interrupted by nothing
 * outside the tab. This states the truth and, where there is a way forward,
 * offers it — and a test button, because "it should work" is not evidence.
 */
function DeliveryCard({
  permission,
  onEnable,
}: {
  permission: NotificationPermission | 'unsupported';
  onEnable?: () => void;
}) {
  const [sent, setSent] = useState(false);

  const spec = {
    granted: {
      tone: 'success' as const,
      icon: BellRing,
      title: 'Desktop alerts are on',
      body: 'A matching incident raises a pop-up and a chime even when this tab is behind another window.',
    },
    default: {
      tone: 'warning' as const,
      icon: Bell,
      title: 'Desktop alerts are not switched on yet',
      body: 'Matching incidents show an on-screen alert, but nothing reaches you once this tab is behind another window.',
    },
    denied: {
      tone: 'danger' as const,
      icon: BellOff,
      title: 'This browser is blocking desktop alerts',
      body: 'No pop-up can fire. Ziren cannot ask again — the block has to be lifted from the padlock icon in the address bar, then reload.',
    },
    unsupported: {
      tone: 'warning' as const,
      icon: BellOff,
      title: 'This browser has no notification support',
      body: 'On-screen alerts are the only delivery available here. A current desktop browser will do better.',
    },
  }[permission];

  function sendTest() {
    try {
      new Notification('Ziren test alert', {
        body: 'This is what a new incident notification looks like on this screen.',
        tag: 'ziren-test',
      });
      setSent(true);
      setTimeout(() => setSent(false), 3000);
    } catch {
      /* some browsers refuse without a service worker */
    }
  }

  return (
    <Callout
      action={
        permission === 'default' && onEnable ? (
          // Routed through the shell, not Notification.requestPermission(): the
          // shell's version builds the audio context during this click, which
          // is the user gesture browsers require, and the raw API would grant
          // notifications and leave the chime permanently silent.
          <Button onClick={onEnable} size="sm">
            <Bell data-icon="inline-start" />
            Turn on desktop alerts
          </Button>
        ) : permission === 'granted' ? (
          <Button onClick={sendTest} size="sm" variant="outline">
            <Send data-icon="inline-start" />
            {sent ? 'Sent ✓' : 'Send a test'}
          </Button>
        ) : undefined
      }
      icon={spec.icon}
      title={spec.title}
      tone={spec.tone}
    >
      {spec.body}
    </Callout>
  );
}

/**
 * Whether this page can make a sound right now, and how to stop being asked to
 * click after every reload.
 *
 * A browser keeps a page silent until it has seen a click or key press, and a
 * website cannot override that. The two ways round it are the user's to make:
 * clicking once, or telling the browser this site may play sound.
 */
function SoundStatusCard({ audioReady }: { audioReady: boolean | null }) {
  if (audioReady === null) return null;

  return audioReady ? (
    <Callout icon={Volume2} title="The alarm is on" tone="success">
      A new report sounds for as long as it waits, while this tab is open. If it is ever silent
      after you reload the page, click anywhere once. To have it start by itself every time,
      allow Sound for this site: the icon at the left of the address bar, then Site settings,
      then Sound, then Allow.
    </Callout>
  ) : (
    <Callout icon={VolumeX} title="The alarm is waiting for a click" tone="warning">
      Browsers keep a page silent until you click or press a key on it. Click anywhere on this
      page and the alarm is on. To skip this after every reload, allow Sound for this site: the
      icon at the left of the address bar, then Site settings, then Sound, then Allow.
    </Callout>
  );
}

function TestSound({ volume }: { volume: number }) {
  const [playing, setPlaying] = useState(false);

  async function play() {
    setPlaying(true);
    try {
      const audio = new Audio('/NotificationSound.mp3');
      audio.volume = volume;
      await audio.play();
      // A couple of seconds is enough to judge the level; the real alarm loops.
      setTimeout(() => { audio.pause(); setPlaying(false); }, 2500);
    } catch {
      // The file is missing or blocked: fall back to the synthesised chime the
      // console itself falls back to, so the test still tells the truth.
      try {
        const Ctor = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
        const ctx = new Ctor();
        const osc = ctx.createOscillator();
        const gain = ctx.createGain();
        osc.connect(gain);
        gain.connect(ctx.destination);
        gain.gain.value = 0.3 * volume;
        osc.frequency.value = 880;
        osc.start();
        osc.stop(ctx.currentTime + 0.4);
      } catch { /* no audio at all */ }
      setTimeout(() => setPlaying(false), 600);
    }
  }

  return (
    <Button disabled={playing} onClick={play} size="sm" type="button" variant="outline">
      <Play data-icon="inline-start" />
      {playing ? 'Playing…' : 'Play a test'}
    </Button>
  );
}

// ── Notification centre (the bell) ───────────────────────────────────────

function InboxCard({ token }: { token: string }) {
  const [unread, setUnread] = useState<number | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(() => {
    fetchUnreadCount(token)
      .then(r => setUnread(r.unread_count))
      .catch(() => setError('Could not load your notifications.'));
  }, [token]);

  useEffect(() => { load(); }, [load]);

  async function markAll() {
    setBusy(true);
    setError(null);
    try {
      await markAllNotificationsRead(token);
      setUnread(0);
    } catch {
      setError('Could not mark them as read.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <Card
      description="The bell at the top of the screen: announcements and administrative events addressed to you. These are kept on your account, not on this browser."
      title="Your notification inbox"
    >
      <div className="flex flex-wrap items-center justify-between gap-3">
        <span className="flex items-center gap-3">
          <Inbox aria-hidden="true" className="size-5 text-muted-foreground" />
          {unread === null ? (
            <span className="text-[13px] text-muted-foreground">{error ?? 'Loading…'}</span>
          ) : unread === 0 ? (
            <StatusDot tone="success">Nothing unread</StatusDot>
          ) : (
            <StatusDot tone="warning">{unread} unread</StatusDot>
          )}
        </span>
        <Button disabled={busy || !unread} onClick={markAll} size="sm" variant="outline">
          <CheckCheck data-icon="inline-start" />
          {busy ? 'Working…' : 'Mark all as read'}
        </Button>
      </div>
      {error && unread !== null && <p className="mt-2 text-[12.5px] text-[var(--color-severity-critical)]">{error}</p>}
    </Card>
  );
}
