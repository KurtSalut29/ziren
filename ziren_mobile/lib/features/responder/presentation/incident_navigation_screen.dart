import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/map/offline_map_service.dart';
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
/// It is a BEARING-AND-DISTANCE guidance screen, not turn-by-turn. There is no
/// routing engine in this deployment — no OSRM, no Valhalla, no road graph for
/// Biliran's barangay roads worth paying for — and pretending otherwise would
/// mean drawing a confident line down a road that may not exist. So it shows
/// what it can actually know: where the scene is, where you are, how far apart
/// those are, which way to head, and whether you are getting closer.
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

class _IncidentNavigationScreenState extends State<IncidentNavigationScreen> {
  MapLibreMapController? _ctrl;
  StreamSubscription<Position>? _positionSub;

  Position? _me;
  Line? _routeLine;
  Symbol? _meSymbol;
  bool _styleReady = false;

  /// Keep the camera on the pair. Turned off the moment the crew pans, so the
  /// map stops fighting the hand that is trying to look ahead down the road.
  bool _following = true;

  /// Null until [OfflineMapService.resolveStyle] settles — see [build].
  String? _resolvedStyle;

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

    // A tighter filter than the background ping. This screen is being looked
    // at while moving, so it updates on every ten metres rather than on a
    // timer — a position that lags the truck by a minute is worse than none.
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((pos) {
      if (!mounted) return;
      setState(() => _me = pos);
      _redraw();
    });
  }

  LatLng get _target => LatLng(widget.latitude, widget.longitude);

  double? get _distanceMetres {
    final me = _me;
    if (me == null) return null;
    return Geolocator.distanceBetween(
      me.latitude,
      me.longitude,
      widget.latitude,
      widget.longitude,
    );
  }

  /// Minutes at an assumed provincial road speed.
  ///
  /// The same 30 km/h the backend uses for the resident's ETA, applied to the
  /// same straight-line distance, so the number the crew reads and the number
  /// the family is told cannot disagree. Both round up.
  int? get _etaMinutes {
    final metres = _distanceMetres;
    if (metres == null) return null;
    return ((metres / 1000) / 30.0 * 60).ceil().clamp(0, 600);
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

  Future<void> _onStyleLoaded() async {
    final ctrl = _ctrl;
    if (ctrl == null) return;

    await ctrl.addSymbol(
      SymbolOptions(
        geometry: _target,
        iconImage: 'marker-15',
        iconColor: '#DC2626',
        iconSize: 2.4,
        textField: widget.title,
        textOffset: const Offset(0, 1.8),
        textSize: 12,
        textColor: '#1A1A1A',
        textHaloColor: '#FFFFFF',
        textHaloWidth: 1.5,
      ),
    );

    _styleReady = true;
    await _redraw();
  }

  /// Redraw the crew's dot and the line between them and the scene.
  ///
  /// Symbols and lines are UPDATED in place rather than removed and re-added.
  /// A stream that fires every ten metres would otherwise leave a trail of
  /// stale markers down the road behind the truck.
  Future<void> _redraw() async {
    final ctrl = _ctrl;
    final me = _me;
    if (ctrl == null || me == null || !_styleReady) return;

    final here = LatLng(me.latitude, me.longitude);

    if (_meSymbol == null) {
      _meSymbol = await ctrl.addSymbol(
        SymbolOptions(
          geometry: here,
          iconImage: 'circle-15',
          iconColor: '#1E88E5',
          iconSize: 1.6,
        ),
      );
    } else {
      await ctrl.updateSymbol(_meSymbol!, SymbolOptions(geometry: here));
    }

    // A straight line, and it is drawn dashed for a reason: a solid line down
    // a map reads as a route somebody verified, and this one is a direction,
    // not a road. The crew must not follow it into a river.
    final coords = [here, _target];
    if (_routeLine == null) {
      _routeLine = await ctrl.addLine(
        LineOptions(
          geometry: coords,
          lineColor: '#FC5A05',
          lineWidth: 4.0,
          lineOpacity: 0.75,
        ),
      );
    } else {
      await ctrl.updateLine(_routeLine!, LineOptions(geometry: coords));
    }

    if (_following) await _fitBoth(here);
  }

  Future<void> _fitBoth(LatLng here) async {
    final ctrl = _ctrl;
    if (ctrl == null) return;
    final sw = LatLng(
      math.min(here.latitude, _target.latitude),
      math.min(here.longitude, _target.longitude),
    );
    final ne = LatLng(
      math.max(here.latitude, _target.latitude),
      math.max(here.longitude, _target.longitude),
    );
    await ctrl.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(southwest: sw, northeast: ne),
        left: 60,
        right: 60,
        top: 90,
        bottom: 220,
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
            child: _GuidancePanel(
              address: widget.address,
              distanceMetres: _distanceMetres,
              etaMinutes: _etaMinutes,
              bearing: _bearing,
              onOpenExternal: _openExternal,
            ),
          ),
        ],
      ),
    );
  }
}

// ── The panel over the map ────────────────────────────────────

class _GuidancePanel extends StatelessWidget {
  const _GuidancePanel({
    required this.address,
    required this.distanceMetres,
    required this.etaMinutes,
    required this.bearing,
    required this.onOpenExternal,
  });

  final String? address;
  final double? distanceMetres;
  final int? etaMinutes;
  final double? bearing;
  final VoidCallback onOpenExternal;

  @override
  Widget build(BuildContext context) {
    final waiting = distanceMetres == null;

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
                            ? AppLocalizations.of(
                              context,
                            ).respNavStraightDistance
                            : '${AppLocalizations.of(context).respEtaMinutes(etaMinutes!)} · ${AppLocalizations.of(context).respNavStraightDistance}',
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

          // Said plainly, because a line on a map is a promise. This one is a
          // direction, not a route, and a crew that mistakes it for one can
          // drive confidently at a river.
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
                    AppLocalizations.of(context).respNavStraightLine,
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
