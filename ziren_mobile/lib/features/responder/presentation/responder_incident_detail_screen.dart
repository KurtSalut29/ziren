import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/home_kit.dart' show kHomeCanvas;
import '../../../shared/widgets/loading_indicator.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/map/offline_map_service.dart';
import '../domain/responder_ack.dart';
import '../domain/responder_incident_model.dart';
import '../domain/responder_vocabulary.dart';
import '../../../shared/widgets/profile_kit.dart' show initialsOf;
import 'widgets/responder_ui.dart';
import 'incident_navigation_screen.dart';
import 'widgets/incident_action_row.dart';
import 'widgets/responder_action_sheets.dart';
import 'widgets/responder_notes_panel.dart';
import 'widgets/scene_capture_button.dart';
import 'widgets/responder_voice_note.dart';
import '../domain/responder_provider.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import '../../../shared/widgets/ziren_dialogs.dart';

/// Full incident detail screen for Responders.
///
/// Allows:
///  - Viewing full incident details (report text, wizard answers, location)
///  - Viewing reporter identity (name, phone, emergency contacts, trust flags)
///  - Answering the assignment: ACCEPT or CAN'T RESPOND (Phase 6D)
///  - Advancing the FSM: dispatched → en_route → arrived → resolved
///  - Closing with an after-action disposition — what was actually found
///  - Asking a second agency to attend (mutual aid)
///  - Raising their own distress signal
///  - Launching navigation to the incident location
///
/// Does NOT allow:
///  - Severity override (Agency Admin only)
///  - Viewing the full agency queue (only their assigned incidents)
class ResponderIncidentDetailScreen extends StatefulWidget {
  const ResponderIncidentDetailScreen({super.key, required this.incidentId});

  final String incidentId;

  @override
  State<ResponderIncidentDetailScreen> createState() =>
      _ResponderIncidentDetailScreenState();
}

class _ResponderIncidentDetailScreenState
    extends State<ResponderIncidentDetailScreen> {
  // Captured here, not read fresh in dispose(). By the time dispose() runs
  // this element can already be deactivated — Provider's own lookup walks
  // the ancestor tree and throws "Looking up a deactivated widget's
  // ancestor is unsafe" in that case, which is exactly what popping this
  // screen right as it unmounts used to crash with. didChangeDependencies
  // runs while the tree is still active, so the reference is safe to hold.
  ResponderProvider? _provider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ResponderProvider>().loadIncidentDetail(widget.incidentId);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _provider = context.read<ResponderProvider>();
  }

  @override
  void dispose() {
    _provider?.clearDetail();
    super.dispose();
  }

  Future<void> _advanceStatus(
    BuildContext context,
    ResponderIncidentModel incident,
    String newStatus,
  ) async {
    // Closing is no longer a status flip. It collects what the crew
    // actually found, which is the only thing that ever made the severity
    // rubric checkable against reality — see AfterActionSheet.
    if (newStatus == 'resolved') {
      await _closeIncident(context, incident);
      return;
    }

    final confirmed = await _showConfirmDialog(
      context,
      incident.nextActionLabel ?? AppLocalizations.of(context).respUpdateStatus,
      newStatus,
    );
    if (!confirmed || !context.mounted) return;

    final ok = await context.read<ResponderProvider>().advanceStatus(
      incident.id,
      newStatus,
    );

    if (!context.mounted) return;
    if (ok) {
      final l = AppLocalizations.of(context);
      if (newStatus == 'resolved') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.respClosed),
            backgroundColor: ZirenTokens.systemSuccess,
          ),
        );
        context.pop();
      } else if (newStatus == 'en_route') {
        // Said in its own terms: who can now see it. A status flip that changed
        // the button and said nothing left a crew member unsure it had taken.
        _toast(context, l.respEnRouteDone, ZirenTokens.systemSuccess);
      } else if (newStatus == 'arrived') {
        _toast(context, l.respArrivedDone, ZirenTokens.systemSuccess);
      }
    }
  }

  /// Answer the assignment: yes.
  Future<void> _accept(
    BuildContext context,
    ResponderIncidentModel incident,
  ) async {
    final provider = context.read<ResponderProvider>();
    final ok = await provider.acceptIncident(incident.id);
    if (!context.mounted) return;
    final t = AppLocalizations.of(context);
    _toast(
      context,
      ok ? t.respAccepted : provider.answerError ?? t.respAnswerSendFailed,
      ok ? ZirenTokens.systemSuccess : ZirenTokens.systemError,
    );
  }

  /// Answer the assignment: no, and say why.
  Future<void> _decline(
    BuildContext context,
    ResponderIncidentModel incident,
  ) async {
    final choice = await DeclineSheet.show(context);
    if (choice == null || !context.mounted) return;

    final provider = context.read<ResponderProvider>();
    final ok = await provider.declineIncident(
      incident.id,
      reason: choice.$1,
      note: choice.$2,
    );
    if (!context.mounted) return;
    final t = AppLocalizations.of(context);
    if (ok) {
      _toast(context, t.respDeclineSent, ZirenTokens.systemWarning);
      context.pop();
    } else {
      _toast(
        context,
        provider.answerError ?? t.respAnswerSendFailed,
        ZirenTokens.systemError,
      );
    }
  }

  /// Close the call with a disposition.
  Future<void> _closeIncident(
    BuildContext context,
    ResponderIncidentModel incident,
  ) async {
    final result = await AfterActionSheet.show(
      context,
      categoryLabel: incident.categoryLabel,
    );
    if (result == null || !context.mounted) return;

    final provider = context.read<ResponderProvider>();
    final ok = await provider.closeIncident(
      incident.id,
      outcome: result.outcome,
      notes: result.notes,
      injured: result.injured,
      fatal: result.fatal,
      transported: result.transported,
    );
    if (!context.mounted) return;
    if (ok) {
      _toast(
        context,
        AppLocalizations.of(context).respClosed,
        ZirenTokens.systemSuccess,
      );
      context.pop();
    } else {
      _toast(
        context,
        provider.answerError ?? AppLocalizations.of(context).respCloseFailed,
        ZirenTokens.systemError,
      );
    }
  }

  /// Ask a second agency to attend the same emergency.
  Future<void> _requestBackup(
    BuildContext context,
    ResponderIncidentModel incident,
  ) async {
    final choice = await BackupSheet.show(
      context,
      excludeAgencyType: incident.agencyType,
    );
    if (choice == null || !context.mounted) return;

    final provider = context.read<ResponderProvider>();
    final station = await provider.requestBackup(
      incident.id,
      agencyType: choice.$1,
      reason: choice.$2,
    );
    if (!context.mounted) return;
    final t = AppLocalizations.of(context);
    _toast(
      context,
      station != null
          ? t.respBackupSentTo(station)
          : provider.answerError ?? t.respAnswerSendFailed,
      station != null ? ZirenTokens.systemInfo : ZirenTokens.systemError,
    );
  }

  /// "The situation is worse than assessed" — Section 14. Notifies the
  /// Agency Admin; never touches the incident's own severity.
  Future<void> _escalate(
    BuildContext context,
    ResponderIncidentModel incident,
  ) async {
    final reason = await EscalateSheet.show(context);
    if (reason == null || !context.mounted) return;

    final provider = context.read<ResponderProvider>();
    final error = await provider.escalateIncident(incident.id, reason);
    if (!context.mounted) return;
    _toast(
      context,
      error ?? AppLocalizations.of(context).respEscalateSent,
      error == null ? ZirenTokens.severityHigh : ZirenTokens.systemError,
    );
  }

  /// The responder's own emergency.
  ///
  /// Confirmed rather than instant, and that is a real trade-off rather
  /// than caution for its own sake. An accidental distress signal costs a
  /// dispatcher a phone call and a crew their credibility the next time
  /// they press it; the button is already behind a long-press, so this
  /// dialog is the second of two deliberate acts, not the first.
  Future<void> _raiseDistress(
    BuildContext context,
    ResponderIncidentModel incident,
  ) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showZirenDialog<bool>(
      context,
      icon: LucideIcons.triangle_alert,
      tone: ZirenTone.danger,
      title: l.respDistressTitle,
      message: l.respDistressBody,
      actions: [
        ZirenDialogAction(
          label: l.respDistressYes,
          value: true,
          kind: ZirenActionKind.danger,
        ),
        ZirenDialogAction(label: l.respDistressNo, value: false),
      ],
    );
    if (confirmed != true || !context.mounted) return;

    final provider = context.read<ResponderProvider>();
    final live = await provider.raiseDistress(incidentId: incident.id);
    if (!context.mounted) return;
    final t = AppLocalizations.of(context);
    _toast(
      context,
      live ? t.respDistressSentLive : t.respDistressSentQueued,
      ZirenTokens.systemError,
    );
  }

  void _toast(BuildContext context, String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<bool> _showConfirmDialog(
    BuildContext context,
    String action,
    String newStatus,
  ) async {
    final l = AppLocalizations.of(context);
    final resolving = newStatus == 'resolved';
    return await showZirenDialog<bool>(
          context,
          icon:
              resolving ? LucideIcons.circle_check_big : LucideIcons.navigation,
          tone: resolving ? ZirenTone.success : ZirenTone.brand,
          title: action,
          message: resolving ? l.respConfirmResolve : l.respConfirmStatusUpdate,
          actions: [
            ZirenDialogAction(
              label: action,
              value: true,
              kind:
                  resolving ? ZirenActionKind.success : ZirenActionKind.primary,
            ),
            ZirenDialogAction(label: l.respCancel, value: false),
          ],
        ) ??
        false;
  }

  /// Navigate to the scene, ON ZIREN'S OWN MAP.
  ///
  /// This used to fire a `geo:` intent and leave the app entirely. Ziren has
  /// a map of its own, and handing the crew to another product to look at the
  /// same island made that map decorative. Worse: the moment they switched
  /// away, the status buttons, the approach hazards, the reporter's number and
  /// the acceptance countdown were all an app-switch away — at exactly the
  /// moment those matter most.
  ///
  /// IncidentNavigationScreen keeps them here: the scene, their live position,
  /// the distance, the bearing, and an ETA computed from the same 30 km/h the
  /// backend uses for the resident's, so the crew and the family waiting are
  /// never told different numbers.
  ///
  /// It is guidance, not turn-by-turn — there is no routing engine in this
  /// deployment — so the hand-off to Google Maps survives as a clearly
  /// labelled second choice inside that screen, rather than as the only thing
  /// this button could ever do.
  ///
  /// Coordinates are required for that path. An incident carrying only an
  /// address still falls back to an external search, and one with neither says
  /// so rather than doing nothing.
  Future<void> _launchNavigation(
    double? lat,
    double? lng,
    String? address,
  ) async {
    if (lat != null && lng != null) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder:
              (_) => IncidentNavigationScreen(
                latitude: lat,
                longitude: lng,
                title: AppLocalizations.of(context).respIncident,
                address: address,
              ),
        ),
      );
      return;
    }

    if (address == null || address.trim().isEmpty) {
      _toast(
        context,
        AppLocalizations.of(context).respNoLocationRecorded,
        ZirenTokens.systemWarning,
      );
      return;
    }

    // Nothing to draw, so somebody else's search is the only useful thing
    // left. canLaunchUrl is deliberately not used as a gate: on Android 11+
    // it returns false for any intent the manifest's <queries> block does not
    // declare, which turns a working maps app into a dead button for a reason
    // invisible from the phone.
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query='
      '${Uri.encodeComponent(address.trim())}',
    );
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // fall through to the message below
    }
    if (!mounted) return;
    _toast(
      context,
      'Walang mabuksang mapa sa telepono na ito.',
      ZirenTokens.systemError,
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ResponderProvider>();
    final incident = provider.detailIncident;

    return Scaffold(
      backgroundColor: kHomeCanvas,
      appBar: AppBar(
        backgroundColor: ZirenTokens.surfaceCard,
        surfaceTintColor: Colors.transparent,
        leading: BackButton(onPressed: () => context.pop()),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              incident?.categoryLabel ??
                  AppLocalizations.of(context).respIncident,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: ZirenTokens.textPrimary,
              ),
            ),
            if (incident != null)
              Text(
                incident.shortId,
                style: TextStyle(fontSize: 12, color: ZirenTokens.textMuted),
              ),
          ],
        ),
      ),
      body: SafeArea(
        bottom: false,
        child:
            provider.loadingDetail
                ? const Center(child: LoadingIndicator())
                : provider.detailError != null
                ? _ErrorView(message: provider.detailError!)
                : incident == null
                ? const Center(child: LoadingIndicator())
                : _DetailBody(
                  incident: incident,
                  provider: provider,
                  onAdvanceStatus:
                      (newStatus) =>
                          _advanceStatus(context, incident, newStatus),
                  onAccept: () => _accept(context, incident),
                  onDecline: () => _decline(context, incident),
                  onRequestBackup: () => _requestBackup(context, incident),
                  onEscalate: () => _escalate(context, incident),
                  onPanic: () => _raiseDistress(context, incident),
                  onNavigate:
                      () => _launchNavigation(
                        incident.latitude,
                        incident.longitude,
                        incident.locationAddress ?? incident.landmarkNote,
                      ),
                ),
      ),
    );
  }
}

// ── Detail body ───────────────────────────────────────────────

/// The call, top to bottom in the order a crew needs it: warnings on the
/// road, what happened, where the assignment stands, where to go, who to
/// call. The one button that moves the call forward is pinned to the bottom
/// of the screen, under the thumb, instead of at the top where it had to be
/// reached for - and it is the only full-width coloured button on the page.
class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.incident,
    required this.provider,
    required this.onAdvanceStatus,
    required this.onAccept,
    required this.onDecline,
    required this.onRequestBackup,
    required this.onEscalate,
    required this.onPanic,
    required this.onNavigate,
  });
  final ResponderIncidentModel incident;
  final ResponderProvider provider;
  final ValueSetter<String> onAdvanceStatus;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onRequestBackup;
  final VoidCallback onEscalate;
  final VoidCallback onPanic;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final closed = ResponderVocabulary.isClosed(incident);
    final hasAction =
        incident.needsAnswer ||
        (incident.nextStatus != null && incident.nextActionLabel != null);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Approach hazards ─────────────────────────
                //
                // FIRST, above the report itself. A crew reads this screen
                // in the cab before pulling away; a cut bridge found at the
                // bottom of the page is a cut bridge found by arriving at it.
                if (incident.hazards.isNotEmpty)
                  _HazardBanner(hazards: incident.hazards),

                if (provider.statusUpdateError != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: ZirenTokens.space12),
                    padding: const EdgeInsets.all(ZirenTokens.space12),
                    decoration: BoxDecoration(
                      color: ZirenTokens.systemErrorBg,
                      borderRadius: BorderRadius.circular(ZirenTokens.radius12),
                      border: Border.all(
                        color: ZirenTokens.systemError.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      provider.statusUpdateError!,
                      style: const TextStyle(
                        color: ZirenTokens.systemError,
                        fontSize: 13,
                      ),
                    ),
                  ),

                // ── What happened ────────────────────────────
                _SummaryCard(incident: incident),

                // ── Where the assignment stands ──────────────
                if (closed)
                  _ClosedBanner(text: t.respClosedBanner)
                else
                  _DetailCard(
                    icon: LucideIcons.route,
                    title: t.respStepsTitle,
                    child: AssignmentProgress(incident: incident),
                  ),

                // ── Where ────────────────────────────────────
                _DetailCard(
                  icon: LucideIcons.map_pin,
                  title: t.respCardLocation,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        incident.locationAddress ?? t.respNoLocation,
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.3,
                          fontWeight: FontWeight.w800,
                          color: ZirenTokens.textPrimary,
                        ),
                      ),
                      if (incident.landmarkNote?.trim().isNotEmpty == true) ...[
                        const SizedBox(height: ZirenTokens.space10),
                        _LandmarkBox(
                          label: t.respFieldLandmark,
                          value: incident.landmarkNote!.trim(),
                        ),
                      ],
                      if (incident.latitude != null &&
                          incident.longitude != null) ...[
                        const SizedBox(height: ZirenTokens.space12),
                        _InlineMap(
                          lat: incident.latitude!,
                          lng: incident.longitude!,
                        ),
                        const SizedBox(height: ZirenTokens.space8),
                        _GpsRow(
                          lat: incident.latitude!,
                          lng: incident.longitude!,
                        ),
                      ],
                      if (!closed) ...[
                        const SizedBox(height: ZirenTokens.space12),
                        OutlinedButton.icon(
                          icon: const Icon(LucideIcons.navigation, size: 18),
                          label: Text(t.respNavigate),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: ZirenTokens.brandOrange,
                            minimumSize: const Size.fromHeight(48),
                            side: const BorderSide(
                              color: ZirenTokens.brandOrange,
                              width: 1.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            textStyle: responderButtonText(
                              context,
                              14.5,
                              FontWeight.w800,
                            ),
                          ),
                          onPressed: onNavigate,
                        ),
                      ],
                    ],
                  ),
                ),

                // ── Who reported ─────────────────────────────
                _ReporterCard(incident: incident),

                // ── Station ──────────────────────────────────
                if (incident.stationName != null)
                  _DetailCard(
                    icon: LucideIcons.building,
                    title: t.respCardStation,
                    child: Text(
                      [
                        incident.stationName!,
                        if (incident.stationAddress?.isNotEmpty == true)
                          incident.stationAddress!,
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: ZirenTokens.textSecondary,
                      ),
                    ),
                  ),

                // ── Field updates / communication ────────────
                //
                // Only once the crew has actually taken the call.
                if (incident.status != 'dispatched' ||
                    incident.isAcceptedNotMoving) ...[
                  const SizedBox(height: ZirenTokens.space4),
                  ResponderNotesPanel(incidentId: incident.id),
                ],

                // Mutual aid, scene photos and the responder's own panic
                // button. Last on the page, far from the status button that
                // is pressed on every call.
                if (!closed)
                  _EmergencyActions(
                    incidentId: incident.id,
                    sceneCaptureEnabled: incident.status == 'arrived',
                    onRequestBackup: onRequestBackup,
                    onEscalate: onEscalate,
                    onPanic: onPanic,
                    busy: provider.answering || provider.raisingDistress,
                  ),
              ],
            ),
          ),
        ),

        // ── The next step, under the thumb ───────────────────
        if (hasAction)
          _StatusActionBar(
            incident: incident,
            provider: provider,
            onAdvanceStatus: onAdvanceStatus,
            onAccept: onAccept,
            onDecline: onDecline,
          ),
      ],
    );
  }
}

// ── Summary ───────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.incident});

  final ResponderIncidentModel incident;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final closed = ResponderVocabulary.isClosed(incident);
    final assigned = incident.dispatchedAt;
    return Container(
      margin: const EdgeInsets.only(bottom: ZirenTokens.space12),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: ZirenTokens.surfaceBorder.withValues(alpha: 0.8),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 5,
              color:
                  closed
                      ? ZirenTokens.surfaceBorder
                      : ResponderVocabulary.color(incident.severity),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(ZirenTokens.space16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CategoryTile(
                          category: incident.incidentCategory,
                          severity: incident.severity,
                          closed: closed,
                          size: 46,
                        ),
                        const SizedBox(width: ZirenTokens.space12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                incident.categoryLabel,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: ZirenTokens.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                incident.shortId,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: ZirenTokens.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: ZirenTokens.space12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        SeverityChip(
                          severity: incident.severity,
                          muted: closed,
                        ),
                        PhaseChip(incident: incident),
                        if (incident.sosFlag && !closed) const SosChip(),
                      ],
                    ),
                    const SizedBox(height: ZirenTokens.space12),
                    Text(
                      t.respCardReport.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                        color: ZirenTokens.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      incident.reportText,
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                        color: ZirenTokens.textPrimary,
                      ),
                    ),
                    // Directly under the text: when the transcript and the
                    // recording disagree, nobody should have to go looking
                    // for the recording to find that out.
                    ResponderVoiceNote(incidentId: incident.id),
                    const SizedBox(height: ZirenTokens.space10),
                    Row(
                      children: [
                        Icon(
                          LucideIcons.clock,
                          size: 13,
                          color: ZirenTokens.textMuted,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            [
                              t.respReportedAgo(
                                ResponderVocabulary.elapsed(incident.createdAt),
                              ),
                              if (assigned != null)
                                t.respAssignedAgo(
                                  ResponderVocabulary.elapsed(assigned),
                                ),
                            ].join(' · '),
                            style: TextStyle(
                              fontSize: 12,
                              color: ZirenTokens.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClosedBanner extends StatelessWidget {
  const _ClosedBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: ZirenTokens.space12),
      padding: const EdgeInsets.all(ZirenTokens.space12),
      decoration: BoxDecoration(
        color: ZirenTokens.statusResolvedBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: ZirenTokens.statusResolved.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            LucideIcons.circle_check_big,
            size: 18,
            color: ZirenTokens.statusResolved,
          ),
          const SizedBox(width: ZirenTokens.space8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: ZirenTokens.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LandmarkBox extends StatelessWidget {
  const _LandmarkBox({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space10),
      decoration: BoxDecoration(
        color: ZirenTokens.brandSubtle,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(
            LucideIcons.landmark,
            size: 18,
            color: ZirenTokens.brandOrange,
          ),
          const SizedBox(width: ZirenTokens.space10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: ZirenTokens.textSecondary,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: ZirenTokens.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GpsRow extends StatelessWidget {
  const _GpsRow({required this.lat, required this.lng});

  final double lat;
  final double lng;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
    return Row(
      children: [
        Icon(LucideIcons.locate_fixed, size: 14, color: ZirenTokens.textMuted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '${t.respFieldGps}  $text',
            style: TextStyle(fontSize: 12.5, color: ZirenTokens.textSecondary),
          ),
        ),
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: text));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(t.respGpsCopied),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
          icon: const Icon(LucideIcons.copy, size: 14),
          label: Text(t.respCopy),
          style: TextButton.styleFrom(
            foregroundColor: ZirenTokens.textSecondary,
            visualDensity: VisualDensity.compact,
            textStyle: responderButtonText(context, 12.5, FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

// ── Reporter ──────────────────────────────────────────────────

class _ReporterCard extends StatelessWidget {
  const _ReporterCard({required this.incident});

  final ResponderIncidentModel incident;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final name = incident.reporterName?.trim();
    return _DetailCard(
      icon: LucideIcons.user_round,
      title: t.respCardReporter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: ZirenTokens.surfaceRaised,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  name?.isNotEmpty == true ? initialsOf(name!) : '?',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: ZirenTokens.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: ZirenTokens.space10),
              Expanded(
                child: Text(
                  name?.isNotEmpty == true ? name! : t.respReporterUnknown,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: ZirenTokens.textPrimary,
                  ),
                ),
              ),
              _TrustChip(
                icon:
                    incident.reporterVerified
                        ? LucideIcons.badge_check
                        : LucideIcons.circle_question_mark,
                label:
                    incident.reporterVerified
                        ? t.respVerified
                        : t.respUnverified,
                color:
                    incident.reporterVerified
                        ? ZirenTokens.systemSuccess
                        : ZirenTokens.textMuted,
              ),
            ],
          ),
          if (incident.reporterWarningCount > 0 || incident.sosFlag) ...[
            const SizedBox(height: ZirenTokens.space8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (incident.reporterWarningCount > 0)
                  _TrustChip(
                    icon: LucideIcons.triangle_alert,
                    label: t.respPriorWarnings(incident.reporterWarningCount),
                    color: ZirenTokens.systemWarning,
                  ),
                if (incident.sosFlag)
                  _TrustChip(
                    icon: LucideIcons.megaphone,
                    label: t.respSosFlagged,
                    color: ZirenTokens.severityCritical,
                  ),
              ],
            ),
          ],
          if (incident.reporterPhone != null) ...[
            const SizedBox(height: ZirenTokens.space12),
            _CallRow(label: t.respFieldPhone, phone: incident.reporterPhone!),
          ],
          if (incident.emergencyContactNumber != null ||
              incident.emergencyContactName != null) ...[
            const SizedBox(height: ZirenTokens.space8),
            _CallRow(
              label: [
                t.respEmergencyContactShort,
                if (incident.emergencyContactName?.isNotEmpty == true)
                  incident.emergencyContactName!,
              ].join(' · '),
              phone: incident.emergencyContactNumber,
            ),
          ],
        ],
      ),
    );
  }
}

/// A number with a real Call button, not an underlined link: a crew in
/// gloves needs a target, and the old orange underline read as decoration.
class _CallRow extends StatelessWidget {
  const _CallRow({required this.label, required this.phone});

  final String label;
  final String? phone;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceRaised.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.phone, size: 16, color: ZirenTokens.textSecondary),
          const SizedBox(width: ZirenTokens.space10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: ZirenTokens.textMuted,
                  ),
                ),
                Text(
                  phone ?? '—',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: ZirenTokens.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          if (phone != null)
            FilledButton.icon(
              onPressed: () async {
                try {
                  await launchUrl(Uri(scheme: 'tel', path: phone));
                } catch (_) {
                  // No dialer: nothing else useful to do from here.
                }
              },
              icon: const Icon(LucideIcons.phone_call, size: 16),
              label: Text(t.respCall),
              style: FilledButton.styleFrom(
                backgroundColor: ZirenTokens.systemSuccess,
                foregroundColor: Colors.white,
                elevation: 0,
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: responderButtonText(context, 13.5, FontWeight.w800),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Status action bar (bottom) ────────────────────────────────

class _StatusActionBar extends StatelessWidget {
  const _StatusActionBar({
    required this.incident,
    required this.provider,
    required this.onAdvanceStatus,
    required this.onAccept,
    required this.onDecline,
  });
  final ResponderIncidentModel incident;
  final ResponderProvider provider;
  final ValueSetter<String> onAdvanceStatus;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final nextStatus = incident.nextStatus;
    final nextLabel = incident.nextActionLabel;

    // UNANSWERED ASSIGNMENTS DO NOT GET A STATUS BUTTON. Letting a crew tap
    // "En Route" without accepting would leave the dispatcher's board showing
    // an unanswered assignment for someone already driving to it.
    final awaitingAnswer = incident.needsAnswer;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        border: Border(top: BorderSide(color: ZirenTokens.surfaceBorder)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (awaitingAnswer) ...[
              _AckCountdown(ack: incident.ack),
              const SizedBox(height: ZirenTokens.space10),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: ElevatedButton.icon(
                      onPressed: provider.answering ? null : onAccept,
                      icon:
                          provider.answering
                              ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(
                                    Colors.white,
                                  ),
                                ),
                              )
                              : const Icon(LucideIcons.check, size: 20),
                      label: Text(t.respAccept),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ZirenTokens.systemSuccess,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        minimumSize: const Size.fromHeight(54),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: responderButtonText(
                          context,
                          15,
                          FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: ZirenTokens.space8),
                  Expanded(
                    flex: 2,
                    child: OutlinedButton(
                      onPressed: provider.answering ? null : onDecline,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: ZirenTokens.systemError,
                        side: BorderSide(
                          color: ZirenTokens.systemError.withValues(alpha: 0.5),
                          width: 1.4,
                        ),
                        minimumSize: const Size.fromHeight(54),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: responderButtonText(
                          context,
                          13.5,
                          FontWeight.w800,
                        ),
                      ),
                      child: Text(t.respDecline, textAlign: TextAlign.center),
                    ),
                  ),
                ],
              ),
            ] else if (nextStatus != null && nextLabel != null) ...[
              // What this button does, said before the button does it.
              Row(
                children: [
                  Text(
                    t.respNextStep.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                      color: ZirenTokens.textMuted,
                    ),
                  ),
                  const Spacer(),
                  if (incident.isAcceptedNotMoving)
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            LucideIcons.circle_check_big,
                            size: 13,
                            color: ZirenTokens.systemSuccess,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              t.respStatusAccepted,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: ZirenTokens.systemSuccess,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (incident.status == 'en_route' &&
                      incident.etaLabel(t) != null)
                    Flexible(
                      child: Text(
                        t.respTellingResident(incident.etaLabel(t) ?? ''),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: ZirenTokens.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: ZirenTokens.space8),
              ElevatedButton.icon(
                onPressed:
                    provider.updatingStatus
                        ? null
                        : () => onAdvanceStatus(nextStatus),
                icon:
                    provider.updatingStatus
                        ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                        : Icon(switch (nextStatus) {
                          'resolved' => LucideIcons.circle_check_big,
                          'arrived' => LucideIcons.map_pin_check,
                          _ => LucideIcons.navigation,
                        }, size: 22),
                label: Text(nextLabel),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      nextStatus == 'resolved'
                          ? ZirenTokens.systemSuccess
                          : ZirenTokens.brandOrange,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: responderButtonText(context, 16, FontWeight.w900),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The same window the dispatcher's board is watching.
///
/// Shown so a crew knows when their silence is about to become somebody
/// else's problem. Nothing punitive happens when it expires — the incident
/// simply turns loud on the board and a human reassigns it — and the copy
/// says so rather than leaving a red bar to imply otherwise.
class _AckCountdown extends StatelessWidget {
  const _AckCountdown({required this.ack});

  final ResponderAck ack;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final overdue = ack.isOverdue;
    final color = overdue ? ZirenTokens.systemError : ZirenTokens.systemWarning;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              overdue ? LucideIcons.bell_ring : LucideIcons.timer,
              size: 15,
              color: color,
            ),
            const SizedBox(width: ZirenTokens.space4),
            Expanded(
              child: Text(
                overdue
                    ? t.respNoAnswerSeen
                    : t.respAnswerWithin(ack.remainingLabel),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
            if (ack.declineCount > 0)
              Text(
                t.respDeclinedTimes(ack.declineCount),
                style: TextStyle(fontSize: 11, color: ZirenTokens.textMuted),
              ),
          ],
        ),
        const SizedBox(height: ZirenTokens.space6),
        ClipRRect(
          borderRadius: BorderRadius.circular(ZirenTokens.radius4),
          child: LinearProgressIndicator(
            value: ack.elapsedFraction,
            minHeight: 5,
            backgroundColor: color.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}

// ── Detail card ───────────────────────────────────────────────

class _DetailCard extends StatelessWidget {
  const _DetailCard({
    required this.icon,
    required this.title,
    required this.child,
  });
  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: ZirenTokens.space12),
      padding: const EdgeInsets.all(ZirenTokens.space16),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: ZirenTokens.surfaceBorder.withValues(alpha: 0.8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: ZirenTokens.textSecondary),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: ZirenTokens.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: ZirenTokens.space12),
          child,
        ],
      ),
    );
  }
}

// ── Trust chip ────────────────────────────────────────────────

class _TrustChip extends StatelessWidget {
  const _TrustChip({
    required this.icon,
    required this.label,
    required this.color,
  });
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 3, 9, 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(ZirenTokens.radius32),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Error view ────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ZirenTokens.space32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.circle_alert,
              size: 48,
              color: ZirenTokens.textMuted,
            ),
            const SizedBox(height: ZirenTokens.space12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: ZirenTokens.textSecondary),
            ),
            const SizedBox(height: ZirenTokens.space16),
            ElevatedButton(
              onPressed: () => context.pop(),
              child: Text(AppLocalizations.of(context).respGoBack),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Inline map preview ────────────────────────────────────────
// Non-interactive pin preview shown inside the LOCATION card.
// TODO 6C.1: swap assets/map/biliran.mbtiles stub with real tile file.

class _InlineMap extends StatefulWidget {
  const _InlineMap({required this.lat, required this.lng});
  final double lat;
  final double lng;

  @override
  State<_InlineMap> createState() => _InlineMapState();
}

class _InlineMapState extends State<_InlineMap> {
  String? _styleJson;

  @override
  void initState() {
    super.initState();
    // WAS: rootBundle.loadString('assets/map/style.json').
    //
    // That style's vector source is http://localhost:7654 — a tile server on
    // the developer's machine. On a handset `localhost` IS the handset, so
    // nothing ever answered: MapLibre painted only the style's background
    // layer and the crew got a flat beige rectangle where the scene should
    // be. No error and no log — a blank map looks exactly like one that has
    // not finished loading.
    //
    // assets/map/biliran.mbtiles is the offline answer for a province with
    // patchy coverage — TODO 6C.1 is done, see offline_map_service.dart.
    // resolveStyle() picks satellite when reachable and the offline vector
    // style, served locally from that mbtiles file, when it is not.
    OfflineMapService.instance.resolveStyle().then((style) {
      if (mounted) setState(() => _styleJson = style);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_styleJson == null) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          color: ZirenTokens.surfaceRaised,
          borderRadius: BorderRadius.circular(ZirenTokens.radius8),
        ),
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 180,
        child: MapLibreMap(
          styleString: _styleJson!,
          initialCameraPosition: CameraPosition(
            target: LatLng(widget.lat, widget.lng),
            zoom: 15.0,
          ),
          // Disable all interaction — this is a static preview
          scrollGesturesEnabled: false,
          zoomGesturesEnabled: false,
          rotateGesturesEnabled: false,
          tiltGesturesEnabled: false,
          onMapCreated: (ctrl) async {
            await ctrl.addSymbol(
              SymbolOptions(
                geometry: LatLng(widget.lat, widget.lng),
                iconImage: 'marker-15',
                iconColor: '#E53935',
                iconSize: 2.0,
              ),
            );
          },
        ),
      ),
    );
  }
}

// ── Approach hazards ──────────────────────────────────────────

/// Standing local knowledge about reaching this place.
///
/// Amber rather than red, deliberately. Red is reserved for critical severity
/// across this whole product (see app_tokens.dart) and a hazard is not the
/// emergency — borrowing the colour would blunt the one that matters.
class _HazardBanner extends StatelessWidget {
  const _HazardBanner({required this.hazards});

  final List<ApproachHazard> hazards;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: ZirenTokens.space12),
      padding: const EdgeInsets.all(ZirenTokens.space12),
      decoration: BoxDecoration(
        color: ZirenTokens.systemWarningBg,
        borderRadius: BorderRadius.circular(ZirenTokens.radius12),
        border: Border.all(
          color: ZirenTokens.systemWarning.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                LucideIcons.triangle_alert,
                size: 18,
                color: ZirenTokens.systemWarning,
              ),
              const SizedBox(width: ZirenTokens.space6),
              Flexible(
                child: Text(
                  AppLocalizations.of(context).respHazardBanner(hazards.length),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: ZirenTokens.systemWarning,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: ZirenTokens.space8),
          for (final h in hazards)
            Padding(
              padding: const EdgeInsets.only(bottom: ZirenTokens.space6),
              child: RichText(
                text: TextSpan(
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: ZirenTokens.textPrimary,
                  ),
                  children: [
                    TextSpan(
                      text: '${h.typeLabel(AppLocalizations.of(context))} · ',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: h.note),
                    TextSpan(
                      text: '  (${h.distanceLabel})',
                      style: TextStyle(
                        color: ZirenTokens.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Mutual aid + responder safety ─────────────────────────────

/// The two things a crew needs that are not about the incident's status.
///
/// Placed at the very bottom of the scroll on purpose. Both are rare, and
/// putting either near the status buttons — which are pressed on every single
/// call — would make a misfire a matter of one wrong thumb.
class _EmergencyActions extends StatelessWidget {
  const _EmergencyActions({
    required this.incidentId,
    required this.sceneCaptureEnabled,
    required this.onRequestBackup,
    required this.onEscalate,
    required this.onPanic,
    required this.busy,
  });

  final String incidentId;
  final bool sceneCaptureEnabled;
  final VoidCallback onRequestBackup;
  final VoidCallback onEscalate;
  final VoidCallback onPanic;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: ZirenTokens.space16),

        // Grouped as rows in one card rather than three stacked outline
        // buttons — see IncidentActionRow's doc comment for why. Each
        // icon keeps its own semantic colour (info for mutual aid,
        // high-severity amber for escalation); only the shape changed.
        IncidentActionCard(
          children: [
            IncidentActionRow(
              icon: LucideIcons.megaphone,
              iconColor: ZirenTokens.systemInfo,
              label: AppLocalizations.of(context).respBackupAction,
              onTap: busy ? null : onRequestBackup,
            ),
            // "Worse than assessed" — Section 14. Distinct from mutual aid:
            // this does not ask for another agency, it tells THIS one the
            // severity may be wrong, so the Agency Admin can reassess.
            IncidentActionRow(
              icon: LucideIcons.triangle_alert,
              iconColor: ZirenTokens.severityHigh,
              label: 'Escalate Incident',
              onTap: busy ? null : onEscalate,
            ),
            SceneCaptureButton(
              incidentId: incidentId,
              enabled: sceneCaptureEnabled,
            ),
          ],
        ),
        const SizedBox(height: ZirenTokens.space16),

        // LONG PRESS, not tap. This is the one control on the screen whose
        // accidental activation costs somebody else's emergency: a dispatcher
        // drops what they are doing and a unit is diverted. A deliberate hold
        // is the cheapest possible guard, and a crew in genuine trouble can
        // still do it one-handed without looking.
        Semantics(
          button: true,
          label: AppLocalizations.of(context).respDistressSemantics,
          child: GestureDetector(
            onLongPress: busy ? null : onPanic,
            child: Container(
              padding: const EdgeInsets.symmetric(
                vertical: ZirenTokens.space16,
              ),
              decoration: BoxDecoration(
                color: ZirenTokens.systemErrorBg,
                borderRadius: BorderRadius.circular(ZirenTokens.radius12),
                border: Border.all(
                  color: ZirenTokens.systemError.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                children: [
                  const Icon(
                    LucideIcons.siren,
                    color: ZirenTokens.systemError,
                    size: 26,
                  ),
                  const SizedBox(height: ZirenTokens.space4),
                  Text(
                    AppLocalizations.of(context).respDistressHold,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: ZirenTokens.systemError,
                    ),
                  ),
                  SizedBox(height: ZirenTokens.space2),
                  Text(
                    AppLocalizations.of(context).respDistressHoldBody,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: ZirenTokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: ZirenTokens.space24),
      ],
    );
  }
}
