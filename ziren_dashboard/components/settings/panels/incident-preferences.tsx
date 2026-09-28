'use client';

import {
  Bot, CalendarRange, FileAudio, ListChecks, ListOrdered, MapPin, RefreshCw,
  Rows3,
} from 'lucide-react';
import { incidentPrefs, type IncidentPrefs } from '@/lib/prefs/definitions';
import {
  Callout, Card, PanelHeader, Row, RowList, SavedFlash, Segmented, ToggleRow,
} from '@/components/settings/kit';
import { Button } from '@/components/efferd/ui/button';

export function IncidentPreferencesPanel() {
  const prefs = incidentPrefs.use();
  const set = (patch: Partial<IncidentPrefs>) => incidentPrefs.set(patch);

  return (
    <div className="flex flex-col gap-6">
      <PanelHeader
        description="How incidents are listed and how much of a report the record panel draws. These change what this screen SHOWS — never what is stored, scored or sent to a crew."
        icon={ListChecks}
        meta={<SavedFlash signal={JSON.stringify(prefs)} />}
        scope="browser"
        title="Incident Preferences"
      />

      <Card title="Lists">
        <RowList>
          <Row
            description={`The live queue asks the server for changes every ${prefs.refreshSeconds} seconds. A faster refresh shows a new report sooner; new-report alerts have their own timer under Notifications.`}
            icon={RefreshCw}
            label="Live queue refresh"
          >
            <Segmented
              ariaLabel="Live queue refresh"
              onChange={v => set({ refreshSeconds: v })}
              options={[
                { value: 5, label: '5 s' },
                { value: 15, label: '15 s' },
                { value: 30, label: '30 s' },
                { value: 60, label: '1 min' },
              ]}
              value={prefs.refreshSeconds}
            />
          </Row>
          <Row
            description="How far back Incident Records looks when you open it. You can still change it on the page for one visit."
            icon={CalendarRange}
            label="Records: opens on"
          >
            <Segmented
              ariaLabel="Default records window"
              onChange={v => set({ historyDays: v })}
              options={[
                { value: 7, label: '7 days' },
                { value: 30, label: '30 days' },
                { value: 90, label: '90 days' },
                { value: 365, label: '1 year' },
              ]}
              value={prefs.historyDays}
            />
          </Row>
          <Row
            description="Fewer rows load faster and scroll less; more rows mean fewer pages to click through."
            icon={ListOrdered}
            label="Records per page"
          >
            <Segmented
              ariaLabel="Records per page"
              onChange={v => set({ recordsPerPage: v })}
              options={[
                { value: 25, label: '25' },
                { value: 50, label: '50' },
                { value: 100, label: '100' },
              ]}
              value={prefs.recordsPerPage}
            />
          </Row>
        </RowList>
      </Card>

      <Card
        description="Sections of the full report a dispatcher opens. Hide the ones your agency never uses to shorten the read; you can bring any of them back here."
        title="Record panel"
      >
        <RowList>
          <ToggleRow
            checked={prefs.showAiSuggestion}
            description="The panel explaining why the rules suggested this severity — the rule that fired and the signals it read. The suggestion itself is still used to rank the queue."
            icon={Bot}
            id="inc-show-ai"
            label="Severity reasoning"
            onChange={v => set({ showAiSuggestion: v })}
          />
          <ToggleRow
            checked={prefs.showWizardAnswers}
            description="The who, what and how the resident answered in the report form, laid out under each heading."
            icon={Rows3}
            id="inc-show-wizard"
            label="Report form answers"
            onChange={v => set({ showWizardAnswers: v })}
          />
          <ToggleRow
            checked={prefs.showLocationDetail}
            description="The exact coordinates and any landmark the resident gave, beneath the address."
            icon={MapPin}
            id="inc-show-location"
            label="Coordinates and landmark"
            onChange={v => set({ showLocationDetail: v })}
          />
          <ToggleRow
            checked={prefs.showRecording}
            description="The player for the resident's voice recording, with its transcript and the option to correct it."
            icon={FileAudio}
            id="inc-show-recording"
            label="Voice recording"
            onChange={v => set({ showRecording: v })}
          />
        </RowList>
      </Card>

      {!prefs.showAiSuggestion && (
        <Callout title="Severity reasoning is hidden on this screen" tone="warning">
          The rules still run and still rank the queue; you just cannot see why on this
          screen. A dispatcher overriding a severity is best served by seeing the reason,
          so consider leaving this on.
        </Callout>
      )}

      <div className="flex justify-end">
        <Button onClick={() => incidentPrefs.reset()} size="sm" variant="ghost">
          Reset incident preferences
        </Button>
      </div>
    </div>
  );
}
