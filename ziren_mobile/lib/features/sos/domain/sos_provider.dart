import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/errors/failures.dart';
import '../../incident_report/domain/incident_provider.dart' show IncidentCategory;
import '../../incident_report/domain/landmark_index.dart';
import '../../incident_report/domain/location_naming.dart';
import '../data/sos_repository.dart';
import 'sos_result.dart';

enum SosStatus { idle, locating, submitting, success, error }

/// State manager for the SOS Quick-Report flow.
///
/// Responsibilities:
/// - Client-side cooldown enforcement (advisory — server enforces authoritatively)
/// - GPS location capture before the confirmation screen
/// - SOS submission via [SosRepository]
/// - Resolved station display on the confirmation screen
/// - Follow-up description attachment after dispatch
class SosProvider extends ChangeNotifier {
  SosProvider({
    SosRepository? repository,
    Future<LandmarkIndex> Function()? landmarks,
  }) : _repo = repository ?? SosRepository(),
       _landmarks = landmarks ?? LandmarkIndex.load;

  final SosRepository _repo;

  /// Where the nearest landmark is looked up. Injected by tests; the app
  /// reads the map data bundled in assets/map.
  final Future<LandmarkIndex> Function() _landmarks;

  // ── Status ────────────────────────────────────────────────
  SosStatus _status = SosStatus.idle;
  String? _errorMessage;
  SosResult? _lastResult;

  SosStatus get status => _status;
  String? get errorMessage => _errorMessage;
  SosResult? get lastResult => _lastResult;
  bool get isSubmitting => _status == SosStatus.submitting;
  bool get isLocating => _status == SosStatus.locating;

  // ── Location ──────────────────────────────────────────────
  Position? _position;
  bool _locationDenied = false;
  String? _locationAddress;
  bool _geocoding = false;

  Position? get position => _position;
  bool get locationDenied => _locationDenied;
  bool get hasLocation => _position != null;

  /// Test seam: [fetchLocation] reads the GPS through platform plugins that a
  /// unit test cannot run.
  @visibleForTesting
  set debugPosition(Position? position) => _position = position;

  /// A real place name — "San Roque, Larrazabal, Naval, Biliran" — not raw
  /// coordinates. Set the instant a position is known (from the on-device
  /// Biliran table alone) and refined shortly after by [LocationNaming],
  /// the same resolver IncidentProvider uses for a normal report. Null only
  /// before the first fix arrives.
  String? get locationAddress => _locationAddress;
  bool get geocoding => _geocoding;

  // ── Landmark ──────────────────────────────────────────────
  // Stations asked for a landmark on every report: GPS inside a barangay is
  // not an address a crew can drive to. SOS stays typing-free, so the
  // landmark nearest the fix is found from the map bundled in the app (no
  // network) the moment the fix arrives and shown on the confirm screen. The
  // resident can correct it there, but never has to.
  String? _detectedLandmark;
  String? _typedLandmark;
  bool _findingLandmark = false;

  /// The landmark nearest the GPS fix, from the bundled map; null when none
  /// is within [LandmarkIndex.maxLandmarkMetres].
  String? get detectedLandmark => _detectedLandmark;

  /// What the resident typed over the detected one, if anything.
  String? get typedLandmark => _typedLandmark;

  /// True while the bundled map is being searched for the fix.
  bool get findingLandmark => _findingLandmark;

  /// The note the station receives: the resident's own words when they gave
  /// some, else "Near" and the detected landmark, else nothing.
  String? get landmarkNote {
    final typed = _typedLandmark;
    if (typed != null) return typed;
    final found = _detectedLandmark;
    return found == null ? null : 'Near $found';
  }

  /// Override the detected landmark. Empty text goes back to the detected one.
  void setTypedLandmark(String? text) {
    final trimmed = text?.trim() ?? '';
    _typedLandmark = trimmed.isEmpty ? null : trimmed;
    notifyListeners();
  }

  /// Look up the landmark nearest the current fix. Runs by itself after
  /// every fix; public so a test can drive it without the GPS plugin.
  Future<void> detectLandmark() async {
    final pos = _position;
    if (pos == null) return;
    _findingLandmark = true;
    notifyListeners();
    String? found;
    try {
      final index = await _landmarks();
      found = index.nearestLandmark(pos.latitude, pos.longitude)?.name;
    } catch (_) {
      found = null;
    }
    // A newer fix may have arrived while the index loaded.
    if (_position != pos) return;
    _detectedLandmark = found;
    _findingLandmark = false;
    notifyListeners();
  }

  // ── Category (optional) ──────────────────────────────────
  // Unset by default — an SOS with no category behaves exactly as it always
  // has (nearest station of any agency). Set, it tells the server which
  // agency to prefer, so the right kind of crew is dispatched first instead
  // of whichever station happens to be closest. Never required to submit.
  IncidentCategory? _category;

  IncidentCategory? get category => _category;

  void setCategory(IncidentCategory? category) {
    _category = category;
    notifyListeners();
  }

  // ── Client-side cooldown ──────────────────────────────────
  // Mirrors the server-side 30-minute cooldown.
  // Advisory only — the server is the authoritative check.
  static const _prefsKey = 'sos_last_submitted_at';
  static const _cooldownMinutes = 30;

  DateTime? _lastSubmittedAt;

  bool get isCoolingDown {
    if (_lastSubmittedAt == null) return false;
    return DateTime.now().difference(_lastSubmittedAt!) <
        const Duration(minutes: _cooldownMinutes);
  }

  Duration get cooldownRemaining {
    if (_lastSubmittedAt == null) return Duration.zero;
    final elapsed = DateTime.now().difference(_lastSubmittedAt!);
    final remaining = const Duration(minutes: _cooldownMinutes) - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  int get cooldownMinutesLeft => cooldownRemaining.inMinutes + 1;

  // ── Init ──────────────────────────────────────────────────

  /// Call once when the SOS feature becomes active.
  Future<void> initialize() async {
    await _loadCooldownFromPrefs();
    await fetchLocation();
  }

  Future<void> _loadCooldownFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_prefsKey);
      if (stored != null) {
        _lastSubmittedAt = DateTime.tryParse(stored);
      }
    } catch (_) {
      // Non-fatal — cooldown state lost on reinstall, server enforces anyway
    }
    notifyListeners();
  }

  Future<void> _saveCooldownToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, DateTime.now().toIso8601String());
    } catch (_) {}
  }

  // ── Location ──────────────────────────────────────────────

  Future<void> fetchLocation() async {
    _status = SosStatus.locating;
    notifyListeners();

    final locationStatus = await Permission.location.request();
    if (locationStatus.isDenied || locationStatus.isPermanentlyDenied) {
      _locationDenied = true;
      _status = SosStatus.idle;
      notifyListeners();
      return;
    }

    try {
      _position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      _locationDenied = false;
    } catch (_) {
      _locationDenied = true;
    }

    _status = SosStatus.idle;
    notifyListeners();

    if (_position != null) {
      unawaited(_resolveAddress(_position!));
      unawaited(detectLandmark());
    }
  }

  /// Names the fix — instantly from the on-device table, then again once
  /// Nominatim answers (or doesn't; [LocationNaming.resolve] falls back to
  /// the same instant guess on any failure). Not awaited by [fetchLocation]:
  /// the resident should never wait on this to see their GPS status, and
  /// [SosConfirmScreen] shows a spinner beside the address in the meantime.
  Future<void> _resolveAddress(Position pos) async {
    _locationAddress = LocationNaming.guess(pos);
    _geocoding = true;
    notifyListeners();

    final resolved = await LocationNaming.resolve(pos);
    // The resident could have refreshed location again while this was in
    // flight; only apply the answer if it is still about the current fix.
    if (_position != pos) return;
    _locationAddress = resolved;
    _geocoding = false;
    notifyListeners();
  }

  // ── Submit ────────────────────────────────────────────────

  bool _failedOffline = false;

  /// The last SOS reached nobody — no connection. The screen then offers the
  /// station hotlines, since a call still works with only a signal.
  bool get failedOffline => _failedOffline;

  /// Submit the SOS report.
  /// [description] is optional — the server stores "SOS" if omitted.
  Future<bool> submit({String? description}) async {
    _status = SosStatus.submitting;
    _errorMessage = null;
    _failedOffline = false;
    notifyListeners();

    // Normally found already, while the resident read the screen. A send
    // that beat the lookup still waits for it: it is local and quick, and a
    // report without a landmark is what the stations asked us to stop.
    if (_position != null &&
        _typedLandmark == null &&
        _detectedLandmark == null) {
      await detectLandmark();
    }

    try {
      _lastResult = await _repo.submitSos(
        latitude: _position?.latitude,
        longitude: _position?.longitude,
        description: description,
        incidentCategory: _category?.value,
        locationAddress: _locationAddress,
        landmarkNote: landmarkNote,
      );

      _lastSubmittedAt = DateTime.now();
      await _saveCooldownToPrefs();

      _status = SosStatus.success;
      notifyListeners();
      return true;
    } on NetworkFailure catch (e) {
      _status = SosStatus.error;
      _errorMessage = e.message;
      _failedOffline = true;
      notifyListeners();
      return false;
    } on ServerFailure catch (e) {
      _status = SosStatus.error;
      _errorMessage = e.message;
      notifyListeners();
      return false;
    } catch (_) {
      _status = SosStatus.error;
      _errorMessage = 'SOS could not be sent. Please call 911 directly.';
      notifyListeners();
      return false;
    }
  }

  void reset() {
    _status = SosStatus.idle;
    _errorMessage = null;
    _lastResult = null;
    _category = null;
    _locationAddress = null;
    _geocoding = false;
    _detectedLandmark = null;
    _typedLandmark = null;
    _findingLandmark = false;
    notifyListeners();
  }
}
