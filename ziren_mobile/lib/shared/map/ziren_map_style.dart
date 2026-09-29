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

import 'dart:convert';

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

/// The glyph ranges bundled under assets/map/fonts, served by the same
/// loopback server as the tiles. Latin only: every label uses `name:latin`.
const Map<String, String> kBundledFontDirs = {
  'Noto Sans Regular': 'noto-regular',
  'Noto Sans Medium': 'noto-medium',
};

/// The offline map: OpenMapTiles-schema vector tiles read out of the bundled
/// `assets/map/biliran.mbtiles` extract, served locally by
/// `OfflineMapService` on [port] — the same extract, and the same look, as
/// the web dashboard's street map (ziren_dashboard/components/map/
/// maplibre-style.ts).
///
/// Labels are included now. They used to be left out on purpose: a symbol
/// layer with a `textField` and no glyphs configured silently fails to
/// render. The fonts are bundled (assets/map/fonts) and served by the same
/// loopback server as the tiles, so an offline map finally carries place and
/// street names, with no font server to depend on.
String buildOfflineStyle(int port) => jsonEncode(_style(port, satellite: false));

/// The online map: Esri satellite imagery, with our own roads and labels over
/// it, and our street map UNDER it — so if Esri is slow or unreachable the
/// map shows streets instead of a grey void. Replaces the CARTO labels layer
/// [kZirenMapStyle] used, which was one more server to depend on.
String buildHybridStyle(int port) => jsonEncode(_style(port, satellite: true));

const List<String> _kMinorRoads = ['service', 'tertiary', 'minor'];
const List<String> _kMajorRoads = ['motorway', 'trunk', 'primary', 'secondary'];
/// Landmarks a crew is sent by — seen from furthest out.
const List<String> _kPoiEmergency = ['hospital', 'doctors', 'police', 'fire_station', 'town_hall', 'ferry_terminal'];

/// Public places people give directions by.
const List<String> _kPoiCivic = [
  'school', 'college', 'kindergarten', 'university', 'place_of_worship', 'post', 'library', 'office',
  'cemetery', 'information', 'shelter', 'bus', 'fuel', 'bank', 'atm', 'pharmacy',
];

/// OpenMapTiles poi class -> sprite icon. Must match the dashboard's POI_ICON.
const List<dynamic> _kPoiIcon = [
  'match', ['get', 'class'],
  'hospital', 'poi-hospital',
  'doctors', 'poi-doctors',
  'police', 'poi-police',
  'fire_station', 'poi-fire_station',
  'town_hall', 'poi-town_hall',
  'ferry_terminal', 'poi-ferry',
  ['school', 'college', 'kindergarten', 'university'], 'poi-school',
  'place_of_worship', 'poi-worship',
  'post', 'poi-post',
  'library', 'poi-library',
  'office', 'poi-office',
  'cemetery', 'poi-cemetery',
  'information', 'poi-info',
  'shelter', 'poi-shelter',
  'bus', 'poi-bus',
  'fuel', 'poi-fuel',
  ['bank', 'atm'], 'poi-bank',
  'pharmacy', 'poi-pharmacy',
  ['shop', 'grocery', 'clothing_store', 'multi', 'hardware', 'convenience', 'mobile_phone', 'furniture'], 'poi-shop',
  ['fast_food', 'restaurant', 'bakery', 'bar', 'beer', 'ice_cream'], 'poi-food',
  'cafe', 'poi-cafe',
  'lodging', 'poi-lodging',
  ['attraction', 'castle', 'art_gallery', 'museum', 'monument'], 'poi-attraction',
  ['park', 'campsite', 'garden', 'playground'], 'poi-park',
  ['pitch', 'sports_centre', 'swimming_pool', 'basketball', 'stadium'], 'poi-sports',
  'poi-generic',
];

Map<String, dynamic> _poiLayer(
  String id,
  List<dynamic> filter,
  double minzoom,
  String textColor,
  String halo, {
  required bool emergency,
}) =>
    {
      'id': id,
      'type': 'symbol',
      'source': 'biliran',
      'source-layer': 'poi',
      'minzoom': minzoom,
      // Every landmark carries a label: its name, or what it is (_kPoiLabel).
      'filter': filter,
      'layout': {
        'icon-image': _kPoiIcon,
        'icon-size': emergency ? ['interpolate', ['linear'], ['zoom'], 11.5, 0.75, 15, 1] : 1,
        // Emergency facilities always draw; place names step around them.
        'icon-allow-overlap': emergency,
        // The name shows with the icon and tries every side for room; an
        // ordinary landmark with no room is dropped whole, never left as a
        // nameless icon. Emergency facilities always keep their icon.
        'text-field': _kPoiLabel,
        'text-font': [emergency ? 'Noto Sans Medium' : 'Noto Sans Regular'],
        'text-size': emergency ? 11.5 : 10.5,
        'text-variable-anchor': ['top', 'bottom', 'right', 'left'],
        'text-radial-offset': emergency ? 1.1 : 0.9,
        'text-justify': 'auto',
        'text-max-width': 9,
        'text-optional': emergency,
      },
      'paint': {'text-color': textColor, 'text-halo-color': halo, 'text-halo-width': 1.4},
    };

const List<dynamic> _kName = ['coalesce', ['get', 'name:latin'], ['get', 'name']];

/// A landmark's name, or, when OpenStreetMap has none, what it is
/// ("Police Station", "Basketball Court"), so no icon is ever drawn bare.
/// Must match the dashboard's POI_LABEL.
const List<dynamic> _kPoiLabel = [
  'coalesce', ['get', 'name:latin'], ['get', 'name'],
  ['match', ['get', 'subclass'],
    'basketball', 'Basketball Court', 'multi', 'Multi-purpose Court', 'volleyball', 'Volleyball Court', 'tennis', 'Tennis Court',
    'athletics', 'Track Oval', 'swimming_pool', 'Swimming Pool', 'community_centre', 'Barangay Hall', 'grave_yard', 'Cemetery',
    'viewpoint', 'Viewpoint', 'government', 'Government Office', 'food_court', 'Food Court', 'artwork', 'Monument',
    'convenience', 'Store', 'general', 'Store', 'confectionery', 'Bakery',
    ['match', ['get', 'class'],
      'hospital', 'Hospital', 'doctors', 'Health Center', 'police', 'Police Station', 'fire_station', 'Fire Station',
      'town_hall', 'Town Hall', 'ferry_terminal', 'Port', 'pitch', 'Court', 'basketball', 'Basketball Court',
      'multi', 'Multi-purpose Court', 'athletics', 'Track Oval', 'running', 'Track Oval', 'sports_centre', 'Sports Center',
      'swimming_pool', 'Swimming Pool', 'cemetery', 'Cemetery', 'place_of_worship', 'Church', 'shelter', 'Shelter',
      'gate', 'Gate', 'park', 'Park', 'playground', 'Playground', 'picnic_site', 'Picnic Area',
      'campsite', 'Campsite', 'attraction', 'Tourist Spot', 'school', 'School', 'library', 'Library',
      'post', 'Post Office', 'office', 'Office', 'restaurant', 'Restaurant', 'cafe', 'Cafe',
      'fast_food', 'Eatery', 'bakery', 'Bakery', 'shop', 'Store', 'clothing_store', 'Clothing Store',
      'pharmacy', 'Pharmacy', 'bank', 'Bank', 'atm', 'ATM', 'fuel', 'Gas Station',
      'lodging', 'Lodging', 'parking', 'Parking', 'toilets', 'Restroom', 'reservoir', 'Reservoir',
      'art_gallery', 'Monument',
      'Landmark'],
  ],
];

/// Road width by zoom, so a highway reads as one from the island view down
/// to a street. [extra] widens it for the casing drawn underneath.
List<dynamic> _roadWidth(double base, [double extra = 0]) => [
      'interpolate', ['exponential', 1.5], ['zoom'],
      10, base * 0.4 + extra,
      14, base * 2 + extra,
      18, base * 9 + extra,
    ];

List<Map<String, dynamic>> _roads(String prefix, double opacity) {
  Map<String, dynamic> line(String id, List<String> classes, String color, double base, [double extra = 0]) => {
        'id': '$prefix$id',
        'type': 'line',
        'source': 'biliran',
        'source-layer': 'transportation',
        'filter': ['in', ['get', 'class'], ['literal', classes]],
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {'line-color': color, 'line-width': _roadWidth(base, extra), 'line-opacity': opacity},
      };
  return [
    line('road-minor-casing', _kMinorRoads, '#d3c9b8', 1.1, 1.5),
    line('road-major-casing', _kMajorRoads, '#d3c9b8', 1.7, 1.5),
    line('road-minor', _kMinorRoads, '#ffffff', 1.1),
    line('road-major', _kMajorRoads, '#fcd69a', 1.7),
  ];
}

Map<String, dynamic> _style(int port, {required bool satellite}) {
  const src = 'biliran';
  final base = 'http://127.0.0.1:$port';
  // Labels over photography need white text on a dark halo; over the street
  // map, the reverse.
  final text = satellite ? '#ffffff' : '#2b2b2b';
  final muted = satellite ? '#f1f1f1' : '#5c5c5c';
  final halo = satellite ? 'rgba(0,0,0,0.75)' : 'rgba(255,255,255,0.92)';

  return {
    'version': 8,
    'glyphs': '$base/fonts/{fontstack}/{range}.pbf',
    'sprite': '$base/sprite/sprite',
    'sources': {
      src: {
        'type': 'vector',
        'tiles': ['$base/tiles/{z}/{x}/{y}.pbf'],
        'minzoom': 9,
        'maxzoom': 15,
        'attribution': '© OpenStreetMap contributors © OpenMapTiles',
      },
      if (satellite)
        'satellite': {
          'type': 'raster',
          'tiles': [
            'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
          ],
          'tileSize': 256,
          'maxzoom': 18,
          'attribution': 'Tiles © Esri — Source: Esri, Maxar, Earthstar Geographics, and the GIS User Community',
        },
    },
    'layers': [
      // Land is the background; OpenMapTiles draws the sea as water.
      {'id': 'background', 'type': 'background', 'paint': {'background-color': '#f2efe9'}},
      {
        'id': 'landcover', 'type': 'fill', 'source': src, 'source-layer': 'landcover',
        'paint': {'fill-color': '#d6e8c8', 'fill-opacity': 0.8},
      },
      {
        'id': 'landuse', 'type': 'fill', 'source': src, 'source-layer': 'landuse',
        'paint': {'fill-color': '#ebe6dc', 'fill-opacity': 0.8},
      },
      {
        'id': 'park', 'type': 'fill', 'source': src, 'source-layer': 'park',
        'paint': {'fill-color': '#c8e3bc', 'fill-opacity': 0.7},
      },
      {'id': 'water', 'type': 'fill', 'source': src, 'source-layer': 'water', 'paint': {'fill-color': '#aad3df'}},
      {
        'id': 'waterway', 'type': 'line', 'source': src, 'source-layer': 'waterway',
        'paint': {
          'line-color': '#aad3df',
          'line-width': ['interpolate', ['linear'], ['zoom'], 10, 0.6, 16, 3],
        },
      },
      {
        'id': 'building', 'type': 'fill', 'source': src, 'source-layer': 'building', 'minzoom': 14,
        'paint': {'fill-color': '#dcd4c6', 'fill-outline-color': '#c9bfae'},
      },
      ..._roads('', 1),
      if (satellite) ...[
        {'id': 'satellite', 'type': 'raster', 'source': 'satellite'},
        ..._roads('photo-', 0.35),
      ],
      {
        'id': 'boundary', 'type': 'line', 'source': src, 'source-layer': 'boundary',
        'filter': ['all', ['<=', ['get', 'admin_level'], 8], ['!=', ['get', 'maritime'], 1]],
        'paint': {'line-color': '#9c8fb4', 'line-width': 1, 'line-dasharray': [3, 2], 'line-opacity': 0.7},
      },
      {
        'id': 'road-name', 'type': 'symbol', 'source': src, 'source-layer': 'transportation_name', 'minzoom': 13,
        'layout': {
          'symbol-placement': 'line',
          'text-field': _kName,
          'text-font': ['Noto Sans Regular'],
          'text-size': ['interpolate', ['linear'], ['zoom'], 13, 10, 17, 13],
        },
        'paint': {'text-color': muted, 'text-halo-color': halo, 'text-halo-width': 1.5},
      },
      // Every landmark, with its icon (assets/map/sprite, made by the
      // dashboard's scripts/make-map-assets.mjs — the same icons the web map
      // draws). Emergency facilities first and from further out; the last
      // layer's symbols win collisions, so they are listed last.
      // Unnamed courts, chapels, sheds: labelled by what they are, street
      // level only, and first to give way in a collision.
      _poiLayer('poi-unnamed', ['all', ['!', ['has', 'name']], ['!', ['in', ['get', 'class'], ['literal', _kPoiEmergency]]]], 16, muted, halo, emergency: false),
      _poiLayer('poi-other', ['all', ['has', 'name'], ['!', ['in', ['get', 'class'], ['literal', [..._kPoiEmergency, ..._kPoiCivic]]]]], 15.5, muted, halo, emergency: false),
      _poiLayer('poi-civic', ['all', ['has', 'name'], ['in', ['get', 'class'], ['literal', _kPoiCivic]]], 14, muted, halo, emergency: false),
      {
        'id': 'place-small', 'type': 'symbol', 'source': src, 'source-layer': 'place', 'minzoom': 12,
        'filter': ['in', ['get', 'class'], ['literal', ['village', 'hamlet', 'suburb', 'neighbourhood', 'isolated_dwelling']]],
        'layout': {
          'text-variable-anchor': ['center', 'top', 'bottom', 'left', 'right'],
          'text-radial-offset': 0.9,'text-field': _kName, 'text-font': ['Noto Sans Regular'], 'text-size': 11, 'text-max-width': 8},
        'paint': {'text-color': text, 'text-halo-color': halo, 'text-halo-width': 1.5},
      },
      {
        'id': 'place-town', 'type': 'symbol', 'source': src, 'source-layer': 'place',
        'filter': ['in', ['get', 'class'], ['literal', ['city', 'town']]],
        'layout': {
          'text-variable-anchor': ['center', 'top', 'bottom', 'left', 'right'],
          'text-radial-offset': 0.9,
          'text-field': _kName,
          'text-font': ['Noto Sans Medium'],
          'text-size': ['interpolate', ['linear'], ['zoom'], 9, 12, 14, 17],
          'text-max-width': 8,
        },
        'paint': {'text-color': text, 'text-halo-color': halo, 'text-halo-width': 1.8},
      },
      // Last, so it is PLACED first: town names step around these icons.
      _poiLayer('poi-emergency', ['in', ['get', 'class'], ['literal', _kPoiEmergency]], 11.5, text, halo, emergency: true),
    ],
  };
}
