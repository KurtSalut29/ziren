import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/ziren_dialogs.dart';
import '../../../shared/widgets/ziren_toast.dart';
import '../../../shared/widgets/ziren_card.dart';
import '../../../shared/widgets/ziren_spine.dart';
import '../domain/incident_category_style.dart';
import '../domain/incident_model.dart';
import '../domain/incident_provider.dart';
import 'incident_labels.dart';
import 'widgets/incident_feedback_sheet.dart';
import 'widgets/incident_thread_sheet.dart';
import 'widgets/review_notice.dart';
import '../../notifications/presentation/notice_view.dart' show noticeStage;
import 'widgets/transcript_prompt.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Everything about one report, on its own screen.
///
/// My Reports used to answer this with an inline dropdown on the card
/// itself — enough for the stage rail, not enough once Trash needed its own
/// confirmation step and a permanent-deletion countdown to live somewhere.
/// Splitting those into a real screen is also just a more honest shape for
/// "all the details of my report" than a card that grows taller in place.
class ReportDetailScreen extends StatefulWidget {
  const ReportDetailScreen({super.key, required this.incident});

  final IncidentModel incident;

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  static const _sequence = ['received', 'processing', 'dispatched', 'resolved'];

  bool _isOpen(IncidentModel i) =>
      i.status != 'resolved' && i.status != 'cancelled';

  /// The list this screen was opened from keeps reloading (pull-to-refresh,
  /// after withdrawing); reading the live copy by id means a status change
  /// that lands while this screen is open is not stuck showing what the
  /// resident tapped a minute ago.
  IncidentModel _current(IncidentProvider provider) {
    for (final i in provider.myIncidents) {
      if (i.id == widget.incident.id) return i;
    }
    return widget.incident;
  }

  IncidentCategory _categoryOf(IncidentModel incident) {
    final structured = IncidentCategory.fromValue(incident.incidentCategory);
    if (structured != null) return structured;
    for (final c in IncidentCategory.values) {
      if (incident.reportText.startsWith('${c.label} — ')) return c;
    }
    return IncidentCategory.other;
  }

  Color _badgeColor(IncidentModel incident) =>
      (incident.isRejected ||
              incident.isCancelledByAgency ||
              incident.needsClarification)
          ? ZirenTokens.systemWarning
          : _statusColor(incident);

  Color _statusColor(IncidentModel incident) => switch (incident.status) {
    'resolved' => ZirenTokens.statusResolved,
    'cancelled' => ZirenTokens.statusCancelled,
    'dispatched' || 'en_route' || 'arrived' => ZirenTokens.statusDispatched,
    'processing' => ZirenTokens.statusProcessing,
    _ => ZirenTokens.statusReceived,
  };

  String _fullTimestamp(DateTime t) {
    final mm = t.month.toString().padLeft(2, '0');
    final dd = t.day.toString().padLeft(2, '0');
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    final ampm = t.hour < 12 ? 'AM' : 'PM';
    return '$mm/$dd/${t.year} · $h:$m $ampm';
  }

  double? _distanceKm(IncidentModel incident, Position? from) {
    final lat = incident.latitude;
    final lng = incident.longitude;
    if (from == null || lat == null || lng == null) return null;
    return Geolocator.distanceBetween(from.latitude, from.longitude, lat, lng) /
        1000;
  }

  /// Confirm, then move to Trash. Mirrors the guard the backend itself
  /// enforces (only while still `received`, before anyone has acted) — the
  /// button is hidden past that point, and the server's own refusal text is
  /// shown verbatim on the rare race where it changed between render and tap.
  Future<void> _confirmTrash(BuildContext context, IncidentModel incident) async {
    final l10n = AppLocalizations.of(context);
    final provider = context.read<IncidentProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final confirmed = await showZirenDialog<bool>(
      context,
      icon: LucideIcons.trash,
      tone: ZirenTone.danger,
      title: l10n.withdrawConfirmTitle,
      message: l10n.withdrawConfirmBody,
      actions: [
        ZirenDialogAction(
          label: l10n.withdrawConfirmAction,
          value: true,
          kind: ZirenActionKind.danger,
          icon: LucideIcons.trash,
        ),
        ZirenDialogAction(label: l10n.withdrawCancelAction, value: false),
      ],
    );
    if (confirmed != true) return;

    final error = await provider.withdrawIncident(incident.id);
    if (error != null) {
      ZirenToast.error(messenger, error);
      return;
    }
    // Nothing left on this screen a resident needs once their own report is
    // the thing that just moved to Trash — back to the list, where the
    // "deletes in 30 days" state now shows up under the Trash filter.
    navigator.pop();
    // What just happened, in its own terms - moved to Trash, and how long it stays
    // there. NOT "Report updated", and not the "Cancelled" pop-up this used to
    // trigger a moment later (see NotificationProvider: a resident's own
    // withdrawal is never announced back to them).
    ZirenToast.success(messenger, l10n.withdrawDone, icon: LucideIcons.trash);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final provider = context.watch<IncidentProvider>();
    final incident = _current(provider);
    final category = _categoryOf(incident);
    final categoryColor = IncidentCategoryStyle.color(category);
    final categoryIcon = IncidentCategoryStyle.icon(category);
    // En route and arrived are both part of "responder on the way". Reading
    // them as "not on the list" (-1) is what emptied the rail once a responder
    // was actually coming.
    final stage = noticeStage(incident.status);
    final isOpen = _isOpen(incident);
    final distanceKm = _distanceKm(incident, provider.currentPosition);
    final daysLeft = incident.daysUntilPurge;
    final canViewOnMap = incident.latitude != null && incident.longitude != null;

    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      appBar: AppBar(title: Text(t.reportDetailsTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            ZirenTokens.space16,
            ZirenTokens.space8,
            ZirenTokens.space16,
            ZirenTokens.space32,
          ),
          children: [
            // ── Header: category, status, when ────────────────
            ZirenCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: categoryColor.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Icon(categoryIcon, size: 22, color: categoryColor),
                      ),
                      const SizedBox(width: ZirenTokens.space12),
                      Expanded(
                        child: Text(
                          IncidentLabels.categoryShort(t, category),
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: ZirenTokens.textPrimary,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: ZirenTokens.space10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _badgeColor(incident).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(ZirenTokens.radius32),
                        ),
                        child: Text(
                          IncidentLabels.reportStatus(t, incident),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _badgeColor(incident),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: ZirenTokens.space16),
                  Divider(height: 1, color: ZirenTokens.surfaceBorder),
                  const SizedBox(height: ZirenTokens.space16),
                  Text(
                    incident.reportText.isEmpty
                        ? (incident.locationAddress ?? t.noDetails)
                        : incident.reportText,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: ZirenTokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            // ── The agency's decision, in words ───────────────
            //
            // A rejected report used to arrive in Trash with nothing said.
            // Now it says what happened, why, and what to do next - and the
            // "what next" is a call to the station or a fresh report, because
            // for a real emergency a rejected report is not the end of it.
            if (incident.isRejected) ...[
              const SizedBox(height: ZirenTokens.space12),
              ReviewNotice(
                icon: LucideIcons.circle_x,
                title: t.reportRejectedTitle,
                body:
                    (incident.rejectionReason ?? '').trim().isEmpty
                        ? null
                        : t.reportRejectedReason(incident.rejectionReason!),
                footnote: t.reportRejectedHelp,
                actions: [
                  ReviewAction(
                    icon: LucideIcons.phone,
                    label: t.reportRejectedCall,
                    onTap: () => context.push('/emergency-contacts'),
                  ),
                  ReviewAction(
                    icon: LucideIcons.file_plus,
                    label: t.reportFileAgain,
                    filled: true,
                    onTap: () => context.push('/report'),
                  ),
                ],
              ),
            ] else if (incident.isCancelledByAgency) ...[
              // The agency cancelled it. Said plainly, with what to do about it -
              // and the reason is in the messages, where it was written.
              const SizedBox(height: ZirenTokens.space12),
              ReviewNotice(
                icon: LucideIcons.circle_x,
                title: t.notifCancelledTitle,
                body: t.notifCancelledBody,
                footnote: t.notifCancelledHelp,
                actions: [
                  ReviewAction(
                    icon: LucideIcons.message_square,
                    label: t.notifOpenChat,
                    onTap: () => showIncidentThreadSheet(context, incident),
                  ),
                  ReviewAction(
                    icon: LucideIcons.phone,
                    label: t.reportRejectedCall,
                    onTap: () => context.push('/emergency-contacts'),
                  ),
                  ReviewAction(
                    icon: LucideIcons.file_plus,
                    label: t.reportFileAgain,
                    filled: true,
                    onTap: () => context.push('/report'),
                  ),
                ],
              ),
            ] else if (incident.needsClarification) ...[
              const SizedBox(height: ZirenTokens.space12),
              ReviewNotice(
                icon: LucideIcons.message_circle_question_mark,
                title: t.clarificationTitle,
                label: t.clarificationAsked,
                body: incident.clarificationNote,
                footnote: t.clarificationReplyHint,
                actions: [
                  ReviewAction(
                    icon: LucideIcons.reply,
                    label: t.clarificationReply,
                    filled: true,
                    onTap: () async {
                      final provider = context.read<IncidentProvider>();
                      await showIncidentThreadSheet(context, incident);
                      // The server puts the report back in review when the
                      // answer lands; read it again so this screen says so.
                      await provider.loadMyIncidents();
                    },
                  ),
                ],
              ),
            ],

            // ── Trash countdown, if this report is there ──────
            if (incident.status == 'cancelled' && daysLeft != null) ...[
              const SizedBox(height: ZirenTokens.space12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: ZirenTokens.space16,
                  vertical: ZirenTokens.space12,
                ),
                decoration: BoxDecoration(
                  color: ZirenTokens.statusCancelled.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(ZirenTokens.radius16),
                  border: Border.all(
                    color: ZirenTokens.statusCancelled.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.trash,
                      size: 18,
                      color: ZirenTokens.textSecondary,
                    ),
                    const SizedBox(width: ZirenTokens.space10),
                    Expanded(
                      child: Text(
                        t.trashDeletesInDays(daysLeft),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: ZirenTokens.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── Transcript re-check ────────────────────────────
            if (incident.heardText != null && !incident.transcriptSettled) ...[
              const SizedBox(height: ZirenTokens.space12),
              TranscriptPrompt(incident: incident),
            ],

            // ── Stage rail ─────────────────────────────────────
            const SizedBox(height: ZirenTokens.space12),
            ZirenCard(
              child: ZirenSpine(
                nodes: [
                  for (var s = 0; s < _sequence.length; s++)
                    SpineNode(
                      title: IncidentLabels.status(t, _sequence[s]),
                      timestamp: switch (_sequence[s]) {
                        'received' => _fullTimestamp(incident.createdAt),
                        'dispatched' =>
                          incident.dispatchedAt != null
                              ? _fullTimestamp(incident.dispatchedAt!)
                              : null,
                        'resolved' =>
                          incident.resolvedAt != null
                              ? _fullTimestamp(incident.resolvedAt!)
                              : null,
                        _ => null,
                      },
                      state:
                          incident.status == 'cancelled'
                              ? (s == 0
                                  ? SpineState.halted
                                  : SpineState.pending)
                              : s < stage
                              ? SpineState.done
                              : s == stage
                              ? (s == _sequence.length - 1
                                  ? SpineState.done
                                  : SpineState.active)
                              : SpineState.pending,
                    ),
                ],
              ),
            ),

            // ── Location ───────────────────────────────────────
            if (incident.locationAddress != null) ...[
              const SizedBox(height: ZirenTokens.space12),
              ZirenCard(
                // Only tappable when there is somewhere on the map for the
                // tap to actually go — an older report, or one filed with
                // no GPS fix, has an address string but no coordinates.
                onTap:
                    canViewOnMap
                        ? () => context.push('/report-map/${incident.id}')
                        : null,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      LucideIcons.map_pin,
                      size: 18,
                      color: ZirenTokens.textMuted,
                    ),
                    const SizedBox(width: ZirenTokens.space10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            incident.locationAddress!,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: ZirenTokens.textPrimary,
                            ),
                          ),
                          if (distanceKm != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              t.reportsLocationDistance(
                                incident.locationAddress!,
                                distanceKm.toStringAsFixed(1),
                              ),
                              style: TextStyle(
                                fontSize: 12,
                                color: ZirenTokens.textMuted,
                              ),
                            ),
                          ],
                          if (canViewOnMap) ...[
                            const SizedBox(height: ZirenTokens.space6),
                            Text(
                              t.reportsViewOnMap,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: ZirenTokens.brandOrange,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (canViewOnMap)
                      Icon(
                        LucideIcons.chevron_right,
                        size: 18,
                        color: ZirenTokens.textMuted,
                      ),
                  ],
                ),
              ),
            ],

            // ── Actions ────────────────────────────────────────
            const SizedBox(height: ZirenTokens.space16),
            if (isOpen)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => showIncidentThreadSheet(context, incident),
                  icon: const Icon(LucideIcons.message_square, size: 16),
                  label: Text(t.reportsAddInformation),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ZirenTokens.brandOrange,
                    side: const BorderSide(color: ZirenTokens.brandOrange),
                    padding: const EdgeInsets.symmetric(
                      vertical: ZirenTokens.space12,
                    ),
                  ),
                ),
              )
            else if (incident.status == 'resolved')
              _FeedbackPrompt(incidentId: incident.id),

            if (incident.status == 'received') ...[
              const SizedBox(height: ZirenTokens.space8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _confirmTrash(context, incident),
                  icon: const Icon(LucideIcons.trash, size: 16),
                  label: Text(t.withdrawReport),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ZirenTokens.severityCritical,
                    side: BorderSide(
                      color: ZirenTokens.severityCritical.withValues(alpha: 0.5),
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: ZirenTokens.space12,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Rate your experience" — spec Section 26. Checks whether the resident has
/// already rated this incident before offering the prompt again, so a report
/// reopened a second time does not ask twice.
class _FeedbackPrompt extends StatefulWidget {
  const _FeedbackPrompt({required this.incidentId});
  final String incidentId;

  @override
  State<_FeedbackPrompt> createState() => _FeedbackPromptState();
}

class _FeedbackPromptState extends State<_FeedbackPrompt> {
  IncidentFeedback? _existing;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    context.read<IncidentProvider>().fetchMyFeedback(widget.incidentId).then((
      f,
    ) {
      if (mounted) {
        setState(() {
          _existing = f;
          _checked = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) return const SizedBox(height: 34);

    if (_existing != null) {
      return Row(
        children: [
          const Icon(
            LucideIcons.star,
            size: 16,
            color: ZirenTokens.severityMedium,
          ),
          const SizedBox(width: ZirenTokens.space4),
          Flexible(child: Text(
            AppLocalizations.of(
              context,
            ).reportsAlreadyRated('${_existing!.rating}'),
            style: TextStyle(fontSize: 12, color: ZirenTokens.textMuted),
          )),
        ],
      );
    }

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed:
            () async {
              final provider = context.read<IncidentProvider>();
              await showIncidentFeedbackSheet(context, widget.incidentId);
              if (!mounted) return;
              final f = await provider.fetchMyFeedback(widget.incidentId);
              if (mounted) setState(() => _existing = f);
            },
        icon: const Icon(LucideIcons.star, size: 16),
        label: Text(AppLocalizations.of(context).reportsRateService),
        style: OutlinedButton.styleFrom(
          foregroundColor: ZirenTokens.severityMedium,
          side: const BorderSide(color: ZirenTokens.severityMedium),
          padding: const EdgeInsets.symmetric(vertical: ZirenTokens.space12),
        ),
      ),
    );
  }
}
