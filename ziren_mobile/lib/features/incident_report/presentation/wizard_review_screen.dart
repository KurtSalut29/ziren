import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/loading_indicator.dart';
import 'incident_labels.dart';
import 'wizard_shared.dart';
import '../domain/incident_provider.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../hotlines/presentation/hotlines_view.dart';
import '../../../shared/widgets/ziren_photo_sheet.dart';

/// Step 2 of 2 — review summary before final submit.
///
/// Assembles and displays category, location, catch-all text/voice detail,
/// and attached media. No forced-choice question answers are collected or
/// shown — there aren't any.
/// Resident can tap "Baguhin" on any section to go back.
/// Submit calls IncidentProvider.submitIncident() with assembled report_text
/// plus the structured fields above.
class WizardReviewScreen extends StatelessWidget {
  const WizardReviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final provider = context.watch<IncidentProvider>();

    if (provider.incidentCategory == null || !provider.hasStation) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.go('/report/category'),
      );
      return const SizedBox.shrink();
    }

    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      appBar: AppBar(
        title: Text(t.reviewTitle),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const WizardProgress(step: 2, totalSteps: 2),
            WizardStationBanner(provider: provider),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(ZirenTokens.space16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: ZirenTokens.space8),

                    // ── Category section ─────────────────────
                    _ReviewSection(
                      label: t.reviewTypeOfEmergency,
                      onEdit: () => context.go('/report/category'),
                      child: _ReviewValue(
                        provider.incidentCategory!.label,
                        bold: true,
                      ),
                    ),

                    // ── Location ─────────────────────────────
                    _ReviewSection(
                      label: t.reviewLocation,
                      onEdit: () => context.go('/report/category'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _ReviewValue(
                            provider.incidentAddress ??
                                (provider.incidentLat != null
                                    ? 'GPS: ${provider.incidentLat!.toStringAsFixed(5)}, '
                                        '${provider.incidentLng!.toStringAsFixed(5)}'
                                    : t.reviewNoGps),
                          ),
                          if (provider.reportingElsewhere)
                            _ReviewValue(
                              '${t.locReviewReporterLabel}: '
                              '${provider.locationAddress ?? t.locReviewReporterUnknown}',
                            ),
                          if (provider.landmarkNote != null)
                            _ReviewValue('📍 ${provider.landmarkNote!}'),
                        ],
                      ),
                    ),

                    // ── Who ──────────────────────────────────
                    if (provider.victimRelationship != null)
                      _ReviewSection(
                        label: t.reviewRelationship,
                        onEdit: () => context.go('/report/category'),
                        child: _ReviewValue(provider.victimRelationship!.label),
                      ),

                    // ── Catch-all free text ──────────────────
                    if (_catchAll(provider).isNotEmpty)
                      _ReviewSection(
                        label: t.reviewExtraDetails,
                        onEdit: () => context.go('/report/category'),
                        child: _ReviewValue(_catchAll(provider)),
                      ),

                    // ── Media attachments ────────────────────
                    _MediaAttachmentSection(provider: provider),

                    const SizedBox(height: ZirenTokens.space16),

                    // ── Submit error ─────────────────────────
                    if (provider.submitError != null)
                      Container(
                        padding: const EdgeInsets.all(ZirenTokens.space12),
                        margin: const EdgeInsets.only(
                          bottom: ZirenTokens.space12,
                        ),
                        decoration: BoxDecoration(
                          color: ZirenTokens.systemErrorBg,
                          borderRadius: BorderRadius.circular(
                            ZirenTokens.radius8,
                          ),
                          border: Border.all(
                            color: ZirenTokens.systemError.withValues(
                              alpha: 0.40,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              LucideIcons.circle_alert,
                              size: 16,
                              color: ZirenTokens.systemError,
                            ),
                            const SizedBox(width: ZirenTokens.space8),
                            Expanded(
                              child: Text(
                                provider.submitError!,
                                style: const TextStyle(
                                  color: ZirenTokens.systemError,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    // Nothing reached the server: a call still gets through.
                    if (provider.submitFailedOffline)
                      Padding(
                        padding: const EdgeInsets.only(bottom: ZirenTokens.space12),
                        child: SizedBox(
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
                              category: provider.incidentCategory,
                              offline: true,
                            ),
                          ),
                        ),
                      ),

                    // ── Disclaimer ───────────────────────────
                    Container(
                      padding: const EdgeInsets.all(ZirenTokens.space12),
                      decoration: BoxDecoration(
                        color: ZirenTokens.systemWarningBg,
                        borderRadius: BorderRadius.circular(
                          ZirenTokens.radius8,
                        ),
                        border: Border.all(
                          color: ZirenTokens.systemWarning.withValues(
                            alpha: 0.35,
                          ),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            LucideIcons.gavel,
                            size: 16,
                            color: ZirenTokens.systemWarning,
                          ),
                          SizedBox(width: ZirenTokens.space8),
                          Expanded(
                            child: Text(
                              t.reviewFalseReportWarning,
                              style: TextStyle(
                                fontSize: 12,
                                color: ZirenTokens.systemWarning,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: ZirenTokens.space24),
                  ],
                ),
              ),
            ),

            // ── Submit button ─────────────────────────────────
            _SubmitBar(provider: provider),
          ],
        ),
      ),
    );
  }

  String _catchAll(IncidentProvider p) =>
      (p.wizardAnswers['catch_all'] as String?)?.trim() ?? '';
}

// ── Submit bar ────────────────────────────────────────────────

class _SubmitBar extends StatelessWidget {
  const _SubmitBar({required this.provider});
  final IncidentProvider provider;

  Future<void> _submit(BuildContext context) async {
    final reportText = provider.buildReportText(
      catchAll: provider.wizardAnswers['catch_all'] as String?,
    );

    // Captured before submitting: submitIncident() clears the selection on
    // success, and the acknowledgement below still needs them.
    final category = provider.incidentCategory;
    final stationName = provider.selectedStation?.name;
    final hasLocation = provider.incidentLat != null;

    final success = await provider.submitIncident(
      reportText: reportText,
      locationAddress: provider.incidentAddress,
    );
    if (!context.mounted) return;

    if (success) {
      _showSuccessSheet(
        context,
        incidentId: provider.lastSubmitted?.id,
        category: category,
        stationName: stationName,
        hasLocation: hasLocation,
        // What actually reached the server, not what was attached. A photo
        // that could not be uploaded is dropped so the report can still go,
        // and echoing the attached count would claim evidence that is not
        // there.
        mediaCount: provider.lastSubmitMediaCount,
      );
    }
  }

  /// Confirms what was recorded — never how urgently it ranks.
  ///
  /// The triage model has already scored this report by the time this sheet
  /// appears, and none of that reaches the resident on purpose. Severity is
  /// how the dispatcher orders a queue; to the person who just reported an
  /// emergency, "low priority" reads as "you are not important", and the
  /// predictable response is to re-report or to overstate the next one. What
  /// is useful to them is the opposite: proof that the report is complete and
  /// where it went.
  ///
  /// Everything shown here is the resident's own input echoed back.
  void _showSuccessSheet(
    BuildContext context, {
    required String? incidentId,
    required IncidentCategory? category,
    required String? stationName,
    required bool hasLocation,
    required int mediaCount,
  }) {
    final l10n = AppLocalizations.of(context);

    // A short human-quotable reference. The previous version did
    // `(incidentId ?? '').substring(0, 8)`, where the `?? ''` fallback — the
    // branch meant to handle a missing id — was itself a RangeError waiting
    // to happen. Length is checked instead of assumed.
    final referenceId =
        (incidentId != null && incidentId.length >= 8)
            ? incidentId.substring(0, 8).toUpperCase()
            : incidentId?.toUpperCase();

    showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      backgroundColor: ZirenTokens.surfaceOverlay,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ZirenTokens.radius16),
        ),
      ),
      builder:
          (_) => Padding(
            padding: const EdgeInsets.all(ZirenTokens.space32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  LucideIcons.circle_check,
                  size: 64,
                  color: ZirenTokens.systemSuccess,
                ),
                const SizedBox(height: ZirenTokens.space16),
                Text(
                  l10n.reportReceivedTitle,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: ZirenTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: ZirenTokens.space8),
                Text(
                  l10n.reportReceivedBody,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: ZirenTokens.textMuted,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: ZirenTokens.space16),

                // What was recorded. Acknowledgement, not ranking.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(ZirenTokens.space16),
                  decoration: BoxDecoration(
                    color: ZirenTokens.surfaceRaised,
                    borderRadius: BorderRadius.circular(ZirenTokens.radius12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (category != null)
                        _AckRow(
                          label: l10n.recordedAs,
                          value: IncidentLabels.category(l10n, category),
                          emphasise: true,
                        ),
                      if (stationName != null) ...[
                        const SizedBox(height: ZirenTokens.space8),
                        _AckRow(label: l10n.sentTo, value: stationName),
                      ],
                      if (hasLocation || mediaCount > 0) ...[
                        const SizedBox(height: ZirenTokens.space12),
                        Wrap(
                          spacing: ZirenTokens.space12,
                          runSpacing: 4,
                          children: [
                            if (hasLocation) _AckCheck(l10n.locationAttached),
                            if (mediaCount > 0)
                              _AckCheck(l10n.mediaAttached(mediaCount)),
                          ],
                        ),
                      ],
                      if (referenceId != null) ...[
                        const SizedBox(height: ZirenTokens.space12),
                        Text(
                          '${l10n.reportIdLabel}: $referenceId',
                          style: TextStyle(
                            fontSize: 12,
                            color: ZirenTokens.textMuted,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: ZirenTokens.space24),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ZirenTokens.brandOrange,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    context.push('/my-reports');
                  },
                  child: Text(l10n.trackReport),
                ),
                const SizedBox(height: ZirenTokens.space12),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ZirenTokens.textPrimary,
                    minimumSize: const Size.fromHeight(48),
                    side: BorderSide(
                      color: ZirenTokens.surfaceBorder,
                      width: 1.4,
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    context.read<IncidentProvider>()
                      ..resetSubmitStatus()
                      ..clearStation();
                    context.go('/home');
                  },
                  child: Text(l10n.backToHome),
                ),
              ],
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final isSubmitting = provider.submitStatus == SubmitStatus.submitting;

    return Container(
      padding: EdgeInsets.fromLTRB(
        ZirenTokens.space16,
        ZirenTokens.space12,
        ZirenTokens.space16,
        ZirenTokens.space12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        border: Border(top: BorderSide(color: ZirenTokens.surfaceBorder)),
      ),
      child:
          isSubmitting
              ? const LoadingIndicator()
              : ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: ZirenTokens.brandOrange,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ZirenTokens.radius12),
                  ),
                ),
                icon: const Icon(LucideIcons.send, size: 18),
                label: Text(
                  t.reviewSubmit,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                onPressed: () => _submit(context),
              ),
    );
  }
}

// ── Review section card ───────────────────────────────────────

class _ReviewSection extends StatelessWidget {
  const _ReviewSection({
    required this.label,
    required this.child,
    required this.onEdit,
  });
  final String label;
  final Widget child;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: ZirenTokens.space12),
      padding: const EdgeInsets.all(ZirenTokens.space16),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        borderRadius: BorderRadius.circular(ZirenTokens.radius12),
        border: Border.all(color: ZirenTokens.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: ZirenTokens.textMuted,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              if (onEdit != null)
                GestureDetector(
                  onTap: onEdit,
                  child: Text(
                    t.actionEdit,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: ZirenTokens.brandOrange,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: ZirenTokens.space8),
          child,
        ],
      ),
    );
  }
}

class _ReviewValue extends StatelessWidget {
  const _ReviewValue(this.text, {this.bold = false});
  final String text;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: ZirenTokens.space4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          color: ZirenTokens.textPrimary,
          height: 1.4,
        ),
      ),
    );
  }
}

// ── Media attachment section ──────────────────────────────────────────────────
// Mirrors _MediaAttachmentSection in report_form_screen.dart.
// Lives here so the wizard review step can add/remove files before submit
// without depending on the legacy free-text form screen.

class _MediaAttachmentSection extends StatelessWidget {
  const _MediaAttachmentSection({required this.provider});
  final IncidentProvider provider;

  Future<void> _pickMedia(
    BuildContext context,
    ImageSource source,
    bool isVideo,
  ) async {
    final service = provider.mediaUploadService;
    final file =
        isVideo
            ? await service.pickVideo(source: source)
            : await service.pickPhoto(source: source);
    if (file != null) provider.addMedia(file);
  }

  Future<void> _showPickerSheet(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final choice = await showZirenPhotoSourceSheet(
      context,
      title: t.quickAddPhoto,
      takePhoto: t.reviewTakePhoto,
      recordVideo: t.reviewRecordVideo,
      chooseFromGallery: t.reviewChooseFromGallery,
    );
    if (choice == null || !context.mounted) return;
    switch (choice) {
      case ZirenPhotoSource.camera:
        _pickMedia(context, ImageSource.camera, false);
      case ZirenPhotoSource.video:
        _pickMedia(context, ImageSource.camera, true);
      case ZirenPhotoSource.gallery:
        _pickMedia(context, ImageSource.gallery, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final media = provider.selectedMedia;

    return Container(
      margin: const EdgeInsets.only(bottom: ZirenTokens.space12),
      padding: const EdgeInsets.all(ZirenTokens.space16),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        borderRadius: BorderRadius.circular(ZirenTokens.radius12),
        border: Border.all(color: ZirenTokens.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────
          Row(
            children: [
              Text(
                t.reviewAttachmentsSection,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: ZirenTokens.textMuted,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              if (media.length < 5)
                GestureDetector(
                  onTap: () => _showPickerSheet(context),
                  child: Text(
                    t.reviewAddAttachment,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: ZirenTokens.brandOrange,
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: ZirenTokens.space8),

          // ── Media error ──────────────────────────────────
          if (provider.mediaError != null) ...[
            Text(
              provider.mediaError!,
              style: const TextStyle(
                fontSize: 12,
                color: ZirenTokens.systemError,
              ),
            ),
            const SizedBox(height: ZirenTokens.space8),
          ],

          // ── Thumbnails or empty hint ──────────────────────
          if (media.isNotEmpty)
            SizedBox(
              height: 80,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: media.length,
                separatorBuilder:
                    (_, __) => const SizedBox(width: ZirenTokens.space8),
                itemBuilder:
                    (_, i) => _MediaThumb(
                      file: media[i],
                      onRemove: () => provider.removeMedia(i),
                    ),
              ),
            )
          else
            Text(
              t.reviewAttachmentsHint,
              style: TextStyle(fontSize: 12, color: ZirenTokens.textMuted),
            ),
        ],
      ),
    );
  }
}

// ── Media thumbnail ───────────────────────────────────────────

class _MediaThumb extends StatelessWidget {
  const _MediaThumb({required this.file, required this.onRemove});
  final File file;
  final VoidCallback onRemove;

  bool get _isVideo {
    final ext = file.path.split('.').last.toLowerCase();
    return ['mp4', 'mov', 'avi', '3gp', 'mkv'].contains(ext);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(ZirenTokens.radius8),
          child:
              _isVideo
                  ? Container(
                    width: 80,
                    height: 80,
                    color: ZirenTokens.surfaceRaised,
                    child: Icon(
                      LucideIcons.video,
                      color: ZirenTokens.textSecondary,
                      size: 32,
                    ),
                  )
                  : Image.file(file, width: 80, height: 80, fit: BoxFit.cover),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: ZirenTokens.surfaceOverlay,
                shape: BoxShape.circle,
              ),
              child: Icon(
                LucideIcons.x,
                color: ZirenTokens.textPrimary,
                size: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One "label: value" line in the acknowledgement block.
class _AckRow extends StatelessWidget {
  const _AckRow({
    required this.label,
    required this.value,
    this.emphasise = false,
  });

  final String label;
  final String value;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: ',
          style: TextStyle(fontSize: 13, color: ZirenTokens.textMuted),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: emphasise ? FontWeight.w700 : FontWeight.w600,
              color: ZirenTokens.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

/// A ticked item confirming something was attached.
///
/// Deliberately plain: a tick and a noun. Anything more emphatic here starts
/// to read as a judgement about the report rather than a receipt for it.
class _AckCheck extends StatelessWidget {
  const _AckCheck(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          LucideIcons.check,
          size: 14,
          color: ZirenTokens.systemSuccess,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: ZirenTokens.textSecondary,
          ),
        ),
      ],
    );
  }
}
