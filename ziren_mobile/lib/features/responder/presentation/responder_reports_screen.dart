import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/home_kit.dart';
import '../domain/responder_incident_model.dart';
import '../domain/responder_provider.dart';
import '../domain/responder_trends.dart';
import '../domain/responder_vocabulary.dart';
import 'widgets/responder_charts.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Every report that has been assigned to this responder — open and closed.
///
/// WHAT REPLACED WHAT
///
/// This tab used to be Stats. Its figures now live on Home, where they sit
/// beside the work they describe instead of a tap away from it, and the slot
/// they vacated goes to the one thing the responder had no way to reach: the
/// full record of what has been sent to them.
///
/// Before this, the open assignments were on Home and the closed ones were on
/// a screen nothing linked to. A responder asked "did I get that fire on
/// Tuesday" had to remember whether it was still open to know which screen to
/// look on — a question about the app, standing in front of a question about
/// the work.
///
/// ONE LIST, THREE FILTERS, AND THE DEFAULT IS EVERYTHING
///
/// The filters are a view of one list, not three lists. "All" leads because
/// the question that brings someone here is usually "where is that report",
/// and the answer must not depend on guessing its state first.
///
/// The order is not chronological throughout, deliberately. Open assignments
/// come first in the order they should be worked — worst tier, then longest
/// waiting — and closed ones follow newest-first. A single date sort would
/// bury a critical call that arrived this morning under twelve things finished
/// this afternoon.
class ResponderReportsScreen extends StatefulWidget {
  const ResponderReportsScreen({super.key});

  @override
  State<ResponderReportsScreen> createState() => _ResponderReportsScreenState();
}

enum _Filter { all, active, closed }

enum _View { list, record }

class _ResponderReportsScreenState extends State<ResponderReportsScreen> {
  _Filter _filter = _Filter.all;
  _View _view = _View.list;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final p = context.read<ResponderProvider>();
      p.loadQueue();
      p.loadHistory();
    });
  }

  Future<void> _refresh() async {
    final p = context.read<ResponderProvider>();
    await Future.wait([p.loadQueue(), p.loadHistory()]);
  }

  /// Open assignments in working order, then closed ones newest-first.
  List<ResponderIncidentModel> _rows(ResponderProvider p) {
    final active = ResponderVocabulary.sorted(p.queue);
    final closed = [...p.history]..sort((a, b) {
      // resolvedAt is null on a cancelled incident that was never resolved;
      // createdAt is the honest fallback rather than dropping the row.
      final at = a.resolvedAt ?? a.createdAt;
      final bt = b.resolvedAt ?? b.createdAt;
      return bt.compareTo(at);
    });

    return switch (_filter) {
      _Filter.all => [...active, ...closed],
      _Filter.active => active,
      _Filter.closed => closed,
    };
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ResponderProvider>();
    final rows = _rows(p);
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final loading = p.loadingQueue || p.loadingHistory;
    final error = p.queueError ?? p.historyError;

    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: ZirenTokens.brandOrange,
          onRefresh: _refresh,
          child: ListView(
            // Always scrollable, so pull-to-refresh works on a screen whose
            // content fits — which for a responder with nothing assigned is
            // exactly the screen they most want to refresh.
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(0, 0, 0, 96 + bottomInset),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  kHomeGutter,
                  ZirenTokens.space24,
                  kHomeGutter,
                  0,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        'My reports',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          color: ZirenTokens.textPrimary,
                        ),
                      ),
                    ),
                    if (loading)
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: ZirenTokens.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(kHomeGutter, 4, kHomeGutter, 0),
                child: Text(
                  'Everything a dispatcher has sent you.',
                  style: TextStyle(
                    fontSize: 13,
                    color: ZirenTokens.textSecondary,
                  ),
                ),
              ),

              // ── List / Record ───────────────────────────────
              //
              // Two different questions, not one long scroll: "where is that
              // report" (List) and "how has my shift/record been" (Record).
              // Stacking a chart section below a potentially-long list is the
              // same "too much on one screen" mistake Home just had — this
              // avoids repeating it by making it a choice instead of a scroll.
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  kHomeGutter,
                  ZirenTokens.space16,
                  kHomeGutter,
                  0,
                ),
                child: _ViewToggle(
                  view: _view,
                  onChanged: (v) => setState(() => _view = v),
                ),
              ),

              if (error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    kHomeGutter,
                    ZirenTokens.space16,
                    kHomeGutter,
                    0,
                  ),
                  child: _ErrorNote(message: error),
                ),

              // ── Filters ───────────────────────────────────
              if (_view == _View.list) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    kHomeGutter,
                    ZirenTokens.space16,
                    kHomeGutter,
                    0,
                  ),
                  child: Row(
                    children: [
                      _FilterChip(
                        label: 'All',
                        count: p.queue.length + p.history.length,
                        selected: _filter == _Filter.all,
                        onTap: () => setState(() => _filter = _Filter.all),
                      ),
                      const SizedBox(width: ZirenTokens.space8),
                      _FilterChip(
                        label: 'Open',
                        count: p.queue.length,
                        selected: _filter == _Filter.active,
                        onTap: () => setState(() => _filter = _Filter.active),
                      ),
                      const SizedBox(width: ZirenTokens.space8),
                      _FilterChip(
                        label: 'Closed',
                        count: p.history.length,
                        selected: _filter == _Filter.closed,
                        onTap: () => setState(() => _filter = _Filter.closed),
                      ),
                    ],
                  ),
                ),

                // ── The list ──────────────────────────────────
                if (rows.isEmpty && !loading)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      kHomeGutter,
                      ZirenTokens.space32,
                      kHomeGutter,
                      0,
                    ),
                    child: _EmptyNote(filter: _filter),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      kHomeGutter,
                      ZirenTokens.space12,
                      kHomeGutter,
                      0,
                    ),
                    child: Column(
                      children: [
                        for (final r in rows) ...[
                          ReportRow(
                            incident: r,
                            onTap:
                                () =>
                                    context.push('/responder/incident/${r.id}'),
                          ),
                          const SizedBox(height: ZirenTokens.space8),
                        ],
                      ],
                    ),
                  ),

                // The cap is real and worth saying out loud. /responder/history
                // returns the 50 most recent closed incidents; a responder who
                // has closed more than that will not find the oldest here, and
                // would otherwise conclude the record had lost them.
                if (_filter != _Filter.active && p.history.length >= 50)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      kHomeGutter,
                      ZirenTokens.space12,
                      kHomeGutter,
                      0,
                    ),
                    child: Text(
                      'Showing your 50 most recent closed incidents.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: ZirenTokens.textMuted,
                      ),
                    ),
                  ),
              ] else
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    kHomeGutter,
                    ZirenTokens.space16,
                    kHomeGutter,
                    0,
                  ),
                  child: _RecordView(
                    history: p.history,
                    medianResponseMinutes: p.medianResponseMinutes,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Pieces ────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? ZirenTokens.brandOrange : ZirenTokens.surfaceCard,
            borderRadius: BorderRadius.circular(ZirenTokens.radius12),
            border: Border.all(
              color:
                  selected
                      ? ZirenTokens.brandOrange
                      : ZirenTokens.surfaceBorder,
            ),
          ),
          child: Text(
            '$label · $count',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color:
                  selected
                      ? ZirenTokens.textInverse
                      : ZirenTokens.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// One report in the list.
///
/// Public because the design-preview test renders it directly — a widget only
/// reachable through a live provider is a widget nothing can screenshot.
class ReportRow extends StatelessWidget {
  const ReportRow({super.key, required this.incident, required this.onTap});

  final ResponderIncidentModel incident;
  final VoidCallback onTap;

  /// The time this row is about.
  ///
  /// A closed incident is filed by when it closed; an open one by how long it
  /// has been waiting. Showing "reported 3d ago" on something finished last
  /// week answers a question nobody asked.
  String get _when {
    if (ResponderVocabulary.isClosed(incident)) {
      final t = incident.resolvedAt ?? incident.createdAt;
      return 'Closed ${ResponderVocabulary.elapsed(t)} ago';
    }
    return 'Waiting ${ResponderVocabulary.elapsed(incident.createdAt)}';
  }

  @override
  Widget build(BuildContext context) {
    final tint = ResponderVocabulary.color(incident.severity);
    final closed = ResponderVocabulary.isClosed(incident);
    final title =
        incident.reportText.isEmpty
            ? incident.categoryLabel
            : incident.reportText;

    return Material(
      color: ZirenTokens.surfaceCard,
      borderRadius: BorderRadius.circular(kCardRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(kCardRadius),
        child: Container(
          padding: const EdgeInsets.all(ZirenTokens.space12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(kCardRadius),
            border: Border.all(
              color: ZirenTokens.surfaceBorder.withValues(alpha: 0.8),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // A closed incident's tile is muted. The colour is still there
              // in the severity word beside the title, so nothing is lost —
              // but a wall of red for work already done reads as a wall of
              // emergencies, which is the opposite of what it is.
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color:
                      closed
                          ? ZirenTokens.surfaceRaised
                          : tint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(ZirenTokens.radius12),
                ),
                child: Icon(
                  ResponderVocabulary.icon(incident.severity),
                  size: 18,
                  color: closed ? ZirenTokens.textMuted : tint,
                ),
              ),
              const SizedBox(width: ZirenTokens.space10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                        color: ZirenTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${incident.locationAddress ?? incident.stationName ?? 'Location unknown'} · ${incident.shortId}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: ZirenTokens.textMuted,
                      ),
                    ),
                    const SizedBox(height: ZirenTokens.space8),
                    Row(
                      children: [
                        _Pill(
                          text: ResponderVocabulary.statusShort(incident),
                          tint: ResponderVocabulary.statusColor(
                            incident.status,
                          ),
                          bg: ResponderVocabulary.statusBackground(
                            incident.status,
                          ),
                        ),
                        const SizedBox(width: ZirenTokens.space6),
                        _Pill(
                          text: ResponderVocabulary.label(incident.severity),
                          tint: closed ? ZirenTokens.textMuted : tint,
                          bg:
                              closed
                                  ? ZirenTokens.surfaceRaised
                                  : tint.withValues(alpha: 0.10),
                        ),
                        const Spacer(),
                        Flexible(
                          child: Text(
                            _when,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: ZirenTokens.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                LucideIcons.chevron_right,
                size: 18,
                color: ZirenTokens.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.tint, required this.bg});

  final String text;
  final Color tint;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(ZirenTokens.radius32),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.3,
          color: tint,
        ),
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote({required this.filter});

  final _Filter filter;

  @override
  Widget build(BuildContext context) {
    final (icon, title, body) = switch (filter) {
      _Filter.active => (
        LucideIcons.circle_check,
        'Nothing open',
        'No assignment is waiting on you right now.',
      ),
      _Filter.closed => (
        LucideIcons.rotate_ccw,
        'Nothing closed yet',
        'Incidents you finish will be filed here.',
      ),
      _Filter.all => (
        LucideIcons.inbox,
        'No reports yet',
        'Anything a dispatcher sends you will appear here, open or closed.',
      ),
    };

    return Column(
      children: [
        Icon(icon, size: 34, color: ZirenTokens.textDisabled),
        const SizedBox(height: ZirenTokens.space12),
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: ZirenTokens.textSecondary,
          ),
        ),
        const SizedBox(height: ZirenTokens.space4),
        Text(
          body,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.4,
            color: ZirenTokens.textMuted,
          ),
        ),
      ],
    );
  }
}

class _ErrorNote extends StatelessWidget {
  const _ErrorNote({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space12),
      decoration: BoxDecoration(
        color: ZirenTokens.systemErrorBg,
        borderRadius: BorderRadius.circular(ZirenTokens.radius12),
        border: Border.all(
          color: ZirenTokens.systemError.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            LucideIcons.cloud_off,
            size: 16,
            color: ZirenTokens.systemError,
          ),
          const SizedBox(width: ZirenTokens.space8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: ZirenTokens.systemError,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.view, required this.onChanged});

  final _View view;
  final ValueChanged<_View> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceRaised,
        borderRadius: BorderRadius.circular(ZirenTokens.radius12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ViewToggleSegment(
              label: 'List',
              selected: view == _View.list,
              onTap: () => onChanged(_View.list),
            ),
          ),
          Expanded(
            child: _ViewToggleSegment(
              label: 'Record',
              selected: view == _View.record,
              onTap: () => onChanged(_View.record),
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewToggleSegment extends StatelessWidget {
  const _ViewToggleSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: ZirenTokens.motionBase,
        curve: Curves.easeOut,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? ZirenTokens.surfaceCard : Colors.transparent,
          borderRadius: BorderRadius.circular(ZirenTokens.radius8),
          boxShadow: selected ? ZirenTokens.shadowSm : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: selected ? ZirenTokens.textPrimary : ZirenTokens.textMuted,
          ),
        ),
      ),
    );
  }
}

/// Shift analytics — the charts that used to live on Home, moved here so
/// "how is my shift/record looking" has one home separate from Home's "what
/// do I do right now". Every figure traces back to `history`/`dashboard`
/// data the app already fetches; see ResponderTrends for why these are
/// derived on the device rather than a backend series endpoint.
class _RecordView extends StatelessWidget {
  const _RecordView({
    required this.history,
    required this.medianResponseMinutes,
  });

  final List<ResponderIncidentModel> history;
  final double? medianResponseMinutes;

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return const _EmptyRecordNote();
    }

    final closedWeek = ResponderTrends.closedPerDay(history);
    final weekTruncated = ResponderTrends.windowIsTruncated(history);
    final closedMix = ResponderTrends.severityMix(history);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClosedPerDayChart(days: closedWeek, truncated: weekTruncated),
        const SizedBox(height: ZirenTokens.space12),
        SeverityMixRing(
          mix: closedMix,
          title: 'What you have closed',
          emptyNote:
              'Nothing closed yet. Once you finish an incident, the mix of '
              'what you handle shows up here.',
        ),
        const SizedBox(height: ZirenTokens.space12),
        _TypicalResponseCard(median: medianResponseMinutes),
      ],
    );
  }
}

class _TypicalResponseCard extends StatelessWidget {
  const _TypicalResponseCard({required this.median});

  final double? median;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space16),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        borderRadius: BorderRadius.circular(ZirenTokens.radius16),
        border: Border.all(color: ZirenTokens.surfaceBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: ZirenTokens.statusProcessing.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(
              LucideIcons.timer,
              size: 18,
              color: ZirenTokens.statusProcessing,
            ),
          ),
          const SizedBox(width: ZirenTokens.space12),
          Expanded(
            child: Text(
              AppLocalizations.of(context).respProfileTypicalResponse,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: ZirenTokens.textPrimary,
              ),
            ),
          ),
          Text(
            ResponderVocabulary.minutes(median),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: ZirenTokens.statusProcessing,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyRecordNote extends StatelessWidget {
  const _EmptyRecordNote();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: ZirenTokens.space32),
      child: Column(
        children: [
          Icon(
            LucideIcons.trending_up,
            size: 34,
            color: ZirenTokens.textDisabled,
          ),
          SizedBox(height: ZirenTokens.space12),
          Text(
            'Nothing to show yet',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: ZirenTokens.textSecondary,
            ),
          ),
          SizedBox(height: ZirenTokens.space4),
          Text(
            'Close your first incident and your shift record will show up '
            'here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: ZirenTokens.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
