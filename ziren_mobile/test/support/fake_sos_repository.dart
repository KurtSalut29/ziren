import 'package:geolocator/geolocator.dart';
import 'package:ziren/features/sos/data/sos_repository.dart';
import 'package:ziren/features/sos/domain/sos_result.dart';

/// An SOS backend that answers however the test says. Counts its calls so a
/// test can also assert that it was NOT asked.
class FakeSosRepository extends SosRepository {
  FakeSosRepository(this._outcome);

  final Future<SosResult> Function() _outcome;
  int calls = 0;

  /// The landmark note the last submit carried.
  String? lastLandmarkNote;

  @override
  Future<SosResult> submitSos({
    double? latitude,
    double? longitude,
    String? description,
    String? incidentCategory,
    String? locationAddress,
    String? landmarkNote,
  }) {
    calls++;
    lastLandmarkNote = landmarkNote;
    return _outcome();
  }
}

const SosResult kSosResult = SosResult(
  id: '11111111-2222-3333-4444-555555555555',
  reportText: 'SOS',
  status: 'received',
  submittedVia: 'sos',
  createdAt: '2026-09-24T01:00:00+00:00',
  stationName: 'BFP Naval Main Station',
);

/// A GPS fix in Naval, Biliran.
Position kNavalPosition() => Position(
  latitude: 11.5836,
  longitude: 124.4063,
  timestamp: DateTime.utc(2026, 9, 24),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);
