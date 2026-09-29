import '../../../l10n/app_localizations.dart';

/// The acceptance verdict for one assignment, as the backend computed it.
///
/// WHY THE PHONE DOES NOT WORK THIS OUT FOR ITSELF
///
/// It has everything it would need — `dispatched_at` is on the row and the
/// deadline is a fixed function of severity. It still must not, because the
/// dispatcher's board is deriving the same verdict at the same moment from the
/// same columns, and the failure mode of two independent implementations is a
/// board showing OVERDUE in red beside a phone still counting down. Whichever
/// one is wrong, the crew and the dispatcher are now arguing about the clock
/// instead of the fire.
///
/// So `responder_ack.py` decides and this parses. The only arithmetic here is
/// ticking the countdown between polls, and it is anchored to the number the
/// server sent rather than to a locally computed deadline.
class ResponderAck {
  const ResponderAck({
    required this.state,
    required this.deadlineSeconds,
    this.secondsWaiting,
    this.secondsRemaining,
    this.declinedReason,
    this.declineCount = 0,
  });

  /// 'pending' | 'accepted' | 'declined' | 'overdue' | 'not_applicable'
  final String state;

  /// The policy that applied to this incident, so the UI can draw a
  /// proportion without hardcoding the severity table a third time.
  final int deadlineSeconds;

  final int? secondsWaiting;
  final int? secondsRemaining;
  final String? declinedReason;

  /// Never reset by reassignment. Three refusals on one incident is a
  /// coverage problem, not a responder problem, and it stays visible.
  final int declineCount;

  factory ResponderAck.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      // An incident from a backend that predates migration 024, or one the
      // queue did not annotate. 'not_applicable' rather than 'pending': an
      // unknown acceptance state must not make the phone shout.
      return const ResponderAck(state: 'not_applicable', deadlineSeconds: 60);
    }
    return ResponderAck(
      state: json['state'] as String? ?? 'not_applicable',
      deadlineSeconds: (json['deadline_seconds'] as num?)?.toInt() ?? 60,
      secondsWaiting: (json['seconds_waiting'] as num?)?.toInt(),
      secondsRemaining: (json['seconds_remaining'] as num?)?.toInt(),
      declinedReason: json['declined_reason'] as String?,
      declineCount: (json['decline_count'] as num?)?.toInt() ?? 0,
    );
  }

  bool get isPending => state == 'pending';
  bool get isOverdue => state == 'overdue';
  bool get isAccepted => state == 'accepted';

  /// Whether this assignment is still waiting on an answer from this crew.
  /// The one question the full-screen alert is raised on.
  bool get needsAnswer => isPending || isOverdue;

  /// 0.0 → just dispatched, 1.0 → out of time. Drives the ring on the alert
  /// screen. Anchored to the server's own deadline, never a local constant.
  double get elapsedFraction {
    final waited = secondsWaiting;
    if (waited == null || deadlineSeconds <= 0) return 0;
    return (waited / deadlineSeconds).clamp(0.0, 1.0);
  }

  /// The countdown, ticked locally between polls.
  ///
  /// Returns a NEW instance rather than mutating: these hang off immutable
  /// incident models, and a mutable clock inside one would make two widgets
  /// holding the same incident disagree about the time.
  ResponderAck tick(int seconds) {
    if (!needsAnswer) return this;
    final waited = (secondsWaiting ?? 0) + seconds;
    final left = deadlineSeconds - waited;
    return ResponderAck(
      state: left > 0 ? 'pending' : 'overdue',
      deadlineSeconds: deadlineSeconds,
      secondsWaiting: waited,
      secondsRemaining: left > 0 ? left : 0,
      declinedReason: declinedReason,
      declineCount: declineCount,
    );
  }

  /// "0:47" — the countdown as a crew reads it.
  String get remainingLabel {
    final left = secondsRemaining ?? 0;
    final m = left ~/ 60;
    final s = left % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

/// Why a crew could not take a call.
///
/// THE KEY IS A WIRE CONTRACT. These six strings are the backend's
/// `_DECLINE_REASONS` and the database's CHECK constraint, and they are const
/// for that reason — a localised key fails validation with a 422 the responder
/// cannot act on, silently, in the one flow where being unable to answer
/// matters.
///
/// The LABEL is not. It is looked up from AppLocalizations so the responder
/// reads their own language, exactly as every resident screen does. Keeping
/// the two apart in the type is what makes the distinction hard to get wrong
/// later.
class DeclineReason {
  const DeclineReason(this.key);

  final String key;

  static const all = <DeclineReason>[
    DeclineReason('vehicle_down'),
    DeclineReason('already_committed'),
    DeclineReason('out_of_area'),
    DeclineReason('insufficient_crew'),
    DeclineReason('road_impassable'),
    DeclineReason('other'),
  ];

  String label(AppLocalizations t) => switch (key) {
    'vehicle_down' => t.respReasonVehicleDown,
    'already_committed' => t.respReasonCommitted,
    'out_of_area' => t.respReasonOutOfArea,
    'insufficient_crew' => t.respReasonCrew,
    'road_impassable' => t.respReasonRoad,
    _ => t.respReasonOther,
  };

  String hint(AppLocalizations t) => switch (key) {
    'vehicle_down' => t.respReasonVehicleDownHint,
    'already_committed' => t.respReasonCommittedHint,
    'out_of_area' => t.respReasonOutOfAreaHint,
    'insufficient_crew' => t.respReasonCrewHint,
    'road_impassable' => t.respReasonRoadHint,
    _ => t.respReasonOtherHint,
  };
}

/// What the crew found. The backend's `_OUTCOMES`, same wire contract.
///
/// This is the list that makes the severity rubric measurable: an incident the
/// rubric scored `critical` that closes as `false_alarm` is a rubric miss that
/// can be counted, and before this existed that comparison could not be made
/// at all. Which is exactly why the key must survive translation untouched.
class IncidentOutcome {
  const IncidentOutcome(this.key);

  final String key;

  static const all = <IncidentOutcome>[
    IncidentOutcome('handled_on_scene'),
    IncidentOutcome('transported'),
    IncidentOutcome('turned_over'),
    IncidentOutcome('false_alarm'),
    IncidentOutcome('nobody_found'),
    IncidentOutcome('refused_assistance'),
    IncidentOutcome('unable_to_access'),
    IncidentOutcome('other'),
  ];

  String label(AppLocalizations t) => switch (key) {
    'handled_on_scene' => t.respOutcomeHandled,
    'transported' => t.respOutcomeTransported,
    'turned_over' => t.respOutcomeTurnedOver,
    'false_alarm' => t.respOutcomeFalseAlarm,
    'nobody_found' => t.respOutcomeNobodyFound,
    'refused_assistance' => t.respOutcomeRefused,
    'unable_to_access' => t.respOutcomeNoAccess,
    _ => t.respOutcomeOther,
  };

  String hint(AppLocalizations t) => switch (key) {
    'handled_on_scene' => t.respOutcomeHandledHint,
    'transported' => t.respOutcomeTransportedHint,
    'turned_over' => t.respOutcomeTurnedOverHint,
    'false_alarm' => t.respOutcomeFalseAlarmHint,
    'nobody_found' => t.respOutcomeNobodyFoundHint,
    'refused_assistance' => t.respOutcomeRefusedHint,
    'unable_to_access' => t.respOutcomeNoAccessHint,
    _ => t.respOutcomeOtherHint,
  };

  static IncidentOutcome? byKey(String? key) {
    for (final o in all) {
      if (o.key == key) return o;
    }
    return null;
  }
}

/// Standing local knowledge about reaching a place.
///
/// Cut bridges, roads only a motorcycle fits down, dogs, live wires. This
/// knowledge exists in Biliran entirely inside the heads of the crews who have
/// been there, and it leaves when they transfer. A responder who learns about
/// the washed-out bridge by arriving at it has lost the call.
class ApproachHazard {
  const ApproachHazard({
    required this.id,
    required this.hazardType,
    required this.note,
    required this.distanceKm,
  });

  final String id;
  final String hazardType;
  final String note;
  final double distanceKm;

  factory ApproachHazard.fromJson(Map<String, dynamic> json) => ApproachHazard(
    id: json['id'] as String,
    hazardType: json['hazard_type'] as String? ?? 'other',
    note: json['note'] as String? ?? '',
    distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0,
  );

  String typeLabel(AppLocalizations t) => switch (hazardType) {
    'road_impassable' => t.respHazardRoad,
    'access_difficult' => t.respHazardAccess,
    'security' => t.respHazardSecurity,
    'animal' => t.respHazardAnimal,
    'structural' => t.respHazardStructural,
    _ => t.respHazardOther,
  };

  /// "300 m" under a kilometre, "1.4 km" above it. A crew reading this while
  /// driving should not have to parse "0.3 km".
  ///
  /// Not localised: these are SI units and read the same in both languages.
  String get distanceLabel =>
      distanceKm < 1
          ? '${(distanceKm * 1000).round()} m'
          : '${distanceKm.toStringAsFixed(1)} km';
}
