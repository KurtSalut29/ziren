'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { AlertCircle, ExternalLink, Image as ImageIcon, Video } from 'lucide-react';
import { fetchIncidentMedia, type IncidentMedia } from '@/lib/api/dispatch';

/**
 * The photos and videos on a report: the resident's, and the crew's from the
 * scene.
 *
 * The media endpoint has signed these all along, but the only thing on the
 * dashboard that read it was the voice-note player, which keeps the audio and
 * drops the rest. A photo a resident attached reached the database and no one
 * else (evaluator finding #1, 2026-10-05).
 *
 * Links are signed for five minutes. A picture that has already loaded stays
 * on screen; a video played after the link has lapsed fails to load, and that
 * error fetches fresh links once rather than leaving a dead player.
 */
export function IncidentAttachments({
  incidentId,
  token,
}: {
  incidentId: string;
  token: string | null;
}) {
  const [media, setMedia] = useState<IncidentMedia[] | null>(null);
  const [failed, setFailed] = useState(false);
  const refreshed = useRef(false);

  const load = useCallback(
    (signal: { cancelled: boolean }) => {
      if (!token) return;
      fetchIncidentMedia(incidentId, token)
        .then((items) => { if (!signal.cancelled) { setMedia(items); setFailed(false); } })
        // An attachment panel that cannot load must not take the incident with
        // it; it says so instead of vanishing, since an absent panel and a
        // broken one would otherwise look the same.
        .catch(() => { if (!signal.cancelled) setFailed(true); });
    },
    [incidentId, token],
  );

  useEffect(() => {
    const signal = { cancelled: false };
    refreshed.current = false;
    load(signal);
    return () => { signal.cancelled = true; };
  }, [load]);

  /** One fresh fetch when a link has lapsed; never a loop. */
  const onLinkError = useCallback(() => {
    if (refreshed.current) return;
    refreshed.current = true;
    load({ cancelled: false });
  }, [load]);

  if (failed) {
    return (
      <p className="mt-4 flex items-center gap-1.5 text-body-sm text-[var(--color-text-muted)]">
        <AlertCircle size={13} strokeWidth={2} />
        Could not load the photos and videos on this report.
      </p>
    );
  }
  if (!media) return null;

  const visual = media.filter((m) => m.kind !== 'audio');
  if (visual.length === 0) return null;

  const fromReporter = visual.filter((m) => m.source !== 'scene');
  const fromScene = visual.filter((m) => m.source === 'scene');

  return (
    <div className="mt-4 flex flex-col gap-3" data-testid="incident-attachments">
      {fromReporter.length > 0 && (
        <Group items={fromReporter} onLinkError={onLinkError} title="Photos and videos from the resident" />
      )}
      {fromScene.length > 0 && (
        <Group items={fromScene} onLinkError={onLinkError} title="Photos from the crew on scene" />
      )}
    </div>
  );
}

function Group({
  title,
  items,
  onLinkError,
}: {
  title: string;
  items: IncidentMedia[];
  onLinkError: () => void;
}) {
  const photos = items.filter((m) => m.kind === 'image').length;
  const videos = items.length - photos;
  const count = [
    photos ? `${photos} photo${photos === 1 ? '' : 's'}` : null,
    videos ? `${videos} video${videos === 1 ? '' : 's'}` : null,
  ].filter(Boolean).join(' · ');

  return (
    <section>
      <div className="mb-2 flex items-center gap-2">
        <ImageIcon className="shrink-0 text-muted-foreground" size={14} strokeWidth={2} />
        <span className="text-[13.5px] font-semibold text-foreground">{title}</span>
        <span className="text-[12px] text-muted-foreground">{count}</span>
      </div>
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
        {items.map((m) => <Tile item={m} key={m.path} onLinkError={onLinkError} />)}
      </div>
    </section>
  );
}

function Tile({ item, onLinkError }: { item: IncidentMedia; onLinkError: () => void }) {
  const frame =
    'relative overflow-hidden rounded-[10px] border border-[var(--color-surface-border)] bg-[var(--color-surface-raised)]';

  if (!item.url) {
    return (
      <div className={`${frame} flex aspect-[4/3] flex-col items-center justify-center gap-1.5 p-3 text-center`}>
        <AlertCircle className="text-muted-foreground" size={18} strokeWidth={2} />
        <span className="text-[12px] text-muted-foreground">
          This {item.kind === 'video' ? 'video' : 'photo'} could not be opened.
        </span>
      </div>
    );
  }

  if (item.kind === 'video') {
    return (
      <div className={`${frame} aspect-[4/3]`}>
        <video
          className="h-full w-full bg-black object-contain"
          controls
          onError={onLinkError}
          playsInline
          preload="metadata"
          src={item.url}
        />
        <span className="pointer-events-none absolute left-2 top-2 flex items-center gap-1 rounded-full bg-black/60 px-2 py-0.5 text-[11px] font-semibold text-white">
          <Video size={11} strokeWidth={2.5} /> Video
        </span>
      </div>
    );
  }

  // Opens full size in a new tab, where it can be zoomed and saved; a thumbnail
  // is too small to read a plate number or a house number from.
  return (
    <a
      className={`${frame} group block aspect-[4/3]`}
      href={item.url}
      rel="noopener noreferrer"
      target="_blank"
      title="Open full size"
    >
      {/* Signed, short-lived storage URLs: next/image would try to optimise
          and cache them, which is exactly what they must not be. */}
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        alt="Attachment on the report"
        className="h-full w-full object-cover transition-transform duration-200 group-hover:scale-[1.03]"
        loading="lazy"
        onError={onLinkError}
        src={item.url}
      />
      <span className="absolute bottom-2 right-2 flex items-center gap-1 rounded-full bg-black/60 px-2 py-0.5 text-[11px] font-semibold text-white opacity-0 transition-opacity group-hover:opacity-100">
        <ExternalLink size={11} strokeWidth={2.5} /> Full size
      </span>
    </a>
  );
}
