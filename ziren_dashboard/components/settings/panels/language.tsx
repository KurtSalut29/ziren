'use client';

import { useEffect, useState } from 'react';
import { Globe, Languages, Mic, Hash } from 'lucide-react';
import { ApiError, apiClient } from '@/lib/api/client';
import { signOut } from '@/lib/hooks/useAuth';
import { displayPrefs, type DisplayPrefs } from '@/lib/prefs/definitions';
import { formatDate, formatNumber } from '@/lib/format/datetime';
import {
  Callout, Card, PanelHeader, Row, RowList, SavedFlash, Segmented, StatusDot,
} from '@/components/settings/kit';
import { useNotice } from '@/lib/toast';

/**
 * The account's preferred language, as the backend validates it (see
 * UpdateProfileRequest): exactly these four.
 */
const ACCOUNT_LANGUAGES = ['English', 'Filipino', 'Bisaya', 'Waray'] as const;
type AccountLanguage = (typeof ACCOUNT_LANGUAGES)[number];

/** Fixed, so the preview never moves under the reader. */
const SAMPLE = new Date('2026-03-08T15:48:00+08:00');

export function LanguagePanel({ token }: { token: string }) {
  const display = displayPrefs.use();
  const [language, setLanguage] = useState<AccountLanguage | null>(null);
  const setStatus = useNotice();
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    apiClient
      .get<{ preferred_language: string | null }>('/users/me', token)
      .then(me => {
        const v = me.preferred_language as AccountLanguage | null;
        setLanguage(v && ACCOUNT_LANGUAGES.includes(v) ? v : 'English');
      })
      .catch((e: unknown) => {
        if (e instanceof ApiError && e.status === 401) { signOut(); return; }
        setStatus({ tone: 'danger', text: 'Could not load your account language.' });
      })
      .finally(() => setLoading(false));
  }, [token, setStatus]);

  async function saveLanguage(next: AccountLanguage) {
    const before = language;
    setLanguage(next);
    setStatus(null);
    try {
      await apiClient.patch('/users/me', { preferred_language: next }, token);
      setStatus({ tone: 'success', text: `Account language set to ${next}.` });
    } catch (e) {
      setLanguage(before);
      setStatus({ tone: 'danger', text: e instanceof Error ? e.message : 'Could not save.' });
    }
  }

  const set = (patch: Partial<DisplayPrefs>) => displayPrefs.set(patch);

  return (
    <div className="flex flex-col gap-6">
      <PanelHeader
        description="The language of the console itself, how month names and numbers are written, and the languages Ziren can read in a resident’s report."
        icon={Globe}
        meta={<SavedFlash signal={JSON.stringify(display)} />}
        scope={['browser', 'account']}
        title="Language & Region"
      />

      <Callout title="The console is written in English" tone="info">
        Every label, message and menu in this dashboard is in English, and there is no
        translated version to switch to yet. What you can change is how dates and numbers are
        written, and your account’s preferred language below. Reports themselves are read in
        whichever language the resident used — nothing is translated before it is scored.
      </Callout>

      <Card
        description="Month names and number grouping wherever the console writes them."
        title="Regional format"
      >
        <RowList>
          <Row
            description={
              <>
                Example:{' '}
                <span className="font-mono text-foreground">
                  {formatDate(SAMPLE, { ...display, dateStyle: 'medium' })} · {formatNumber(12345, display)}
                </span>
              </>
            }
            icon={Hash}
            label="Format region"
          >
            <Segmented
              ariaLabel="Format region"
              onChange={v => set({ locale: v })}
              options={[
                { value: 'en-PH', label: 'English (Philippines)' },
                { value: 'fil-PH', label: 'Filipino' },
                { value: 'en-US', label: 'English (US)' },
              ]}
              value={display.locale}
            />
          </Row>
        </RowList>
        <p className="mt-3 text-[12.5px] text-muted-foreground">
          Date order and 12/24-hour time are chosen under Appearance; this only affects month
          names and number grouping.
        </p>
      </Card>

      <Card
        description="Recorded on your profile. It does not translate the console."
        title="Preferred language on your account"
      >
        <RowList>
          <Row icon={Languages} label="Account language">
            {loading ? (
              <span className="text-[13px] text-muted-foreground">Loading…</span>
            ) : language ? (
              <Segmented
                ariaLabel="Account language"
                onChange={saveLanguage}
                options={ACCOUNT_LANGUAGES.map(l => ({ value: l, label: l }))}
                value={language}
              />
            ) : null}
          </Row>
        </RowList>
      </Card>

      <Card
        description="What the triage system reads, and how, when a report comes in."
        title="Languages in reports"
      >
        <RowList>
          <Row
            description="Typed reports in English, Filipino, Cebuano/Bisaya and Waray are all read as written, including mixed sentences."
            icon={Languages}
            label="Written reports"
          >
            <StatusDot tone="success">Understood</StatusDot>
          </Row>
          <Row
            description="A resident’s voice recording is turned into text by a speech engine. Waray and Bisaya are where it is weakest, so the recording is always kept and is the authority: a dispatcher can listen and correct the transcript."
            icon={Mic}
            label="Voice recordings"
          >
            <StatusDot tone="warning">Best effort</StatusDot>
          </Row>
          <Row
            description="A dictionary of corrections for common Waray/Bisaya/Filipino mis-hearings is applied to the transcript, and every substitution is shown next to the text it changed."
            label="Spelling corrections"
          >
            <StatusDot tone="success">Applied</StatusDot>
          </Row>
        </RowList>
      </Card>
    </div>
  );
}
