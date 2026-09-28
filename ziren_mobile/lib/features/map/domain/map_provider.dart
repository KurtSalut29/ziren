import 'package:flutter/foundation.dart';

import '../../incident_report/data/incident_repository.dart';
import '../../incident_report/data/station_repository.dart';
import '../../incident_report/domain/incident_model.dart';
import '../../incident_report/domain/station_model.dart';
import '../../responder/data/responder_repository.dart';

/// Manages the data layer for the map screen.
///
/// Fetches stations plus ONE of two incident sets, depending on who is
/// looking:
///
///   - Resident  → their own reports, via /incidents/my
///   - Responder → the incidents ASSIGNED to them, via /responder/queue
///
/// THE SECOND CASE DID NOT EXIST, and its absence was silent. The
/// responder shell's Map tab reuses this screen, so a responder opening it
/// was shown the reports they had personally filed as a civilian — which
/// for every responder in this deployment is none. The map drew stations
/// and nothing else, and an empty incident layer looks exactly like a
/// quiet night, so there was nothing on it to tap and no way to tell that
/// from working correctly.
class MapProvider extends ChangeNotifier {
  MapProvider()
    : _incidentRepo = IncidentRepository(),
      _stationRepo = StationRepository(),
      _responderRepo = ResponderRepository();

  final IncidentRepository _incidentRepo;
  final StationRepository _stationRepo;
  final ResponderRepository _responderRepo;

  // ── State ─────────────────────────────────────────────────

  List<IncidentModel> _incidents = [];
  List<StationModel> _stations = [];

  bool _loading = false;
  String? _error;

  // ── Filter state ──────────────────────────────────────────

  /// The one agency the filter row is narrowed to, or null for all three.
  ///
  /// Exclusive rather than a per-agency toggle: tapping BFP means "show me
  /// BFP", not "hide BFP" — the three pills read as one choice (which
  /// service), not three independent switches.
  String? _onlyAgency;

  bool get loading => _loading;
  String? get error => _error;

  List<IncidentModel> get incidents => _incidents;

  List<StationModel> get visibleStations =>
      _onlyAgency == null
          ? _stations
          : _stations.where((s) => s.agencyType == _onlyAgency).toList();

  bool isAgencyVisible(String agencyType) =>
      _onlyAgency == null || _onlyAgency == agencyType;

  /// Tapping the agency already shown alone clears back to all three — the
  /// same one-tap-in, one-tap-out pattern as the My Reports filter row —
  /// otherwise it narrows to just that one.
  void toggleAgency(String agencyType) {
    _onlyAgency = _onlyAgency == agencyType ? null : agencyType;
    notifyListeners();
  }

  // ── Load ──────────────────────────────────────────────────

  /// Load the map for a RESPONDER: their assigned incidents, plus stations.
  ///
  /// The responder queue returns a different model, so each row is mapped
  /// onto IncidentModel — the shape the pins are drawn from. Only the
  /// fields the map actually uses are carried across; this is a projection
  /// for drawing, not a second source of truth about an incident.
  Future<void> loadForResponder() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _responderRepo.getMyQueue(),
        _stationRepo.fetchAllStations(),
      ]);

      final queue = results[0] as List<dynamic>;
      _incidents = [
        for (final i in queue)
          IncidentModel(
            id: i.id as String,
            reportText: i.reportText as String,
            status: i.status as String,
            submittedVia: 'internet',
            createdAt: i.createdAt as DateTime,
            severity: i.severity as String?,
            latitude: i.latitude as double?,
            longitude: i.longitude as double?,
            locationAddress: i.locationAddress as String?,
          ),
      ];
      _stations = results[1] as List<StationModel>;
    } catch (e) {
      _error = 'Could not load map data. Check your connection.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Load both datasets in parallel. Safe to call on every map entry.
  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _incidentRepo.getMyIncidents().catchError((_) => <IncidentModel>[]),
        _stationRepo.fetchAllStations(),
      ]);

      _incidents = results[0] as List<IncidentModel>;
      _stations = results[1] as List<StationModel>;
    } catch (e) {
      _error = 'Could not load map data. Check your connection.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Incidents that have GPS coordinates — these get pins on the map.
  List<IncidentModel> get plottableIncidents =>
      _incidents
          .where((i) => i.latitude != null && i.longitude != null)
          .toList();

  /// Stations that have GPS coordinates.
  List<StationModel> get plottableStations =>
      visibleStations
          .where((s) => s.latitude != null && s.longitude != null)
          .toList();

  /// Looks a station up by id regardless of the agency filter — the "which
  /// station responded to this one report" view (My Reports → View on Map)
  /// needs to find it even while the filter row is narrowed to a different
  /// agency, or would still be narrowed from whatever the resident last set
  /// on a previous visit to this same, state-preserving tab.
  StationModel? stationById(String? id) {
    if (id == null) return null;
    for (final s in _stations) {
      if (s.id == id) return s;
    }
    return null;
  }
}
