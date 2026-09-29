'use client';

import {
  Building2, Compass, MapPin, RefreshCw, Ruler, Tag, Users, Siren, Layers,
} from 'lucide-react';
import { mapPrefs, type MapPrefs } from '@/lib/prefs/definitions';
import { formatCoordinates, formatDistanceKm } from '@/lib/format/geo';
import {
  Card, ChoiceOption, OptionCards, PanelHeader, Row, RowList, SavedFlash,
  Segmented, ToggleRow, Callout,
} from '@/components/settings/kit';
import { Button } from '@/components/efferd/ui/button';

const BASEMAPS: ChoiceOption<MapPrefs['basemap']>[] = [
  {
    value: 'satellite',
    label: 'Satellite',
    icon: Layers,
    hint: 'Esri aerial photography with our roads and place names on top. Falls back to the street map if the imagery cannot load.',
  },
  {
    value: 'streets',
    label: 'Street map',
    icon: MapPin,
    hint: 'Ziren’s own copy of the OpenStreetMap map of Biliran — no outside server needed. Best for reading street and sitio names.',
  },
];

/** Naval, Biliran — a fixed example so the coordinate preview never moves. */
const SAMPLE_LAT = 11.5586;
const SAMPLE_LON = 124.398;

export function MapLocationPanel() {
  const prefs = mapPrefs.use();
  const set = (patch: Partial<MapPrefs>) => mapPrefs.set(patch);

  return (
    <div className="flex flex-col gap-6">
      <PanelHeader
        description="What the Incident Map shows when it opens, which basemap it draws, and the units used for distances and coordinates anywhere in the console."
        icon={MapPin}
        meta={<SavedFlash signal={JSON.stringify(prefs)} />}
        scope="browser"
        title="Map & Location"
      />

      <Card
        description="Takes effect on the map straight away, including one that is already open."
        title="Basemap"
      >
        <OptionCards
          ariaLabel="Basemap"
          columns={2}
          onChange={v => set({ basemap: v })}
          options={BASEMAPS}
          value={prefs.basemap}
        />
      </Card>

      <Card
        description="Which layers are switched on when the map opens. You can still toggle any of them from the map’s own toolbar for the visit; that never changes this default."
        title="Layers on open"
      >
        <RowList>
          <ToggleRow
            checked={prefs.layerIncidents}
            description="Open reports, drawn by severity."
            icon={Siren}
            id="map-layer-incidents"
            label="Incidents"
            onChange={v => set({ layerIncidents: v })}
          />
          <ToggleRow
            checked={prefs.layerResponders}
            description="Responders on duty, where they last reported."
            icon={Users}
            id="map-layer-responders"
            label="Responders"
            onChange={v => set({ layerResponders: v })}
          />
          <ToggleRow
            checked={prefs.layerStations}
            description="Station pins for every agency in view."
            icon={Building2}
            id="map-layer-stations"
            label="Stations"
            onChange={v => set({ layerStations: v })}
          />
        </RowList>
      </Card>

      <Card title="Labels and refresh">
        <RowList>
          <ToggleRow
            checked={prefs.alwaysLabels}
            description="Station names normally hide when you zoom out so the map does not turn to text. Turn this on to keep them at every zoom."
            icon={Tag}
            id="map-always-labels"
            label="Always show station labels"
            onChange={v => set({ alwaysLabels: v })}
          />
          <Row
            description={`Currently every ${prefs.refreshSeconds} seconds. The map keeps its position and zoom while it refreshes.`}
            icon={RefreshCw}
            label="Refresh the map every"
          >
            <Segmented
              ariaLabel="Map refresh interval"
              onChange={v => set({ refreshSeconds: v })}
              options={[
                { value: 15, label: '15 s' },
                { value: 30, label: '30 s' },
                { value: 60, label: '1 min' },
                { value: 120, label: '2 min' },
              ]}
              value={prefs.refreshSeconds}
            />
          </Row>
        </RowList>
      </Card>

      <Card
        description="Used for the response distance to a station, and for the coordinates shown on an incident."
        title="Units and coordinates"
      >
        <RowList>
          <Row
            description={`Example: a station 3.4 km away reads “${formatDistanceKm(3.4, prefs)}”.`}
            icon={Ruler}
            label="Distance"
          >
            <Segmented
              ariaLabel="Distance unit"
              onChange={v => set({ units: v })}
              options={[
                { value: 'km', label: 'Kilometres' },
                { value: 'mi', label: 'Miles' },
              ]}
              value={prefs.units}
            />
          </Row>
          <Row
            description={
              <>
                Example, Naval town centre:{' '}
                <span className="font-mono text-foreground">{formatCoordinates(SAMPLE_LAT, SAMPLE_LON, prefs)}</span>
              </>
            }
            icon={Compass}
            label="Coordinate format"
          >
            <Segmented
              ariaLabel="Coordinate format"
              onChange={v => set({ coordFormat: v })}
              options={[
                { value: 'decimal', label: 'Decimal' },
                { value: 'dms', label: 'Degrees, minutes, seconds' },
              ]}
              value={prefs.coordFormat}
            />
          </Row>
        </RowList>
      </Card>

      <Callout title="About location on this console" tone="info">
        Ziren shows where a report was filed from and where responders last reported; it
        does not track this computer. There is no location permission to grant here, and
        nothing on this page reads your position.
      </Callout>

      <div className="flex justify-end">
        <Button onClick={() => mapPrefs.reset()} size="sm" variant="ghost">
          Reset map preferences
        </Button>
      </div>
    </div>
  );
}
