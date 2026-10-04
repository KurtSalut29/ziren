import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/geo/geodesic.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/map/offline_map_service.dart';
import '../../../shared/map/road_route.dart';
import '../../../shared/theme/app_tokens.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Getting to the scene, on Ziren's own map.
///
/// WHY THIS REPLACED THE GOOGLE MAPS HAND-OFF
///
/// The Navigate button used to fire a `geo:` intent and leave the app. Three
/// things were wrong with that, in increasing order of seriousness:
///
///   1. Ziren already has a map. Sending a crew out of the product to look at
///      the same island in someone else's app makes the map tab decorative.
///   2. The moment they leave, Ziren stops being the thing on screen — so the
///      status buttons, the hazards, the reporter's number and the ACCEPT
///      countdown are all one app-switch away at the moment they matter most.
///   3. Nothing came back. The responder's position kept pinging, but the crew
///      had no reading of distance or ETA unless they returned to the app.
///
/// WHAT THIS IS, HONESTLY
///
/// A route along the roads, not turn-by-turn. The road path comes from the
/// same OSRM server the resident map's "Get directions" uses ([RoadRoute]),
/// fetched once and trimmed as the crew drives, and fetched again only when
/// they leave it. When OSRM cannot be reached the screen falls back to the
/// straight line it used to draw, dashed and labelled as a direction rather
/// than a road, so the crew is never shown a confident line that is not one.
///
/// It used to draw ONLY that straight line, with its two ends as annotation
/// symbols (`addSymbol`). MapLibre rejected that annotation layer ("invalid
/// value for text-font and will not render text"), and a tester saw a straight
/// line with no pin at either end (2026-09-30). Both ends are now drawn as
/// GeoJSON circle layers, the way the rest of the app's maps draw points.
///
/// For an unfamiliar address a crew may still want real driving directions,
/// so the hand-off remains — as a secondary button, clearly labelled, rather
/// than as the only thing the primary button could do.
class IncidentNavigationScreen extends StatefulWidget {
  const IncidentNavigationScreen({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.title,
    this.address,
  });

  final double latitude;
  final double longitude;
  final String title;
  final String? address;

  @override
  State<IncidentNavigationScreen> createState() =>
      _IncidentNavigationScreenState();
}

// Sources and layers, named because they are updated in place on every fix
// rather than torn down and re-added: a stream that fires every ten metres
// would otherwise leave a trail of stale marks down the road behind the truck.
const _kRouteSource = 'nav-route-src';
const _kRouteCasing = 'nav-route-casing';
const _kRouteLine = 'nav-route';
const _kSceneSource = 'nav-scene-src';
const _kSceneHalo = 'nav-scene-halo';
const _kScenePoint = 'nav-scene-point';
const _kSceneLabel = 'nav-scene-label';
const _kMeSource = 'nav-me-src';
const _kMeHalo = 'nav-me-halo';
const _kMePoint = 'nav-me-point';
const _kMeLabel = 'nav-me-label';

const _kSceneHex = '#DC2626';
const _kMeHex = '#1E88E5';
const _kRouteHex = '#FC5A05';

/// The bundled glyphs (assets/map/fonts). A text layer asking for a font the
/// style does not serve renders no text at all.
const List<dynamic> _kLabelFont = [
  Expressions.literal,
  ['Noto Sans Medium'],
];

const _kEmpty = {'type': 'FeatureCollection', 'features': <dynamic>[]};

/// How far off the fetched road the crew can be before it is fetched again.
/// GPS on a phone in a moving vehicle wanders by a few tens of metres; a
/// turn onto another road puts it well past this.
const double kNavOffRouteMetres = 90;

/// Never ask OSRM more often than this. It is a shared community server.
const Duration kNavRefetchGap = Duration(seconds: 20);

/// Whether to ask OSRM for a road path now.
///
/// Pure so a test can pin it: fetch when there is no road yet, or when the
/// crew has left the one they have, but never more often than
/// [kNavRefetchGap], so a server that is down is not hammered once per fix.
@visibleForTesting
bool navNeedsRoute({
  required bool haveRoad,
  required double? offRouteMetres,
  required DateTime? lastAttempt,
  required DateTime now,
}) {
  if (lastAttempt != null && now.difference(lastAttempt) < kNavRefetchGap) {
    return false;
  }
  if (!haveRoad) return true;
  return (offRouteMetres ?? 0) > kNavOffRouteMetres;
}

class _IncidentNavigationScreenState extends State<IncidentNavigationScreen> {
  MapLibreMapController? _ctrl;
  StreamSubscription<Position>? _positionSub;

  Position? _me;
  bool _styleReady = false;

  /// The road path, when OSRM gave one. Null means the straight line.
  RoadRoute? _road;
  bool _fetchingRoad = false;
  DateTime? _lastRoadAttempt;

  /// Whether the line currently drawn is dashed (the straight fallback).
  bool? _drawnDashed;

  /// Keep the camera on the pair. Turned off the moment the crew pans, so the
  /// map stops fighting the hand that is trying to look ahead down the road.
  bool _following = true;

  /// Null until [OfflineMapService.resolveStyle] settles — see [build].
  String? _resolvedStyle;

  bool get _styleHasGlyphs => _resolvedStyle?.contains('"glyphs"') ?? false;

  @override
  void initState() {
    super.initState();
    _startTracking();
    OfflineMapService.instance.resolveStyle().then((style) {
      if (mounted) setState(() => _resolvedStyle = style);
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }

  Future<void> _startTracking() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    // The last fix the phone already has, so the crew's own pin appears
    // straight away instead of after the first ten metres of driving.
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && mounted && _me == null) _onPosition(last);
    } catch (_) {
      // Not every platform keeps one. The stream below still delivers.
    }

    // A tighter filter than the background ping. This screen is being looked
    // at while moving, so it updates on every ten metres rather than on a
    // timer — a position that lags the truck by a minute is worse than none.
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((pos) {
      if (mounted) _onPosition(pos);
    });
  }

  void _onPosition(Position pos) {
    setState(() => _me = pos);
    _maybeFetchRoad();
    _redraw();
  }

  LatLng get _target => LatLng(widget.latitude, widget.longitude);

  /// What is left of the road path from where the crew is now.
  RemainingRoute? get _remaining {
    final me = _me;
    final road = _road;
    if (me == null || road == null) return null;
    return road.remainingFrom(me.latitude, me.longitude);
  }

  double? get _straightMetres {
    final me = _me;
    if (me == null) return null;
    return RoadRoute.metresBetween(
      me.latitude,
      me.longitude,
      widget.latitude,
      widget.longitude,
    );
  }

  /// Along the road when there is one, else in a straight line.
  double? get _distanceMetres {
    final remaining = _remaining;
    if (remaining == null) return _straightMetres;
    final end = remaining.coordinates.last;
    // The road stops at the nearest road to the scene; the last stretch
    // from there to the scene itself is added on foot, in a straight line.
    return remaining.metres +
        RoadRoute.metresBetween(end[1], end[0], widget.latitude, widget.longitude);
  }

  /// Minutes at the assumed provincial road speed ([Geodesic.assumedSpeedKmh],
  /// the same the backend uses for the resident's ETA). Rounded up.
  int? get _etaMinutes {
    final metres = _distanceMetres;
    if (metres == null) return null;
    // The shared model (rounded up, never 0, capped at 600), not a local copy:
    // this screen used ceil() from 0, so it quoted 12 min for a 6 km trip the
    // backend and dashboard call 13, and "0 min" at the gate (finding #24).
    return Geodesic.etaMinutes(metres / 1000);
  }

  /// Bearing from the crew to the scene, in compass degrees.
  double? get _bearing {
    final me = _me;
    if (me == null) return null;
    return Geolocator.bearingBetween(
      me.latitude,
      me.longitude,
      widget.latitude,
      widget.longitude,
    );
  }

  Future<void> _maybeFetchRoad() async {
    final me = _me;
    if (me == null || _fetchingRoad) return;
    final now = DateTime.now();
    if (!navNeedsRoute(
      haveRoad: _road != null,
      offRouteMetres: _remaining?.offRouteMetres,
      lastAttempt: _lastRoadAttempt,
      now: now,
    )) {
      return;
    }
    _fetchingRoad = true;
    _lastRoadAttempt = now;
    final road = await RoadRoute.fetch(
      me.latitude,
      me.longitude,
      widget.latitude,
      widget.longitude,
    );
    _fetchingRoad = false;
    if (!mounted || road == null) return;
    setState(() => _road = road);
    await _redraw();
  }

  Future<void> _onStyleLoaded() async {
    final ctrl = _ctrl;
    if (ctrl == null) return;
    // Labels are feature data, not layer text, so they follow the language.
    _meLabel = AppLocalizations.of(context).mapYouLabel;
    try {
      await ctrl.addSource(
        _kRouteSource,
        const GeojsonSourceProperties(data: _kEmpty),
      );
      // A white casing under the orange, so the route reads on satellite
      // imagery as well as on the plain street map.
      await ctrl.addLayer(
        _kRouteSource,
        _kRouteCasing,
        const LineLayerProperties(
          lineColor: '#FFFFFF',
          lineWidth: 8,
          lineOpacity: 0.9,
          lineJoin: 'round',
          lineCap: 'round',
        ),
      );
      await ctrl.addLayer(
        _kRouteSource,
        _kRouteLine,
        const LineLayerProperties(
          lineColor: _kRouteHex,
          lineWidth: 5,
          lineJoin: 'round',
          lineCap: 'round',
        ),
      );

      await ctrl.addSource(
        _kSceneSource,
        GeojsonSourceProperties(data: _point(_target, widget.title)),
      );
      await ctrl.addLayer(
        _kSceneSource,
        _kSceneHalo,
        const CircleLayerProperties(
          circleRadius: 24,
          circleColor: _kSceneHex,
          circleOpacity: 0.18,
          circleStrokeWidth: 1.5,
          circleStrokeColor: _kSceneHex,
          circleStrokeOpacity: 0.55,
        ),
      );
      await ctrl.addLayer(
        _kSceneSource,
        _kScenePoint,
        const CircleLayerProperties(
          circleRadius: 10,
          circleColor: _kSceneHex,
          circleStrokeWidth: 3,
          circleStrokeColor: '#FFFFFF',
        ),
      );

      await ctrl.addSource(
        _kMeSource,
        const GeojsonSourceProperties(data: _kEmpty),
      );
      await ctrl.addLayer(
        _kMeSource,
        _kMeHalo,
        const CircleLayerProperties(
          circleRadius: 18,
          circleColor: _kMeHex,
          circleOpacity: 0.2,
        ),
      );
      await ctrl.addLayer(
        _kMeSource,
        _kMePoint,
        const CircleLayerProperties(
          circleRadius: 8,
          circleColor: _kMeHex,
          circleStrokeWidth: 3,
          circleStrokeColor: '#FFFFFF',
        ),
      );

      if (_styleHasGlyphs) {
        await ctrl.addLayer(
          _kSceneSource,
          _kSceneLabel,
          _labelLayer(_kSceneHex, offset: 1.7),
        );
        await ctrl.addLayer(
          _kMeSource,
          _kMeLabel,
          _labelLayer(_kMeHex, offset: 1.4),
        );
      }
    } catch (e) {
      // The map was closed while this ran, or the style changed under it.
      debugPrint('[nav] map layers not added: $e');
      return;
    }

    if (!mounted) return;
    _styleReady = true;
    await _redraw();
    // Nothing to fit yet: frame the scene so it is on screen while the
    // crew's own position is still being found.
    if (_me == null && _following) {
      await ctrl.animateCamera(CameraUpdate.newLatLngZoom(_target, 15));
    }
  }

  String _meLabel = '';

  static Map<String, dynamic> _point(LatLng at, String label) => {
    'type': 'FeatureCollection',
    'features': [
      {
        'type': 'Feature',
        'properties': {'label': label},
        'geometry': {
          'type': 'Point',
          'coordinates': [at.longitude, at.latitude],
        },
      },
    ],
  };

  static SymbolLayerProperties _labelLayer(String hex, {required double offset}) =>
      SymbolLayerProperties(
        textField: [Expressions.get, 'label'],
        textFont: _kLabelFont,
        textSize: 12,
        textColor: '#FFFFFF',
        textHaloColor: hex,
        textHaloWidth: 2.2,
        textAnchor: 'top',
        textOffset: [
          Expressions.literal,
          [0, offset],
        ],
        textAllowOverlap: true,
        textIgnorePlacement: true,
      );

  /// The line from the crew to the scene: along the road when there is one,
  /// straight otherwise.
  List<List<double>> _lineCoordinates(Position me) {
    final here = [me.longitude, me.latitude];
    final scene = [widget.longitude, widget.latitude];
    final remaining = _remaining;
    if (remaining == null) return [here, scene];
    // OSRM starts and ends on the nearest ROAD, not on the points it was
    // given, so the real ends are joined back on: the line always starts at
    // the crew and ends exactly on the scene.
    return [here, ...remaining.coordinates, scene];
  }

  /// Redraw the crew's dot and the line between them and the scene.
  Future<void> _redraw() async {
    final ctrl = _ctrl;
    final me = _me;
    if (ctrl == null || me == null || !_styleReady) return;

    final coords = _lineCoordinates(me);
    final dashed = _road == null;
    try {
      await ctrl.setGeoJsonSource(
        _kMeSource,
        _point(LatLng(me.latitude, me.longitude), _meLabel),
      );
      // Dashed only for the straight fallback: a solid line down a map reads
      // as a road somebody verified, and a straight line is a direction, not
      // a road. The crew must not follow it into a river.
      if (_drawnDashed != dashed) {
        await ctrl.setLayerProperties(
          _kRouteLine,
          LineLayerProperties(
            lineColor: _kRouteHex,
            lineWidth: 5,
            lineJoin: 'round',
            lineCap: dashed ? 'butt' : 'round',
            lineDasharray:
                dashed
                    ? const [
                      Expressions.literal,
                      [2, 1.5],
                    ]
                    : null,
          ),
        );
        _drawnDashed = dashed;
      }
      await ctrl.setGeoJsonSource(_kRouteSource, {
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'properties': const <String, dynamic>{},
            'geometry': {'type': 'LineString', 'coordinates': coords},
          },
        ],
      });
      if (_following) await _fit(coords);
    } catch (e) {
      debugPrint('[nav] redraw skipped: $e');
    }
  }

  /// Fit the whole path, not just its two ends: a road that bends away from
  /// the straight line would otherwise run off the edge of the screen.
  Future<void> _fit(List<List<double>> coords) async {
    final ctrl = _ctrl;
    if (ctrl == null) return;
    var south = double.infinity, north = -double.infinity;
    var west = double.infinity, east = -double.infinity;
    for (final c in coords) {
      west = math.min(west, c[0]);
      east = math.max(east, c[0]);
      south = math.min(south, c[1]);
      north = math.max(north, c[1]);
    }
    await ctrl.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(south, west),
          northeast: LatLng(north, east),
        ),
        left: 60,
        right: 60,
        top: 90,
        // Clear of the guidance panel over the bottom of the map.
        bottom: 300,
      ),
    );
  }

  /// The escape hatch to a real routing app.
  ///
  /// Kept because this screen deliberately does not claim to know the roads.
  /// Secondary, and labelled as what it is, so leaving Ziren is a choice the
  /// crew makes rather than the only thing the button could do.
  Future<void> _openExternal() async {
    final uris = [
      Uri.parse(
        'google.navigation:q=${widget.latitude},${widget.longitude}&mode=d',
      ),
      Uri.parse(
        'geo:${widget.latitude},${widget.longitude}'
        '?q=${widget.latitude},${widget.longitude}(Insidente)',
      ),
      Uri.parse(
        'https://www.google.com/maps/dir/?api=1'
        '&destination=${widget.latitude},${widget.longitude}',
      ),
    ];
    for (final uri in uris) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
      } catch (_) {
        // Try the next. canLaunchUrl is not used as a gate — on Android 11+
        // it returns false for any intent the manifest's <queries> block does
        // not declare, which turns a working maps app into a dead button.
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).respNavNoMapsApp),
        backgroundColor: ZirenTokens.systemError,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      appBar: AppBar(title: Text(AppLocalizations.of(context).respNavTitle)),
      body: Stack(
        children: [
          if (_resolvedStyle == null)
            const Center(child: CircularProgressIndicator())
          else
            Listener(
              // Any touch on the map means the crew wants to look somewhere
              // themselves. Auto-follow yanking the camera back is the fastest
              // way to make a map feel broken.
              onPointerDown: (_) {
                if (_following) setState(() => _following = false);
              },
              child: MapLibreMap(
                styleString: _resolvedStyle!,
                initialCameraPosition: CameraPosition(
                  target: _target,
                  zoom: 14,
                ),
                myLocationEnabled: false,
                onMapCreated: (c) => _ctrl = c,
                onStyleLoadedCallback: _onStyleLoaded,
              ),
            ),

          if (!_following)
            Positioned(
              right: ZirenTokens.space16,
              top: ZirenTokens.space16,
              child: FloatingActionButton.small(
                heroTag: 'recenter',
                backgroundColor: ZirenTokens.surfaceCard,
                foregroundColor: ZirenTokens.brandOrange,
                onPressed: () {
                  setState(() => _following = true);
                  _redraw();
                },
                child: const Icon(LucideIcons.locate_fixed),
              ),
            ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: NavGuidancePanel(
              address: widget.address,
              distanceMetres: _distanceMetres,
              etaMinutes: _etaMinutes,
              bearing: _bearing,
              byRoad: _road != null,
              onOpenExternal: _openExternal,
            ),
          ),
        ],
      ),
    );
  }
}

// ── The panel over the map ────────────────────────────────────

/// Public only so a test can draw it: the map above it is a native view a
/// widget test cannot build.
@visibleForTesting
class NavGuidancePanel extends StatelessWidget {
  const NavGuidancePanel({
    super.key,
    required this.address,
    required this.distanceMetres,
    required this.etaMinutes,
    required this.bearing,
    required this.byRoad,
    required this.onOpenExternal,
  });

  final String? address;
  final double? distanceMetres;
  final int? etaMinutes;
  final double? bearing;

  /// Whether [distanceMetres] was measured along a road path or is the
  /// straight-line fallback. The two are labelled differently on purpose.
  final bool byRoad;
  final VoidCallback onOpenExternal;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final waiting = distanceMetres == null;
    final how = byRoad ? t.respNavByRoad : t.respNavStraightDistance;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        ZirenTokens.space16,
        ZirenTokens.space16,
        ZirenTokens.space16,
        ZirenTokens.space24,
      ),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ZirenTokens.radius24),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 18,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (waiting)
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: ZirenTokens.space12),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context).respNavLocating,
                    style: TextStyle(
                      fontSize: 13,
                      color: ZirenTokens.textSecondary,
                    ),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                // The arrow points at the scene, rotated by the true bearing.
                // A crew glancing down while driving reads a direction faster
                // than they read a number.
                Transform.rotate(
                  angle: (bearing ?? 0) * math.pi / 180,
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: ZirenTokens.brandSubtle,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: ZirenTokens.brandOrange.withValues(alpha: 0.4),
                      ),
                    ),
                    child: const Icon(
                      LucideIcons.navigation,
                      color: ZirenTokens.brandOrange,
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(width: ZirenTokens.space16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _distanceLabel(distanceMetres!),
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                          color: ZirenTokens.textPrimary,
                        ),
                      ),
                      Text(
                        etaMinutes == null
                            ? how
                            : '${t.respEtaMinutes(etaMinutes!)} · $how',
                        style: TextStyle(
                          fontSize: 12,
                          color: ZirenTokens.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

          if (address != null && address!.trim().isNotEmpty) ...[
            const SizedBox(height: ZirenTokens.space12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  LucideIcons.map_pin,
                  size: 15,
                  color: ZirenTokens.textMuted,
                ),
                const SizedBox(width: ZirenTokens.space6),
                Expanded(
                  child: Text(
                    address!,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: ZirenTokens.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: ZirenTokens.space12),

          // Said plainly, because a line on a map is a promise. The straight
          // fallback is a direction, not a route, and a crew that mistakes it
          // for one can drive confidently at a river. The road route comes
          // from map data that knows nothing about today's floods.
          Container(
            padding: const EdgeInsets.all(ZirenTokens.space8),
            decoration: BoxDecoration(
              color: ZirenTokens.systemWarningBg,
              borderRadius: BorderRadius.circular(ZirenTokens.radius8),
            ),
            child: Row(
              children: [
                const Icon(
                  LucideIcons.info,
                  size: 14,
                  color: ZirenTokens.systemWarning,
                ),
                const SizedBox(width: ZirenTokens.space6),
                Expanded(
                  child: Text(
                    byRoad ? t.respNavRoadNote : t.respNavStraightLine,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.3,
                      color: ZirenTokens.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: ZirenTokens.space12),

          OutlinedButton.icon(
            onPressed: onOpenExternal,
            icon: const Icon(LucideIcons.route, size: 18),
            label: Text(AppLocalizations.of(context).respNavExternal),
            style: OutlinedButton.styleFrom(
              foregroundColor: ZirenTokens.textSecondary,
              side: BorderSide(color: ZirenTokens.surfaceBorder),
              minimumSize: const Size.fromHeight(46),
            ),
          ),
        ],
      ),
    );
  }

  static String _distanceLabel(double metres) {
    if (metres < 1000) return '${metres.round()} m';
    return '${(metres / 1000).toStringAsFixed(1)} km';
  }
}
