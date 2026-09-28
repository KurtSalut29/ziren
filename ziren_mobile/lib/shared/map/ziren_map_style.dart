/// The one map style every Ziren screen draws from.
///
/// WHY THIS EXISTS
///
/// There were two, and only one of them worked. The Map tab carried an inline
/// OSM raster style and rendered correctly. Every other map — the inline
/// preview on the responder's incident screen — loaded
/// `assets/map/style.json`, whose vector source is:
///
///     "tiles": ["http://localhost:7654/tiles/{z}/{x}/{y}"]
///
/// That is a tile server on the DEVELOPER'S machine. On a handset `localhost`
/// is the handset, so nothing answers, MapLibre falls back to painting the
/// style's `background` layer, and the crew gets a flat beige rectangle where
/// the scene should be. It does not error and it does not log — a blank map
/// looks exactly like a map that has not finished loading.
///
/// The offline vector tiles in assets/map/biliran.mbtiles are the answer for
/// a province with patchy coverage — TODO 6C.1 is done: see
/// `offline_map_service.dart`, which copies the mbtiles asset to a real file,
/// serves it over a loopback HTTP server, and hands [buildOfflineStyle] that
/// server's port. [OfflineMapService.resolveStyle] is what every map screen
/// actually calls; it picks between this style and the offline one itself.
///
/// The style itself has since changed from plain OSM street tiles to a
/// satellite-plus-labels combination — see the doc comment on
/// [kZirenMapStyle] — to match the web dashboard's map, but the reasoning
/// above for why it is one shared raster style rather than per-screen
/// styles is unchanged.
library;

/// Satellite imagery with a place-name overlay — the same two-layer
/// combination the web dashboard's map already uses (ZirenMap.tsx), so a
/// station or incident location reads the same way whether a dispatcher is
/// looking at it on the web or a resident is looking at it on the phone.
///
/// Both layers are raster and both are free, keyless tile services — no
/// Mapbox/Google/Esri account exists for this project, matching the same
/// constraint that made the previous OSM-street style raster-only: no
/// glyph server, so no vector style, so no dependency that can go dark
/// independent of the tile server itself. A raster tile either arrives or
/// it does not.
///
///   1. Esri World Imagery — the actual photography. Capped at its own
///      native zoom (18): Esri's real coverage over Biliran does not go
///      any closer, and requesting past that returns a blank grey tile
///      instead of upscaling the last real one.
///   2. CARTO's labels-only layer, drawn on top — place names and roads
///      with no basemap fill of its own, so it reads as annotations over
///      the photography rather than a second competing map.
///
/// Attribution for both is required by their terms and is rendered by
/// MapLibre's own attribution control — do not remove.
const String kZirenMapStyle = '''
{
  "version": 8,
  "sources": {
    "satellite": {
      "type": "raster",
      "tiles": ["https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"],
      "tileSize": 256,
      "maxzoom": 18,
      "attribution": "Tiles © Esri — Source: Esri, Maxar, Earthstar Geographics, and the GIS User Community"
    },
    "labels": {
      "type": "raster",
      "tiles": ["https://basemaps.cartocdn.com/rastertiles/voyager_only_labels/{z}/{x}/{y}.png"],
      "tileSize": 256,
      "attribution": "© OpenStreetMap contributors © CARTO"
    }
  },
  "layers": [
    {
      "id": "satellite",
      "type": "raster",
      "source": "satellite"
    },
    {
      "id": "labels",
      "type": "raster",
      "source": "labels"
    }
  ]
}
''';

/// Roughly the middle of Biliran, for a map with nothing else to centre on.
const double kBiliranLat = 11.5836;
const double kBiliranLng = 124.4063;

/// The offline map: OpenMapTiles-schema vector tiles read out of the bundled
/// `assets/map/biliran.mbtiles` extract, served locally by
/// `OfflineMapService` on [port].
///
/// Fills and lines only — deliberately no `symbol`/text layers. The satellite
/// style's own doc comment explains why it stays raster-only: no glyph
/// server. A vector style needs one just as much, for the exact reason
/// `_drawPins` in map_screen.dart already hit once — a symbol layer with a
/// `textField` and no glyphs configured in the style silently fails to
/// render, which for an offline map looks identical to the tiles never
/// having loaded at all. Place names can come later behind a bundled font;
/// until then, an offline map with legible shapes and no labels beats one
/// that looks broken.
String buildOfflineStyle(int port) {
  final tileUrl = 'http://127.0.0.1:$port/tiles/{z}/{x}/{y}.pbf';
  return '''
{
  "version": 8,
  "sources": {
    "biliran": {
      "type": "vector",
      "tiles": ["$tileUrl"],
      "minzoom": 9,
      "maxzoom": 15,
      "bounds": [124.3, 11.48, 124.58, 11.72]
    }
  },
  "layers": [
    { "id": "background", "type": "background", "paint": { "background-color": "#eef2f0" } },
    {
      "id": "landcover",
      "type": "fill",
      "source": "biliran",
      "source-layer": "landcover",
      "paint": { "fill-color": "#d9e8d5", "fill-opacity": 0.6 }
    },
    {
      "id": "landuse",
      "type": "fill",
      "source": "biliran",
      "source-layer": "landuse",
      "paint": { "fill-color": "#e6e2d3", "fill-opacity": 0.5 }
    },
    {
      "id": "park",
      "type": "fill",
      "source": "biliran",
      "source-layer": "park",
      "paint": { "fill-color": "#c8e6c0", "fill-opacity": 0.6 }
    },
    {
      "id": "water",
      "type": "fill",
      "source": "biliran",
      "source-layer": "water",
      "paint": { "fill-color": "#a8d0e6" }
    },
    {
      "id": "waterway",
      "type": "line",
      "source": "biliran",
      "source-layer": "waterway",
      "paint": { "line-color": "#a8d0e6", "line-width": 1.2 }
    },
    {
      "id": "building",
      "type": "fill",
      "source": "biliran",
      "source-layer": "building",
      "paint": { "fill-color": "#d8d2c4", "fill-outline-color": "#c3bcaa" }
    },
    {
      "id": "boundary",
      "type": "line",
      "source": "biliran",
      "source-layer": "boundary",
      "paint": { "line-color": "#9a8f7a", "line-width": 1, "line-dasharray": [3, 2] }
    },
    {
      "id": "transportation",
      "type": "line",
      "source": "biliran",
      "source-layer": "transportation",
      "layout": { "line-cap": "round", "line-join": "round" },
      "paint": { "line-color": "#ffffff", "line-width": 1.4 }
    },
    {
      "id": "place",
      "type": "circle",
      "source": "biliran",
      "source-layer": "place",
      "paint": {
        "circle-color": "#8a7f6b",
        "circle-radius": 3,
        "circle-stroke-color": "#ffffff",
        "circle-stroke-width": 1
      }
    }
  ]
}
''';
}
