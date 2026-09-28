'use client';

import { useEffect, useState } from 'react';
import { MessageSquareQuote, Star } from 'lucide-react';
import { fetchIncidentFeedback, type IncidentFeedback } from '@/lib/api/dispatch';

/**
 * The resident's own post-resolution rating (Resident spec Section 26),
 * shown to whoever handled the incident.
 *
 * Until this existed, a resident could rate their experience and a
 * dispatcher had no way to ever see it — the rating reached the database
 * and stopped there. Self-fetching, same pattern as IncidentVoiceNote:
 * this incident's feedback is not worth fetching for every row in the
 * queue on the chance one gets opened, only for the one actually open.
 *
 * Only shown once resolved — feedback cannot exist before then (the
 * backend rejects it with 409), so there is nothing to check for earlier.
 */
export function IncidentFeedbackPanel({
  incidentId,
  token,
  status,
}: {
  incidentId: string;
  token: string | null;
  status: string;
}) {
  const [feedback, setFeedback] = useState<IncidentFeedback | null>(null);
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    if (!token || status !== 'resolved') return;
    let cancelled = false;
    setLoaded(false);
    fetchIncidentFeedback(incidentId, token)
      .then(f => { if (!cancelled) setFeedback(f); })
      // A rating panel that cannot load must not take the incident with it —
      // same reasoning as the voice note attachment.
      .catch(() => { if (!cancelled) setFeedback(null); })
      .finally(() => { if (!cancelled) setLoaded(true); });
    return () => { cancelled = true; };
  }, [incidentId, token, status]);

  if (status !== 'resolved' || !loaded) return null;

  if (!feedback) {
    return (
      <p className="text-[13px] text-muted-foreground">
        Not rated by the reporter yet.
      </p>
    );
  }

  return (
    <div
      className="rounded-lg border p-3"
      style={{
        borderColor: 'var(--color-surface-border)',
        backgroundColor: 'var(--color-surface-raised)',
      }}
    >
      <div className="flex items-center gap-2">
        <div className="flex items-center gap-0.5" aria-label={`${feedback.rating} out of 5 stars`}>
          {Array.from({ length: 5 }).map((_, i) => (
            <Star
              key={i}
              size={15}
              strokeWidth={2}
              // Never the only cue for the number — the sr-only label above
              // carries it too, same rule as every other severity/status
              // colour in this app.
              fill={i < feedback.rating ? 'var(--color-system-warning)' : 'none'}
              stroke={i < feedback.rating ? 'var(--color-system-warning)' : 'var(--color-text-muted)'}
            />
          ))}
        </div>
        <span className="text-[12px] text-muted-foreground">
          {new Date(feedback.created_at).toLocaleDateString()}
        </span>
      </div>
      {feedback.comment && (
        <p className="mt-2 flex items-start gap-1.5 text-[13px] italic text-foreground">
          <MessageSquareQuote className="mt-0.5 shrink-0 text-muted-foreground" size={14} />
          &ldquo;{feedback.comment}&rdquo;
        </p>
      )}
    </div>
  );
}
