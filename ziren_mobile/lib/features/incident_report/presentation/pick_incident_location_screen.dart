
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/map/offline_map_service.dart';
import '../../../shared/map/ziren_map_style.dart';
import '../../../shared/theme/app_tokens.dart';
import '../domain/biliran_places.dart';
import '../domain/incident_provider.dart';
import '../domain/landmark_index.dart';
import '../domain/place_naming.dart';

/// "The incident is somewhere else": the resident moves the map until the pin
/// in the middle sits on the incident, or searches a barangay or landmark by
/// name. Pops with the chosen [LatLng]; pops with nothing on back.
///
/// Works offline: the map, the place names and the search all come from data
/// bundled in the app.
class PickIncidentLocationScreen extends StatefulWidget {
  const PickIncidentLocationScreen({super.key});

  @override
  State<PickIncidentLocationScreen> createState() => _PickIncidentLocationScreenState();
}

class _PickIncidentLocationScreenState extends State<PickIncidentLocationScreen> {
  MapLibreMapController? _map;
  String? _style;
  LandmarkIndex? _index;
  late LatLng _center;
  late double _startZoom;

  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  List<MapPlace> _results = const [];

  @override
  void initState() {
    super.initState();
    final p = context.read<IncidentProvider>();
    final lat = p.incidentLat;
    final lng = p.incidentLng;
    _center = lat != null && lng != null ? LatLng(lat, lng) : const LatLng(kBiliranLat, kBiliranLng);
    _startZoom = lat != null ? 16 : 11.5;
    OfflineMapService.instance.resolveStyle().then((s) {
      if (mounted) setState(() => _style = s);
    });
    LandmarkIndex.load().then((i) {
      if (mounted) setState(() => _index = i);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onCameraIdle() {
    final c = _map?.cameraPosition?.target;
    if (c != null && mounted) setState(() => _center = c);
  }

  void _onSearch(String q) {
    final index = _index;
    setState(() => _results = index == null ? const [] : index.search(q));
  }

  Future<void> _goTo(MapPlace place) async {
    _searchFocus.unfocus();
    setState(() {
      _results = const [];
      _search.text = place.name;
      _center = LatLng(place.lat, place.lng);
    });
    await _map?.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(place.lat, place.lng), place.isLandmark ? 17 : 15.5),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final nearest = BiliranPlaces.nearest(_center.latitude, _center.longitude);
    final address = PlaceNaming.compose(osm: const ResolvedPlace(), nearest: nearest);
    final landmark = _index?.nearestLandmark(_center.latitude, _center.longitude);

    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      appBar: AppBar(title: Text(t.locPickTitle)),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                if (_style == null)
                  const Center(child: CircularProgressIndicator())
                else
                  MapLibreMap(
                    styleString: _style!,
                    initialCameraPosition: CameraPosition(target: _center, zoom: _startZoom),
                    onMapCreated: (c) => _map = c,
                    onCameraIdle: _onCameraIdle,
                    trackCameraPosition: true,
                    compassEnabled: false,
                    rotateGesturesEnabled: false,
                    tiltGesturesEnabled: false,
                  ),
                // The pin never moves; the map moves under it. Its tip is the
                // centre of the map, so it is lifted by half its height.
                IgnorePointer(
                  child: Center(
                    child: Transform.translate(
                      offset: const Offset(0, -22),
                      child: Icon(
                        Icons.location_on,
                        size: 48,
                        color: ZirenTokens.brandOrange,
                        shadows: const [Shadow(blurRadius: 6, color: Colors.black38)],
                      ),
                    ),
                  ),
                ),
                // Search — barangays, sitios and landmarks.
                Positioned(
                  left: ZirenTokens.space12,
                  right: ZirenTokens.space12,
                  top: ZirenTokens.space12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Material(
                        elevation: 3,
                        borderRadius: BorderRadius.circular(ZirenTokens.radius12),
                        color: ZirenTokens.surfaceCard,
                        child: TextField(
                          controller: _search,
                          focusNode: _searchFocus,
                          onChanged: _onSearch,
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: t.locSearchHint,
                            prefixIcon: const Icon(LucideIcons.search, size: 20),
                            suffixIcon: _search.text.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: t.locSearchClear,
                                    icon: const Icon(LucideIcons.x, size: 18),
                                    onPressed: () {
                                      _search.clear();
                                      _onSearch('');
                                    },
                                  ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                          ),
                        ),
                      ),
                      if (_results.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Material(
                          elevation: 3,
                          borderRadius: BorderRadius.circular(ZirenTokens.radius12),
                          color: ZirenTokens.surfaceCard,
                          clipBehavior: Clip.antiAlias,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 300),
                            child: ListView(
                              shrinkWrap: true,
                              padding: EdgeInsets.zero,
                              children: [
                                for (final r in _results)
                                  ListTile(
                                    dense: true,
                                    leading: Icon(
                                      r.isLandmark ? LucideIcons.landmark : LucideIcons.map_pin,
                                      size: 18,
                                    ),
                                    title: Text(r.name),
                                    subtitle: Text(r.isLandmark ? t.locKindLandmark : t.locKindPlace),
                                    onTap: () => _goTo(r),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Where the pin is, and the button that commits it.
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(
                ZirenTokens.space16,
                ZirenTokens.space12,
                ZirenTokens.space16,
                ZirenTokens.space12,
              ),
              decoration: BoxDecoration(
                color: ZirenTokens.surfaceCard,
                border: Border(top: BorderSide(color: ZirenTokens.surfaceBorder)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t.locPickHint,
                    style: TextStyle(fontSize: 12.5, color: ZirenTokens.textSecondary),
                  ),
                  const SizedBox(height: ZirenTokens.space8),
                  Row(
                    children: [
                      Icon(LucideIcons.map_pin, size: 18, color: ZirenTokens.brandOrange),
                      const SizedBox(width: ZirenTokens.space8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              address,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: ZirenTokens.textPrimary,
                              ),
                            ),
                            if (landmark != null)
                              Text(
                                t.locNearLandmark(landmark.name),
                                style: TextStyle(fontSize: 12.5, color: ZirenTokens.textSecondary),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: ZirenTokens.space12),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      icon: const Icon(LucideIcons.check, size: 18),
                      label: Text(t.locPickConfirm),
                      onPressed: () => context.pop(_center),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
