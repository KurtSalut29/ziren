import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:provider/provider.dart';

import '../../../features/incident_report/domain/incident_model.dart';
import '../../../features/incident_report/domain/incident_provider.dart';
import '../../../features/incident_report/domain/station_model.dart';
import '../../../features/hotlines/data/hotlines_store.dart';
import '../../../features/hotlines/domain/station_hotlines.dart';
import '../../../features/hotlines/presentation/hotlines_view.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/ziren_button.dart';
import '../../../shared/widgets/ziren_dialogs.dart';
import '../domain/geo_circle.dart';
import '../../../shared/map/offline_map_service.dart';
import '../../../shared/map/ziren_map_style.dart';
import '../domain/map_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

const _kBiliranCenter = LatLng(kBiliranLat, kBiliranLng);
const _kInitialZoom = 11.5;

// ── Station pin artwork ───────────────────────────────────────────────────
//
// One PNG per agency, registered with MapLibre once per style load. The names
// are namespaced because they share a sprite atlas with the base style, which
// already defines `marker-15`, `circle-15` and friends.
const Map<String, String> _kStationImage = {
  'BFP': 'ziren-bfp',
  'PNP': 'ziren-pnp',
  'MDRRMO': 'ziren-mdrrmo',
};

/// The two person pins, for whoever is holding the phone.
const String _kMeIconResident = 'ziren-resident';
const String _kMeIconResponder = 'ziren-responder';

const Map<String, String> _kMarkerAssets = {
  'ziren-bfp': 'assets/markers/bfp.png',
  'ziren-pnp': 'assets/markers/pnp.png',
  'ziren-mdrrmo': 'assets/markers/mdrrmo.png',
  _kMeIconResident: 'assets/markers/resident.png',
  _kMeIconResponder: 'assets/markers/responder.png',
};

/// The art is 128 physical px tall and registered at the device pixel ratio,
/// so at icon-size 1 it draws ~49 dp on a 420 dpi phone. That is the size
/// users actually saw for months: every scale below was silently rejected
/// (see [_kPinZoomStops]), so pins always drew at 1. When the rejection was
/// fixed, the old 0.32 scale suddenly applied and pins shrank to ~9 dp —
/// reported at once as "lumiit". Scales are now relative to that familiar
/// size, not to a 128 px guess.
const double _kStationIconScale = 0.9;

/// The person pin draws a little larger than a station: it marks where the
/// viewer is, which is the one position on this map they are certain about.
const double _kMeIconScale = 1.0;

/// The person pins stand on a glow ring rather than ending in a point. Its
/// centre is the position, and it sits at roughly 87% of the image height —
/// so 128 * (1 - 0.87) ≈ 17 pixels below the anchor.
const double _kMeTipInset = 17;

/// Multiplies every pin's base scale so pins grow as the viewer zooms in,
/// instead of holding a fixed screen size while the map itself grows around
/// them.
///
/// Reported live as pins "getting so small" while zooming in — the pin
/// hadn't actually shrunk (icon-size with no zoom expression is constant in
/// screen pixels, same as any Google Maps marker), but a fixed-size pin next
/// to an ever-more-zoomed-in, ever-more-detailed satellite view reads as
/// smaller by comparison, and the same pin next to a zoomed-out view reads
/// as comparatively bigger. Confirmed with the user this direction — bigger
/// up close, smaller pulled back — is what they actually want, not a
/// perfectly fixed size.
///
/// Earlier versions of this curve were tuned against complaints while the
/// whole expression was being rejected (below), so none of them was ever
/// seen. This one keeps the familiar size (1.0) at a town view (14), eases
/// down to about half at a regional view, and grows only a little up close.
///
/// Zoom → scale stops. Use [_pinScale], never these directly inside a
/// `multiply`: MapLibre only accepts `["zoom"]` as the input of a TOP-LEVEL
/// interpolate, and silently rejects the whole icon-size otherwise (logcat:
/// `icon-size "zoom" expression may only be used as input to a top-level
/// "step" or "interpolate" expression`) — which is how pins went unscaled.
const List<double> _kPinZoomStops = [7, 0.5, 9, 0.65, 11.5, 0.85, 14, 1.0, 16, 1.1, 18, 1.25];

/// icon-size for a pin whose normal size is [base]: the zoom curve above
/// with every stop pre-multiplied by [base], so zoom stays top-level.
List<dynamic> _pinScale(double base) => [
      Expressions.interpolate,
      ['linear'],
      [Expressions.zoom],
      for (var i = 0; i < _kPinZoomStops.length; i += 2) ...[
        _kPinZoomStops[i],
        _kPinZoomStops[i + 1] * base,
      ],
    ];

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, this.forResponder = false, this.focusIncidentId});

  /// Draw the incidents ASSIGNED to this responder rather than the ones
  /// they filed themselves.
  ///
  /// The responder shell reuses this whole screen, and without the flag it
  /// showed a crew their own civilian reports — none, for every responder
  /// in this deployment. Stations drew, incidents did not, and an empty
  /// layer is indistinguishable from a quiet night.
  final bool forResponder;

  /// Set from My Reports' "View on Map" action (see ReportDetailScreen):
  /// once this report's pin is drawn, the map centres on it and opens the
  /// same detail sheet a tap on the pin would — landing a resident exactly
  /// where they asked to go, not on the province-wide default view with
  /// one more pin among many for them to go find themselves.
  final String? focusIncidentId;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

// Sources and layers for the device's own position. Named, because they are
// updated in place on every new fix rather than being torn down and re-added.
const _kMeAccuracySource = 'me-accuracy-src';
const _kMeAccuracyFill = 'me-accuracy-fill';
const _kMeAccuracyLine = 'me-accuracy-line';
const _kMePointSource = 'me-point-src';
const _kMePointLayer = 'me-point';

// The "Get directions" line — a straight line from the device to a station,
// drawn on Ziren's own map instead of handing off to an external navigation
// app. Named and reused rather than torn down/re-added, same reasoning as
// the device's own position layers above.
const _kRouteLineSource = 'route-line-src';
const _kRouteLineLayer = 'route-line';

// Stations and incidents — one shared GeoJSON source and symbol layer each,
// same reasoning as the device's own position above, and the only way to get
// a zoom-driven icon-size expression at all: the annotation API these used
// to go through (ctrl.addSymbol) stores icon-size as a plain per-feature
// value with no way to hand it a zoom expression.
const _kStationSource = 'stations-src';
const _kStationLayer = 'stations';

// Invisible circle layers, one per source above, whose only job is to be
// tapped. The icon layers already carry `iconAllowOverlap`/
// `iconIgnorePlacement`, so their icon shrinks when zoomed out (see
// _pinScale) — well under
// ZirenTokens.minTouchTarget (48px), and confirmed live: taps within the
// icon's own visible bounds routinely missed it. A circle layer hit-tests
// against its geometric radius rather than rasterised icon pixels, so a
// fixed-radius, zero-opacity circle on the same point gives every pin a
// consistent, reliable touch target without changing how anything looks.
const _kStationTapAreaLayer = 'stations-tap-area';

// Names under the pins — each station's name, and "You" under the viewer's
// own pin. Separate text-only layers, never a textField on the pin layers
// themselves: a symbol layer whose text cannot render (a style without
// glyphs) drops its icon with it, and a pin must always draw.
const _kStationLabelLayer = 'stations-label';
const _kMeLabelLayer = 'me-label';

/// Fonts for the pin labels, served by OfflineMapService like every other
/// label. Wrapped in `literal`: a bare list is read as an expression and
/// rejected ("invalid value for text-font").
const List<dynamic> _kPinLabelFont = [
  Expressions.literal,
  ['Noto Sans Medium'],
];
const double _kTapAreaRadius = 24;

class _MapScreenState extends State<MapScreen> {
  final _mapProvider = MapProvider();
  MapLibreMapController? _mapController;

  /// The provider that owns the GPS fix. Held so the listener can be removed;
  /// context is not safe to read from dispose().
  IncidentProvider? _incidents;

  /// Layers cannot be added before the style exists, and a fix can arrive
  /// first.
  bool _styleReady = false;

  /// Whether the pin artwork made it into the sprite atlas.
  ///
  /// Read by the layer builders rather than passed down, because the device
  /// marker is created in a different method from the one that registers the
  /// images. False means every marker falls back to the style's built-in
  /// sprites — a plainer map, never an empty one.
  bool _markerArtReady = false;

  /// The station shown on the bottom card.
  ///
  /// Set when a pin is tapped. Null means the card falls back to whichever
  /// visible station is nearest the device — the "nearby emergency station"
  /// the mockup card promises before the resident has touched anything.
  StationModel? _selectedStation;

  /// Whether the bottom card's station list is expanded.
  ///
  /// Tapping a pin on the map is one way to change the card's station;
  /// this is the other, for whenever that pin is small, overlapping a
  /// cluster, or just not worth the reach — picking from a plain list of
  /// every visible station, nearest first, is the more reliable path on
  /// a phone.
  bool _stationPickerOpen = false;

  /// Guards [_maybeFocusInitialIncident] to run once. [_drawPins] itself is
  /// already one-shot, but that guard belongs to drawing the layers, not to
  /// this — keeping them separate means a future reason to redraw incidents
  /// (mirroring [_refreshStationSource]) would not silently disable this too.
  bool _focusHandled = false;

  /// The report [MapScreen.focusIncidentId] resolved to, and the station
  /// handling it — both null until [_drawPins] resolves them, and null for
  /// good if the id did not match anything plottable.
  IncidentModel? _focusIncident;
  StationModel? _focusStation;

  /// Whether the focused report's card is showing at the bottom of the map.
  /// It is a card over the map, not a modal sheet: see
  /// [_maybeFocusInitialIncident].
  bool _focusCardOpen = false;

  /// Which station sits at each feature index in [_kStationSource], in the
  /// same order the GeoJSON was built — a tap on the shared layer comes back
  /// as a feature id, not a model, and this is how it is turned back into
  /// one.
  List<StationModel> _plottedStations = [];

  /// The viewer's reports with coordinates. Not drawn (see [_drawPins]);
  /// only searched for the one report [MapScreen.focusIncidentId] names.
  List<IncidentModel> _plottedIncidents = [];

  /// Whether marker art has been requested from the atlas.
  ///
  /// Guards [_drawPins] against running twice — style-load and data-load
  /// race each other (see the note on [_drawPins]), and either one can
  /// finish first.
  bool _pinsDrawn = false;

  /// Whether this screen is on screen right now, read from [TickerMode].
  ///
  /// THE MAP IS BUILT ONLY WHILE IT CAN BE SEEN, and that is the fix for "the
  /// map stops responding after I have used the rest of the app".
  ///
  /// The resident shell keeps every tab alive in an IndexedStack, so this
  /// widget - and the native MapLibre view under it - used to survive being
  /// hidden behind another tab or a full-screen route and then be shown again.
  /// On Android the platform view does not reliably get its touch input back
  /// after that (it depends on the handset and its GPU driver, which is why the
  /// same build worked on some phones and not others), and logging out fixed it
  /// only because it tore the whole shell down. Flutter reports "hidden" to
  /// everything under an opaque route or an inactive tab as
  /// `TickerMode.of(context) == false`, so the native view is disposed then and
  /// created fresh on return: the same thing logging out was doing, without the
  /// logging out.
  bool _visible = true;
  bool _visibilityKnown = false;

  /// New each time the map is (re)built, so Flutter mounts a fresh native view
  /// rather than reusing one that has lost its input.
  Key _mapKey = UniqueKey();

  /// Where the camera was when the map was last hidden, so coming back does not
  /// throw the resident back to the province-wide view.
  CameraPosition? _lastCamera;

  /// Null until [OfflineMapService.resolveStyle] settles — see [build],
  /// which shows a loading spinner in place of the map itself rather than
  /// constructing MapLibreMap with a style that might get replaced a moment
  /// later. Swapping `styleString` on a live controller would fire
  /// onStyleLoadedCallback a second time and re-run every piece of state in
  /// this class that assumes it only ever runs once.
  String? _resolvedStyle;

  /// Whether the loaded style can draw text: Ziren's own styles serve fonts,
  /// the raster fallback (kZirenMapStyle) does not. Pin labels are only
  /// added when it can.
  bool get _styleHasGlyphs => _resolvedStyle?.contains('"glyphs"') ?? false;

  @override
  void initState() {
    super.initState();
    OfflineMapService.instance.resolveStyle().then((style) {
      if (mounted) setState(() => _resolvedStyle = style);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Which incidents this map is about depends on who is looking.
      widget.forResponder
          ? _mapProvider.loadForResponder()
          : _mapProvider.load();
      // Stations and incidents are drawn once both the map style and this
      // data are ready — whichever finishes second triggers the draw. See
      // _drawPins for why a single call in onStyleLoadedCallback alone was
      // not enough.
      _mapProvider.addListener(_onMapDataChanged);
      // The map is the one screen where a resident can see for themselves
      // whether Ziren knows where they are, so it asks for a fix on entry
      // rather than waiting for a report to be started.
      final incidents = context.read<IncidentProvider>();
      _incidents = incidents..addListener(_onLocationChanged);
      incidents.fetchLocation();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.of(context);
    if (_visibilityKnown && visible == _visible) return;
    final first = !_visibilityKnown;
    _visibilityKnown = true;
    _visible = visible;
    // initState already started everything for the first show.
    if (first) return;

    if (visible) {
      // Back on screen: a new native view, and fresh data - incidents move
      // while a resident is elsewhere in the app.
      _mapKey = UniqueKey();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.forResponder
            ? _mapProvider.loadForResponder()
            : _mapProvider.load();
      });
    } else {
      // Hidden: the native view is about to be disposed, and every layer in it
      // goes with it.
      _lastCamera = _mapController?.cameraPosition ?? _lastCamera;
      _mapController = null;
      _styleReady = false;
      _pinsDrawn = false;
      _markerArtReady = false;
    }
  }

  @override
  void dispose() {
    _incidents?.removeListener(_onLocationChanged);
    _mapProvider.removeListener(_onMapDataChanged);
    _mapProvider.dispose();
    super.dispose();
  }

  void _onLocationChanged() {
    if (mounted) _renderMyLocation();
  }

  void _onMapDataChanged() {
    // Only once the fetch has actually settled — a mid-flight notifyListeners
    // (loading: true) has nothing plottable yet, and drawing an empty list
    // here would flip _pinsDrawn true and skip the real draw once data
    // arrives.
    if (!mounted || _mapProvider.loading) return;
    // The very first time, lay down the sources and layers. Every time
    // after — an agency filter pill, most likely — the layers already
    // exist and only the station source's own features need refreshing.
    if (!_pinsDrawn) {
      _drawPins();
    } else {
      _refreshStationSource();
    }
  }

  void _onMapCreated(MapLibreMapController ctrl) {
    _mapController = ctrl;
    // A new native map has none of the layers the last one had.
    _styleReady = false;
    _pinsDrawn = false;
    _markerArtReady = false;
    // One shared listener for both raw layers, routed by layerId rather than
    // one closure per pin the way the old per-symbol onSymbolTapped did —
    // there is no per-feature callback to attach to on a style layer, only
    // this controller-wide stream, so the feature id (this layer's array
    // index into _plottedStations at the time it was
    // drawn) is what tells two taps on the same layer apart.
    ctrl.onFeatureTapped.add((id, point, coordinates, layerId) {
      // id arrives as a String even though the GeoJSON gave every feature a
      // plain integer id — the native plugin reads it back via the Mapbox
      // Java SDK's Feature.id(), which is typed String regardless of what
      // the source JSON's id looked like. Checking `id is num` here (as if
      // the int survived as an int) was the actual bug: it was never true,
      // so every tap on a station or incident silently did nothing.
      final index = int.tryParse(id.toString());
      if (index == null) return;
      // The tap-area layers (see _kStationTapAreaLayer) share the exact same
      // per-feature index as their visible icon layer, so both route here
      // identically — they exist only to give the real layer a bigger, more
      // reliable hit-box, not a different meaning.
      if ((layerId == _kStationLayer || layerId == _kStationTapAreaLayer) &&
          index >= 0 &&
          index < _plottedStations.length) {
        _onStationTap(_plottedStations[index]);
      }
    });
  }

  Future<void> _onStyleLoaded() async {
    final ctrl = _mapController;
    if (ctrl == null) return;
    _styleReady = true;
    // Registered once, here, unconditionally — never inside _drawPins.
    // It used to live inside _drawPins, which _addMyLocationLayers below
    // depends on (_markerArtReady) but does not itself call. When
    // _drawPins bailed out early because the station/incident fetch was
    // still in flight, _registerMarkerImages never ran, _markerArtReady
    // stayed at its default false, and the device's own pin silently fell
    // back to a plain circle instead of the real artwork — a second,
    // separate symptom of the exact same race as the one on _drawPins.
    await _registerMarkerImages(ctrl);
    // Added before stations/incidents so the device sits above them.
    await _addMyLocationLayers(ctrl);
    await _renderMyLocation();
    await _drawPins();
  }

  /// Plots every station and incident currently known to [_mapProvider].
  ///
  /// Split out of onStyleLoadedCallback because that fires once, on its own
  /// schedule, and the station/incident fetch is a separate network round
  /// trip racing it. A map opened on a fast style load and a slow Supabase
  /// response drew zero stations — not because none existed, but because
  /// this loop ran against a still-empty list and nothing ever asked it to
  /// run again once the real list arrived. Now it is called from both
  /// directions (style-ready, and data-ready via [_onMapDataChanged]), and
  /// runs only once regardless of which fires first or second.
  /// The GeoJSON feature list for [_plottedStations], in the same order —
  /// shared by the initial draw and every later refresh (agency filter
  /// changes) so the two never drift into building the source differently.
  List<Map<String, dynamic>> _buildStationFeatures(bool haveArt) => [
    for (var idx = 0; idx < _plottedStations.length; idx++)
      () {
        final s = _plottedStations[idx];
        final art = haveArt ? _kStationImage[s.agencyType] : null;
        return {
          'type': 'Feature',
          'id': idx,
          'properties': {
            // The agency's own pin when it is registered, and the style's
            // built-in sprite tinted by agency when it is not — an image
            // that failed to load must not take the station off the map
            // with it.
            'iconImage': art ?? 'marker-15',
            if (art == null) 'iconColor': _agencyHex(s.agencyType),
            'name': s.name,
          },
          'geometry': {
            'type': 'Point',
            'coordinates': [s.longitude, s.latitude],
          },
        };
      }(),
  ];

  /// Re-reads which stations the agency filter currently allows and pushes
  /// them straight into the existing station source.
  ///
  /// Not a call to [_drawPins]: that function is guarded to run exactly
  /// once (see its own comment on the race it exists to close), which is
  /// correct for the one-time style/data race but wrong here — a filter
  /// pill tap fires this every time, and _drawPins would silently no-op
  /// after the first one. The layers themselves never need to change, only
  /// which features are in the source feeding them, so this updates the
  /// source in place instead of tearing anything down.
  Future<void> _refreshStationSource() async {
    final ctrl = _mapController;
    if (ctrl == null || !_pinsDrawn) return;

    _plottedStations = _mapProvider.plottableStations;
    try {
      await ctrl.setGeoJsonSource(_kStationSource, {
        'type': 'FeatureCollection',
        'features': _buildStationFeatures(_markerArtReady),
      });
    } catch (e, st) {
      debugPrint('[map] station source refresh FAILED: $e\n$st');
    }
  }

  Future<void> _drawPins() async {
    final ctrl = _mapController;
    // The bug this replaced, one level deeper: _pinsDrawn was being set
    // before checking whether _mapProvider had actually finished loading.
    // Called from _onStyleLoaded before the station fetch resolved, this
    // ran its loop against an empty list, found nothing to draw, and still
    // latched _pinsDrawn — permanently skipping the real draw once the data
    // arrived a moment later. Guarding on `loading` here, not just in the
    // caller, means it is impossible to mark this done before there is
    // something to actually show.
    if (ctrl == null || !_styleReady || _pinsDrawn || _mapProvider.loading) {
      return;
    }
    _pinsDrawn = true;

    // Registered once already, in _onStyleLoaded — read the result rather
    // than requesting it again.
    final haveArt = _markerArtReady;

    _plottedIncidents = _mapProvider.plottableIncidents;

    // Focused on one report (My Reports → View on Map): the only station
    // this view has any business showing is the one handling THAT report —
    // not every station the resident could file a new one to. Resolved
    // here, before the station source is built, rather than after, so the
    // very first draw already respects it instead of drawing everyone and
    // narrowing a moment later.
    final focusId = widget.focusIncidentId;
    if (focusId != null) {
      for (final i in _plottedIncidents) {
        if (i.id == focusId) {
          _focusIncident = i;
          break;
        }
      }
      _focusStation = _mapProvider.stationById(_focusIncident?.stationId);
      _plottedStations = _focusStation != null ? [_focusStation!] : const [];
    } else {
      _plottedStations = _mapProvider.plottableStations;
    }

    debugPrint(
      '[map] _drawPins: haveArt=$haveArt, '
      'stationCount=${_plottedStations.length}',
    );

    try {
      final stationFeatures = _buildStationFeatures(haveArt);

      await ctrl.addSource(
        _kStationSource,
        GeojsonSourceProperties(
          data: {'type': 'FeatureCollection', 'features': stationFeatures},
        ),
      );
      await ctrl.addLayer(
        _kStationSource,
        _kStationLayer,
        SymbolLayerProperties(
          iconImage: [Expressions.get, 'iconImage'],
          iconColor: haveArt ? null : [Expressions.get, 'iconColor'],
          iconSize: _pinScale(haveArt ? _kStationIconScale : 1.8),
          iconAnchor: haveArt ? 'bottom' : null,
          // Never dropped for collision — see the "me" layer's own comment
          // on why. With several agency pins only ~100-150m apart
          // (BFP/PNP/MDRRMO in the same town), the collision engine would
          // otherwise be constantly re-deciding which pins can be shown as
          // the zoom level changes, and a pin transitioning between hidden
          // and shown fades through that change rather than snapping —
          // which read, live, as "the pin gets so small" while pinch-
          // zooming, on top of the separate zoom-scale issue this layer's
          // iconSize expression above actually addresses.
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
          // No textField here, deliberately: a symbol layer whose text cannot
          // render (the fallback kZirenMapStyle has no `glyphs`) fails to
          // draw ENTIRELY, icon included — confirmed via logcat. The name is
          // its own layer below, so a missing font costs the label only.
        ),
        belowLayerId: _kMePointLayer,
      );
      if (_styleHasGlyphs) {
        await ctrl.addLayer(
          _kStationSource,
          _kStationLabelLayer,
          const SymbolLayerProperties(
            textField: [Expressions.get, 'name'],
            textFont: _kPinLabelFont,
            textSize: 11,
            textColor: '#1A1A1A',
            textHaloColor: '#FFFFFF',
            textHaloWidth: 1.6,
            // The pin stands ON the point (anchor bottom), so its name goes
            // under the point, clear of the art.
            textAnchor: 'top',
            textOffset: [
              Expressions.literal,
              [0, 0.3],
            ],
            textMaxWidth: 9,
            // Crowded town centres (BFP, PNP and MDRRMO a street apart) drop
            // overlapping names rather than stack them; zooming in brings
            // them back. The pins themselves never drop.
            textAllowOverlap: false,
          ),
          belowLayerId: _kMePointLayer,
          // The province view is 21 names on one island — unreadable.
          minzoom: 12,
        );
      }
      // See _kStationTapAreaLayer: a fixed-size, invisible hit target on top
      // of the icon so a tap near a small or zoomed-out pin still lands.
      await ctrl.addLayer(
        _kStationSource,
        _kStationTapAreaLayer,
        const CircleLayerProperties(
          circleRadius: _kTapAreaRadius,
          circleOpacity: 0,
        ),
      );
    } catch (e, st) {
      debugPrint('[map] station layer FAILED: $e\n$st');
    }

    // Reports are deliberately NOT drawn as dots on this map (removed at the
    // user's request, 2026-09-30): a coloured dot read as clutter, not
    // information. A single report opened from My Reports still gets its
    // line from the responding station and its detail card.
    _maybeFocusInitialIncident();
  }

  /// The colour of the line from a focused report to its station — carries
  /// the same meaning the status pill does elsewhere in the app (see
  /// ZirenTokens.statusReceived/Processing/Dispatched/Resolved/Cancelled;
  /// hex literals repeated here for the same reason _agencyHex
  /// above does, rather than importing app_tokens.dart's Color values
  /// only to unwrap them back into hex strings).
  String _statusLineHex(String status) => switch (status) {
    'resolved' => '#16A34A',
    'dispatched' || 'en_route' || 'arrived' => '#FC5A05',
    'processing' => '#4F46E5',
    'cancelled' => '#9CA3AF',
    _ => '#6B7280', // received, or a future status this build doesn't know
  };

  /// Centres on [MapScreen.focusIncidentId], once, the first time it appears
  /// among the viewer's reports — drawing a status-coloured
  /// line to the responding station if one is known, and opening the same
  /// report detail card.
  ///
  /// Silent no-op if the id is missing, unmatched (deleted, or filed by a
  /// different account than the one now signed in), or has no coordinates
  /// — the resident still lands on a working map, just without the extra
  /// step this was meant to save them.
  void _maybeFocusInitialIncident() {
    if (_focusHandled) return;
    if (widget.focusIncidentId == null) return;
    _focusHandled = true;

    final incident = _focusIncident;
    if (incident == null) return;
    final lat = incident.latitude;
    final lng = incident.longitude;
    if (lat == null || lng == null) return;

    final station = _focusStation;
    final stationLat = station?.latitude;
    final stationLng = station?.longitude;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (station != null && stationLat != null && stationLng != null) {
        // Help travels FROM the station TO the incident — the direction a
        // resident actually cares about here, even though the line itself
        // draws identically either way.
        await _drawRoute(
          fromLat: stationLat,
          fromLng: stationLng,
          toLat: lat,
          toLng: lng,
          color: _statusLineHex(incident.status),
        );
      } else {
        await _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: LatLng(lat, lng), zoom: 16),
          ),
        );
      }
      if (!mounted) return;
      // Not the modal sheet a tap on the pin opens. Its scrim dims the map and
      // swallows every touch until it is dismissed, so a resident who came
      // here to look at the map found it frozen behind a grey veil. This card
      // sits over the bottom of the map instead, and the map above it stays
      // live.
      setState(() => _focusCardOpen = true);
    });
  }

  /// Load the pin artwork into the map's sprite atlas.
  ///
  /// Returns whether it worked. A missing or corrupt asset is not worth
  /// failing a map over — the caller falls back to the style's built-in
  /// sprite, tinted by agency, which is exactly what this screen drew before.
  /// A station that vanishes because a PNG did not decode would be a far worse
  /// outcome than one drawn with a plainer pin.
  Future<bool> _registerMarkerImages(MapLibreMapController ctrl) async {
    try {
      for (final entry in _kMarkerAssets.entries) {
        final bytes = await rootBundle.load(entry.value);
        await ctrl.addImage(entry.key, bytes.buffer.asUint8List());
      }
      _markerArtReady = true;
    } catch (e) {
      debugPrint('[map] marker art unavailable, using built-in pins: $e');
      _markerArtReady = false;
    }
    return _markerArtReady;
  }

  /// Registers the two sources and three layers that draw the device.
  ///
  /// They start empty. A fix may not exist yet, may be refused, or may never
  /// arrive; the layers still exist, so every later update is a data swap
  /// rather than a rebuild that could race the style.
  Future<void> _addMyLocationLayers(MapLibreMapController ctrl) async {
    await ctrl.addSource(
      _kMeAccuracySource,
      GeojsonSourceProperties(data: GeoCircle.empty),
    );
    await ctrl.addLayer(
      _kMeAccuracySource,
      _kMeAccuracyFill,
      const FillLayerProperties(fillColor: '#1E88E5', fillOpacity: 0.12),
    );
    await ctrl.addLayer(
      _kMeAccuracySource,
      _kMeAccuracyLine,
      const LineLayerProperties(
        lineColor: '#1E88E5',
        lineWidth: 1.5,
        lineOpacity: 0.55,
      ),
    );

    await ctrl.addSource(
      _kMePointSource,
      GeojsonSourceProperties(data: GeoCircle.empty),
    );

    // The person pin, when its artwork loaded — a resident's or a responder's,
    // depending on who is holding the phone.
    //
    // THE ACCURACY CIRCLE STAYS, AND THAT IS THE POINT
    //
    // The pin replaces the blue dot and nothing else. The circle around it is
    // how far wrong the fix may be, and it is the only thing on this screen
    // that distinguishes a position good to five metres from one good to a
    // kilometre. Swapping a dot for a nicer dot is cosmetic; dropping the
    // circle with it would restore exactly the false confidence it was added
    // to remove.
    if (_markerArtReady) {
      await ctrl.addLayer(
        _kMePointSource,
        _kMePointLayer,
        SymbolLayerProperties(
          iconImage:
              widget.forResponder ? _kMeIconResponder : _kMeIconResident,
          iconSize: _pinScale(_kMeIconScale),
          iconAnchor: 'bottom',
          // Array values go in as a `literal`: a bare [0, 17] is read as an
          // expression and rejected ("icon-offset value must be an array of
          // 2 numbers"), which left the pin's tip off the fix.
          iconOffset: const [Expressions.literal, [0, _kMeTipInset]],
          // Never dropped for collision. Every other mark on this map can be
          // hidden by a neighbour without costing anything; the one that says
          // where the viewer is standing cannot.
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
        ),
      );
      if (_styleHasGlyphs && mounted) {
        await ctrl.addLayer(
          _kMePointSource,
          _kMeLabelLayer,
          SymbolLayerProperties(
            textField: AppLocalizations.of(context).mapYouLabel,
            textFont: _kPinLabelFont,
            textSize: 12,
            textColor: '#FFFFFF',
            textHaloColor: '#1E88E5',
            textHaloWidth: 2.2,
            // Under the glow ring the pin stands on, which is the position.
            textAnchor: 'top',
            textOffset: const [
              Expressions.literal,
              [0, 0.6],
            ],
            // Like the pin: where the viewer stands is never hidden.
            textAllowOverlap: true,
            textIgnorePlacement: true,
          ),
        );
      }
    } else {
      await ctrl.addLayer(
        _kMePointSource,
        _kMePointLayer,
        const CircleLayerProperties(
          circleRadius: 7,
          circleColor: '#1E88E5',
          circleStrokeWidth: 3,
          circleStrokeColor: '#FFFFFF',
        ),
      );
    }

    await ctrl.addSource(
      _kRouteLineSource,
      GeojsonSourceProperties(data: GeoCircle.empty),
    );
    await ctrl.addLayer(
      _kRouteLineSource,
      _kRouteLineLayer,
      const LineLayerProperties(
        lineColor: '#FC5A05',
        lineWidth: 3,
        lineOpacity: 0.85,
        // As a `literal`, or MapLibre rejects it and draws the line solid.
        lineDasharray: [Expressions.literal, [2, 1.5]],
      ),
    );
  }

  /// Pushes the current fix into the map.
  ///
  /// Two shapes, and the second is the one that matters. The dot is where the
  /// device believes it is; the circle is how far wrong that belief may be.
  /// Showing only the dot is what let a position over a kilometre out look
  /// exactly like a good one.
  Future<void> _renderMyLocation() async {
    final ctrl = _mapController;
    if (ctrl == null || !_styleReady) return;

    final pos = _incidents?.currentPosition;
    if (pos == null) {
      await ctrl.setGeoJsonSource(_kMeAccuracySource, GeoCircle.empty);
      await ctrl.setGeoJsonSource(_kMePointSource, GeoCircle.empty);
      return;
    }

    // A fix always reports some accuracy; clamp so a zero or nonsense value
    // cannot collapse the circle into an invisible point and quietly restore
    // the false confidence this is here to remove.
    final radius =
        pos.accuracy.isFinite && pos.accuracy > 5 ? pos.accuracy : 5.0;

    await ctrl.setGeoJsonSource(
      _kMeAccuracySource,
      GeoCircle.featureCollection(
        lat: pos.latitude,
        lon: pos.longitude,
        radiusMetres: radius,
      ),
    );
    await ctrl.setGeoJsonSource(_kMePointSource, {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'properties': const <String, dynamic>{},
          'geometry': {
            'type': 'Point',
            'coordinates': [pos.longitude, pos.latitude],
          },
        },
      ],
    });
  }

  /// Centre on the device.
  ///
  /// The button used to animate to a hardcoded province centre — it was
  /// labelled as locating the user and did not look at the user's location at
  /// all. When there is no fix it now says so instead of pretending.
  Future<void> _locateMe() async {
    final pos = _incidents?.currentPosition;
    if (pos == null) {
      await _incidents?.fetchLocation();
      if (!mounted) return;
      if (_incidents?.currentPosition == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).mapNoLocationYet)),
        );
        return;
      }
    }
    final p = _incidents!.currentPosition!;
    // Zoom chosen so the accuracy circle is legible: a good fix reads as a
    // small ring around a building, a poor one visibly swallows the barangay.
    await _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: LatLng(p.latitude, p.longitude), zoom: 16),
      ),
    );
  }

  /// "Get directions" without leaving the app — draws a road-following route
  /// from the device to [station] on Ziren's own map when one can be fetched,
  /// falling back to a straight line when it cannot, and fits both ends in
  /// view either way.
  ///
  /// The route comes from OSRM's public demo routing server — free, keyless,
  /// no account for this project to hold — but it is exactly that: a shared
  /// community demo with no uptime guarantee and no rate-limit protection,
  /// not infrastructure to depend on for an emergency app. So it is never the
  /// only path: any failure (down, slow, rate-limited, malformed reply) falls
  /// straight back to the direct line, which needs nothing external and
  /// cannot itself fail. "Get directions" doing something is more important
  /// than the something being road-accurate.
  Future<void> _showDirectionsOnMap(StationModel station) async {
    final lat = station.latitude;
    final lng = station.longitude;
    if (lat == null || lng == null) return;

    var pos = _incidents?.currentPosition;
    if (pos == null) {
      await _incidents?.fetchLocation();
      if (!mounted) return;
      pos = _incidents?.currentPosition;
      if (pos == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).mapNoLocationYet)),
        );
        return;
      }
    }

    await _drawRoute(
      fromLat: pos.latitude,
      fromLng: pos.longitude,
      toLat: lat,
      toLng: lng,
    );
  }

  /// The shared line-drawing step behind both "Get directions" (device to a
  /// station) and the focused report view's "help is coming from here" line
  /// (an incident to the station handling it) — only the two endpoints and
  /// the colour differ between them.
  ///
  /// The route comes from OSRM's public demo routing server — free, keyless,
  /// no account for this project to hold — but it is exactly that: a shared
  /// community demo with no uptime guarantee and no rate-limit protection,
  /// not infrastructure to depend on for an emergency app. So it is never the
  /// only path: any failure (down, slow, rate-limited, malformed reply) falls
  /// straight back to the direct line, which needs nothing external and
  /// cannot itself fail. A line appearing is more important than the line
  /// being road-accurate.
  Future<void> _drawRoute({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
    String color = '#FC5A05',
  }) async {
    final ctrl = _mapController;
    if (ctrl == null) return;

    final roadRoute = await _fetchRoadRoute(fromLat, fromLng, toLat, toLng);
    final coordinates =
        roadRoute ??
        [
          [fromLng, fromLat],
          [toLng, toLat],
        ];
    if (!mounted) return;

    await ctrl.setLayerProperties(
      _kRouteLineLayer,
      LineLayerProperties(lineColor: color),
    );
    await ctrl.setGeoJsonSource(_kRouteLineSource, {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'properties': const <String, dynamic>{},
          'geometry': {'type': 'LineString', 'coordinates': coordinates},
        },
      ],
    });

    final south = math.min(fromLat, toLat);
    final north = math.max(fromLat, toLat);
    final west = math.min(fromLng, toLng);
    final east = math.max(fromLng, toLng);
    await ctrl.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(south, west),
          northeast: LatLng(north, east),
        ),
        left: 60,
        top: 100,
        right: 60,
        // Clears the station card overlapping the bottom of the map, so
        // the line's own endpoint is not hidden behind it.
        bottom: 340,
      ),
    );
  }

  /// A road-following path from ([fromLat], [fromLng]) to ([toLat], [toLng]),
  /// as a list of `[lon, lat]` pairs ready to drop straight into a GeoJSON
  /// LineString — or null if OSRM's demo server did not answer with one for
  /// any reason. Every failure mode collapses to null on purpose: a caller
  /// that only has to handle "got a route" and "did not" cannot forget to
  /// fall back.
  Future<List<List<double>>?> _fetchRoadRoute(
    double fromLat,
    double fromLng,
    double toLat,
    double toLng,
  ) async {
    try {
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '$fromLng,$fromLat;$toLng,$toLat'
        '?geometries=geojson&overview=full',
      );
      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = body['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) return null;

      final geometry = (routes.first as Map<String, dynamic>)['geometry']
          as Map<String, dynamic>?;
      final coords = geometry?['coordinates'] as List<dynamic>?;
      if (coords == null || coords.isEmpty) return null;

      return [
        for (final c in coords)
          [(c[0] as num).toDouble(), (c[1] as num).toDouble()],
      ];
    } catch (e) {
      debugPrint('[map] OSRM route fetch failed, falling back to line: $e');
      return null;
    }
  }

  String _agencyHex(String type) => switch (type) {
    'BFP' => '#E53935',
    'PNP' => '#1E88E5',
    _ => '#43A047',
  };

  /// A tapped pin becomes the card at the bottom of the screen, replacing
  /// whatever it was showing before — the nearest station, or an earlier tap.
  /// Picking one from the open list (see [_stationPickerOpen]) lands here
  /// too, and closes it the same way choosing a pin would.
  void _onStationTap(StationModel station) {
    setState(() {
      _selectedStation = station;
      _stationPickerOpen = false;
    });
  }

  /// The station the bottom card shows: a tapped pin, so long as its agency
  /// is still visible under the current filter, otherwise the nearest
  /// visible station to the device. Null only when nothing plottable exists.
  StationModel? _resolveDisplayStation(MapProvider provider) {
    final selected = _selectedStation;
    if (selected != null && provider.isAgencyVisible(selected.agencyType)) {
      return selected;
    }

    final stations = provider.plottableStations;
    if (stations.isEmpty) return null;

    final pos = _incidents?.currentPosition;
    if (pos == null) return stations.first;

    var nearest = stations.first;
    var nearestMetres = double.infinity;
    for (final s in stations) {
      final metres = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        s.latitude!,
        s.longitude!,
      );
      if (metres < nearestMetres) {
        nearestMetres = metres;
        nearest = s;
      }
    }
    return nearest;
  }

  /// Straight-line distance from the device to [station], in kilometres. Null
  /// when there is no fix yet — the card falls back to naming the agency.
  double? _distanceKmTo(StationModel? station) {
    final pos = _incidents?.currentPosition;
    if (station == null ||
        pos == null ||
        station.latitude == null ||
        station.longitude == null) {
      return null;
    }
    return Geolocator.distanceBetween(
          pos.latitude,
          pos.longitude,
          station.latitude!,
          station.longitude!,
        ) /
        1000;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    return ChangeNotifierProvider.value(
      value: _mapProvider,
      child: Consumer<MapProvider>(
        builder: (context, provider, _) {
          // Locked to one report and its station — see _maybeFocusInitialIncident.
          // The normal "pick any station" chrome (agency pills, the
          // nearest-station card with its own picker) would let a resident
          // wander off that one station, which defeats the point of a view
          // that exists to answer "who is handling MY report".
          final isFocused = widget.focusIncidentId != null;
          final displayStation = _resolveDisplayStation(provider);
          final displayDistanceKm = _distanceKmTo(displayStation);
          // Nearest first — the same order a resident would scan a list
          // looking for "which of these is actually close".
          final pickerStations = [...provider.plottableStations]..sort(
            (a, b) => (_distanceKmTo(a) ?? double.infinity).compareTo(
              _distanceKmTo(b) ?? double.infinity,
            ),
          );

          return Scaffold(
            backgroundColor: ZirenTokens.surfaceBase,
            body: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  // ── Header ──────────────────────────────────
                  _MapHeader(
                    title:
                        widget.forResponder
                            ? t.mapResponderTitle
                            : isFocused
                            ? t.mapReportLocationTitle
                            : t.mapNearbyStationsTitle,
                    showBack: widget.forResponder || isFocused,
                  ),

                  // ── Agency filter pills ─────────────────────
                  if (!isFocused) ...[
                    _AgencyFilterRow(provider: provider),
                    const SizedBox(height: ZirenTokens.space8),
                  ],

                  // ── Map + everything that overlaps it ───────
                  Expanded(
                    child: Stack(
                      children: [
                        if (_resolvedStyle == null)
                          const Center(child: CircularProgressIndicator())
                        else if (_visible)
                          MapLibreMap(
                            // See [_mapKey]: a fresh native view every time the
                            // map comes back on screen.
                            key: _mapKey,
                            styleString: _resolvedStyle!,
                            initialCameraPosition:
                                _lastCamera ??
                                const CameraPosition(
                                  target: _kBiliranCenter,
                                  zoom: _kInitialZoom,
                                ),
                            onMapCreated: _onMapCreated,
                            onStyleLoadedCallback: _onStyleLoaded,
                            compassEnabled: false,
                            rotateGesturesEnabled: false,
                            // Tracked so the camera survives the map being
                            // rebuilt - see [_lastCamera].
                            trackCameraPosition: true,
                          )
                        else
                          const SizedBox.expand(),

                        // ── Floating map controls ─────────────
                        Positioned(
                          right: ZirenTokens.space16,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _MyLocationChip(
                                  provider: context.watch<IncidentProvider>(),
                                ),
                                const SizedBox(height: ZirenTokens.space12),
                                _MapFab(
                                  icon: LucideIcons.locate_fixed,
                                  iconColor: ZirenTokens.brandOrange,
                                  onTap: _locateMe,
                                ),
                              ],
                            ),
                          ),
                        ),

                        // ── Loading overlay ───────────────────
                        if (provider.loading) const _LoadingOverlay(),

                        // ── Error banner ───────────────────────
                        if (provider.error != null)
                          _ErrorBanner(message: provider.error!),

                        // ── Nearest / selected station card ───
                        // Suppressed when focused — the incident detail
                        // sheet _maybeFocusInitialIncident opens already
                        // covers this report's own status, and letting the
                        // resident pick a DIFFERENT station from here would
                        // contradict "only the station that responded".
                        if (isFocused &&
                            _focusCardOpen &&
                            _focusIncident != null)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: GestureDetector(
                              // A downward flick puts the card away; tapping
                              // the report's own pin brings it back.
                              onVerticalDragEnd: (details) {
                                if ((details.primaryVelocity ?? 0) > 250) {
                                  setState(() => _focusCardOpen = false);
                                }
                              },
                              child: _IncidentDetailSheet(
                                incident: _focusIncident!,
                              ),
                            ),
                          ),
                        if (displayStation != null && !isFocused)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: _StationDetailSheet(
                              station: displayStation,
                              distanceKm: displayDistanceKm,
                              onGetDirections:
                                  () => _showDirectionsOnMap(displayStation),
                              pickerOpen: _stationPickerOpen,
                              onTogglePicker:
                                  () => setState(
                                    () =>
                                        _stationPickerOpen =
                                            !_stationPickerOpen,
                                  ),
                              otherStations:
                                  pickerStations
                                      .where((s) => s.id != displayStation.id)
                                      .toList(),
                              distanceKmTo: _distanceKmTo,
                              onSelectStation: _onStationTap,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Header ──────────────────────────────────────────────────────

/// Back arrow (when there is somewhere to go back to) plus the screen title.
///
/// The resident reaches this screen as the Map tab — the root of its own
/// branch in the bottom nav, nothing to pop back to — while the responder
/// shell pushes it on top of an existing stack. [showBack] is driven by
/// which of those this instance is, not by whether a Navigator happens to
/// report a stack at the moment of the tap.
class _MapHeader extends StatelessWidget {
  const _MapHeader({required this.title, required this.showBack});

  final String title;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZirenTokens.space8,
        ZirenTokens.space8,
        ZirenTokens.space20,
        ZirenTokens.space4,
      ),
      child: Row(
        children: [
          if (showBack)
            IconButton(
              icon: Icon(
                LucideIcons.arrow_left,
                color: ZirenTokens.textPrimary,
              ),
              onPressed: () {
                if (context.canPop()) context.pop();
              },
            )
          else
            const SizedBox(width: ZirenTokens.space12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: ZirenTokens.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Floating map button ────────────────────────────────────────

/// A plain circular white FAB, the shared shape behind both buttons that
/// float on the right edge of the map.
class _MapFab extends StatelessWidget {
  const _MapFab({
    required this.icon,
    required this.iconColor,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: ZirenTokens.surfaceCard,
          shape: BoxShape.circle,
          boxShadow: ZirenTokens.shadowMd,
        ),
        child: Icon(icon, size: 20, color: iconColor),
      ),
    );
  }
}

// ── Where the device thinks it is ──────────────────────────────

/// Reads out the fix behind the blue dot.
///
/// The dot alone invites belief. Android hands back a cell-tower position
/// through the same call as a satellite one, and Ziren spent a whole
/// investigation unable to tell which had produced a report, because nothing
/// read `Position.accuracy`. The number is small, and it is the difference
/// between an address and a guess.
///
/// Drawn as a circular button rather than a text chip so it can sit stacked
/// with the recenter control on the map's edge; the detail it used to show
/// inline now surfaces in a SnackBar on tap, so nothing that was legible
/// before is lost — just one tap further away.
class _MyLocationChip extends StatelessWidget {
  const _MyLocationChip({required this.provider});

  final IncidentProvider provider;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final pos = provider.currentPosition;

    final String detail;
    final Color colour;
    final IconData icon;

    if (provider.locationDenied) {
      detail = t.mapLocationOff;
      colour = ZirenTokens.systemError;
      icon = LucideIcons.map_pin_off;
    } else if (pos == null) {
      detail = t.mapLocationSearching;
      colour = ZirenTokens.textMuted;
      icon = LucideIcons.locate_fixed;
    } else if (provider.locationIsPrecise) {
      detail = t.mapLocationPrecise(pos.accuracy.round());
      colour = ZirenTokens.systemSuccess;
      icon = LucideIcons.locate_fixed;
    } else {
      // The case worth shouting about: the circle on the map is wide, and the
      // resident is the only one who can say whether it is in the right place.
      detail = t.mapLocationImprecise(pos.accuracy.round());
      colour = ZirenTokens.systemWarning;
      icon = LucideIcons.locate;
    }

    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(detail)));
      },
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: ZirenTokens.surfaceCard,
          shape: BoxShape.circle,
          border: Border.all(color: colour.withValues(alpha: 0.4)),
          boxShadow: ZirenTokens.shadowMd,
        ),
        child: Icon(icon, size: 19, color: colour),
      ),
    );
  }
}

// ── Agency filter row ──────────────────────────────────────────

class _AgencyFilterRow extends StatelessWidget {
  const _AgencyFilterRow({required this.provider});
  final MapProvider provider;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ZirenTokens.space20),
      child: Row(
        children: [
          _FilterChip(
            label: 'BFP',
            icon: LucideIcons.flame,
            color: ZirenTokens.agencyBFP,
            active: provider.isAgencyVisible('BFP'),
            onTap: () => provider.toggleAgency('BFP'),
          ),
          const SizedBox(width: ZirenTokens.space8),
          _FilterChip(
            label: 'PNP',
            icon: LucideIcons.shield,
            color: ZirenTokens.agencyPNP,
            active: provider.isAgencyVisible('PNP'),
            onTap: () => provider.toggleAgency('PNP'),
          ),
          const SizedBox(width: ZirenTokens.space8),
          _FilterChip(
            label: 'MDRRMO',
            icon: LucideIcons.shield_plus,
            color: ZirenTokens.agencyMDRRMO,
            active: provider.isAgencyVisible('MDRRMO'),
            onTap: () => provider.toggleAgency('MDRRMO'),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: ZirenTokens.motionQuick,
        padding: const EdgeInsets.symmetric(
          horizontal: ZirenTokens.space12,
          vertical: ZirenTokens.space8,
        ),
        decoration: BoxDecoration(
          color: active ? color : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(ZirenTokens.radius16),
          border: Border.all(
            color: active ? color : color.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: active ? Colors.white : color),
            const SizedBox(width: ZirenTokens.space6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Station detail card ────────────────────────────────────────

/// The card overlapping the bottom of the map: whichever station is
/// selected or nearest, its distance, and the one action a resident standing
/// in front of this card actually wants — directions.
///
/// The station row itself is a second way to change that station, besides
/// tapping a pin on the map: tapping it drops down a plain list of every
/// other visible station, nearest first. A small pin in a cluster is a hard
/// target on a phone; a list row never is.
class _StationDetailSheet extends StatelessWidget {
  const _StationDetailSheet({
    required this.station,
    this.distanceKm,
    required this.onGetDirections,
    required this.pickerOpen,
    required this.onTogglePicker,
    required this.otherStations,
    required this.distanceKmTo,
    required this.onSelectStation,
  });

  final StationModel station;
  final double? distanceKm;
  final VoidCallback onGetDirections;

  final bool pickerOpen;
  final VoidCallback onTogglePicker;

  /// Every other visible station, nearest first — see [_MapScreenState.build].
  final List<StationModel> otherStations;
  final double? Function(StationModel?) distanceKmTo;
  final ValueChanged<StationModel> onSelectStation;

  static Color _agencyColor(String type) => switch (type) {
    'BFP' => ZirenTokens.agencyBFP,
    'PNP' => ZirenTokens.agencyPNP,
    _ => ZirenTokens.agencyMDRRMO,
  };

  static Color _agencyBg(String type) => switch (type) {
    'BFP' => ZirenTokens.agencyBFPBg,
    'PNP' => ZirenTokens.agencyPNPBg,
    _ => ZirenTokens.agencyMDRRMOBg,
  };

  static IconData _agencyIcon(String type) => switch (type) {
    'BFP' => LucideIcons.flame,
    'PNP' => LucideIcons.shield,
    _ => LucideIcons.shield_plus,
  };

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final color = _agencyColor(station.agencyType);
    final bg = _agencyBg(station.agencyType);
    final icon = _agencyIcon(station.agencyType);
    final canPick = otherStations.isNotEmpty;

    final km = distanceKm;
    final subtitle =
        km == null
            ? station.agencyType
            : t.mapStationDistance(km.toStringAsFixed(1), station.agencyType);

    return Container(
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ZirenTokens.radius20),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
        ZirenTokens.space20,
        ZirenTokens.space20,
        ZirenTokens.space20,
        ZirenTokens.space20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: canPick ? onTogglePicker : null,
            borderRadius: BorderRadius.circular(ZirenTokens.radius12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(ZirenTokens.space12),
                  decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                  child: Icon(icon, size: 24, color: color),
                ),
                const SizedBox(width: ZirenTokens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        station.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: ZirenTokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: ZirenTokens.space2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: ZirenTokens.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (canPick)
                  Padding(
                    padding: const EdgeInsets.only(left: ZirenTokens.space8),
                    child: Icon(
                      pickerOpen
                          ? LucideIcons.chevron_up
                          : LucideIcons.chevron_down,
                      size: 20,
                      color: ZirenTokens.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          if (pickerOpen && canPick) ...[
            const SizedBox(height: ZirenTokens.space12),
            Divider(height: 1, color: ZirenTokens.surfaceBorder),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(top: ZirenTokens.space4),
                itemCount: otherStations.length,
                itemBuilder: (context, index) {
                  final s = otherStations[index];
                  final sKm = distanceKmTo(s);
                  return InkWell(
                    onTap: () => onSelectStation(s),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: ZirenTokens.space8,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _agencyIcon(s.agencyType),
                            size: 18,
                            color: _agencyColor(s.agencyType),
                          ),
                          const SizedBox(width: ZirenTokens.space10),
                          Expanded(
                            child: Text(
                              s.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: ZirenTokens.textPrimary,
                              ),
                            ),
                          ),
                          if (sKm != null)
                            Text(
                              t.mapStationDistanceShort(
                                sKm.toStringAsFixed(1),
                              ),
                              style: TextStyle(
                                fontSize: 12,
                                color: ZirenTokens.textMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: ZirenTokens.space16),
          ZirenButton(
            label: t.mapGetDirections,
            icon: LucideIcons.map_pin,
            onPressed: onGetDirections,
          ),
          // The station's own hotline, from the same list the offline sheet
          // uses — so it is there with or without a connection.
          ListenableBuilder(
            listenable: HotlinesStore.instance,
            builder: (context, _) {
              StationHotline? entry;
              for (final h in HotlinesStore.instance.entries) {
                if (h.agencyId == station.agencyId) entry = h;
              }
              if (entry == null || entry.numbers.isEmpty) {
                return const SizedBox.shrink();
              }
              final numbers = entry.numbers;
              return Padding(
                padding: const EdgeInsets.only(top: ZirenTokens.space10),
                child: OutlinedButton.icon(
                  icon: Icon(LucideIcons.phone, size: 18, color: ZirenTokens.systemSuccess),
                  label: Text(
                    numbers.length == 1
                        ? '${t.hotlinesStationCall} · ${numbers.first.display}'
                        : t.hotlinesStationCall,
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: ZirenTokens.textPrimary,
                  ),
                  onPressed: () async {
                    if (numbers.length == 1) {
                      await callHotline(context, numbers.first);
                      return;
                    }
                    final picked = await showZirenOptionSheet<HotlineNumber>(
                      context,
                      title: station.name,
                      options: [
                        for (final n in numbers)
                          ZirenSheetOption(
                            icon: LucideIcons.phone,
                            label: n.display,
                            subtitle: n.label,
                            value: n,
                            tone: ZirenTone.success,
                          ),
                      ],
                    );
                    if (picked != null && context.mounted) {
                      await callHotline(context, picked);
                    }
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Incident detail sheet ──────────────────────────────────────

class _IncidentDetailSheet extends StatelessWidget {
  const _IncidentDetailSheet({required this.incident});
  final IncidentModel incident;

  @override
  Widget build(BuildContext context) {
    final (statusColor, statusBg, statusLabel) = _statusStyle(incident.status);
    final (severityColor, _, severityLabel) = _severityStyle(incident.severity);

    return Container(
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ZirenTokens.radius24),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
        ZirenTokens.space20,
        ZirenTokens.space12,
        ZirenTokens.space20,
        ZirenTokens.space32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: ZirenTokens.surfaceBorder,
                borderRadius: BorderRadius.circular(ZirenTokens.radius4),
              ),
            ),
          ),
          const SizedBox(height: ZirenTokens.space20),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: ZirenTokens.space10,
                  vertical: ZirenTokens.space4,
                ),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(ZirenTokens.radius32),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
              if (incident.severity != null) ...[
                const SizedBox(width: ZirenTokens.space8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ZirenTokens.space10,
                    vertical: ZirenTokens.space4,
                  ),
                  decoration: BoxDecoration(
                    color: severityColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(ZirenTokens.radius32),
                    border: Border.all(
                      color: severityColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    severityLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: severityColor,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              Text(
                _timeAgo(incident.createdAt),
                style: TextStyle(
                  fontSize: 12,
                  color: ZirenTokens.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: ZirenTokens.space16),
          Text(
            incident.reportText,
            style: TextStyle(
              fontSize: 14,
              color: ZirenTokens.textPrimary,
              height: 1.5,
            ),
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
          ),
          if (incident.locationAddress != null) ...[
            const SizedBox(height: ZirenTokens.space12),
            Row(
              children: [
                Icon(
                  LucideIcons.map_pin,
                  size: 14,
                  color: ZirenTokens.textMuted,
                ),
                const SizedBox(width: ZirenTokens.space4),
                Expanded(
                  child: Text(
                    incident.locationAddress!,
                    style: TextStyle(
                      fontSize: 12,
                      color: ZirenTokens.textMuted,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  (Color, Color, String) _statusStyle(String status) => switch (status) {
    'received' => (
      ZirenTokens.statusReceived,
      ZirenTokens.statusReceivedBg,
      'Received',
    ),
    'processing' => (
      ZirenTokens.statusProcessing,
      ZirenTokens.statusProcessingBg,
      'Processing',
    ),
    'dispatched' => (
      ZirenTokens.statusDispatched,
      ZirenTokens.statusDispatchedBg,
      'Dispatched',
    ),
    'resolved' => (
      ZirenTokens.statusResolved,
      ZirenTokens.statusResolvedBg,
      'Resolved',
    ),
    'cancelled' => (
      ZirenTokens.statusCancelled,
      ZirenTokens.statusCancelledBg,
      'Cancelled',
    ),
    _ => (ZirenTokens.textMuted, ZirenTokens.surfaceRaised, status),
  };

  (Color, Color, String) _severityStyle(String? severity) => switch (severity) {
    'critical' => (
      ZirenTokens.severityCritical,
      ZirenTokens.severityCriticalBg,
      'Critical',
    ),
    'high' => (ZirenTokens.severityHigh, ZirenTokens.severityHighBg, 'High'),
    'medium' => (
      ZirenTokens.severityMedium,
      ZirenTokens.severityMediumBg,
      'Medium',
    ),
    'low' => (ZirenTokens.severityLow, ZirenTokens.severityLowBg, 'Low'),
    _ => (
      ZirenTokens.textMuted,
      ZirenTokens.surfaceRaised,
      severity ?? 'Unknown',
    ),
  };

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ── Loading overlay ────────────────────────────────────────────

class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: ZirenTokens.space12,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: ZirenTokens.space16,
            vertical: ZirenTokens.space10,
          ),
          decoration: BoxDecoration(
            color: ZirenTokens.surfaceCard,
            borderRadius: BorderRadius.circular(ZirenTokens.radius32),
            boxShadow: ZirenTokens.shadowMd,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(ZirenTokens.brandOrange),
                ),
              ),
              const SizedBox(width: ZirenTokens.space10),
              Text(
                AppLocalizations.of(context).mapLoading,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: ZirenTokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Error banner ───────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: ZirenTokens.space12,
      left: ZirenTokens.space16,
      right: ZirenTokens.space16,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: ZirenTokens.space16,
          vertical: ZirenTokens.space10,
        ),
        decoration: BoxDecoration(
          color: ZirenTokens.systemErrorBg,
          borderRadius: BorderRadius.circular(ZirenTokens.radius8),
          border: Border.all(
            color: ZirenTokens.systemError.withValues(alpha: 0.30),
          ),
        ),
        child: Row(
          children: [
            Icon(
              LucideIcons.wifi_off,
              size: 16,
              color: ZirenTokens.systemError,
            ),
            const SizedBox(width: ZirenTokens.space8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 12,
                  color: ZirenTokens.systemError,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
