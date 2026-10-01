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
import 'widgets/responder_ui.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import '../../demo/presentation/demo_anchor.dart';

/// Every report that has been assigned to this responder — open and closed.
///
/// Two views of one record: List ("where is that report") and Record ("how
/// has my work been"). The list leads with what is still open, in working
/// order, under its own heading, then the closed calls grouped by when they
/// closed (this week, last week, earlier) — responders found one long
/// undivided list hard to scan, and "On Scene · Waiting 9d" beside
/// "Resolved · Closed 9d ago" did not say which ones still needed them.
///
/// Search matches the report text, the address, the landmark, the category
/// and the INC number, so a report can be found by whatever the crew
/// remembers about it.
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
  final _search = TextEditingController();
  String _query = '';

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

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final p = context.read<ResponderProvider>();
    await Future.wait([p.loadQueue(), p.loadHistory()]);
  }

  bool _matches(ResponderIncidentModel i) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final hay =
        [
          i.reportText,
          i.locationAddress ?? '',
          i.landmarkNote ?? '',
          i.categoryLabel,
          i.shortId,
          ResponderVocabulary.label(i.severity),
        ].join(' ').toLowerCase();
    return q.split(RegExp(r'\s+')).every(hay.contains);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final p = context.watch<ResponderProvider>();
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final loading = p.loadingQueue || p.loadingHistory;
    final error = p.queueError ?? p.historyError;

    final open = ResponderVocabulary.sorted(p.queue).where(_matches).toList();
    final closed =
        ([...p.history]..sort(
          (a, b) => ResponderTrends.closedAt(
            b,
          ).compareTo(ResponderTrends.closedAt(a)),
        )).where(_matches).toList();

    return Scaffold(
      backgroundColor: kHomeCanvas,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: ZirenTokens.brandOrange,
          onRefresh: _refresh,
          child: ListView(
            // Always scrollable, so pull-to-refresh works on a short list.
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(0, 0, 0, 96 + bottomInset),
            children: [
              // ── Title ─────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  kHomeGutter,
                  ZirenTokens.space20,
                  kHomeGutter,
                  0,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.respReportsTitle,
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.6,
                              color: ZirenTokens.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            t.respReportsSubtitle,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: ZirenTokens.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (loading)
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: ZirenTokens.textMuted,
                        ),
                      ),
                  ],
                ),
              ),

              // ── List / Record ─────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  kHomeGutter,
                  ZirenTokens.space16,
                  kHomeGutter,
                  0,
                ),
                child: DemoAnchor(
                  id: 'rrep.toggle',
                  child: _ViewToggle(
                    view: _view,
                    listLabel: t.respViewList,
                    recordLabel: t.respViewRecord,
                    onChanged: (v) => setState(() => _view = v),
                  ),
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

              if (_view == _View.list)
                ..._listView(t, p, open, closed, loading)
              else
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

  List<Widget> _listView(
    AppLocalizations t,
    ResponderProvider p,
    List<ResponderIncidentModel> open,
    List<ResponderIncidentModel> closed,
    bool loading,
  ) {
    final showOpen = _filter != _Filter.closed;
    final showClosed = _filter != _Filter.active;
    final nothing =
        (!showOpen || open.isEmpty) && (!showClosed || closed.isEmpty);

    // Closed calls grouped by the week they closed in.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thisMonday = today.subtract(Duration(days: today.weekday - 1));
    final lastMonday = thisMonday.subtract(const Duration(days: 7));
    final groups = <(String, List<ResponderIncidentModel>)>[
      (t.respSectionThisWeek, []),
      (t.respSectionLastWeek, []),
      (t.respSectionOlder, []),
    ];
    for (final i in closed) {
      final at = ResponderTrends.closedAt(i).toLocal();
      final g =
          !at.isBefore(thisMonday) ? 0 : (!at.isBefore(lastMonday) ? 1 : 2);
      groups[g].$2.add(i);
    }

    // The first row on screen, for the demo to point at.
    final firstId =
        showOpen && open.isNotEmpty
            ? open.first.id
            : (showClosed && closed.isNotEmpty ? closed.first.id : null);

    Widget rows(List<ResponderIncidentModel> list) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: kHomeGutter),
      child: Column(
        children: [
          for (final r in list) ...[
            DemoAnchor(
              id: r.id == firstId ? 'rrep.first' : 'rrep.${r.id}',
              child: ReportRow(
                incident: r,
                onTap: () => context.push('/responder/incident/${r.id}'),
              ),
            ),
            const SizedBox(height: ZirenTokens.space8),
          ],
        ],
      ),
    );

    return [
      // ── Search ────────────────────────────────────
      Padding(
        padding: const EdgeInsets.fromLTRB(
          kHomeGutter,
          ZirenTokens.space16,
          kHomeGutter,
          0,
        ),
        child: DemoAnchor(
          id: 'rrep.search',
          child: TextField(
            controller: _search,
            onChanged: (v) => setState(() => _query = v),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: t.respSearchHint,
              prefixIcon: Icon(
                LucideIcons.search,
                size: 18,
                color: ZirenTokens.textMuted,
              ),
              suffixIcon:
                  _query.isEmpty
                      ? null
                      : IconButton(
                        tooltip: t.respCancel,
                        icon: Icon(
                          LucideIcons.x,
                          size: 18,
                          color: ZirenTokens.textMuted,
                        ),
                        onPressed:
                            () => setState(() {
                              _search.clear();
                              _query = '';
                            }),
                      ),
              filled: true,
              fillColor: ZirenTokens.surfaceCard,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: ZirenTokens.surfaceBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: ZirenTokens.surfaceBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                  color: ZirenTokens.brandOrange,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ),
      ),

      // ── Filters ───────────────────────────────────
      Padding(
        padding: const EdgeInsets.fromLTRB(
          kHomeGutter,
          ZirenTokens.space12,
          kHomeGutter,
          0,
        ),
        child: DemoAnchor(
          id: 'rrep.filters',
          child: Row(
            children: [
              _FilterChip(
                label: t.respFilterAll,
                count: p.queue.length + p.history.length,
                selected: _filter == _Filter.all,
                onTap: () => setState(() => _filter = _Filter.all),
              ),
              const SizedBox(width: ZirenTokens.space8),
              _FilterChip(
                label: t.respFilterOpen,
                count: p.queue.length,
                selected: _filter == _Filter.active,
                attention: p.queue.isNotEmpty,
                onTap: () => setState(() => _filter = _Filter.active),
              ),
              const SizedBox(width: ZirenTokens.space8),
              _FilterChip(
                label: t.respFilterClosed,
                count: p.history.length,
                selected: _filter == _Filter.closed,
                onTap: () => setState(() => _filter = _Filter.closed),
              ),
            ],
          ),
        ),
      ),

      if (nothing && !loading)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            kHomeGutter,
            ZirenTokens.space32,
            kHomeGutter,
            0,
          ),
          child:
              _query.trim().isNotEmpty
                  ? _EmptyNote(
                    icon: LucideIcons.search_x,
                    title: t.respSearchEmpty(_query.trim()),
                    body: '',
                  )
                  : switch (_filter) {
                    _Filter.active => _EmptyNote(
                      icon: LucideIcons.circle_check,
                      title: t.respEmptyOpenTitle,
                      body: t.respEmptyOpenBody,
                    ),
                    _Filter.closed => _EmptyNote(
                      icon: LucideIcons.rotate_ccw,
                      title: t.respEmptyClosedTitle,
                      body: t.respEmptyClosedBody,
                    ),
                    _Filter.all => _EmptyNote(
                      icon: LucideIcons.inbox,
                      title: t.respEmptyAllTitle,
                      body: t.respEmptyAllBody,
                    ),
                  },
        ),

      if (showOpen && open.isNotEmpty) ...[
        _GroupHeading(
          t.respSectionOpen('${open.length}'),
          color: ZirenTokens.statusDispatched,
        ),
        rows(open),
      ],

      if (showClosed)
        for (final g in groups)
          if (g.$2.isNotEmpty) ...[
            _GroupHeading('${g.$1} · ${g.$2.length}'),
            rows(g.$2),
          ],

      // /responder/history returns the 50 most recent closed incidents.
      if (showClosed && p.history.length >= ResponderTrends.historyCap)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            kHomeGutter,
            ZirenTokens.space8,
            kHomeGutter,
            0,
          ),
          child: Text(
            t.respHistoryCapNote,
            style: TextStyle(fontSize: 11.5, color: ZirenTokens.textMuted),
          ),
        ),
    ];
  }
}

// ── Pieces ────────────────────────────────────────────────────

class _GroupHeading extends StatelessWidget {
  const _GroupHeading(this.text, {this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        kHomeGutter,
        ZirenTokens.space20,
        kHomeGutter,
        ZirenTokens.space10,
      ),
      child: Row(
        children: [
          if (color != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(child: ResponderEyebrow(text, color: color)),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.attention = false,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  /// Open calls exist: the count is drawn in the "needs you" orange.
  final bool attention;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: '$label, $count',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color:
                  selected ? ZirenTokens.textPrimary : ZirenTokens.surfaceCard,
              borderRadius: BorderRadius.circular(ZirenTokens.radius32),
              border: Border.all(
                color:
                    selected
                        ? ZirenTokens.textPrimary
                        : ZirenTokens.surfaceBorder,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color:
                          selected
                              ? ZirenTokens.surfaceCard
                              : ZirenTokens.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color:
                        attention
                            ? ZirenTokens.statusDispatched
                            : (selected
                                ? ZirenTokens.surfaceCard.withValues(alpha: 0.2)
                                : ZirenTokens.surfaceRaised),
                    borderRadius: BorderRadius.circular(ZirenTokens.radius32),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                      color:
                          attention
                              ? Colors.white
                              : (selected
                                  ? ZirenTokens.surfaceCard
                                  : ZirenTokens.textSecondary),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One report in a list (Reports, and Home's "Recently closed").
///
/// Open calls carry their severity stripe and full-colour chips; closed ones
/// go quiet (neutral tile, greyed severity) so a list of finished work does
/// not read as a list of emergencies. The time says the thing that matters
/// for each: how long since it was assigned, or since it closed.
class ReportRow extends StatelessWidget {
  const ReportRow({super.key, required this.incident, required this.onTap});

  final ResponderIncidentModel incident;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final closed = ResponderVocabulary.isClosed(incident);
    final title =
        incident.reportText.isEmpty
            ? incident.categoryLabel
            : ResponderVocabulary.reportText(incident.reportText);
    final when =
        closed
            ? t.respClosedAgo(
              ResponderVocabulary.elapsed(ResponderTrends.closedAt(incident)),
            )
            : t.respAssignedAgo(
              ResponderVocabulary.elapsed(
                incident.dispatchedAt ?? incident.createdAt,
              ),
            );

    return ResponderCard(
      stripe: closed ? null : ResponderVocabulary.color(incident.severity),
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CategoryTile(
            category: incident.incidentCategory,
            severity: incident.severity,
            closed: closed,
            size: 40,
          ),
          const SizedBox(width: ZirenTokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                    color:
                        closed
                            ? ZirenTokens.textSecondary
                            : ZirenTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${incident.locationAddress ?? t.respNoLocation} · ${incident.shortId}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: ZirenTokens.textMuted,
                  ),
                ),
                const SizedBox(height: ZirenTokens.space8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    PhaseChip(incident: incident),
                    SeverityChip(severity: incident.severity, muted: closed),
                    if (incident.sosFlag && !closed) const SosChip(),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      closed ? LucideIcons.circle_check : LucideIcons.clock,
                      size: 12,
                      color: ZirenTokens.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        when,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
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
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Icon(
              LucideIcons.chevron_right,
              size: 18,
              color: ZirenTokens.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: ZirenTokens.surfaceRaised,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 28, color: ZirenTokens.textMuted),
        ),
        const SizedBox(height: ZirenTokens.space12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: ZirenTokens.textSecondary,
          ),
        ),
        if (body.isNotEmpty) ...[
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
  const _ViewToggle({
    required this.view,
    required this.listLabel,
    required this.recordLabel,
    required this.onChanged,
  });

  final _View view;
  final String listLabel;
  final String recordLabel;
  final ValueChanged<_View> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ViewToggleSegment(
              icon: LucideIcons.list,
              label: listLabel,
              selected: view == _View.list,
              onTap: () => onChanged(_View.list),
            ),
          ),
          Expanded(
            child: _ViewToggleSegment(
              icon: LucideIcons.chart_no_axes_column,
              label: recordLabel,
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
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: ZirenTokens.motionBase,
          curve: Curves.easeOut,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? ZirenTokens.surfaceCard : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            boxShadow: selected ? ZirenTokens.shadowSm : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color:
                    selected ? ZirenTokens.brandOrange : ZirenTokens.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color:
                      selected
                          ? ZirenTokens.textPrimary
                          : ZirenTokens.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// How the responder's work has been: four figures, closures over time, the
/// severity mix and the kinds of call. Every figure traces back to the
/// history/dashboard data the app already fetches (see ResponderTrends).
class _RecordView extends StatelessWidget {
  const _RecordView({
    required this.history,
    required this.medianResponseMinutes,
  });

  final List<ResponderIncidentModel> history;
  final double? medianResponseMinutes;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (history.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: ZirenTokens.space32),
        child: _EmptyNote(
          icon: LucideIcons.trending_up,
          title: t.respRecEmptyTitle,
          body: t.respRecEmptyBody,
        ),
      );
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weeks = ResponderTrends.closedPerWeek(history);
    final weekSpan = today.difference(weeks.first.day).inDays + 1;
    final truncated = ResponderTrends.windowIsTruncated(
      history,
      days: weekSpan,
    );
    final mix = ResponderTrends.severityMix(history);
    final last = ResponderTrends.lastClosedAt(history);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── The four figures ───────────────────────────
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: ZirenTokens.space10,
          crossAxisSpacing: ZirenTokens.space10,
          childAspectRatio: 1.9,
          children: [
            _Figure(
              icon: LucideIcons.circle_check_big,
              tone: ZirenTokens.statusResolved,
              value: '${history.length}',
              label: t.respRecTotalClosed,
            ),
            _Figure(
              icon: LucideIcons.calendar_days,
              tone: ZirenTokens.textSecondary,
              value: '${ResponderTrends.closedThisWeek(history)}',
              label: t.respRecThisWeek,
            ),
            _Figure(
              icon: ZirenTokens.severityCriticalIcon,
              tone: ZirenTokens.severityCritical,
              value: '${mix['critical'] ?? 0}',
              label: t.respRecCritical,
            ),
            _Figure(
              icon: LucideIcons.timer,
              tone: ZirenTokens.textSecondary,
              value: ResponderVocabulary.minutes(medianResponseMinutes),
              label: t.respRecTypical,
            ),
          ],
        ),
        const SizedBox(height: ZirenTokens.space12),
        ClosedTrendCard(
          title: t.respRecChartTitle,
          weekBars: weeks,
          dayBars: ResponderTrends.closedPerDay(history),
          labels: (t.respRec7Days, t.respRec8Weeks),
          totalLabel: (n) => t.respRecTotal('$n'),
          emptyNote:
              last == null
                  ? t.respRecNoneEver
                  : t.respRecNoneInRange(ResponderVocabulary.elapsed(last)),
          truncatedNote: truncated ? t.respRecTruncated : null,
        ),
        const SizedBox(height: ZirenTokens.space12),
        SeverityMixRing(
          mix: mix,
          title: t.respRecMixTitle,
          emptyNote: t.respRecEmptyBody,
          centerLabel: t.respRecReports,
          trailingFormat: (n) => t.respRecTotal('$n'),
        ),
        const SizedBox(height: ZirenTokens.space12),
        CategoryMixBars(
          title: t.respRecCategoryTitle,
          entries: ResponderTrends.categoryMix(history),
          labelOf: ResponderVocabulary.categoryLabel,
          iconOf: ResponderVocabulary.categoryIcon,
        ),
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.icon,
    required this.tone,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color tone;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final quiet = value == '0' || value == '—';
    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space12),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: ZirenTokens.surfaceBorder.withValues(alpha: 0.8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: quiet ? ZirenTokens.textMuted : tone),
              const SizedBox(width: 6),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 24,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      color:
                          quiet
                              ? ZirenTokens.textMuted
                              : ZirenTokens.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: ZirenTokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
