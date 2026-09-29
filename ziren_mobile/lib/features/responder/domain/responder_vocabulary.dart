import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import 'responder_incident_model.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Where an assignment stands, in the steps a crew thinks in.
///
/// Finer than the wire status: 'dispatched' is two different situations for
/// the crew, "answer this" and "accepted, not moving yet", and a screen that
/// showed both as "Dispatched" left them unsure whether their answer had
/// registered.
enum ResponderPhase {
  newAssignment,
  accepted,
  enRoute,
  onScene,
  resolved,
  cancelled,
}

/// The shared reading of an incident: its colour, its icon, its word, and its
/// place in the working order.
///
/// WHY THIS IS ONE FILE AND NOT FOUR COPIES
///
/// Home, the incoming-report sheet, the Reports list and the charts all have
/// to answer "how bad is this" and they must answer it identically. When the
/// same switch was pasted into each screen, nothing stopped one of them from
/// picking a different amber, or from ranking `high` above `critical`, and the
/// failure would look like a rendering quirk rather than the disagreement it
/// is. A responder comparing the sheet that woke them against the list they
/// scroll must see the same incident described the same way.
///
/// The dispatcher console keeps the same rule in
/// `components/incidents/incident-vocabulary.ts`, for the same reason.
class ResponderVocabulary {
  const ResponderVocabulary._();

  /// Severity tiers, worst first. The order here IS the priority order — the
  /// charts, the queue sort and the legend all read it rather than each
  /// hardcoding a list that could be reordered in one place only.
  static const List<String> tiers = ['critical', 'high', 'medium', 'low'];

  static Color color(String? severity) => switch (severity) {
    'critical' => ZirenTokens.severityCritical,
    'high' => ZirenTokens.severityHigh,
    'medium' => ZirenTokens.severityMedium,
    'low' => ZirenTokens.severityLow,
    _ => ZirenTokens.textMuted,
  };

  static Color background(String? severity) => switch (severity) {
    'critical' => ZirenTokens.severityCriticalBg,
    'high' => ZirenTokens.severityHighBg,
    'medium' => ZirenTokens.severityMediumBg,
    'low' => ZirenTokens.severityLowBg,
    _ => ZirenTokens.surfaceRaised,
  };

  static IconData icon(String? severity) => switch (severity) {
    'critical' => ZirenTokens.severityCriticalIcon,
    'high' => ZirenTokens.severityHighIcon,
    'medium' => ZirenTokens.severityMediumIcon,
    'low' => ZirenTokens.severityLowIcon,
    _ => LucideIcons.circle_question_mark,
  };

  /// The category, in the words this app already shows a responder — the same
  /// bilingual phrasing ResponderIncidentModel.categoryLabel always used, now
  /// in one place so the nearby-incident alert cannot drift from the queue
  /// card. Wire values, not the IncidentCategory enum: this reads what the
  /// backend actually sent, including retired pre-migration-019 categories.
  static String categoryLabel(String? category) {
    switch (category) {
      case 'fire':
        return 'Sunog / Fire';
      case 'medical_trauma':
        return 'Medical / Trauma';
      case 'vehicular':
        return 'Aksidente sa Daan';
      case 'flood_landslide_calamity':
        return 'Baha / Landslide / Kalamidad';
      case 'domestic_dispute_crime':
        return 'Kaguluhan / Krimen';
      case 'hazmat':
        return 'HAZMAT';
      case 'missing_person':
        return 'Nawawalang Tao';
      case 'other':
        return 'Iba pa';
      default:
        return 'Emergency';
    }
  }

  /// What the incident IS, as an icon — fire, medical, road, flood, crime.
  /// Severity says how bad; this says what kind, which is the first thing a
  /// crew needs to know to pick up the right gear.
  static IconData categoryIcon(String? category) => switch (category) {
    'fire' => LucideIcons.flame,
    'medical_trauma' => LucideIcons.stethoscope,
    'vehicular' => LucideIcons.car,
    'flood_landslide_calamity' => LucideIcons.waves_horizontal,
    'domestic_dispute_crime' => LucideIcons.shield,
    'hazmat' => LucideIcons.biohazard,
    'missing_person' => LucideIcons.user_search,
    _ => LucideIcons.siren,
  };

  // ── Phase ───────────────────────────────────────────────────

  static ResponderPhase phase(ResponderIncidentModel i) => switch (i.status) {
    'dispatched' =>
      i.ack.isAccepted ? ResponderPhase.accepted : ResponderPhase.newAssignment,
    'en_route' => ResponderPhase.enRoute,
    'arrived' => ResponderPhase.onScene,
    'resolved' => ResponderPhase.resolved,
    'cancelled' => ResponderPhase.cancelled,
    _ => ResponderPhase.newAssignment,
  };

  static String phaseLabel(ResponderPhase p, AppLocalizations t) => switch (p) {
    ResponderPhase.newAssignment => t.respStatusNew,
    ResponderPhase.accepted => t.respStatusAccepted,
    ResponderPhase.enRoute => t.respStatusEnRoute,
    ResponderPhase.onScene => t.respStatusOnScene,
    ResponderPhase.resolved => t.respStatusResolved,
    ResponderPhase.cancelled => t.respStatusCancelled,
  };

  static IconData phaseIcon(ResponderPhase p) => switch (p) {
    ResponderPhase.newAssignment => LucideIcons.bell_ring,
    ResponderPhase.accepted => LucideIcons.circle_check,
    ResponderPhase.enRoute => LucideIcons.navigation,
    ResponderPhase.onScene => LucideIcons.map_pin_check,
    ResponderPhase.resolved => LucideIcons.circle_check_big,
    ResponderPhase.cancelled => LucideIcons.circle_x,
  };

  /// Three meanings, three colours: orange = waiting on YOU, indigo = in
  /// progress, green = done. Never the agency hue — BFP's red-coral beside
  /// "On Scene" read as a critical alarm on a call that was going fine.
  static Color phaseColor(ResponderPhase p) => switch (p) {
    ResponderPhase.newAssignment => ZirenTokens.statusDispatched,
    ResponderPhase.accepted ||
    ResponderPhase.enRoute ||
    ResponderPhase.onScene => ZirenTokens.statusProcessing,
    ResponderPhase.resolved => ZirenTokens.statusResolved,
    ResponderPhase.cancelled => ZirenTokens.statusCancelled,
  };

  static Color phaseBackground(ResponderPhase p) => switch (p) {
    ResponderPhase.newAssignment => ZirenTokens.statusDispatchedBg,
    ResponderPhase.accepted ||
    ResponderPhase.enRoute ||
    ResponderPhase.onScene => ZirenTokens.statusProcessingBg,
    ResponderPhase.resolved => ZirenTokens.statusResolvedBg,
    ResponderPhase.cancelled => ZirenTokens.statusCancelledBg,
  };

  /// Position on the five-step track Assigned → Accepted → En route →
  /// On scene → Resolved, 0-based. A cancelled call has no place on it.
  static int? stepIndex(ResponderPhase p) => switch (p) {
    ResponderPhase.newAssignment => 0,
    ResponderPhase.accepted => 1,
    ResponderPhase.enRoute => 2,
    ResponderPhase.onScene => 3,
    ResponderPhase.resolved => 4,
    ResponderPhase.cancelled => null,
  };

  /// The tier as a WORD.
  ///
  /// Never omit it in favour of the colour alone. Around 1 in 12 men has a
  /// red-green deficiency, and this app's critical and low tiers are exactly
  /// red and green; a responder who cannot separate them has to be able to
  /// read the tier instead. Same rule the console works to.
  static String label(String? severity) => switch (severity) {
    'critical' => 'CRITICAL',
    'high' => 'HIGH',
    'medium' => 'MEDIUM',
    'low' => 'LOW',
    _ => 'NOT TRIAGED',
  };

  /// Worst first; anything untriaged sorts last.
  ///
  /// Untriaged does NOT mean harmless — it means the rubric has not run yet.
  /// It sorts last only because a tier that is unknown cannot be ranked
  /// against one that is known, and the queue still shows it with a word that
  /// says so rather than an implied "low".
  static int rank(String? severity) {
    final i = tiers.indexOf(severity ?? '');
    return i < 0 ? tiers.length : i;
  }

  /// How full the severity bar runs, 0..1.
  ///
  /// NOT a score, and deliberately not a percentage. The ResQLink prototype
  /// prints "AI 97%" in this spot. Ziren's triage rubric returns a TIER, not a
  /// confidence, so a percentage here would be a number with no source — the
  /// one kind of lie a triage screen cannot afford. The bar carries the tier's
  /// shape; the word beside it carries the meaning.
  static double fill(String? severity) => switch (severity) {
    'critical' => 1.0,
    'high' => 0.75,
    'medium' => 0.5,
    'low' => 0.28,
    _ => 0.15,
  };

  // ── Status ──────────────────────────────────────────────────

  static Color statusColor(String status) => switch (status) {
    'dispatched' => ZirenTokens.statusDispatched,
    'en_route' => ZirenTokens.statusProcessing,
    'arrived' => ZirenTokens.systemSuccess,
    'resolved' => ZirenTokens.statusResolved,
    'cancelled' => ZirenTokens.statusCancelled,
    _ => ZirenTokens.statusReceived,
  };

  static Color statusBackground(String status) => switch (status) {
    'dispatched' => ZirenTokens.statusDispatchedBg,
    'en_route' => ZirenTokens.statusProcessingBg,
    'arrived' => ZirenTokens.systemSuccessBg,
    'resolved' => ZirenTokens.statusResolvedBg,
    'cancelled' => ZirenTokens.statusCancelledBg,
    _ => ZirenTokens.statusReceivedBg,
  };

  /// The status without the instruction attached to it.
  ///
  /// [ResponderIncidentModel.statusLabel] returns "Dispatched — Respond Now",
  /// which is right on a detail screen with room for it and wrong in a chip:
  /// 24 characters sharing a row with a severity bar either wrap or squeeze
  /// everything beside them. Trimming at the dash keeps one status vocabulary
  /// rather than inventing a second one that could drift from the first.
  static String statusShort(ResponderIncidentModel i) =>
      i.statusLabel.split(' — ').first;

  /// True once the incident is off this responder's plate.
  static bool isClosed(ResponderIncidentModel i) =>
      i.status == 'resolved' || i.status == 'cancelled';

  /// A wait, in minutes, as a chip-sized string.
  ///
  /// ONE RULE FOR WAITING, AND WHY IT HAD TO BE FACTORED OUT
  ///
  /// A wait reaches the screen two ways: computed on the phone from
  /// `created_at`, or handed over by the backend as `oldest_waiting_minutes`.
  /// Those used to be formatted by two different functions with two different
  /// rounding rules — [elapsed] truncated to whole days, [minutes] rounded —
  /// and while they lived on separate screens nobody could see it.
  ///
  /// Folding the dashboard into Home put them side by side, and one incident
  /// that had been open for about 2.9 days rendered as "2d" in the pending
  /// card and "3d" in the longest-waiting card, one above the other. Neither
  /// number was wrong; the disagreement was, because a responder reading two
  /// figures for one call has no way to tell which to trust.
  ///
  /// Truncation is the rule here, not rounding: "2d" means at least two days,
  /// which is the honest reading of a wait. [minutes] keeps rounding, because
  /// it formats a measured duration — a typical time to close — where the
  /// nearest value is the accurate one.
  static String waiting(int? minutes) {
    if (minutes == null) return '—';
    if (minutes < 1) return 'just now';
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    if (hours < 24) return '${hours}h';
    return '${hours ~/ 24}d';
  }

  /// Elapsed time since [t]. Delegates, so it cannot drift from [waiting].
  static String elapsed(DateTime t) =>
      waiting(DateTime.now().difference(t).inMinutes);

  /// Minutes as something a person reads at a glance.
  ///
  /// "142m" is arithmetic the reader has to do. Past an hour this switches to
  /// hours, which is the unit the number actually means at that size.
  static String minutes(num? m) {
    if (m == null) return '—';
    if (m < 1) return '<1m';
    if (m < 60) return '${m.round()}m';
    final h = m / 60;
    if (h < 24) return h >= 10 ? '${h.round()}h' : '${h.toStringAsFixed(1)}h';
    return '${(h / 24).round()}d';
  }

  /// The order a responder should work in: worst tier first, and within a
  /// tier, whoever reported first.
  ///
  /// The second half matters as much as the first. Severity alone leaves two
  /// equally critical calls in whatever order the server returned them, which
  /// is no order at all from the responder's seat — and the person who has
  /// been waiting longest is the one the queue owes.
  static int workingOrder(ResponderIncidentModel a, ResponderIncidentModel b) {
    final r = rank(a.severity).compareTo(rank(b.severity));
    if (r != 0) return r;
    return a.createdAt.compareTo(b.createdAt);
  }

  /// The queue in working order. Sorts a copy — the provider's list is shared.
  static List<ResponderIncidentModel> sorted(
    List<ResponderIncidentModel> queue,
  ) => [...queue]..sort(workingOrder);
}
