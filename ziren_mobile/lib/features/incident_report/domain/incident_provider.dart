import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/locale_provider.dart';
import '../../../core/errors/failures.dart';
import '../../../core/network/backend_health.dart';
import 'biliran_places.dart';
import 'landmark_index.dart';
import 'place_naming.dart';
import '../data/incident_repository.dart';
import '../data/media_upload_service.dart';
import '../data/station_repository.dart';
import '../data/voice_note_service.dart';
import 'incident_model.dart';
import 'speech_locale_resolver.dart';
import 'station_model.dart';

enum SubmitStatus { idle, submitting, success, error }

// ── Wizard enums (mirror backend IncidentCategory / VictimRelationship) ──

/// Step 1 of the 5W1H wizard. Must stay in sync with the backend's
/// IncidentCategory and with migration 019's CHECK constraint.
///
/// hazmat and missing_person were retired in Phase 4: the triage model has no
/// class for either, so reports filed under them could never receive a
/// model-derived severity. Both survive as [OverlapFlag] values below, so a
/// resident can still flag a chemical leak or a missing person — it just
/// cannot be the report's primary category.
enum IncidentCategory {
  fire('fire', 'Sunog / Fire'),
  medicalTrauma('medical_trauma', 'Medical / Trauma'),
  vehicular('vehicular', 'Aksidente sa Daan'),
  floodLandslideCalamity(
    'flood_landslide_calamity',
    'Baha / Landslide / Kalamidad',
  ),
  domesticDisputeCrime('domestic_dispute_crime', 'Kaguluhan / Krimen'),
  other('other', 'Iba pa');

  const IncidentCategory(this.value, this.label);
  final String value;
  final String label;

  /// The enum member for a wire value, or null if unrecognised (e.g. a
  /// report with no category — see [IncidentModel.incidentCategory]).
  static IncidentCategory? fromValue(String? value) {
    if (value == null) return null;
    for (final c in IncidentCategory.values) {
      if (c.value == value) return c;
    }
    return null;
  }
}

enum VictimRelationship {
  akoMismo('ako_mismo', 'Ako mismo ang biktima'),
  kamagAnak('kamag_anak', 'Kamag-anak ko'),
  kakilala('kakilala', 'Kakilala ko'),
  estranghero('estranghero', 'Hindi ko kilala');

  const VictimRelationship(this.value, this.label);
  final String value;
  final String label;
}

enum OverlapFlag {
  injuries('injuries', 'May nasugatan'),
  fire('fire', 'May sunog'),
  flooding('flooding', 'May baha'),
  missingPerson('missing_person', 'May nawawala'),
  hazmat('hazmat', 'May mapanganib na kemikal'),
  none('none', 'Wala nang iba');

  const OverlapFlag(this.value, this.label);
  final String value;
  final String label;
}

class IncidentProvider extends ChangeNotifier {
  IncidentProvider({
    IncidentRepository? repository,
    StationRepository? stationRepository,
  }) : _repo = repository ?? IncidentRepository(),
       _stationRepo = stationRepository ?? StationRepository();

  final IncidentRepository _repo;
  final StationRepository _stationRepo;
  final SpeechToText _speech = SpeechToText();
  final MediaUploadService _mediaService = MediaUploadService();
  final VoiceNoteService _voice = VoiceNoteService();

  MediaUploadService get mediaUploadService => _mediaService;

  // ── Station state ─────────────────────────────────────────
  List<StationModel> _stations = [];
  bool _loadingStations = false;
  String? _stationsError;
  StationModel? _selectedStation;

  List<StationModel> get stations => _stations;
  bool get loadingStations => _loadingStations;
  String? get stationsError => _stationsError;
  StationModel? get selectedStation => _selectedStation;
  bool get hasStation => _selectedStation != null;

  // ── Wizard state (5W1H — Steps 1–5) ─────────────────────
  IncidentCategory? _incidentCategory;
  Map<String, dynamic> _wizardAnswers = {};
  final Set<OverlapFlag> _overlapFlags = {};
  VictimRelationship? _victimRelationship;
  String? _landmarkNote;

  /// The free-text description typed on the quick-report screen. Held here
  /// rather than in a local controller so it survives the confirm → review
  /// hand-off — mirrors [landmarkNote]. Not part of [wizardAnswers]: it
  /// never feeds the structured severity payload, only the plain
  /// `reportText` string built at submit time.
  String? _quickNote;

  IncidentCategory? get incidentCategory => _incidentCategory;
  Map<String, dynamic> get wizardAnswers => Map.unmodifiable(_wizardAnswers);
  Set<OverlapFlag> get overlapFlags => Set.unmodifiable(_overlapFlags);
  VictimRelationship? get victimRelationship => _victimRelationship;
  String? get landmarkNote => _landmarkNote;
  String? get quickNote => _quickNote;

  void setCategory(IncidentCategory category) {
    if (_incidentCategory != category) {
      // Changing category invalidates previous answers
      _wizardAnswers = {};
      _overlapFlags.clear();
    }
    _incidentCategory = category;
    notifyListeners();
  }

  void setWizardAnswers(Map<String, dynamic> answers) {
    _wizardAnswers = Map.from(answers);
    notifyListeners();
  }

  void mergeWizardAnswer(String key, dynamic value) {
    _wizardAnswers[key] = value;
    notifyListeners();
  }

  void toggleOverlapFlag(OverlapFlag flag) {
    if (flag == OverlapFlag.none) {
      _overlapFlags
        ..clear()
        ..add(OverlapFlag.none);
    } else {
      _overlapFlags.remove(OverlapFlag.none);
      if (_overlapFlags.contains(flag)) {
        _overlapFlags.remove(flag);
      } else {
        _overlapFlags.add(flag);
      }
    }
    notifyListeners();
  }

  void setVictimRelationship(VictimRelationship rel) {
    _victimRelationship = rel;
    notifyListeners();
  }

  void setLandmarkNote(String? note) {
    _landmarkNote = note?.trim().isEmpty == true ? null : note?.trim();
    notifyListeners();
  }

  void setQuickNote(String? note) {
    _quickNote = note?.trim().isEmpty == true ? null : note?.trim();
    notifyListeners();
  }

  void clearWizard() {
    _incidentCategory = null;
    _wizardAnswers = {};
    _overlapFlags.clear();
    _victimRelationship = null;
    _landmarkNote = null;
    _quickNote = null;
    // A report placed somewhere else belongs to that one report only; the
    // next one starts from "I am at the incident" again.
    _incidentPoint = null;
    _incidentAddress = null;
    _incidentLandmark = null;
    _deviceLandmark = null;
    _landmarkForPoint = null;
    // Including the recording. Home calls this before every report, and a
    // voice note surviving into the next one would attach one emergency's
    // audio to a different emergency.
    discardVoiceNote();
    notifyListeners();
  }

  /// Assembles a human-readable report_text from wizard answers for submission.
  /// This is sent as report_text to the backend alongside the structured fields.
  String buildReportText({String? catchAll}) {
    final cat = _incidentCategory;
    if (cat == null) return catchAll?.trim() ?? '';

    final parts = <String>['[${cat.label.toUpperCase()}]'];

    // Append each wizard answer as a readable phrase
    _wizardAnswers.forEach((key, value) {
      if (value is bool && value) {
        parts.add(key);
      } else if (value is String && value.isNotEmpty) {
        parts.add(value);
      } else if (value is List) {
        parts.add(value.join(', '));
      }
    });

    if (_overlapFlags.isNotEmpty && !_overlapFlags.contains(OverlapFlag.none)) {
      final labels = _overlapFlags.map((f) => f.label).join(', ');
      parts.add('Kasama rin: $labels');
    }

    // The landmark is deliberately NOT appended here. It travels as its own
    // field and the backend reads it for a location only.
    //
    // Folded into report_text it reaches predict.extract() as ordinary report
    // wording, where building words become signals about the incident itself:
    // "Malapit sa: harap ng bahay ni Mang Juan" sets structure_involved and
    // SR005 lifts the report from MODERATE to HIGH. A house standing beside a
    // fire is not a house on fire, and nearly every landmark names a building.

    if (_victimRelationship != null) {
      parts.add('Nag-ulat: ${_victimRelationship!.label}');
    }

    if (catchAll != null && catchAll.trim().isNotEmpty) {
      parts.add(catchAll.trim());
    }

    return parts.join(' · ');
  }

  // ── Coverage mismatch (Phase 9) ──────────────────────────
  bool? _withinCoverage; // null = not yet checked
  bool _checkingCoverage = false;
  double? _distanceKm;

  bool? get withinCoverage => _withinCoverage;
  bool get checkingCoverage => _checkingCoverage;
  double? get distanceKm => _distanceKm;
  bool get hasCoverageMismatch =>
      _withinCoverage != null && _withinCoverage == false;

  void clearCoverageCheck() {
    _withinCoverage = null;
    _checkingCoverage = false;
    _distanceKm = null;
    notifyListeners();
  }

  SubmitStatus _submitStatus = SubmitStatus.idle;
  String? _submitError;
  IncidentModel? _lastSubmitted;

  /// How many photos/videos actually reached the server with the most recent
  /// submit. Not the number the resident attached: an attachment that could
  /// not be uploaded is dropped so the report can still go, and a screen that
  /// echoed the attached count back would be claiming evidence that is not
  /// there.
  int _lastSubmitMediaCount = 0;

  bool _submitFailedOffline = false;

  /// The last send failed because nothing answered — no connection.
  bool get submitFailedOffline => _submitFailedOffline;

  SubmitStatus get submitStatus => _submitStatus;
  String? get submitError => _submitError;
  IncidentModel? get lastSubmitted => _lastSubmitted;
  int get lastSubmitMediaCount => _lastSubmitMediaCount;

  // ── My reports state ─────────────────────────────────────
  List<IncidentModel> _myIncidents = [];
  bool _loadingIncidents = false;
  String? _incidentsError;

  List<IncidentModel> get myIncidents => _myIncidents;
  bool get loadingIncidents => _loadingIncidents;
  String? get incidentsError => _incidentsError;

  // ── Location state ───────────────────────────────────────
  Position? _currentPosition;
  bool _locationDenied = false;
  String? _locationAddress;
  bool _geocoding = false;
  NearestPlace? _nearestPlace;

  Position? get currentPosition => _currentPosition;
  bool get locationDenied => _locationDenied;
  String? get locationAddress => _locationAddress;
  bool get geocoding => _geocoding;

  /// Closest place in Ziren's own Biliran table. Resolved from coordinates
  /// alone, so it is available before — and without — any network call.
  NearestPlace? get nearestPlace => _nearestPlace;

  ResolvedPlace _resolved = const ResolvedPlace();

  /// A named building at the reported position, when OpenStreetMap has one.
  ///
  /// Offered to the resident as a one-tap landmark rather than written into
  /// the report unasked: OSM's idea of the nearest building is often right and
  /// sometimes the one across the street, and only the person standing there
  /// can tell. Null far more often than not — Biliran is thinly mapped, which
  /// is the whole reason the free-text field beside it matters more.
  String? get nearbyLandmark => _resolved.landmark;

  /// Reported GPS accuracy in metres, or null when there is no fix.
  ///
  /// Android will happily return a network-derived position that is kilometres
  /// out, and it looks identical to a satellite fix unless this is read. It is
  /// surfaced so nobody — resident or dispatcher — trusts a name more than the
  /// fix behind it deserves.
  double? get locationAccuracyM => _currentPosition?.accuracy;

  /// A fix good enough to act on without qualification.
  bool get locationIsPrecise =>
      _currentPosition != null && _currentPosition!.accuracy <= 100;

  // ── Where the incident is (when it is not where the phone is) ─────────
  //
  // A report used to be pinned to the phone's GPS, full stop. That is wrong
  // whenever the person reporting is not at the incident — a relative in
  // Larrazabal calls someone in Kawayan and asks them to report it — and the
  // crew would drive to Kawayan. The resident can now say "the incident is
  // somewhere else" and put it on the map. Then:
  //
  //   incidentLat/incidentLng   the point they placed — sent as the incident
  //                             location, routes the report, is where a crew
  //                             goes;
  //   currentPosition           still the phone — sent as reporter_location,
  //                             so the dispatcher sees the two differ.
  //
  // With no point placed everything behaves exactly as before.
  (double, double)? _incidentPoint;
  String? _incidentAddress;
  String? _incidentLandmark;
  String? _deviceLandmark;

  /// Which point [_deviceLandmark] was computed for, so a new GPS fix
  /// recomputes it instead of reusing a landmark from where the phone was.
  (double, double)? _landmarkForPoint;

  /// True once the resident has placed the incident somewhere other than
  /// where they are.
  bool get reportingElsewhere => _incidentPoint != null;

  double? get incidentLat => _incidentPoint?.$1 ?? _currentPosition?.latitude;
  double? get incidentLng => _incidentPoint?.$2 ?? _currentPosition?.longitude;

  /// The address of the incident: the placed point's, or the phone's.
  String? get incidentAddress => reportingElsewhere ? _incidentAddress : _locationAddress;

  /// The landmark nearest the incident, from the map data bundled in the app
  /// (no network needed), or OpenStreetMap's building at the phone's position
  /// when the bundled data has nothing within reach. Null when neither knows
  /// one — the resident then types it.
  String? get suggestedLandmark =>
      reportingElsewhere ? _incidentLandmark : (_deviceLandmark ?? nearbyLandmark);

  /// Place the incident at [lat],[lng] — somewhere other than the phone.
  Future<void> setIncidentPoint(double lat, double lng) async {
    _incidentPoint = (lat, lng);
    _incidentLandmark = null;
    // Named from Ziren's own table at once, so a lost network downgrades the
    // detail rather than removing the address.
    _incidentAddress = PlaceNaming.compose(
      osm: const ResolvedPlace(),
      nearest: BiliranPlaces.nearest(lat, lng),
    );
    notifyListeners();

    final index = await LandmarkIndex.load();
    if (_incidentPoint != (lat, lng)) return; // moved again meanwhile
    _incidentLandmark = index.nearestLandmark(lat, lng)?.name;
    notifyListeners();

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'lat': lat.toString(),
        'lon': lng.toString(),
        'format': 'json',
        'addressdetails': '1',
      });
      final response = await http
          .get(uri, headers: {'User-Agent': 'ZirenEmergencyApp/1.0'})
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200 || _incidentPoint != (lat, lng)) return;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final osm = PlaceNaming.fromOsm(data['address'] as Map<String, dynamic>?);
      _incidentAddress = PlaceNaming.compose(
        osm: osm,
        nearest: BiliranPlaces.nearest(lat, lng),
      );
      _incidentLandmark ??= osm.landmark;
      notifyListeners();
    } catch (_) {
      // Offline or slow: the local name already stands.
    }
  }

  /// Back to "I am at the incident".
  void clearIncidentPoint() {
    if (_incidentPoint == null) return;
    _incidentPoint = null;
    _incidentAddress = null;
    _incidentLandmark = null;
    notifyListeners();
  }

  /// Names the landmark nearest the phone from the bundled map data. Runs on
  /// every new fix; cheap (a few hundred distance checks).
  Future<void> _refreshDeviceLandmark() async {
    final pos = _currentPosition;
    if (pos == null) return;
    final point = (pos.latitude, pos.longitude);
    if (_landmarkForPoint == point) return;
    _landmarkForPoint = point;
    final index = await LandmarkIndex.load();
    _deviceLandmark = index.nearestLandmark(point.$1, point.$2)?.name;
    notifyListeners();
  }

  // ── Speech state ─────────────────────────────────────────
  bool _speechAvailable = false;
  bool _isListening = false;
  String _spokenText = '';

  /// What the recogniser reported about its own certainty, 0..1. Zero means
  /// the platform gave no rating — Android often does not. Kept so the UI can
  /// tell the resident when a transcript is worth a second look, instead of
  /// presenting every result with equal confidence.
  double _speechConfidence = 0;

  /// Locales the device can actually recognise. Empty until [initSpeech] runs.
  List<LocaleName> _speechLocales = const [];

  /// The locale id actually used for the last listen, for diagnostics.
  String? _activeSpeechLocale;

  /// Last error from the recogniser, in the platform's own words. Previously
  /// swallowed, which left the resident holding a dead microphone with no idea
  /// why it stopped.
  String? _speechError;

  bool get speechAvailable => _speechAvailable;
  bool get isListening => _isListening;
  String get spokenText => _spokenText;
  double get speechConfidence => _speechConfidence;
  List<LocaleName> get speechLocales => _speechLocales;
  String? get activeSpeechLocale => _activeSpeechLocale;

  // ── The language the resident SPEAKS ──────────────────────
  //
  // Evaluator finding #22 (2026-10-05): Bisaya voice-to-text came out wrong.
  // The cause was not the recogniser: no report screen ever said which
  // language was being spoken, so every report was heard by the Filipino
  // (Tagalog) recogniser, and SpeechLocaleResolver's Cebuano path for Bisaya
  // was never reached. The app's display language cannot carry it either -
  // it offers only Filipino and English - so this is its own setting, chosen
  // beside the microphone and remembered on the phone.

  static const spokenLanguages = <String>['Filipino', 'Bisaya', 'Waray', 'English'];
  static const _spokenKey = 'ziren.spoken_language';
  String _spokenLanguage = LocaleProvider.languageFilipino;
  String get spokenLanguage => _spokenLanguage;

  /// Whether this phone has a recogniser for the spoken language itself, not
  /// only a fallback. When false the words on screen deserve a second look.
  bool get spokenLanguageNative => SpeechLocaleResolver.hasNativeSupport(
    languageName: _spokenLanguage,
    available: _speechLocales,
  );

  /// The recogniser that will actually be used for [language] on this phone,
  /// as a language code ('ceb', 'fil'...), or null if the phone has none.
  String? recogniserFor(String language) {
    final codes = SpeechLocaleResolver.availableCandidates(
      languageName: language,
      available: _speechLocales,
    );
    return codes.isEmpty ? null : codes.first;
  }

  Future<void> loadSpokenLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_spokenKey);
      if (saved != null && spokenLanguages.contains(saved)) {
        _spokenLanguage = saved;
      } else {
        // First time: whatever the app is displayed in is the best guess.
        _spokenLanguage = LocaleProvider.current.languageCode == 'en'
            ? LocaleProvider.languageEnglish
            : LocaleProvider.languageFilipino;
      }
    } catch (_) {
      // Storage unavailable: keep the default; dictation still works.
    }
  }

  Future<void> setSpokenLanguage(String language) async {
    if (!spokenLanguages.contains(language) || language == _spokenLanguage) return;
    _spokenLanguage = language;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_spokenKey, language);
    } catch (_) {
      // Not remembered across launches, but used for this session.
    }
  }
  String? get speechError => _speechError;

  // ── Media attachments ────────────────────────────────────
  final List<File> _selectedMedia = [];
  bool _uploadingMedia = false;
  String? _mediaError;

  List<File> get selectedMedia => List.unmodifiable(_selectedMedia);
  bool get uploadingMedia => _uploadingMedia;
  String? get mediaError => _mediaError;
  bool get hasMedia => _selectedMedia.isNotEmpty;

  void addMedia(File file) {
    final t = LocaleProvider.strings;
    if (_selectedMedia.length >= MediaUploadService.maxFiles) {
      _mediaError = t.mediaMaxFiles;
      notifyListeners();
      return;
    }
    // Checked the moment the file is chosen (evaluator findings #20 and #21).
    // It used to be checked only by the upload, after Submit, so a resident
    // who recorded a long video learned it was too big at the worst moment.
    final bytes = _fileSize(file);
    if (bytes != null && MediaUploadService.exceedsLimit(bytes)) {
      _mediaError = t.mediaTooLarge(
        (bytes / (1024 * 1024)).toStringAsFixed(0),
        MediaUploadService.maxSizeMb.toString(),
      );
      notifyListeners();
      return;
    }
    _selectedMedia.add(file);
    _mediaError = null;
    notifyListeners();
  }

  static int? _fileSize(File file) {
    try {
      return file.lengthSync();
    } catch (_) {
      return null; // the upload will report it if it really cannot be read
    }
  }

  void removeMedia(int index) {
    if (index >= 0 && index < _selectedMedia.length) {
      _selectedMedia.removeAt(index);
      notifyListeners();
    }
  }

  void clearMedia() {
    _selectedMedia.clear();
    _mediaError = null;
    notifyListeners();
  }

  // ── Phase 9: Coverage validation ─────────────────────────

  /// Called after station selection when GPS is available.
  /// Hits GET /incidents/coverage-check on the FastAPI backend.
  /// Result is informational only — never blocks submission.
  Future<void> checkCoverage() async {
    final station = _selectedStation;
    final pos = _currentPosition;
    if (station == null || pos == null) return;

    _checkingCoverage = true;
    notifyListeners();

    try {
      final result = await _repo.checkStationCoverage(
        stationId: station.id,
        lat: pos.latitude,
        lng: pos.longitude,
      );
      _withinCoverage = result['within_coverage'] as bool? ?? true;
      _distanceKm = (result['distance_km'] as num?)?.toDouble();
    } catch (_) {
      // Fail open — coverage check failing must never block a report
      _withinCoverage = true;
    } finally {
      _checkingCoverage = false;
      notifyListeners();
    }
  }

  // ── Stations ──────────────────────────────────────────────

  Future<void> loadStations() async {
    _loadingStations = true;
    _stationsError = null;
    notifyListeners();
    try {
      _stations = await _stationRepo.fetchAllStations();
    } on NetworkFailure catch (e) {
      _stationsError = e.message;
    } catch (_) {
      _stationsError = 'Could not load stations.';
    } finally {
      _loadingStations = false;
      notifyListeners();
    }
  }

  void selectStation(StationModel station) {
    _selectedStation = station;
    notifyListeners();
  }

  /// Forget the chosen station without touching the rest of the report (unlike
  /// [clearStation], which also clears the wizard). Needed when a report goes
  /// out with no station known: the provider outlives each report, so the last
  /// report's station would otherwise be sent with this one's.
  void clearSelectedStation() {
    if (_selectedStation == null) return;
    _selectedStation = null;
    notifyListeners();
  }

  void clearStation() {
    _selectedStation = null;
    _locationAddress = null;
    _geocoding = false;
    clearCoverageCheck();
    clearWizard();
    notifyListeners();
  }

  /// Grouped view: { 'BFP': [...], 'PNP': [...], 'MDRRMO': [...] }
  Map<String, List<StationModel>> get stationsByAgencyType {
    final map = <String, List<StationModel>>{};
    for (final s in _stations) {
      map.putIfAbsent(s.agencyType, () => []).add(s);
    }
    return map;
  }

  // ── Location ─────────────────────────────────────────────

  StreamSubscription<Position>? _refineSub;

  /// Request location permission and get current position.
  /// Sets [_locationDenied] = true if permission is denied — UI shows fallback.
  ///
  /// Two passes, both capped so this can never stall someone mid-emergency:
  ///
  ///  1. One `getCurrentPosition` call, up to 10s, at the highest accuracy
  ///     tier the device offers (`LocationAccuracy.best`).
  ///  2. If that fix is still coarse (>100m — see [locationIsPrecise]), keep
  ///     listening to the position stream for up to 5 more seconds, taking
  ///     whichever update is tightest. GPS often needs a few extra seconds
  ///     past a first fix to narrow from a network-derived estimate to a
  ///     real satellite lock; this gives it that window without an
  ///     open-ended wait. Total worst case: 15s, then whatever it has.
  Future<void> fetchLocation() async {
    final status = await Permission.location.request();
    if (status.isDenied || status.isPermanentlyDenied) {
      _locationDenied = true;
      notifyListeners();
      return;
    }

    try {
      _currentPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 10),
        ),
      );
      _locationDenied = false;
    } catch (_) {
      _locationDenied = true;
      notifyListeners();
      return;
    }
    notifyListeners();
    // Auto reverse-geocode as soon as we have a position
    if (_currentPosition != null) reverseGeocode();

    if (_currentPosition != null && !locationIsPrecise) {
      await _refineLocation();
    }
  }

  /// Listens for a tighter fix than the one already held, for a bounded
  /// window — see [fetchLocation]'s doc comment for why.
  Future<void> _refineLocation() async {
    await _refineSub?.cancel();
    final completer = Completer<void>();

    _refineSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
    ).listen((pos) {
      if (_currentPosition == null || pos.accuracy < _currentPosition!.accuracy) {
        _currentPosition = pos;
        notifyListeners();
        if (locationIsPrecise && !completer.isCompleted) completer.complete();
      }
    });

    // Whichever comes first: a fix good enough to stop early for, or the
    // time budget running out.
    await Future.any([
      completer.future,
      Future.delayed(const Duration(seconds: 5)),
    ]);

    await _refineSub?.cancel();
    _refineSub = null;
    if (_currentPosition != null) reverseGeocode();
  }

  /// Names [_currentPosition] for a human to read.
  ///
  /// Two sources, in order of trust:
  ///
  ///  1. **Ziren's own Biliran table** — resolved from coordinates on the
  ///     device. It knows every barangay predict.py knows, needs no network,
  ///     and cannot be slower than the GPS fix it is naming.
  ///  2. **Nominatim**, best effort, for a landmark. A building name is worth
  ///     more to a responder than any barangay ("Talustusan Elementary
  ///     School" beats "Talustusan"), but it is a free external service with a
  ///     rate limit, and emergencies and dead networks arrive together. It is
  ///     therefore an enrichment, never the answer.
  ///
  /// The old code had this the other way round and used Nominatim alone. It
  /// reported barangay Talustusan as "Padre Sergio Eamiguel" — 1.66 km wrong —
  /// because OpenStreetMap has no place node for Talustusan and reverse
  /// geocoding returns the nearest name it does have.
  ///
  /// Safe to call repeatedly — debounced by [_geocoding].
  /// The barangay this account registered in, cached for the session.
  ///
  /// Null means either "not fetched yet" or "this account has no barangay on
  /// file"; [_homeFetched] tells the two apart so a genuinely empty answer is
  /// not re-requested on every position update.
  ({String name, String? municipality})? _homeBarangay;
  bool _homeFetched = false;

  /// Read straight from Supabase rather than through the profile endpoint.
  ///
  /// Deliberate, and the same reasoning as AuthProvider.restoreSession: this
  /// feeds the address on an emergency report, so it has to resolve when the
  /// FastAPI backend is unreachable. A resident on one bar of signal is
  /// exactly who needs the address to come out right.
  Future<void> _ensureHomeBarangay() async {
    if (_homeFetched) return;
    _homeFetched = true;
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final row =
          await client
              .from('users')
              .select('barangays(name, municipality)')
              .eq('id', uid)
              .maybeSingle();
      final b = row?['barangays'];
      if (b is Map && b['name'] is String) {
        _homeBarangay = (
          name: b['name'] as String,
          municipality: b['municipality'] as String?,
        );
      }
    } catch (_) {
      // No home barangay simply means this signal is unavailable and the
      // other two decide the name, exactly as before.
      _homeFetched = false;
    }
  }

  Future<void> reverseGeocode() async {
    final pos = _currentPosition;
    if (pos == null || _geocoding) return;

    _geocoding = true;
    unawaited(_refreshDeviceLandmark());
    await _ensureHomeBarangay();
    // Name it from the local table immediately, so a lost network downgrades
    // the detail rather than removing the address.
    _nearestPlace = BiliranPlaces.nearest(pos.latitude, pos.longitude);
    _locationAddress = _composeAddress(pos, null);
    notifyListeners();

    Map<String, dynamic>? osmAddress;
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'lat': pos.latitude.toString(),
        'lon': pos.longitude.toString(),
        'format': 'json',
        'addressdetails': '1',
      });

      final response = await http
          .get(uri, headers: {'User-Agent': 'ZirenEmergencyApp/1.0'})
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        // Kept whole. Every level matters — sitio, barangay, municipality —
        // and picking one field out of it is what produced "San Roque,
        // Biliran" for a point OpenStreetMap was willing to place inside
        // barangay Larrazabal.
        osmAddress = data['address'] as Map<String, dynamic>?;
      }
    } catch (_) {
      // Offline, rate-limited, or slow. The local name already stands.
      osmAddress = null;
    } finally {
      _locationAddress = _composeAddress(pos, osmAddress);
      _geocoding = false;
      notifyListeners();
    }
  }

  /// Builds the address string stored on the incident and shown to the
  /// dispatcher.
  ///
  /// The composition itself lives in PlaceNaming, where it is pure and
  /// testable; this only supplies the two inputs — what OpenStreetMap said,
  /// and what Ziren's own table says — and the accuracy of the fix behind
  /// them.
  String _composeAddress(Position pos, Map<String, dynamic>? osmAddress) {
    _resolved = PlaceNaming.fromOsm(osmAddress);

    final home = _homeBarangay;
    return PlaceNaming.compose(
      osm: _resolved,
      nearest: _nearestPlace,
      accuracyM: pos.accuracy,
      home:
          home == null
              ? null
              : HomeBarangay(
                name: home.name,
                municipality: home.municipality,
                km: BiliranPlaces.distanceToNamed(
                  home.name,
                  pos.latitude,
                  pos.longitude,
                ),
              ),
    );
  }

  // ── Speech-to-text ────────────────────────────────────────

  Future<void> initSpeech() async {
    _speechAvailable = await _speech.initialize(
      onError: (e) {
        _isListening = false;
        _speechError = e.errorMsg;
        notifyListeners();
      },
      onStatus: (status) {
        // The platform ends a session on its own when it decides the speaker
        // has stopped. Without this the UI keeps showing "listening" over a
        // microphone that is no longer recording.
        if (status == 'done' || status == 'notListening') {
          if (_isListening) {
            _isListening = false;
            notifyListeners();
          }
        }
      },
    );

    if (_speechAvailable) {
      try {
        _speechLocales = await _speech.locales();
      } catch (_) {
        _speechLocales = const [];
      }
    }
    await loadSpokenLanguage();
    notifyListeners();
  }

  /// Listen in [localeId], overriding the resolver. Diagnostics only — the
  /// report flow should go through [startListening].
  Future<void> startListeningIn({
    required String localeId,
    required ValueSetter<String> onResult,
  }) => _listen(localeId: localeId, onResult: onResult);

  /// Start listening in the locale that best fits [spokenLanguage].
  ///
  /// [spokenLanguage] is a display name ('Waray', 'Bisaya', 'Filipino',
  /// 'English') — the resident's own setting, not the app's UI locale. Someone
  /// may well read the app in Filipino and speak Waray.
  Future<void> startListening({
    required ValueSetter<String> onResult,
    String? spokenLanguage,
  }) {
    final resolved = SpeechLocaleResolver.resolve(
      languageName: spokenLanguage ?? _spokenLanguage,
      available: _speechLocales,
    );
    return _listen(localeId: resolved, onResult: onResult);
  }

  Future<void> _listen({
    required String? localeId,
    required ValueSetter<String> onResult,
  }) async {
    if (!_speechAvailable) return;
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      _speechError = 'microphone_permission_denied';
      notifyListeners();
      return;
    }

    _isListening = true;
    _spokenText = '';
    _speechConfidence = 0;
    _speechError = null;
    _activeSpeechLocale = localeId;
    notifyListeners();

    await _speech.listen(
      onResult: (result) {
        _spokenText = result.recognizedWords;
        // Only a final result carries a meaningful rating; partials report 0
        // and would otherwise keep resetting a good score to nothing.
        if (result.finalResult) _speechConfidence = result.confidence;
        onResult(_spokenText);
        notifyListeners();
      },
      listenOptions: SpeechListenOptions(
        localeId: localeId,
        listenFor: const Duration(seconds: 60),
        // Was 4 seconds. Someone reporting an emergency stops to breathe, to
        // look, to be told something by a person beside them. Four seconds of
        // silence cut the recording off mid-report.
        pauseFor: const Duration(seconds: 8),
        partialResults: true,
        cancelOnError: false,
      ),
    );
  }

  Future<void> stopListening() async {
    await _speech.stop();
    _isListening = false;
    notifyListeners();
  }

  // ── Voice note ───────────────────────────────────────────────
  //
  // One press captures two things from one act of speaking: the recording the
  // dispatcher listens to, and the transcript that ranks the queue. See
  // VoiceNoteService for why they cannot come from the same plugin.

  File? _voiceNote;
  Duration _voiceNoteLength = Duration.zero;
  bool _isRecordingVoice = false;
  bool _voiceCaptureFailed = false;
  bool _voiceUploadFailed = false;

  /// The recording from the last completed [stopSpeaking], if one was captured.
  File? get voiceNote => _voiceNote;

  /// How many people the resident says are involved.
  ///
  /// MACHINE VALUES — '1person', '2people', '3people', '4plus', 'notsure' —
  /// and never the words on screen. Every other wizard answer is stored as its
  /// Filipino label, which quietly makes the UI copy part of the backend's
  /// scoring table: translating a chip stops it counting, with nothing failing.
  /// This field does not join that arrangement.
  ///
  /// 'notsure' is the default and is stored rather than omitted, so a
  /// dispatcher can tell "asked, and they did not know" from "never asked".
  String? get peopleCount => _wizardAnswers['people_count'] as String?;

  /// Record how many people are involved. Optional, and never blocks sending.
  void setPeopleCount(String value) {
    _wizardAnswers['people_count'] = value;
    notifyListeners();
  }

  bool get isRecordingVoice => _isRecordingVoice;

  /// How long the kept recording runs. Measured by the recorder, not by the
  /// widget that happened to be on screen — a leftover note displayed by a
  /// freshly built widget was showing "0:00" for real audio.
  Duration get voiceNoteLength => _voiceNoteLength;

  /// The microphone never produced a usable recording.
  ///
  /// Distinct from [voiceUploadFailed] on purpose: these need different words.
  /// This one means "say it again or type it"; that one means "we have your
  /// voice but could not send it".
  bool get voiceCaptureFailed => _voiceCaptureFailed;

  /// A recording exists but did not reach the station.
  bool get voiceUploadFailed => _voiceUploadFailed;

  /// Record the resident saying what happened.
  ///
  /// The recogniser is deliberately NOT started alongside this. Measured on a
  /// real handset: starting both produced a 4,257-byte file — about one second
  /// at 32 kbps — because SpeechRecognizer took the microphone away from the
  /// encoder a beat after it opened. The recording looked present and played
  /// for 60 ms, which is worse than not offering it, because the resident
  /// believes the station can hear them.
  ///
  /// So the recorder owns the microphone. The transcript that orders the queue
  /// comes from the category and the typed note, exactly as it did before this
  /// feature existed — nothing regressed — and transcribing the uploaded
  /// audio server-side is what restores it properly.
  Future<void> startVoiceNote() async {
    await discardVoiceNote();
    _voiceCaptureFailed = false;
    _voiceUploadFailed = false;

    try {
      _isRecordingVoice = await _voice.start();
    } catch (_) {
      _isRecordingVoice = false;
    }
    _voiceCaptureFailed = !_isRecordingVoice;
    notifyListeners();
  }

  /// Stop recording and keep the file, if one was actually captured.
  Future<void> stopVoiceNote({Duration? length}) async {
    if (_isRecordingVoice) {
      try {
        _voiceNote = await _voice.stop();
      } catch (_) {
        _voiceNote = null;
      }
      _isRecordingVoice = false;
      _voiceCaptureFailed = _voiceNote == null;
      _voiceNoteLength =
          _voiceNote == null ? Duration.zero : (length ?? Duration.zero);
      // The count question only exists because transcription loses counts, so
      // it appears with the recording and defaults to "not sure" — answered
      // or not, the report sends.
      if (_voiceNote != null) {
        _wizardAnswers.putIfAbsent('people_count', () => 'notsure');
      }
    }
    notifyListeners();
  }

  Future<void> discardVoiceNote() async {
    if (_isRecordingVoice) {
      await _voice.cancel();
      _isRecordingVoice = false;
    }
    await _voice.discard();
    _voiceNote = null;
    _voiceNoteLength = Duration.zero;
    // The question came with the recording; it leaves with it.
    _wizardAnswers.remove('people_count');
    _voiceCaptureFailed = false;
    _voiceUploadFailed = false;
    notifyListeners();
  }

  // ── Submit ────────────────────────────────────────────────

  Future<bool> submitIncident({
    required String reportText,
    String? locationAddress,
  }) async {
    // A station is optional now. With a position the server picks the nearest
    // one itself, which means a slow or momentarily flaky connection does not
    // fail the whole report just because a SEPARATE call (the station list)
    // did not come back in time. Only a report with neither a station nor a
    // position has nowhere to go.
    if (_selectedStation == null && incidentLat == null) {
      _submitStatus = SubmitStatus.error;
      _submitError =
          'We could not find your location. Turn on GPS, or choose a station, '
          'then try again.';
      notifyListeners();
      return false;
    }

    _submitStatus = SubmitStatus.submitting;
    _submitError = null;
    _submitFailedOffline = false;
    _lastSubmitMediaCount = 0;
    notifyListeners();

    // Set once the phone is found to have no working route to the server. From
    // then on nothing more is uploaded: every file would wait out its own
    // timeout first, and the report — the one thing that matters — would wait
    // behind them.
    var offline = false;

    // Upload any selected media first (before creating the incident row)
    final List<String> mediaPaths = [];
    if (_selectedMedia.isNotEmpty) {
      _uploadingMedia = true;
      notifyListeners();

      // One quick look before starting. With signal but no data an upload is
      // neither refused nor answered, so the first photo alone would hold the
      // report for its whole timeout.
      offline = !await BackendHealth.isReachable(
        timeout: const Duration(seconds: 4),
      );
      if (offline) {
        debugPrint(
          '[submitIncident] server unreachable — skipping media, sending the '
          'report on its own',
        );
      }

      final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
      final tempKey = DateTime.now().millisecondsSinceEpoch.toString();

      for (final file in offline ? const <File>[] : _selectedMedia) {
        try {
          final path = await _mediaService.uploadFile(
            file: file,
            userId: userId,
            incidentId: tempKey,
          );
          mediaPaths.add(path);
        } on ServerFailure catch (e) {
          _submitStatus = SubmitStatus.error;
          _submitError = 'Media upload failed: ${e.message}';
          _uploadingMedia = false;
          notifyListeners();
          return false;
        } on NetworkFailure {
          // No internet — every remaining file would fail the same way. Stop
          // uploading and try the report on its own; it may still get through
          // even though a whole photo would not have.
          offline = true;
          debugPrint(
            '[submitIncident] offline — skipping remaining media, '
            'continuing with the report',
          );
          break;
        }
      }
      _uploadingMedia = false;
    }
    // Counted before the voice note joins the list: this is photos and videos.
    _lastSubmitMediaCount = mediaPaths.length;

    // The voice note is uploaded separately from the photos above, and its
    // failure is handled differently on purpose. A photo that will not upload
    // aborts the submit, because the resident chose to attach it and would
    // rather retry than send a report they think has evidence on it. A voice
    // note that will not upload must NOT abort: the transcript already carries
    // the report, the dispatcher can act on it, and refusing to file an
    // emergency because an audio file failed on one bar of signal is the worst
    // possible trade.
    final voice = _voiceNote;
    if (voice != null) {
      if (offline) {
        // Same connection that has just failed; not worth another timeout.
        _voiceUploadFailed = true;
      } else {
        _uploadingMedia = true;
        notifyListeners();
        try {
          mediaPaths.add(
            await _mediaService.uploadFile(
              file: voice,
              userId: Supabase.instance.client.auth.currentUser?.id ?? '',
              incidentId: DateTime.now().millisecondsSinceEpoch.toString(),
            ),
          );
        } on ServerFailure catch (e) {
          // Reported separately from a capture failure. The resident's voice
          // was recorded fine; it just did not reach the station, and telling
          // them "hindi na-record" would send them back to re-record something
          // that already exists.
          _voiceUploadFailed = true;
          debugPrint('[voiceNote] upload failed: ${e.message}');
        } catch (e) {
          _voiceUploadFailed = true;
          debugPrint('[voiceNote] upload failed: $e');
        }
        _uploadingMedia = false;
        notifyListeners();
      }
    }

    try {
      _lastSubmitted = await _repo.submitIncident(
        reportText: reportText,
        stationId: _selectedStation?.id,
        // Where the INCIDENT is — the placed point when there is one.
        latitude: incidentLat,
        longitude: incidentLng,
        locationAddress: reportingElsewhere ? _incidentAddress : locationAddress,
        reportedFromElsewhere: reportingElsewhere,
        reporterLatitude: reportingElsewhere ? _currentPosition?.latitude : null,
        reporterLongitude: reportingElsewhere ? _currentPosition?.longitude : null,
        reporterAddress: reportingElsewhere ? _locationAddress : null,
        mediaUrls: mediaPaths,
        incidentCategory: _incidentCategory?.value,
        wizardAnswers: _wizardAnswers.isEmpty ? null : _wizardAnswers,
        overlapAgencies:
            _overlapFlags.isEmpty
                ? null
                : _overlapFlags.map((f) => f.value).toList(),
        landmarkNote: _landmarkNote,
        victimRelationship: _victimRelationship?.value,
      );
      _submitStatus = SubmitStatus.success;
      clearMedia();
      discardVoiceNote();
      notifyListeners();
      // The resident lands on My Reports next, and it showed the list as it
      // was before this report existed until they pulled to refresh — a
      // report they had just been told was sent was not there.
      unawaited(loadMyIncidents());
      return true;
    } on NetworkFailure catch (e) {
      _submitStatus = SubmitStatus.error;
      _submitError = e.message;
      // Nothing reached the server: the screen offers the station hotlines,
      // because a phone call still works where this did not.
      _submitFailedOffline = true;
      notifyListeners();
      return false;
    } on ServerFailure catch (e) {
      _submitStatus = SubmitStatus.error;
      _submitError = e.message;
      notifyListeners();
      return false;
    } catch (_) {
      _submitStatus = SubmitStatus.error;
      _submitError = 'Something went wrong. Please try again.';
      notifyListeners();
      return false;
    }
  }

  void resetSubmitStatus() {
    _submitStatus = SubmitStatus.idle;
    _submitError = null;
    _submitFailedOffline = false;
    clearMedia();
    clearWizard();
    notifyListeners();
  }

  // ── My reports ────────────────────────────────────────────

  Future<void> loadMyIncidents() async {
    // Don't fire a second parallel request if one is already in-flight
    if (_loadingIncidents) return;

    _loadingIncidents = true;
    _incidentsError = null;
    notifyListeners();

    try {
      _myIncidents = await _repo.getMyIncidents();
    } on NetworkFailure catch (e) {
      debugPrint('[loadMyIncidents] NetworkFailure: ${e.message}');
      _incidentsError = e.message;
    } on ServerFailure catch (e) {
      debugPrint('[loadMyIncidents] ServerFailure: ${e.message}');
      _incidentsError = e.message;
    } catch (e, st) {
      debugPrint('[loadMyIncidents] unexpected error: $e\n$st');
      _incidentsError = 'Failed to load your reports.';
    } finally {
      _loadingIncidents = false;
      notifyListeners();
    }
  }

  /// Take back a report. Returns null on success, or a message to show.
  ///
  /// The list is reloaded from the server rather than patched locally: the
  /// backend decides whether a withdrawal was allowed, and a screen that
  /// optimistically greys out a report the server refused to withdraw would be
  /// telling the resident help is not coming when it is.
  Future<String?> withdrawIncident(String incidentId, {String? reason}) async {
    try {
      await _repo.withdrawIncident(incidentId, reason: reason);
      await loadMyIncidents();
      return null;
    } on ServerFailure catch (e) {
      await loadMyIncidents();
      return e.message;
    } on NetworkFailure catch (e) {
      return e.message;
    } catch (e, st) {
      debugPrint('[withdrawIncident] unexpected error: $e\n$st');
      return 'Could not withdraw this report.';
    }
  }

  // ── Incident thread ("Add Information" / Section 16 communication) ──
  //
  // Kept as thin pass-throughs rather than provider-held state: only one
  // thread is ever open on screen at a time, so the sheet that shows it owns
  // its own loading/list state, the same way IncidentNotesPanel does on the
  // dashboard side of this same table.

  Future<List<IncidentNote>> fetchIncidentNotes(String incidentId) =>
      _repo.getIncidentNotes(incidentId);

  /// Returns an error message, or null on success.
  Future<String?> sendIncidentNote(String incidentId, String body) async {
    try {
      await _repo.addIncidentNote(incidentId, body);
      return null;
    } on ServerFailure catch (e) {
      return e.message;
    } on NetworkFailure catch (e) {
      return e.message;
    } catch (e, st) {
      debugPrint('[sendIncidentNote] unexpected error: $e\n$st');
      return 'Could not send your message.';
    }
  }

  // ── Post-resolution feedback (Section 26) ────────────────────────

  Future<IncidentFeedback?> fetchMyFeedback(String incidentId) =>
      _repo.getMyFeedback(incidentId);

  /// Returns an error message, or null on success.
  Future<String?> submitIncidentFeedback(
    String incidentId, {
    required int rating,
    String? comment,
  }) async {
    try {
      await _repo.submitFeedback(
        incidentId: incidentId,
        rating: rating,
        comment: comment,
      );
      return null;
    } on ServerFailure catch (e) {
      return e.message;
    } on NetworkFailure catch (e) {
      return e.message;
    } catch (e, st) {
      debugPrint('[submitIncidentFeedback] unexpected error: $e\n$st');
      return 'Could not save your feedback.';
    }
  }

  @override
  void dispose() {
    _refineSub?.cancel();
    super.dispose();
  }
}
