'use client';

import { useEffect, useState } from 'react';
import {
  ClipboardCopy, Keyboard, LifeBuoy, Mail, MessageCircleQuestion, Phone,
} from 'lucide-react';
import { fetchSupportContacts, type SupportContacts } from '@/lib/api/account';
import { fetchHealth, type HealthResponse } from '@/lib/api/health';
import { buildDiagnostics } from '@/lib/utils/diagnostics';
import { DISPATCH_TARGET_MINUTES } from '@/components/incidents/incident-vocabulary';
import { Button } from '@/components/efferd/ui/button';
import { Skeleton } from '@/components/efferd/ui/skeleton';
import { Callout, Card, Kbd, PanelHeader, Row, RowList } from '@/components/settings/kit';
import { cn } from '@/lib/utils';

export function SupportPanel({
  token,
  role,
  agencyType,
  isProvincialAdmin,
}: {
  token: string;
  role: string | null;
  agencyType: string | null;
  isProvincialAdmin: boolean;
}) {
  const [contacts, setContacts] = useState<SupportContacts | null>(null);
  const [contactsFailed, setContactsFailed] = useState(false);
  const [health, setHealth] = useState<HealthResponse | null>(null);
  const [healthFailed, setHealthFailed] = useState(false);
  const [copied, setCopied] = useState(false);
  const [problem, setProblem] = useState('');

  useEffect(() => {
    fetchSupportContacts(token).then(setContacts).catch(() => setContactsFailed(true));
    fetchHealth(token).then(setHealth).catch(() => setHealthFailed(true));
  }, [token]);

  const diagnostics = () => buildDiagnostics({ role, agencyType, health, healthFailed });
  const report = () => `What went wrong:\n${problem.trim() || '(describe it here)'}\n\n${diagnostics()}`;

  async function copy() {
    try {
      await navigator.clipboard.writeText(report());
      setCopied(true);
      setTimeout(() => setCopied(false), 2200);
    } catch { /* clipboard blocked — the text is in the box to copy by hand */ }
  }

  const firstAdmin = contacts?.provincial_admins.find(p => p.email);
  const mailto = firstAdmin
    ? `mailto:${firstAdmin.email}?subject=${encodeURIComponent('Ziren dashboard problem')}&body=${encodeURIComponent(report())}`
    : null;

  return (
    <div className="flex flex-col gap-6">
      <PanelHeader
        description="Who to ask, how a shift works, the answers to the things people get stuck on, and a way to report a problem so it can actually be fixed."
        icon={LifeBuoy}
        title="Help & Support"
      />

      <Card
        description={
          isProvincialAdmin
            ? 'You are the top of the console — there is no one above you in it. For a fault in the platform itself, copy the diagnostics below and send them to whoever maintains this deployment.'
            : 'Start with the Provincial Admin for your agency type; they can reset access, fix an account and approve responders.'
        }
        title="Who to contact"
      >
        {contacts === null && !contactsFailed ? (
          <Skeleton className="h-20 rounded-[12px]" />
        ) : contactsFailed ? (
          <Callout title="Could not look up your contacts" tone="warning">
            Ask your agency for its Provincial Admin’s number.
          </Callout>
        ) : (
          <RowList>
              {contacts?.provincial_admins.map(p => (
                <Row
                  description={
                    <span className="flex flex-wrap gap-x-4 gap-y-1">
                      {p.email && (
                        <a className="inline-flex items-center gap-1.5 underline underline-offset-2" href={`mailto:${p.email}`}>
                          <Mail className="size-3.5" />{p.email}
                        </a>
                      )}
                      {p.phone_number && (
                        <a className="inline-flex items-center gap-1.5 underline underline-offset-2" href={`tel:${p.phone_number}`}>
                          <Phone className="size-3.5" />{p.phone_number}
                        </a>
                      )}
                      {!p.email && !p.phone_number && 'No contact details on file.'}
                    </span>
                  }
                  key={p.email ?? p.full_name}
                  label={`${p.full_name} — ${agencyType ?? ''} Provincial Admin`}
                />
              ))}
              {contacts?.provincial_admins.length === 0 && !isProvincialAdmin && (
                <Row description="No Provincial Admin account is registered for your agency type. Ask your agency head." label="No Provincial Admin found" />
              )}
              {contacts?.agency && (
                <Row
                  description={
                    contacts.agency.contact_number || contacts.agency.email
                      ? [contacts.agency.contact_number, contacts.agency.email].filter(Boolean).join(' · ')
                      : 'No contact details recorded for your agency.'
                  }
                  label={`${contacts.agency.name} (your agency)`}
                />
              )}
            </RowList>
        )}
      </Card>

      <Card
        description="The path a report takes, from a resident’s phone to a closed record. Most of what you do on the console is one of these steps."
        title="Your first shift, step by step"
      >
        <ol className="flex flex-col gap-4">
          {[
            ['A report arrives', 'It appears in Incident Management, and if it earns an alert (see Alerts) the screen interrupts, plays the alarm and flashes the tab until someone opens it.'],
            ['Read it', 'Open the report. The panel sets it out as who, what, when, where and how, with the resident’s own words, the coordinates, the voice recording if there is one, and why the rules suggested the severity they did.'],
            ['Review it', 'Accept the report as genuine, ask the resident for clarification, or reject it. A report has to be accepted before it can be dispatched.'],
            ['Dispatch', 'Confirm the severity — you can override the suggestion, and you must say why — and assign a responder from your agency who is approved and on duty.'],
            ['Follow it', 'The status moves from dispatched to en route to arrived. The crew has a short time to accept; an assignment nobody answers is shown overdue.'],
            ['Close it', 'Resolve the incident once it is over. The crew records what they found, which is what later shows whether the severity was right.'],
            ['Look it up later', 'Every incident becomes a record with its own number in Incident Records — find it by that number, or filter by date, type, severity or station.'],
          ].map(([title, body], i) => (
            <li className="flex gap-4" key={title}>
              <span
                aria-hidden="true"
                className="flex size-7 shrink-0 items-center justify-center rounded-full text-[12.5px] font-bold"
                style={{ backgroundColor: 'var(--color-brand-subtle)', color: 'var(--color-brand)' }}
              >
                {i + 1}
              </span>
              <span>
                <span className="block text-[13.5px] font-semibold text-foreground">{title}</span>
                <span className="mt-0.5 block max-w-[64ch] text-[13px] leading-relaxed text-[var(--color-text-secondary)]">{body}</span>
              </span>
            </li>
          ))}
        </ol>
      </Card>

      <Card
        description="What each level means when you are deciding, and how quickly the console expects a dispatch."
        flush
        title="Severity levels"
      >
        <RowList>
          {([
            ['critical', 'Critical', 'Life is in immediate danger — fire with people trapped or dead, mass casualty, hazardous materials.', 'var(--color-severity-critical)'],
            ['high', 'High', 'Confirmed injuries or an armed incident. Fast response needed.', 'var(--color-severity-high)'],
            ['medium', 'Medium', 'Property damage or a dispute with no injury reported.', 'var(--color-severity-medium)'],
            ['low', 'Low', 'Informational, with no immediate threat.', 'var(--color-severity-low)'],
          ] as const).map(([key, label, desc, color]) => (
            <Row
              description={desc}
              key={key}
              label={label}
              badge={<span aria-hidden="true" className="size-2 rounded-full" style={{ backgroundColor: color }} />}
            >
              <span className="font-mono text-[12.5px] tabular-nums text-muted-foreground">
                dispatch within {DISPATCH_TARGET_MINUTES[key]} min
              </span>
            </Row>
          ))}
          <Row
            description="The rules could not score it, so it always alerts and is held to the strictest clock. It needs a person to read it — it is not a low-priority report."
            label="Not yet scored"
          />
        </RowList>
      </Card>

      <Card description="Tap a question to open it." title="Common questions">
        <div className="-mx-5 -mb-4 divide-y divide-[var(--color-surface-border)]">
          {FAQ.map(item => (
            <Faq answer={item.answer} key={item.q} question={item.q} />
          ))}
        </div>
      </Card>

      <Card description="Everything that has a shortcut on this console." title="Keyboard">
        <RowList>
          <Row icon={Keyboard} label="Search everything">
            <span className="flex items-center gap-1"><Kbd>/</Kbd></span>
          </Row>
          <Row icon={Keyboard} label="Show or hide the sidebar">
            <span className="flex items-center gap-1"><Kbd>Ctrl</Kbd><span className="text-muted-foreground">+</span><Kbd>B</Kbd></span>
          </Row>
          <Row icon={Keyboard} label="Close a panel, menu or dialog">
            <Kbd>Esc</Kbd>
          </Row>
          <Row icon={Keyboard} label="Skip past the menu to the page">
            <span className="text-[12.5px] text-muted-foreground">Press <Kbd>Tab</Kbd> once on any page</span>
          </Row>
        </RowList>
        <p className="mt-3 text-[12.5px] text-muted-foreground">On a Mac, use <Kbd>⌘</Kbd> in place of Ctrl.</p>
      </Card>

      <Card
        description="Describe what happened, then send it to your Provincial Admin. The block below is added automatically — it never includes your password, your token or any report text."
        title="Report a problem"
      >
        <div className="flex flex-col gap-3">
          <textarea
            aria-label="What went wrong"
            className="min-h-[96px] w-full resize-y rounded-lg border border-input bg-transparent px-3 py-2 text-[13px] text-foreground outline-none transition-colors placeholder:text-muted-foreground focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 dark:bg-input/30"
            onChange={e => setProblem(e.target.value)}
            placeholder="What were you doing, what did you expect, and what happened instead?"
            value={problem}
          />
          <details className="rounded-[10px] border border-[var(--color-surface-border)] bg-[var(--color-surface-raised)] px-3 py-2">
            <summary className="cursor-pointer text-[12.5px] font-semibold text-[var(--color-text-secondary)]">
              Preview the diagnostics that will be attached
            </summary>
            <pre className="mt-2 max-h-56 overflow-auto whitespace-pre-wrap break-words font-mono text-[11.5px] leading-relaxed text-foreground">
              {typeof window === 'undefined' ? '' : diagnostics()}
            </pre>
          </details>
          <div className="flex flex-wrap gap-2">
            <Button onClick={copy} size="sm">
              <ClipboardCopy data-icon="inline-start" />
              {copied ? 'Copied to clipboard' : 'Copy report'}
            </Button>
            {mailto ? (
              <Button asChild size="sm" variant="outline">
                <a href={mailto}><Mail data-icon="inline-start" />Email it to {firstAdmin?.full_name}</a>
              </Button>
            ) : (
              <span className="self-center text-[12.5px] text-muted-foreground">
                No Provincial Admin email is on file — copy the report and send it another way.
              </span>
            )}
          </div>
        </div>
      </Card>
    </div>
  );
}

// ── FAQ ──────────────────────────────────────────────────────────────────

interface FaqItem { q: string; answer: React.ReactNode }

const FAQ: FaqItem[] = [
  {
    q: 'A report came in and nothing alerted me. Why?',
    answer: (
      <>
        Check four things, in this order. <b>1.</b> The agency’s rules — a severity that is switched off does not
        interrupt (Settings → Alerts). <b>2.</b> This browser’s sound mode and desktop pop-up (Settings →
        Notifications). <b>3.</b> The browser’s own notification permission, which can be blocked from the padlock in
        the address bar. <b>4.</b> The dashboard tab has to be open: alerts are found by this page checking the
        server, so a closed tab hears nothing. Everything always reaches the live queue regardless.
      </>
    ),
  },
  {
    q: 'What does “Not yet scored” mean?',
    answer: 'The rules could not decide a severity — the report gave too little to go on, or the classifier was unavailable when it arrived. It always alerts and is held to the strictest response clock, because it is the report most in need of a human. Read it, then set the severity yourself when you dispatch.',
  },
  {
    q: 'Why does a voice report say “no transcript”?',
    answer: 'A resident’s recording is turned into text after they submit, and that can fail or be skipped — for example if the incident had already been handled, or the speech engine was unavailable. The recording is always kept and is the authority: open the report, play it, and use the correction box to write what was said.',
  },
  {
    q: 'The severity looks wrong. Can I change it?',
    answer: 'Yes. When you dispatch you choose the severity yourself; the rules’ suggestion is only a starting point. If you choose a different one, you are asked for a reason, which is recorded. Overriding is normal and expected — it is how a wrong suggestion is caught.',
  },
  {
    q: 'What does “overdue” mean on an assignment?',
    answer: 'You assigned a crew and they have not accepted it in time: 60 seconds for a critical report, 2 minutes for high, 3 for medium and low. The board shows it overdue and the responder’s phone re-alerts. The full table is under Settings → Alerts.',
  },
  {
    q: 'How do I find an old incident?',
    answer: (
      <>
        Open <b>Incident Records</b>. If you know its number (like ZIR-2026-000123) type it in the record box — it
        finds the record however old it is. Otherwise filter by date, status, severity or type, or search the
        page for a word, a place or a responder’s name.
      </>
    ),
  },
  {
    q: 'The map is grey or missing tiles.',
    answer: 'The map draws its imagery from online tile servers, so it needs an internet connection. Try the Street map basemap (Settings → Map & Location) — it uses a different provider — and check the dot beside your avatar, which shows whether the console can reach the server.',
  },
  {
    q: 'Times look an hour or more off.',
    answer: 'By default the console shows times in this computer’s own time zone. If the computer’s clock or zone is wrong, so is every time. Switch to Philippine Time under Settings → Appearance to show every record on the province’s clock whatever the computer says.',
  },
  {
    q: 'I cannot sign in.',
    answer: 'Check the email and password, and that Caps Lock is off. Too many wrong attempts in a short time are blocked for a minute, so wait and try again. If it still fails, your Provincial Admin can confirm your account is active and send a password reset.',
  },
  {
    q: 'Someone else used my account.',
    answer: (
      <>
        Change your password and end every other session at once: Settings → <b>Account & Security</b> to change it,
        then <b>Login & Devices</b> to sign out other devices and review the sign-in history for anything you do not
        recognise. Tell your Provincial Admin.
      </>
    ),
  },
];

function Faq({ question, answer }: { question: string; answer: React.ReactNode }) {
  return (
    <details className="group px-5 py-3.5">
      <summary className="flex cursor-pointer list-none items-center gap-3 text-[13.5px] font-medium text-foreground marker:content-none">
        <MessageCircleQuestion aria-hidden="true" className="size-4 shrink-0 text-muted-foreground" />
        <span className="flex-1">{question}</span>
        <span
          aria-hidden="true"
          className={cn('text-[18px] leading-none text-muted-foreground transition-transform group-open:rotate-45')}
        >
          +
        </span>
      </summary>
      <div className="mt-2.5 max-w-[66ch] pl-7 text-[13px] leading-relaxed text-[var(--color-text-secondary)]">
        {answer}
      </div>
    </details>
  );
}
