import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/profile_kit.dart';
import '../../../shared/widgets/ziren_dialogs.dart';
import '../../../shared/widgets/ziren_toast.dart';
import '../../../shared/widgets/ziren_spine.dart';
import '../domain/incident_category_style.dart';
import '../domain/incident_model.dart';
import '../domain/incident_provider.dart';
import 'incident_labels.dart';
import 'widgets/incident_feedback_sheet.dart';
import 'widgets/incident_thread_sheet.dart';
import 'widgets/report_stage_track.dart';
import 'widgets/review_notice.dart';
import '../../notifications/presentation/notice_view.dart' show noticeStage;
import 'widgets/transcript_prompt.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import '../../demo/presentation/demo_anchor.dart';

/// Everything about one report, on its own screen.
///
/// My Reports used to answer this with an inline dropdown on the card
/// itself — enough for the stage rail, not enough once Trash needed its own
/// confirmation step and a permanent-deletion countdown to live somewhere.
/// Splitting those into a real screen is also just a more honest shape for
/// "all the details of my report" than a card that grows taller in place.
///
/// Laid out top to bottom as the questions a resident asks: what is happening
/// with it now (the header: status, the named progress steps, what comes
/// next, who is coming), what did I say, where, and how it went so far. What
/// they can do about it (chat, move to Trash, rate) stays pinned at the
/// bottom instead of at the end of a long scroll.
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

  /// The same short form the responder app and the dashboard print, so a
  /// resident reading it out over the phone is understood.
  static String _shortId(String id) {
    final s = id.replaceAll('-', '').toUpperCase();
    return 'INC-${s.substring(s.length > 6 ? s.length - 6 : 0)}';
  }

  static String _via(AppLocalizations t, String via) => switch (via) {
    'sos' => t.reportViaSos,
    'sms' => t.reportViaSms,
    'internet' || 'app' || 'wizard' || 'quick' => t.reportViaApp,
    _ => via,
  };

  /// Confirm, then move to Trash. Mirrors the guard the backend itself
  /// enforces (only while still `received`, before anyone has acted) — the
  /// button is hidden past that point, and the server's own refusal text is
  /// shown verbatim on the rare race where it changed between render and tap.
  Future<void> _confirmTrash(
    BuildContext context,
    IncidentModel incident,
  ) async {
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
    // En route and arrived are both part of "responder on the way". Reading
    // them as "not on the list" (-1) is what emptied the rail once a responder
    // was actually coming.
    final stage = noticeStage(incident.status);
    final isOpen = _isOpen(incident);
    final distanceKm = _distanceKm(incident, provider.currentPosition);
    final daysLeft = incident.daysUntilPurge;
    final canViewOnMap =
        incident.latitude != null && incident.longitude != null;

    final actions = _ActionBar.forIncident(
      incident: incident,
      isOpen: isOpen,
      onChat: () => showIncidentThreadSheet(context, incident),
      onTrash: () => _confirmTrash(context, incident),
    );

    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      appBar: AppBar(
        backgroundColor: ZirenTokens.surfaceBase,
        title: Text(t.reportDetailsTitle),
      ),
      bottomNavigationBar:
          actions == null
              ? null
              : DemoAnchor(id: 'detail.actions', child: actions),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          ZirenTokens.space16,
          ZirenTokens.space8,
          ZirenTokens.space16,
          ZirenTokens.space32,
        ),
        children: [
          // ── Header: what is happening with it now ─────────
          DemoAnchor(
            id: 'detail.hero',
            child: _HeroCard(
              incident: incident,
              category: category,
              statusLabel: IncidentLabels.reportStatus(t, incident),
              statusColor: _badgeColor(incident),
              sentAt: t.reportSentAt(_fullTimestamp(incident.createdAt)),
              stage: stage,
              live: isOpen,
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

          // ── What you reported ──────────────────────────────
          const SizedBox(height: ZirenTokens.space24),
          DemoAnchor(
            id: 'detail.said',
            child: _Section(
              title: t.reportSectionYourReport,
              child: Container(
                decoration: profileCardDecoration(),
                padding: const EdgeInsets.all(ZirenTokens.space16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      LucideIcons.quote,
                      size: 18,
                      color: ZirenTokens.textMuted,
                    ),
                    const SizedBox(width: ZirenTokens.space10),
                    Expanded(
                      child: Text(
                        incident.reportText.isEmpty
                            ? (incident.locationAddress ?? t.noDetails)
                            : IncidentLabels.reportText(t, incident.reportText),
                        style: TextStyle(
                          fontSize: 14.5,
                          height: 1.55,
                          color: ZirenTokens.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Location ───────────────────────────────────────
          if (incident.locationAddress != null || canViewOnMap) ...[
            const SizedBox(height: ZirenTokens.space24),
            ProfileGroup(
              title: t.reportSectionLocation,
              children: [
                if (incident.locationAddress != null)
                  ProfileTile(
                    icon: LucideIcons.map_pin,
                    label: t.reportFactAddress,
                    value: incident.locationAddress!,
                  ),
                if (distanceKm != null)
                  ProfileTile(
                    icon: LucideIcons.navigation,
                    label: t.reportFactDistance,
                    value: t.reportDistanceKm(distanceKm.toStringAsFixed(1)),
                  ),
                // Only when there is somewhere on the map to go — an older
                // report, or one filed with no GPS fix, has an address string
                // but no coordinates.
                if (canViewOnMap)
                  DemoAnchor(
                    id: 'detail.map',
                    child: ProfileTile(
                      key: const Key('report-view-on-map'),
                      icon: LucideIcons.map,
                      label: t.reportsViewOnMap,
                      tone: ZirenTokens.brandOrange,
                      onTap: () => context.push('/report-map/${incident.id}'),
                    ),
                  ),
              ],
            ),
          ],

          // ── Progress, with every timestamp ─────────────────
          const SizedBox(height: ZirenTokens.space24),
          DemoAnchor(
            id: 'detail.progress',
            child: _Section(
              title: t.reportSectionProgress,
              child: Container(
                decoration: profileCardDecoration(),
                padding: const EdgeInsets.all(ZirenTokens.space16),
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
            ),
          ),

          // ── Details ────────────────────────────────────────
          const SizedBox(height: ZirenTokens.space24),
          ProfileGroup(
            title: t.reportSectionDetails,
            children: [
              ProfileTile(
                icon: LucideIcons.hash,
                label: t.reportFactId,
                value: _shortId(incident.id),
              ),
              ProfileTile(
                icon:
                    incident.submittedVia == 'sos'
                        ? LucideIcons.siren
                        : LucideIcons.smartphone,
                label: t.reportFactVia,
                value: _via(t, incident.submittedVia),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A titled block, headed the same way as [ProfileGroup].
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: ZirenTokens.space4,
            bottom: ZirenTokens.space8,
          ),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
              color: ZirenTokens.textSecondary,
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// The top of the screen: the category, the status, when it was sent, and —
/// while it is still being handled — the named progress steps, what comes
/// next, and who is on the way.
class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.incident,
    required this.category,
    required this.statusLabel,
    required this.statusColor,
    required this.sentAt,
    required this.stage,
    required this.live,
  });

  final IncidentModel incident;
  final IncidentCategory category;
  final String statusLabel;
  final Color statusColor;
  final String sentAt;
  final int stage;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final color = IncidentCategoryStyle.color(category);
    final eta = incident.etaLabel(t);
    final nextLabels = [
      t.stageShortChecking,
      t.stageShortOnTheWay,
      t.stageShortResolved,
    ];

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: profileCardDecoration(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The category's colour washes the top of the card: the one thing
          // on this screen that says at a glance what kind of report it is.
          Container(
            color: color.withValues(alpha: ZirenTokens.isDark ? 0.16 : 0.08),
            padding: const EdgeInsets.fromLTRB(
              ZirenTokens.space16,
              ZirenTokens.space16,
              ZirenTokens.space16,
              ZirenTokens.space16,
            ),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    IncidentCategoryStyle.icon(category),
                    size: 26,
                    color: color,
                  ),
                ),
                const SizedBox(width: ZirenTokens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        IncidentLabels.categoryShort(t, category),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: ZirenTokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sentAt,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: ZirenTokens.textSecondary,
                        ),
                      ),
                      const SizedBox(height: ZirenTokens.space8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _Pill(label: statusLabel, color: statusColor),
                          if (incident.submittedVia == 'sos')
                            _Pill(
                              label: 'SOS',
                              color: ZirenTokens.severityCritical,
                              icon: LucideIcons.siren,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (live)
            Padding(
              padding: const EdgeInsets.all(ZirenTokens.space16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ReportStageTrack(status: incident.status),
                  if (stage < 3) ...[
                    const SizedBox(height: ZirenTokens.space12),
                    Row(
                      children: [
                        Icon(
                          LucideIcons.arrow_right,
                          size: 14,
                          color: ZirenTokens.textMuted,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            t.reportNextStep(nextLabels[stage]),
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: ZirenTokens.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  // Who is coming and roughly when — the question a person
                  // waiting actually has. Vague on purpose: "about 7
                  // minutes", never a clock time (see IncidentModel.etaLabel).
                  if (eta != null) ...[
                    const SizedBox(height: ZirenTokens.space12),
                    Container(
                      padding: const EdgeInsets.all(ZirenTokens.space12),
                      decoration: BoxDecoration(
                        color: ZirenTokens.statusDispatched.withValues(
                          alpha: 0.10,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            LucideIcons.truck,
                            size: 18,
                            color: ZirenTokens.statusDispatched,
                          ),
                          const SizedBox(width: ZirenTokens.space10),
                          Expanded(
                            child: Text(
                              incident.respondingAgency != null
                                  ? t.activeReportAgencyEnRoute(
                                    incident.respondingAgency!,
                                    eta,
                                  )
                                  : t.activeReportResponderEnRoute(eta),
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: ZirenTokens.statusDispatched,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(ZirenTokens.radius32),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, size: 12, color: color)
          else
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
                fontSize: 12,
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

/// What the resident can do, pinned under the scroll: chat with the station
/// while it is open (and move it to Trash while nobody has acted on it yet),
/// or rate the service once it is resolved.
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.children});

  final List<Widget> children;

  /// Null when there is nothing to do (a cancelled report).
  static Widget? forIncident({
    required IncidentModel incident,
    required bool isOpen,
    required VoidCallback onChat,
    required VoidCallback onTrash,
  }) {
    if (isOpen) {
      return Builder(
        builder: (context) {
          final t = AppLocalizations.of(context);
          final chat = ElevatedButton.icon(
            key: const Key('report-chat'),
            onPressed: onChat,
            icon: const Icon(LucideIcons.message_square, size: 18),
            label: Text(
              t.reportsAddInformation,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: ZirenTokens.brandOrange,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ZirenTokens.radius16),
              ),
            ),
          );
          return _ActionBar(
            children: [
              // Only while still `received` — the backend refuses it once
              // anyone has acted.
              if (incident.status == 'received') ...[
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('report-trash'),
                    onPressed: onTrash,
                    icon: const Icon(LucideIcons.trash, size: 16),
                    label: Text(
                      t.withdrawReport,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ZirenTokens.severityCritical,
                      minimumSize: const Size.fromHeight(52),
                      side: BorderSide(
                        color: ZirenTokens.severityCritical.withValues(
                          alpha: 0.5,
                        ),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          ZirenTokens.radius16,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: ZirenTokens.space10),
              ],
              Expanded(child: chat),
            ],
          );
        },
      );
    }
    if (incident.status == 'resolved') {
      return _ActionBar(
        children: [Expanded(child: _FeedbackPrompt(incidentId: incident.id))],
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        border: Border(top: BorderSide(color: ZirenTokens.surfaceBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            ZirenTokens.space16,
            ZirenTokens.space12,
            ZirenTokens.space16,
            ZirenTokens.space12,
          ),
          child: Row(children: children),
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
    if (!_checked) return const SizedBox(height: 52);

    if (_existing != null) {
      return SizedBox(
        height: 52,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              LucideIcons.star,
              size: 16,
              color: ZirenTokens.severityMedium,
            ),
            const SizedBox(width: ZirenTokens.space6),
            Flexible(
              child: Text(
                AppLocalizations.of(
                  context,
                ).reportsAlreadyRated('${_existing!.rating}'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: ZirenTokens.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: () async {
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
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: ZirenTokens.severityMedium),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZirenTokens.radius16),
        ),
      ),
    );
  }
}
