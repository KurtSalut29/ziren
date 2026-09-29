import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../domain/incident_category_style.dart';
import '../domain/incident_provider.dart';
import '../domain/nearest_station.dart';
import '../../../l10n/app_localizations.dart';
import 'incident_labels.dart';
import 'widgets/quick_report_kit.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../hotlines/presentation/hotlines_view.dart';

/// Quick report — step 2 of 2. Everything collected on the previous screen,
/// echoed back for a last look before it becomes a real dispatch.
///
/// Sending here commits a crew and a vehicle — the same guard the SOS path
/// and the full 5W1H wizard both carry, for the same reason.
class QuickReportReviewScreen extends StatefulWidget {
  const QuickReportReviewScreen({super.key});

  @override
  State<QuickReportReviewScreen> createState() =>
      _QuickReportReviewScreenState();
}

class _QuickReportReviewScreenState extends State<QuickReportReviewScreen> {
  bool _sending = false;

  /// [nearest] is null when the station list could not be loaded (e.g. a slow
  /// or momentarily flaky connection). The report is then sent with the GPS
  /// fix alone: the server picks the nearest station itself.
  Future<void> _send(IncidentProvider p, NearestStation? nearest) async {
    final t = AppLocalizations.of(context);
    setState(() => _sending = true);
    if (nearest != null) {
      p.selectStation(nearest.station);
    } else {
      // The provider outlives each report; without this the last report's
      // station would ride along with this one.
      p.clearSelectedStation();
    }

    final label = IncidentLabels.categoryShort(t, p.incidentCategory!);
    final note = p.quickNote?.trim() ?? '';

    final hadVoiceNote = p.voiceNote != null;

    // The backend requires report_text to be at least 10 characters, and
    // every category's short label ("Fire", "Accident", ...) is shorter
    // than that on its own — a submission with nothing typed used to send
    // just the bare label and get rejected with a 422 every single time,
    // for every category, with no way for a resident relying on voice (or
    // submitting on category alone — neither the note nor the recording is
    // required to reach this screen) to ever get a report through. The
    // transcript can't fill the gap either: it's generated asynchronously,
    // after the report is already saved, so it isn't available yet at
    // submission time. Both fallbacks are long enough on their own and say
    // plainly what's actually true right now, rather than claiming a
    // recording exists when the resident never made one.
    final reportText =
        note.isNotEmpty
            ? '$label — $note'
            : hadVoiceNote
            ? t.quickVoiceOnlyReportText(label)
            : t.quickNoDetailsReportText(label);

    final ok = await p.submitIncident(
      reportText: reportText,
      locationAddress: p.incidentAddress,
    );

    if (!mounted) return;
    setState(() => _sending = false);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: ZirenTokens.systemSuccess,
          content: Text(
            // The pre-selected station's name is only shown when the server
            // actually resolved one from it: without a loaded station list,
            // the backend picked the nearest station from coordinates alone,
            // and that pick is not guaranteed to match what was shown here.
            nearest != null
                ? t.quickSentTo(nearest.station.name)
                : t.reportReceivedBody,
          ),
        ),
      );
      final id = p.lastSubmitted?.id;
      if (hadVoiceNote && id != null) {
        context
            .push(
              '/report/confirm/$id'
              '${nearest != null ? '?station=${Uri.encodeComponent(nearest.station.name)}' : ''}',
            )
            .then((_) {
              if (mounted) context.go('/my-reports');
            });
      } else {
        context.go('/my-reports');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final p = context.watch<IncidentProvider>();
    final category = p.incidentCategory;

    if (category == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => context.go('/home'));
      return const SizedBox.shrink();
    }

    final nearest = NearestStationResolver.resolve(p);
    // Sendable with a station OR with a GPS fix alone: the station list is a
    // separate network call from the report submit itself, and requiring it
    // to succeed first means one slow call can block a report the actual
    // submit would have gotten through fine.
    final canSend = nearest != null || p.incidentLat != null;
    final agencyName = switch (nearest?.station.agencyType) {
      'BFP' => t.agencyBfp,
      'PNP' => t.agencyPnp,
      'MDRRMO' => t.agencyMdrrmo,
      _ => t.quickReviewReceivingAgency,
    };

    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      appBar: AppBar(
        title: Text(t.quickReviewTitle),
        leading: BackButton(onPressed: () => context.pop()),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: ZirenTokens.space16),
            child: Center(child: QuickReportStepDots(step: 2)),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(ZirenTokens.space16),
                children: [
                  // ── Careful-review banner ─────────────────
                  Container(
                    padding: const EdgeInsets.all(ZirenTokens.space12),
                    decoration: BoxDecoration(
                      color: ZirenTokens.severityCriticalBg,
                      borderRadius: BorderRadius.circular(ZirenTokens.radius12),
                      border: Border.all(
                        color: ZirenTokens.severityCriticalBorder,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          LucideIcons.shield,
                          size: 18,
                          color: ZirenTokens.severityCritical,
                        ),
                        const SizedBox(width: ZirenTokens.space10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                t.quickReviewCareful,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: ZirenTokens.severityCritical,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                t.quickReviewWillSendTo(agencyName),
                                style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.35,
                                  color: ZirenTokens.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: ZirenTokens.space16),

                  // ── Category ────────────────────────────────
                  _ReviewCard(
                    onEdit: () => context.pop(),
                    editLabel: t.actionEdit,
                    child: Row(
                      children: [
                        Icon(
                          IncidentCategoryStyle.icon(category),
                          size: 20,
                          color: IncidentCategoryStyle.color(category),
                        ),
                        const SizedBox(width: ZirenTokens.space10),
                        Flexible(child: Text(
                          IncidentLabels.categoryShort(t, category),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: IncidentCategoryStyle.color(category),
                          ),
                        )),
                      ],
                    ),
                  ),

                  const SizedBox(height: ZirenTokens.space12),

                  // ── Location + landmark + description ─────
                  _ReviewCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ReviewRow(
                          icon: LucideIcons.map_pin,
                          label: t.reviewLocation,
                          value:
                              p.incidentAddress ??
                              (p.incidentLat != null
                                  ? '${p.incidentLat!.toStringAsFixed(5)}, '
                                      '${p.incidentLng!.toStringAsFixed(5)}'
                                  : t.reviewNoGps),
                        ),
                        // Said out loud, so a resident who placed the incident
                        // elsewhere sees that the station will know it.
                        if (p.reportingElsewhere) ...[
                          const _ReviewDivider(),
                          _ReviewRow(
                            icon: LucideIcons.user_round,
                            label: t.locReviewReporterLabel,
                            value: p.locationAddress ?? t.locReviewReporterUnknown,
                          ),
                        ],
                        if (p.landmarkNote != null) ...[
                          const _ReviewDivider(),
                          _ReviewRow(
                            icon: LucideIcons.signpost,
                            label: t.quickLandmark,
                            value: p.landmarkNote!,
                          ),
                        ],
                        if ((p.quickNote?.trim().isNotEmpty ?? false)) ...[
                          const _ReviewDivider(),
                          _ReviewRow(
                            icon: LucideIcons.notebook_text,
                            label: t.quickReviewDescription,
                            value: p.quickNote!.trim(),
                          ),
                        ],
                      ],
                    ),
                  ),

                  if (p.voiceNote != null) ...[
                    const SizedBox(height: ZirenTokens.space12),
                    _ReviewCard(child: _VoiceReviewRow(provider: p)),
                  ],

                  if (p.selectedMedia.isNotEmpty) ...[
                    const SizedBox(height: ZirenTokens.space12),
                    _ReviewCard(
                      onEdit: () => context.pop(),
                      editLabel: t.actionEdit,
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(
                              ZirenTokens.radius8,
                            ),
                            child: Image.file(
                              p.selectedMedia.first,
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: ZirenTokens.space10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  t.quickReviewPhoto,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: ZirenTokens.textMuted,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  t.quickReviewAttachedCount(
                                    p.selectedMedia.length,
                                  ),
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: ZirenTokens.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: ZirenTokens.space12),

                  // ── Receiving agency ────────────────────────
                  _ReviewCard(
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: ZirenTokens.brandSubtle,
                            borderRadius: BorderRadius.circular(
                              ZirenTokens.radius8,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            LucideIcons.truck,
                            size: 18,
                            color: ZirenTokens.brandOrange,
                          ),
                        ),
                        const SizedBox(width: ZirenTokens.space10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                t.quickReviewReceivingAgency,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: ZirenTokens.textMuted,
                                  letterSpacing: 0.6,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                nearest != null
                                    ? '$agencyName — ${nearest.station.name}'
                                    // "Your location is needed" only when it
                                    // really is missing; a GPS fix with no
                                    // station list is a different situation.
                                    : p.incidentLat != null
                                    ? t.quickStationAuto
                                    : t.quickStationUnknown,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: ZirenTokens.textPrimary,
                                ),
                              ),
                              if (nearest != null)
                                Text(
                                  t.quickReviewAway(
                                    nearest.km.toStringAsFixed(1),
                                  ),
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
                  ),

                  if (p.submitError != null) ...[
                    const SizedBox(height: ZirenTokens.space12),
                    Container(
                      padding: const EdgeInsets.all(ZirenTokens.space12),
                      decoration: BoxDecoration(
                        color: ZirenTokens.systemErrorBg,
                        borderRadius: BorderRadius.circular(
                          ZirenTokens.radius12,
                        ),
                        border: Border.all(
                          color: ZirenTokens.severityCriticalBorder,
                        ),
                      ),
                      child: Text(
                        p.submitError!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: ZirenTokens.systemError,
                        ),
                      ),
                    ),
                    // Nothing reached the server. A call still gets through
                    // where this did not — offer the stations for this kind
                    // of emergency right here, nearest first.
                    if (p.submitFailedOffline) ...[
                      const SizedBox(height: ZirenTokens.space10),
                      SizedBox(
                        height: 50,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: ZirenTokens.systemSuccess,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(LucideIcons.phone, size: 18),
                          label: Text(t.hotlinesCallInstead),
                          onPressed: () => showHotlinesSheet(
                            context,
                            category: p.incidentCategory,
                            offline: true,
                          ),
                        ),
                      ),
                    ],
                  ],

                  const SizedBox(height: ZirenTokens.space16),
                ],
              ),
            ),

            // ── Edit / Send bar ───────────────────────────────
            Container(
              padding: EdgeInsets.fromLTRB(
                ZirenTokens.space16,
                ZirenTokens.space12,
                ZirenTokens.space16,
                ZirenTokens.space12 + MediaQuery.of(context).padding.bottom,
              ),
              decoration: BoxDecoration(
                color: ZirenTokens.surfaceCard,
                border: Border(
                  top: BorderSide(color: ZirenTokens.surfaceBorder),
                ),
              ),
              child:
                  _sending
                      ? const LoadingIndicator()
                      : Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => context.pop(),
                              child: Text(t.actionEdit),
                            ),
                          ),
                          const SizedBox(width: ZirenTokens.space12),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              onPressed:
                                  canSend ? () => _send(p, nearest) : null,
                              child: Text(t.quickSendReport),
                            ),
                          ),
                        ],
                      ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewDivider extends StatelessWidget {
  const _ReviewDivider();

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: ZirenTokens.space10),
    child: Divider(height: 1, color: ZirenTokens.surfaceBorder),
  );
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.child, this.onEdit, this.editLabel});
  final Widget child;
  final VoidCallback? onEdit;
  final String? editLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space12),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        borderRadius: BorderRadius.circular(ZirenTokens.radius12),
        border: Border.all(color: ZirenTokens.surfaceBorder),
      ),
      child:
          onEdit == null
              ? child
              : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: child),
                  GestureDetector(
                    onTap: onEdit,
                    child: Text(
                      editLabel!,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: ZirenTokens.brandOrange,
                      ),
                    ),
                  ),
                ],
              ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: ZirenTokens.textMuted),
        const SizedBox(width: ZirenTokens.space10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: ZirenTokens.textMuted,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: ZirenTokens.textPrimary,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Play/pause + duration for the recorded voice note. Its own tiny player
/// instance — the confirm screen's [VoiceReportControl] is not reused here
/// because this row is read-only (no re-record, no discard).
class _VoiceReviewRow extends StatefulWidget {
  const _VoiceReviewRow({required this.provider});
  final IncidentProvider provider;

  @override
  State<_VoiceReviewRow> createState() => _VoiceReviewRowState();
}

class _VoiceReviewRowState extends State<_VoiceReviewRow> {
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final note = widget.provider.voiceNote;
    if (note == null) return;
    if (_playing) {
      await _player.stop();
      if (mounted) setState(() => _playing = false);
    } else {
      await _player.play(DeviceFileSource(note.path));
      if (mounted) setState(() => _playing = true);
    }
  }

  String _clock(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Row(
      children: [
        InkWell(
          onTap: _toggle,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: ZirenTokens.brandSubtle,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              _playing ? LucideIcons.pause : LucideIcons.play,
              size: 20,
              color: ZirenTokens.brandOrange,
            ),
          ),
        ),
        const SizedBox(width: ZirenTokens.space10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                t.quickReviewVoiceRecording,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: ZirenTokens.textMuted,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${_clock(widget.provider.voiceNoteLength)} · '
                '${t.quickReviewAttached}',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: ZirenTokens.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
