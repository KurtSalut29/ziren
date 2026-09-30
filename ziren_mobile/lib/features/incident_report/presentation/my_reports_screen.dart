import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../domain/incident_category_style.dart';
import '../domain/incident_model.dart';
import '../domain/incident_provider.dart';
import 'incident_labels.dart';
import 'report_detail_screen.dart';
import 'widgets/report_stage_track.dart';
import 'widgets/review_notice.dart';
import 'widgets/transcript_prompt.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// My Reports — a card per report, newest first, grouped by filter.
///
/// Each card is a scannable summary; tapping it pushes [ReportDetailScreen]
/// for the full report — the stage rail, every timestamp, and the actions
/// (add information, rate service, move to Trash) that used to live inside
/// an inline dropdown here. That dropdown ran out of room once Trash needed
/// its own confirmation step and a permanent-deletion countdown, and a card
/// that grows taller in place is a worse way to show "all the details" than
/// a screen built for exactly that.
class MyReportsScreen extends StatefulWidget {
  const MyReportsScreen({super.key});

  @override
  State<MyReportsScreen> createState() => _MyReportsScreenState();
}

class _MyReportsScreenState extends State<MyReportsScreen> {
  ReportFilter _filter = ReportFilter.lahat;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<IncidentProvider>();
      if (!provider.loadingIncidents && provider.myIncidents.isEmpty) {
        provider.loadMyIncidents();
      }
      // Backs the "how far is this from me now" line on each card — see
      // _ReportCard's location row. Never blocks the list from showing;
      // cards with no fix yet just omit the distance.
      if (provider.currentPosition == null) provider.fetchLocation();
    });
  }

  bool _isOpen(IncidentModel i) =>
      i.status != 'resolved' && i.status != 'cancelled';

  /// Withdrawn by the resident. Kept out of every other filter.
  ///
  /// These used to fall into "Done" alongside resolved reports, which reads as
  /// "this was handled" for something nobody ever attended — the opposite of
  /// what happened. A report the resident took back is its own outcome.
  ///
  /// NOT every cancelled report. An agency rejection is also status
  /// `cancelled`, and it used to land in Trash too - so a resident whose report
  /// an agency had just turned down found it in a bin, with no word about why.
  /// A rejected report stays in the live list, marked Rejected, with the
  /// reason on the card.
  bool _isTrashed(IncidentModel i) => i.isWithdrawn;

  List<IncidentModel> _visible(List<IncidentModel> all) => switch (_filter) {
    // "All" means all the live history. Withdrawn reports are reachable only
    // from Trash, the same way a deleted file is not also still in the folder.
    ReportFilter.lahat => all.where((i) => !_isTrashed(i)).toList(),
    ReportFilter.bukas => all.where(_isOpen).toList(),
    ReportFilter.tapos => all.where((i) => !_isOpen(i) && !_isTrashed(i)).toList(),
    ReportFilter.basura => all.where(_isTrashed).toList(),
  };

  /// Buckets used as rail section breaks. Coarse on purpose — an exact
  /// timestamp matters on one report, not across a history.
  String _bucket(AppLocalizations l10n, DateTime t) {
    final now = DateTime.now();
    final days = now.difference(t).inDays;
    if (days == 0) return l10n.groupToday;
    if (days == 1) return l10n.groupYesterday;
    if (days < 7) return l10n.groupThisWeek;
    if (days < 30) return l10n.groupThisMonth;
    return l10n.groupOlder;
  }

  String _clock(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IncidentProvider>();
    final all = provider.myIncidents;
    final visible = _visible(all);
    final openCount = all.where(_isOpen).length;
    // The summary line counts the live history only. A withdrawn report is not
    // one of "your 5 reports" any more — it is in Trash, and counting it here
    // while "All" hides it would contradict the screen underneath.
    final counted = all.where((i) => !_isTrashed(i)).length;

    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      body: SafeArea(
        child: RefreshIndicator(
          color: ZirenTokens.brandOrange,
          onRefresh: () => provider.loadMyIncidents(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // ── Title block. No AppBar: a bar with a back arrow and a
              //    refresh icon is chrome, and this is a root tab.
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    ZirenTokens.space20,
                    ZirenTokens.space20,
                    ZirenTokens.space20,
                    ZirenTokens.space16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context).myReportsTitle,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.6,
                          height: 1.15,
                          color: ZirenTokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        counted == 0
                            ? AppLocalizations.of(context).noReportsYetBody
                            : openCount > 0
                            ? AppLocalizations.of(
                              context,
                            ).reportsOpenCount(openCount, counted)
                            : AppLocalizations.of(
                              context,
                            ).reportsAllDone(counted),
                        style: TextStyle(
                          fontSize: 14,
                          color: ZirenTokens.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (all.isNotEmpty)
                SliverToBoxAdapter(
                  child: ReportFilterRow(
                    active: _filter,
                    onChanged: (f) => setState(() => _filter = f),
                    counts: {
                      ReportFilter.lahat: counted,
                      ReportFilter.bukas: openCount,
                      ReportFilter.tapos:
                          all
                              .where((i) => !_isOpen(i) && !_isTrashed(i))
                              .length,
                      ReportFilter.basura: all.where(_isTrashed).length,
                    },
                  ),
                ),

              // ── Body ────────────────────────────────────
              if (provider.loadingIncidents && all.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (provider.incidentsError != null && all.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _ErrorState(
                    message: provider.incidentsError!,
                    onRetry: () => provider.loadMyIncidents(),
                  ),
                )
              else if (visible.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(filter: _filter),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    ZirenTokens.space16,
                    ZirenTokens.space4,
                    ZirenTokens.space16,
                    ZirenTokens.space32,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final incident = visible[index];
                      final bucket = _bucket(
                        AppLocalizations.of(context),
                        incident.createdAt,
                      );
                      final l10n = AppLocalizations.of(context);
                      final showBucket =
                          index == 0 ||
                          _bucket(l10n, visible[index - 1].createdAt) !=
                              bucket;
                      final bucketSize =
                          showBucket
                              ? visible
                                  .where(
                                    (i) => _bucket(l10n, i.createdAt) == bucket,
                                  )
                                  .length
                              : 0;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showBucket)
                            _BucketHeading(
                              label: bucket,
                              count: bucketSize,
                              first: index == 0,
                            ),
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: ZirenTokens.space12,
                            ),
                            child: _ReportCard(
                              incident: incident,
                              clock: _clock(incident.createdAt),
                              fromPosition: provider.currentPosition,
                              onTap:
                                  () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder:
                                          (_) => ReportDetailScreen(
                                            incident: incident,
                                          ),
                                    ),
                                  ),
                            ),
                          ),
                        ],
                      );
                    }, childCount: visible.length),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

enum ReportFilter { lahat, bukas, tapos, basura }

// ── Filter row ────────────────────────────────────────────────

/// The All / Active / Resolved / Trash chips.
///
/// Public only so a test can pump it at narrow widths and large system fonts:
/// as a Row it painted "RIGHT OVERFLOWED BY 14 PIXELS" on a 360dp phone.
@visibleForTesting
class ReportFilterRow extends StatelessWidget {
  const ReportFilterRow({
    super.key,
    required this.active,
    required this.onChanged,
    this.counts = const {},
  });

  final ReportFilter active;
  final ValueChanged<ReportFilter> onChanged;

  /// How many reports each filter holds, drawn beside its label. A filter
  /// missing from the map shows no count.
  final Map<ReportFilter, int> counts;

  static String _label(AppLocalizations l10n, ReportFilter f) => switch (f) {
    ReportFilter.lahat => l10n.filterAll,
    ReportFilter.bukas => l10n.filterOpen,
    ReportFilter.tapos => l10n.filterDone,
    ReportFilter.basura => l10n.filterTrash,
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZirenTokens.space16,
        0,
        ZirenTokens.space16,
        ZirenTokens.space12,
      ),
      // A Wrap, not a Row: four chips with "Resolved" and a larger system font
      // are wider than a 360dp phone, and a Row there paints the yellow-and-
      // black "RIGHT OVERFLOWED BY 14 PIXELS" stripe over the header (reported
      // by testers). A Wrap drops the last chip to a second line instead.
      child: Wrap(
        spacing: ZirenTokens.space6,
        runSpacing: ZirenTokens.space8,
        children:
            ReportFilter.values.map((f) {
              final selected = f == active;
              final count = counts[f];
              // Not Colors.white: the chip's own fill is ZirenTokens.textPrimary,
              // which is near-black in light mode but near-white in dark mode.
              // surfaceBase is that same pair's opposite extreme in both themes,
              // so it stays readable whichever theme flipped textPrimary.
              final fg =
                  selected ? ZirenTokens.surfaceBase : ZirenTokens.textSecondary;
              // Open reports still need someone: their count is drawn in the
              // "in progress" orange so it is noticed from across the list.
              final attention =
                  f == ReportFilter.bukas && (count ?? 0) > 0 && !selected;
              return Semantics(
                button: true,
                selected: selected,
                child: GestureDetector(
                  onTap: () => onChanged(f),
                  child: AnimatedContainer(
                    duration: ZirenTokens.motionPress,
                    height: 38,
                    padding: EdgeInsets.only(
                      left: ZirenTokens.space12,
                      right:
                          count == null
                              ? ZirenTokens.space12
                              : ZirenTokens.space6,
                    ),
                    decoration: BoxDecoration(
                      color:
                          selected
                              ? ZirenTokens.textPrimary
                              : ZirenTokens.surfaceCard,
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
                        Text(
                          _label(AppLocalizations.of(context), f),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: fg,
                          ),
                        ),
                        if (count != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            constraints: const BoxConstraints(minWidth: 20),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  attention
                                      ? ZirenTokens.statusDispatched
                                      : selected
                                      ? ZirenTokens.surfaceBase.withValues(
                                        alpha: 0.18,
                                      )
                                      : ZirenTokens.surfaceRaised,
                              borderRadius: BorderRadius.circular(
                                ZirenTokens.radius32,
                              ),
                            ),
                            child: Text(
                              '$count',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: attention ? Colors.white : fg,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
      ),
    );
  }
}

// ── One report card ─────────────────────────────────────────────

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.incident,
    required this.clock,
    required this.fromPosition,
    required this.onTap,
  });

  final IncidentModel incident;
  final String clock;

  /// The resident's current fix, if one has been acquired — used only to
  /// show "how far is this past incident from where I am now" on the card.
  /// Null just omits that line; it never blocks the list.
  final Position? fromPosition;
  final VoidCallback onTap;

  /// Straight-line distance from [fromPosition] to where this incident was
  /// reported, in km — or null if either point is unknown.
  double? get _distanceKm {
    final pos = fromPosition;
    final lat = incident.latitude;
    final lng = incident.longitude;
    if (pos == null || lat == null || lng == null) return null;
    return Geolocator.distanceBetween(pos.latitude, pos.longitude, lat, lng) /
        1000;
  }

  /// A category to draw the card in, even when [IncidentModel.incidentCategory]
  /// is null — every card gets one of the six category treatments, never a
  /// generic document icon.
  ///
  /// Older reports (filed before the category field existed, or via the SOS
  /// path) carry no structured category, but the quick-report flow always
  /// prefixes `report_text` with the category's own label — see
  /// `'$label — $note'` in quick_report_review_screen.dart — so that prefix
  /// is a reliable second source before falling back to [IncidentCategory.other].
  IncidentCategory get _category {
    final structured = IncidentCategory.fromValue(incident.incidentCategory);
    if (structured != null) return structured;
    for (final c in IncidentCategory.values) {
      if (incident.reportText.startsWith('${c.label} — ')) return c;
    }
    return IncidentCategory.other;
  }

  Color get _badgeColor =>
      // Amber for both: something for the resident to read or do. Not red -
      // red is the critical-severity signal and nothing else.
      (incident.isRejected ||
              incident.isCancelledByAgency ||
              incident.needsClarification)
          ? ZirenTokens.systemWarning
          : _statusColor;

  Color get _statusColor => switch (incident.status) {
    'resolved' => ZirenTokens.statusResolved,
    'cancelled' => ZirenTokens.statusCancelled,
    'dispatched' || 'en_route' || 'arrived' => ZirenTokens.statusDispatched,
    'processing' => ZirenTokens.statusProcessing,
    _ => ZirenTokens.statusReceived,
  };

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final category = _category;
    final categoryColor = IncidentCategoryStyle.color(category);
    final categoryIcon = IncidentCategoryStyle.icon(category);
    final title = IncidentLabels.categoryShort(t, category);
    final daysLeft = incident.daysUntilPurge;

    // Still being handled: drawn in full colour with its progress. Finished
    // and withdrawn reports go quiet, so a history of closed reports does
    // not read as a list of emergencies.
    final live = incident.status != 'resolved' && incident.status != 'cancelled';
    final body =
        incident.reportText.isEmpty
            ? (incident.locationAddress ?? t.noDetails)
            : IncidentLabels.reportText(t, incident.reportText);

    return Material(
      color: ZirenTokens.surfaceCard,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color:
                  live
                      ? categoryColor.withValues(alpha: 0.35)
                      : ZirenTokens.surfaceBorder,
            ),
          ),
          // A Stack, not an IntrinsicHeight row: the notices and transcript
          // prompt below cannot be measured intrinsically.
          child: Stack(
              children: [
                Padding(
                    padding: const EdgeInsets.fromLTRB(
                      ZirenTokens.space16 + 1,
                      ZirenTokens.space12 + 2,
                      ZirenTokens.space12,
                      ZirenTokens.space12 + 2,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: categoryColor.withValues(
                                  alpha: live ? 0.14 : 0.08,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                categoryIcon,
                                size: 21,
                                color:
                                    live
                                        ? categoryColor
                                        : categoryColor.withValues(alpha: 0.7),
                              ),
                            ),
                            const SizedBox(width: ZirenTokens.space10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w800,
                                      color: ZirenTokens.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      Icon(
                                        LucideIcons.clock,
                                        size: 12,
                                        color: ZirenTokens.textMuted,
                                      ),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          clock,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
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
                            const SizedBox(width: ZirenTokens.space8),
                            _StatusPill(
                              label: IncidentLabels.reportStatus(t, incident),
                              color: _badgeColor,
                            ),
                          ],
                        ),
                        const SizedBox(height: ZirenTokens.space10),
                        Text(
                          body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.45,
                            color: ZirenTokens.textSecondary,
                          ),
                        ),
                        if (incident.locationAddress != null) ...[
                          const SizedBox(height: ZirenTokens.space10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: ZirenTokens.space10,
                              vertical: ZirenTokens.space6,
                            ),
                            decoration: BoxDecoration(
                              color: ZirenTokens.surfaceRaised,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  LucideIcons.map_pin,
                                  size: 13,
                                  color: ZirenTokens.textMuted,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _distanceKm != null
                                        ? t.reportsLocationDistance(
                                          incident.locationAddress!,
                                          _distanceKm!.toStringAsFixed(1),
                                        )
                                        : incident.locationAddress!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: ZirenTokens.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (live) ...[
                          const SizedBox(height: ZirenTokens.space12),
                          ReportStageTrack(status: incident.status, compact: true),
                        ],

              // What the agency decided, said on the card itself. A rejection
              // with no reason, or a question nobody sees, is the whole
              // problem this replaces.
              if (incident.isRejected) ...[
                const SizedBox(height: ZirenTokens.space12),
                ReviewNotice(
                  icon: LucideIcons.circle_x,
                  title: t.reportRejectedTitle,
                  body:
                      (incident.rejectionReason ?? '').trim().isEmpty
                          ? null
                          : t.reportRejectedReason(incident.rejectionReason!),
                ),
              ] else if (incident.isCancelledByAgency) ...[
                const SizedBox(height: ZirenTokens.space12),
                ReviewNotice(
                  icon: LucideIcons.circle_x,
                  title: t.notifCancelledTitle,
                  body: t.notifCancelledBody,
                  cue: t.notifOpenChat,
                ),
              ] else if (incident.needsClarification) ...[
                const SizedBox(height: ZirenTokens.space12),
                ReviewNotice(
                  icon: LucideIcons.message_circle_question_mark,
                  title: t.clarificationTitle,
                  body: incident.clarificationNote,
                  cue: t.clarificationReply,
                ),
              ],

              // A second chance to check the transcript.
              //
              // The confirm screen right after sending is one
              // chance, and it lands on someone who is standing in
              // front of the emergency. The reports whose
              // transcripts are worst come from people who were
              // panicking, and they are exactly the people who will
              // skip it. This is the same question asked again from
              // somewhere safe.
              if (incident.heardText != null &&
                  !incident.transcriptSettled) ...[
                const SizedBox(height: ZirenTokens.space12),
                TranscriptPrompt(incident: incident),
              ],

              // In Trash: how long until this is gone for good.
              if (incident.status == 'cancelled' && daysLeft != null) ...[
                const SizedBox(height: ZirenTokens.space8),
                Row(
                  children: [
                    Icon(
                      LucideIcons.trash,
                      size: 13,
                      color: ZirenTokens.textMuted,
                    ),
                    const SizedBox(width: ZirenTokens.space4),
                    Flexible(child: Text(
                      t.trashDeletesInDays(daysLeft),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: ZirenTokens.textMuted,
                      ),
                    )),
                  ],
                ),
              ],
                      ],
                    ),
                ),
                // The category's colour down the leading edge — the fastest
                // way to tell a fire from a flood while scrolling.
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 5,
                    color:
                        live
                            ? categoryColor
                            : categoryColor.withValues(alpha: 0.25),
                  ),
                ),
              ],
          ),
        ),
      ),
    );
  }
}

/// The report's status, as a pill with a dot of the same colour.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 170),
      padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(ZirenTokens.radius32),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A date group ("Today", "This week") with how many reports it holds.
class _BucketHeading extends StatelessWidget {
  const _BucketHeading({
    required this.label,
    required this.count,
    required this.first,
  });

  final String label;
  final int count;
  final bool first;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: first ? ZirenTokens.space4 : ZirenTokens.space16,
        bottom: ZirenTokens.space10,
        left: ZirenTokens.space4,
      ),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
              color: ZirenTokens.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: ZirenTokens.surfaceRaised,
              borderRadius: BorderRadius.circular(ZirenTokens.radius32),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: ZirenTokens.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Divider(height: 1, color: ZirenTokens.surfaceBorder),
          ),
        ],
      ),
    );
  }
}

// ── States ────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filter});
  final ReportFilter filter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (title, body) = switch (filter) {
      ReportFilter.bukas => (l10n.noOpenReports, l10n.noOpenReportsBody),
      ReportFilter.tapos => (l10n.noResolvedYet, l10n.noResolvedYetBody),
      ReportFilter.lahat => (l10n.noReportsYet, l10n.noReportsYetLong),
      ReportFilter.basura => (l10n.noTrashedReports, l10n.noTrashedReportsBody),
    };

    final (icon, accent) = switch (filter) {
      ReportFilter.bukas => (LucideIcons.activity, ZirenTokens.statusDispatched),
      ReportFilter.tapos => (LucideIcons.circle_check, ZirenTokens.statusResolved),
      ReportFilter.basura => (LucideIcons.trash, ZirenTokens.textMuted),
      ReportFilter.lahat => (LucideIcons.file_text, ZirenTokens.brandOrange),
    };

    return Padding(
      padding: const EdgeInsets.all(ZirenTokens.space32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.07),
            ),
            alignment: Alignment.center,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.14),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 28, color: accent),
            ),
          ),
          const SizedBox(height: ZirenTokens.space20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: ZirenTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: ZirenTokens.textSecondary,
            ),
          ),
          // No reports at all: the one useful next step is making one.
          if (filter == ReportFilter.lahat) ...[
            const SizedBox(height: ZirenTokens.space20),
            ElevatedButton.icon(
              onPressed: () => context.go('/home'),
              icon: const Icon(LucideIcons.siren, size: 18),
              label: Text(l10n.homeReportCtaTitle),
              style: ElevatedButton.styleFrom(
                backgroundColor: ZirenTokens.brandOrange,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: ZirenTokens.space20,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ZirenTokens.radius32),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(ZirenTokens.space32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.cloud_off,
            size: 40,
            color: ZirenTokens.textMuted,
          ),
          const SizedBox(height: ZirenTokens.space12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: ZirenTokens.textSecondary,
            ),
          ),
          const SizedBox(height: ZirenTokens.space20),
          OutlinedButton(
            onPressed: onRetry,
            style: OutlinedButton.styleFrom(
              foregroundColor: ZirenTokens.brandOrange,
              side: const BorderSide(color: ZirenTokens.brandOrange),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ZirenTokens.radius12),
              ),
            ),
            child: Text(AppLocalizations.of(context).retry),
          ),
        ],
      ),
    );
  }
}
