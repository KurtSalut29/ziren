import 'responder_incident_model.dart';
import 'responder_vocabulary.dart';

/// One day's worth of closed work.
class DayCount {
  const DayCount({required this.day, required this.count});

  /// Local midnight for the day this counts.
  final DateTime day;
  final int count;
}

/// The shapes the Home charts draw, derived from data the app already has.
///
/// WHY DERIVED HERE RATHER THAN FETCHED
///
/// `/responder/dashboard` returns scalars — counts and a median. It has no
/// series endpoint, and adding one would be a backend change for a chart. But
/// `/responder/history` already returns each closed incident with its
/// timestamps, so a per-day count is arithmetic on data that is already on the
/// device. Every figure these charts draw traces back to a row a dispatcher
/// created; none of it is generated to fill a shape.
///
/// THE CAP IS THE ONE HONEST PROBLEM, AND IT IS REPORTED
///
/// The history endpoint returns the 50 most recent closed incidents, not "all
/// of the last week". For a responder in Biliran those are the same thing —
/// nobody is closing fifty incidents in seven days. But "almost always the
/// same" is not "the same", and a bar chart that quietly undercounts is worse
/// than no chart: it reads as a slow week. [windowIsTruncated] detects exactly
/// the case where the cap could be hiding closures inside the window, and the
/// chart says so on screen when it does.
class ResponderTrends {
  const ResponderTrends._();

  /// How many closed incidents the history endpoint will return at most.
  /// Mirrors the limit in `ResponderRepository.getHistory`.
  static const int historyCap = 50;

  /// The moment a closed incident is filed under.
  ///
  /// `resolvedAt` for anything that reached an outcome; `createdAt` as the
  /// fallback for a cancelled incident that never did. Dropping those rows
  /// would make cancellations invisible in a record that is partly about how
  /// often they happen.
  static DateTime closedAt(ResponderIncidentModel i) =>
      i.resolvedAt ?? i.createdAt;

  static DateTime _midnight(DateTime t) => DateTime(t.year, t.month, t.day);

  /// Closed incidents per local day, oldest first, always exactly [days] long.
  ///
  /// Days with nothing closed are present with a count of zero. Omitting them
  /// would compress the axis and turn a quiet Tuesday into no Tuesday at all,
  /// which makes an irregular week look like a steady one.
  static List<DayCount> closedPerDay(
    List<ResponderIncidentModel> history, {
    int days = 7,
    DateTime? now,
  }) {
    final today = _midnight(now ?? DateTime.now());
    final start = today.subtract(Duration(days: days - 1));

    final buckets = <DateTime, int>{
      for (var i = 0; i < days; i++) start.add(Duration(days: i)): 0,
    };

    for (final incident in history) {
      final day = _midnight(closedAt(incident).toLocal());
      if (buckets.containsKey(day)) {
        buckets[day] = buckets[day]! + 1;
      }
    }

    return [
      for (var i = 0; i < days; i++)
        DayCount(
          day: start.add(Duration(days: i)),
          count: buckets[start.add(Duration(days: i))]!,
        ),
    ];
  }

  /// True when the 50-row cap could be hiding closures inside the window.
  ///
  /// Both conditions have to hold: the list came back full, AND its oldest row
  /// still falls inside the window. A full list whose oldest row predates the
  /// window proves the window is completely covered — the cap cut off history
  /// older than anything being charted, which costs the chart nothing.
  static bool windowIsTruncated(
    List<ResponderIncidentModel> history, {
    int days = 7,
    DateTime? now,
  }) {
    if (history.length < historyCap) return false;

    final today = _midnight(now ?? DateTime.now());
    final start = today.subtract(Duration(days: days - 1));

    DateTime? oldest;
    for (final i in history) {
      final t = closedAt(i);
      if (oldest == null || t.isBefore(oldest)) oldest = t;
    }
    if (oldest == null) return false;

    return !oldest.isBefore(start);
  }

  /// How many of each severity tier, worst first.
  ///
  /// Keyed by [ResponderVocabulary.tiers] plus a null bucket for anything the
  /// rubric never scored. Tiers with a count of zero are kept so the legend
  /// has a stable shape and a missing tier reads as "none of these" rather
  /// than as a category that does not exist.
  static Map<String, int> severityMix(List<ResponderIncidentModel> incidents) {
    final mix = <String, int>{
      for (final tier in ResponderVocabulary.tiers) tier: 0,
      'unscored': 0,
    };

    for (final i in incidents) {
      final key =
          ResponderVocabulary.tiers.contains(i.severity)
              ? i.severity!
              : 'unscored';
      mix[key] = mix[key]! + 1;
    }
    return mix;
  }

  /// Median minutes from dispatch to close, over the incidents that have both
  /// timestamps.
  ///
  /// Median rather than mean, matching the backend's own figure: one incident
  /// that ran overnight because a road was cut drags a mean far enough to make
  /// a good month look like a bad one.
  ///
  /// Null when nothing qualifies — never zero. A responder who has closed
  /// nothing has no typical time, and printing "0m" would congratulate them
  /// for it.
  static double? medianMinutes(List<ResponderIncidentModel> incidents) {
    final spans = <double>[];
    for (final i in incidents) {
      final from = i.dispatchedAt;
      final to = i.resolvedAt;
      if (from == null || to == null) continue;
      if (i.status != 'resolved') continue;
      final minutes = to.difference(from).inSeconds / 60.0;
      if (minutes >= 0) spans.add(minutes);
    }
    if (spans.isEmpty) return null;

    spans.sort();
    final mid = spans.length ~/ 2;
    return spans.length.isOdd
        ? spans[mid]
        : (spans[mid - 1] + spans[mid]) / 2.0;
  }
}
