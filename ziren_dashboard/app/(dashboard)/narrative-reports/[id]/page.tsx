'use client';

/**
 * One narrative report, on a page of its own - the whole Incident Record Form.
 * The [id] is the INCIDENT's id: an incident has at most one report, and the
 * report is always reached through it. See NarrativeEditor.
 */

import { use } from 'react';
import { NarrativeEditor } from '@/components/narrative/narrative-editor';

export default function NarrativeReportPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  return <NarrativeEditor incidentId={id} key={id} />;
}
