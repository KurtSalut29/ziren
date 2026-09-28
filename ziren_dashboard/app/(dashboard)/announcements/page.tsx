'use client';

/**
 * Announcements — spec Section 14.
 *
 * Provincial Admin gets a publish form plus a management list (every
 * announcement they've sent, with Deactivate). Every other role — this
 * page is reachable by all of them, not just Provincial Admin, since spec
 * Section 14's audience includes residents/responders/agency admins — gets
 * a read-only feed of whatever applies to them, which is exactly the
 * notification center's "View announcements" link target from Task 4.
 */

import { useCallback, useEffect, useState } from 'react';
import { Megaphone, Plus, X } from 'lucide-react';
import { signOut, useAuth } from '@/lib/hooks/useAuth';
import { ApiError, apiClient } from '@/lib/api/client';
import {
  createAnnouncement, deactivateAnnouncement, fetchAnnouncements,
  type Announcement, type AnnouncementCategory, type AnnouncementTarget,
} from '@/lib/api/announcements';
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent,
  AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from '@/components/efferd/ui/alert-dialog';
import { Alert } from '@/components/ui/alert';
import { Button } from '@/components/efferd/ui/button';
import { Input } from '@/components/efferd/ui/input';
import { Label } from '@/components/efferd/ui/label';
import { Textarea } from '@/components/efferd/ui/textarea';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/efferd/ui/select';
import {
  Card, CardContent, CardHeader, CardTitle,
} from '@/components/efferd/ui/card';
import { Skeleton } from '@/components/efferd/ui/skeleton';
import { useNotice } from '@/lib/toast';

interface AgencyOption { id: string; name: string; agency_type: string; }

const CATEGORIES: AnnouncementCategory[] = [
  'maintenance', 'emergency', 'service_interruption', 'feature', 'reminder', 'general',
];
const TARGETS: { value: AnnouncementTarget; label: string }[] = [
  { value: 'all', label: 'All users' },
  { value: 'agency_admin', label: 'Agency Admins' },
  { value: 'responder', label: 'Responders' },
  { value: 'resident', label: 'Residents' },
  { value: 'agency', label: 'Specific agency' },
];

const CATEGORY_COLOR: Record<AnnouncementCategory, string> = {
  maintenance: 'var(--color-status-processing)',
  emergency: 'var(--color-severity-critical)',
  service_interruption: 'var(--color-system-warning)',
  feature: 'var(--color-brand)',
  reminder: 'var(--color-status-dispatched)',
  general: 'var(--color-text-muted)',
};

function PublishForm({ token, agencies, onPublished }: {
  token: string; agencies: AgencyOption[]; onPublished: (msg: string) => void;
}) {
  const [open, setOpen] = useState(false);
  const [form, setForm] = useState({
    title: '', body: '', category: 'general' as AnnouncementCategory,
    target_type: 'all' as AnnouncementTarget, target_agency_id: '',
  });
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // Publish is high-impact — it reaches real recipients the moment it's
  // sent, no undo. The form's own native `required` validation still runs
  // on this submit (nothing here bypasses it); only the actual publish call
  // moves behind a confirm step.
  const [confirmOpen, setConfirmOpen] = useState(false);

  function requestPublish(e: React.FormEvent) {
    e.preventDefault();
    if (form.target_type === 'agency' && !form.target_agency_id) {
      setError('Select an agency.');
      return;
    }
    setError(null);
    setConfirmOpen(true);
  }

  async function doPublish() {
    setConfirmOpen(false);
    setSaving(true);
    setError(null);
    try {
      await createAnnouncement(token, {
        title: form.title,
        body: form.body,
        category: form.category,
        target_type: form.target_type,
        target_agency_id: form.target_type === 'agency' ? form.target_agency_id : undefined,
      });
      onPublished(`Announcement "${form.title}" published.`);
      setForm({ title: '', body: '', category: 'general', target_type: 'all', target_agency_id: '' });
      setOpen(false);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to publish.');
    } finally {
      setSaving(false);
    }
  }

  const audienceLabel = form.target_type === 'agency'
    ? (agencies.find(a => a.id === form.target_agency_id)?.name ?? 'the selected agency')
    : (TARGETS.find(t => t.value === form.target_type)?.label ?? form.target_type);

  if (!open) {
    return (
      <Button className="w-fit" onClick={() => setOpen(true)} size="sm">
        <Plus data-icon="inline-start" />
        New announcement
      </Button>
    );
  }

  return (
    <Card>
      <CardHeader className="flex-row items-center justify-between gap-2 space-y-0">
        <CardTitle className="text-[15px]">New announcement</CardTitle>
        <Button aria-label="Cancel" onClick={() => setOpen(false)} size="icon-sm" variant="ghost">
          <X />
        </Button>
      </CardHeader>
      <CardContent>
        <form className="flex flex-col gap-3" onSubmit={requestPublish}>
          {error && <Alert variant="error" message={error} />}
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="ann-title">Title</Label>
            <Input
              id="ann-title" onChange={e => setForm(f => ({ ...f, title: e.target.value }))}
              required value={form.title}
            />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="ann-body">Message</Label>
            <Textarea
              id="ann-body" onChange={e => setForm(f => ({ ...f, body: e.target.value }))}
              required rows={4} value={form.body}
            />
          </div>
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
            <div className="flex flex-col gap-1.5">
              <Label>Category</Label>
              <Select onValueChange={v => setForm(f => ({ ...f, category: v as AnnouncementCategory }))} value={form.category}>
                <SelectTrigger size="sm"><SelectValue /></SelectTrigger>
                <SelectContent>
                  {CATEGORIES.map(c => <SelectItem key={c} value={c}>{c.replace(/_/g, ' ')}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div className="flex flex-col gap-1.5">
              <Label>Audience</Label>
              <Select onValueChange={v => setForm(f => ({ ...f, target_type: v as AnnouncementTarget }))} value={form.target_type}>
                <SelectTrigger size="sm"><SelectValue /></SelectTrigger>
                <SelectContent>
                  {TARGETS.map(t => <SelectItem key={t.value} value={t.value}>{t.label}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            {form.target_type === 'agency' && (
              <div className="flex flex-col gap-1.5">
                <Label>Agency</Label>
                <Select onValueChange={v => setForm(f => ({ ...f, target_agency_id: v }))} value={form.target_agency_id}>
                  <SelectTrigger size="sm"><SelectValue placeholder="Select agency" /></SelectTrigger>
                  <SelectContent>
                    {agencies.map(a => (
                      <SelectItem key={a.id} value={a.id}>{a.agency_type} — {a.name}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            )}
          </div>
          <Button className="w-fit" disabled={saving} type="submit">
            <Megaphone data-icon="inline-start" />
            {saving ? 'Publishing…' : 'Publish'}
          </Button>
        </form>
      </CardContent>

      <AlertDialog open={confirmOpen} onOpenChange={setConfirmOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              Publish to {audienceLabel}{form.category === 'emergency' ? ' as Emergency' : ''}?
            </AlertDialogTitle>
            <AlertDialogDescription>
              This sends immediately and cannot be recalled — only deactivated afterward.
              {form.target_type === 'all' && ' Every user on Ziren will see this.'}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={saving}>Back</AlertDialogCancel>
            <AlertDialogAction disabled={saving} onClick={() => void doPublish()}>
              Publish
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </Card>
  );
}

export default function AnnouncementsPage() {
  const { token, isProvincialAdmin } = useAuth();
  const [announcements, setAnnouncements] = useState<Announcement[] | null>(null);
  const [agencies, setAgencies] = useState<AgencyOption[]>([]);
  const setMsg = useNotice();
  const [confirmDeactivate, setConfirmDeactivate] = useState<Announcement | null>(null);

  const load = useCallback(() => {
    if (!token) return;
    fetchAnnouncements(token, !isProvincialAdmin)
      .then(setAnnouncements)
      .catch((e: unknown) => {
        if (e instanceof ApiError && e.status === 401) { signOut(); return; }
        setMsg({ type: 'error', text: e instanceof Error ? e.message : 'Failed to load.' });
      });
  }, [token, isProvincialAdmin, setMsg]);

  useEffect(() => { load(); }, [load]);

  useEffect(() => {
    if (!token || !isProvincialAdmin) return;
    apiClient.get<AgencyOption[]>('/users/agencies-list', token).then(setAgencies).catch(() => {});
  }, [token, isProvincialAdmin]);

  async function deactivate(id: string) {
    if (!token) return;
    setConfirmDeactivate(null);
    try {
      await deactivateAnnouncement(token, id);
      setMsg({ type: 'success', text: 'Announcement deactivated.' });
      load();
    } catch (e) {
      setMsg({ type: 'error', text: e instanceof Error ? e.message : 'Failed to deactivate.' });
    }
  }

  return (
    <div className="flex flex-col gap-4 px-6 py-5 md:px-7">

      {isProvincialAdmin && token && (
        <PublishForm agencies={agencies} onPublished={t => { setMsg({ type: 'success', text: t }); load(); }} token={token} />
      )}

      {announcements === null ? (
        <Skeleton className="h-40 rounded-[var(--radius-card)]" />
      ) : announcements.length === 0 ? (
        <div className="flex flex-col items-center gap-2 py-16 text-center">
          <Megaphone className="size-8 text-muted-foreground" />
          <p className="text-[14px] font-semibold text-foreground">No announcements</p>
          <p className="text-[12.5px] text-muted-foreground">
            {isProvincialAdmin ? 'Publish one above.' : 'Nothing has been announced yet.'}
          </p>
        </div>
      ) : (
        <div className="flex flex-col gap-3">
          {announcements.map(a => (
            <Card key={a.id} className={a.is_active ? '' : 'opacity-60'}>
              <CardHeader className="gap-1">
                <div className="flex flex-wrap items-center gap-2">
                  <span
                    className="rounded-full px-2 py-0.5 text-[11px] font-semibold"
                    style={{
                      backgroundColor: `color-mix(in srgb, ${CATEGORY_COLOR[a.category]} 12%, transparent)`,
                      color: CATEGORY_COLOR[a.category],
                    }}
                  >
                    {a.category.replace(/_/g, ' ')}
                  </span>
                  <CardTitle className="text-[14px]">{a.title}</CardTitle>
                  {!a.is_active && (
                    <span className="rounded-full bg-[var(--color-surface-raised)] px-2 py-0.5 text-[11px] text-muted-foreground">
                      Inactive
                    </span>
                  )}
                  {isProvincialAdmin && a.is_active && (
                    <Button className="ml-auto" onClick={() => setConfirmDeactivate(a)} size="xs" variant="ghost">
                      Deactivate
                    </Button>
                  )}
                </div>
              </CardHeader>
              <CardContent className="flex flex-col gap-1">
                <p className="text-[13px] text-foreground">{a.body}</p>
                <p className="text-[11.5px] text-muted-foreground">
                  {new Date(a.created_at).toLocaleString()} · {TARGETS.find(t => t.value === a.target_type)?.label ?? a.target_type}
                </p>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      <AlertDialog
        open={confirmDeactivate !== null}
        onOpenChange={open => { if (!open) setConfirmDeactivate(null); }}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Deactivate &quot;{confirmDeactivate?.title}&quot;?</AlertDialogTitle>
            <AlertDialogDescription>
              It stops appearing in the announcements feed for everyone it currently reaches.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Keep active</AlertDialogCancel>
            <AlertDialogAction
              variant="destructive"
              onClick={() => { if (confirmDeactivate) void deactivate(confirmDeactivate.id); }}
            >
              Deactivate
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
