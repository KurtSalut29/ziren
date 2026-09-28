'use client';

import { useEffect, useState } from 'react';
import { Mic, AlertCircle, Pencil } from 'lucide-react';
import {
  fetchIncidentMedia,
  correctTranscript,
  type IncidentMedia,
} from '@/lib/api/dispatch';

/**
 * The resident's own voice, played back for the dispatcher.
 *
 * This is the one part of a report that does not depend on transcription being
 * right. Waray, Bisaya and Cebuano are where the model is weakest, and a
 * dispatcher in Naval who speaks the language settles in ten seconds what the
 * transcript only guessed at. The written report above stays — it is what
 * ordered this incident in the queue — but when the two disagree, the
 * recording is the one that is true.
 *
 * Links are signed and expire in five minutes, so they are fetched when the
 * incident is opened rather than stored anywhere.
 */
export function IncidentVoiceNote({
  incidentId,
  token,
  heardText,
  onCorrected,
}: {
  incidentId: string;
  token: string | null;
  /** What the recogniser produced, so it can be corrected in place. */
  heardText?: string | null;
  onCorrected?: () => void;
}) {
  const [media, setMedia] = useState<IncidentMedia[] | null>(null);
  const [failed, setFailed] = useState(false);
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState('');
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);

  async function save() {
    if (!token || !draft.trim()) return;
    setSaving(true);
    setSaveError(null);
    try {
      await correctTranscript(incidentId, draft.trim(), token);
      setEditing(false);
      onCorrected?.();
    } catch {
      setSaveError('Could not save the correction.');
    } finally {
      setSaving(false);
    }
  }

  useEffect(() => {
    if (!token) return;
    let cancelled = false;
    fetchIncidentMedia(incidentId, token)
      .then((items) => { if (!cancelled) setMedia(items); })
      // An attachment panel that cannot load must not take the incident with
      // it. The dispatcher still has the report, the location and the actions.
      .catch(() => { if (!cancelled) setFailed(true); });
    return () => { cancelled = true; };
  }, [incidentId, token]);

  if (failed || !media) return null;

  const audio = media.filter((m) => m.kind === 'audio');
  if (audio.length === 0) return null;

  return (
    /* Brand-tinted card + a filled icon badge, not the plain muted box this
       used to be. The component's own docstring calls this recording the one
       part of the report that stays true when the transcript is wrong — that
       is not a detail to leave looking like every other quiet aside on the
       page, so it gets a border thick enough and a heading bold enough to
       stop a dispatcher scrolling past it. */
    <div
      className="mt-4 rounded-lg border-2 p-3"
      style={{
        borderColor: 'color-mix(in srgb, var(--color-brand) 40%, transparent)',
        backgroundColor: 'color-mix(in srgb, var(--color-brand) 6%, transparent)',
      }}
    >
      <div className="mb-2 flex items-center gap-2">
        <span
          className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full"
          style={{ backgroundColor: 'var(--color-brand)' }}
        >
          <Mic size={15} strokeWidth={2.5} className="text-white" />
        </span>
        <span className="text-[14px] font-bold text-foreground">
          Resident&rsquo;s voice report
        </span>
        <span className="text-[12px] text-muted-foreground">
          — what was actually said, not the transcription
        </span>
      </div>

      {/* You are listening to the audio anyway, and you speak the language.
          The resident was standing in front of the emergency; you have a
          minute. */}
      {editing ? (
        <div className="mb-2">
          <textarea
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            rows={3}
            autoFocus
            className="w-full rounded-md border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] p-2 text-body-sm"
          />
          <div className="flex items-center gap-2 mt-2">
            <button
              onClick={save}
              disabled={saving || !draft.trim()}
              className="rounded-md bg-[var(--color-brand)] px-3 py-1.5 text-body-sm font-semibold text-white disabled:opacity-50"
            >
              {saving ? 'Saving…' : 'Save correction'}
            </button>
            <button
              onClick={() => setEditing(false)}
              className="text-body-sm text-[var(--color-text-muted)]"
            >
              Cancel
            </button>
            {saveError && (
              <span className="text-body-sm text-[var(--color-severity-critical)]">
                {saveError}
              </span>
            )}
          </div>
        </div>
      ) : (
        heardText && (
          <button
            onClick={() => {
              setDraft(heardText);
              setEditing(true);
            }}
            className="mb-2 flex items-center gap-1.5 text-body-sm text-[var(--color-brand)] hover:underline"
          >
            <Pencil size={12} strokeWidth={2} />
            This is not what they said — correct it
          </button>
        )
      )}

      {audio.map((item) =>
        item.url ? (
          <audio
            key={item.path}
            controls
            preload="none"
            src={item.url}
            className="w-full"
          />
        ) : (
          <p
            key={item.path}
            className="flex items-center gap-1.5 text-body-sm text-[var(--color-text-muted)]"
          >
            <AlertCircle size={13} strokeWidth={2} />
            Recording unavailable.
          </p>
        ),
      )}
    </div>
  );
}
