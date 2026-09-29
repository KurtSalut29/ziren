# Map files

Everything the dashboard's maps need to draw Biliran, served from the
dashboard itself so the street map never depends on another company's server.

| File | What it is | Made by |
|---|---|---|
| `biliran.pmtiles` | OpenStreetMap vector tiles of Biliran Province, zoom 9–15, OpenMapTiles schema. The same extract the mobile app ships as `ziren_mobile/assets/map/biliran.mbtiles`. | `tools/generate_tiles.ps1` (Planetiler, then converted with the `pmtiles` Python package) |
| `fonts/` | Glyph ranges (Latin, Latin Extended, punctuation) for map labels, in the format MapLibre expects. | Downloaded from protomaps/basemaps-assets |

The style that reads them is `components/map/maplibre-style.ts`. Satellite
imagery is the only thing still fetched from outside (Esri World Imagery).

## Licences

- Map data © OpenStreetMap contributors, under the Open Database Licence
  (ODbL). Tile schema © OpenMapTiles (CC-BY 4.0). The maps show this in
  their attribution control; keep it.
- Noto Sans fonts: SIL Open Font License 1.1.
