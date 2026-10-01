import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/theme/app_tokens.dart';
import '../domain/incident_category_style.dart';
import '../domain/incident_provider.dart';
import '../../../l10n/app_localizations.dart';
import 'incident_labels.dart';
import 'widgets/incident_location_section.dart';
import 'widgets/media_attachment_field.dart';
import 'widgets/quick_report_kit.dart';
import 'widgets/voice_report_control.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import '../../demo/presentation/demo_anchor.dart';

/// Quick report — step 1 of 2. The category is already chosen (a tap on
/// Home's category grid), so this screen only collects what a report cannot
/// go without: where you are, what happened, and anything you want to add.
///
/// Nothing here sends anything. It hands off to [QuickReportReviewScreen],
/// which is the actual confirm step — sending commits a crew and a vehicle,
/// and that cost does not go away because the tap to get here was quick.
class QuickReportConfirmScreen extends StatefulWidget {
  const QuickReportConfirmScreen({super.key});

  @override
  State<QuickReportConfirmScreen> createState() =>
      _QuickReportConfirmScreenState();
}

class _QuickReportConfirmScreenState extends State<QuickReportConfirmScreen> {
  final _noteController = TextEditingController();
  final _landmarkController = TextEditingController();

  /// Set when the resident tried to continue without a landmark.
  bool _landmarkMissing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = context.read<IncidentProvider>();
      p.fetchLocation();
      if (p.stations.isEmpty) p.loadStations();
      final note = p.quickNote;
      if (note != null) _noteController.text = note;
      final landmark = p.landmarkNote;
      if (landmark != null) _landmarkController.text = landmark;
    });
  }

  @override
  void dispose() {
    _landmarkController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _goToReview(IncidentProvider p) {
    // The landmark is required: GPS inside a barangay is not an address a
    // crew can drive to, and the stations asked for it on every report.
    if (_landmarkController.text.trim().isEmpty) {
      setState(() => _landmarkMissing = true);
      return;
    }
    p.setLandmarkNote(_landmarkController.text);
    p.setQuickNote(_noteController.text);
    context.push('/report/quick/review');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final p = context.watch<IncidentProvider>();
    final category = p.incidentCategory;

    // A category is required to get here at all — Home always sets one
    // before pushing this route. If it is somehow missing, there is
    // nothing this screen can usefully show.
    if (category == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => context.go('/home'));
      return const SizedBox.shrink();
    }

    final color = IncidentCategoryStyle.color(category);
    final bg = IncidentCategoryStyle.background(category);
    final canReview = p.incidentLat != null || p.locationDenied;

    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      appBar: AppBar(
        title: Text(
          t.quickFlowTitle(IncidentLabels.categoryShort(t, category)),
        ),
        leading: BackButton(onPressed: () => context.pop()),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: ZirenTokens.space16),
            child: Center(child: QuickReportStepDots(step: 1)),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            ZirenTokens.space16,
            ZirenTokens.space12,
            ZirenTokens.space16,
            ZirenTokens.space16,
          ),
          children: [
            // ── Category banner ─────────────────────────────
            DemoAnchor(
              id: 'report.category',
              child: Container(
                padding: const EdgeInsets.all(ZirenTokens.space16),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(ZirenTokens.radius16),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        IncidentCategoryStyle.icon(category),
                        color: color,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: ZirenTokens.space12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            IncidentLabels.categoryShort(t, category),
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: color,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            t.quickHelpSubtitle,
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
            ),

            const SizedBox(height: ZirenTokens.space20),

            // ── Where: the incident, and a landmark ──────────
            DemoAnchor(
              id: 'report.where',
              child: IncidentLocationSection(
                landmarkController: _landmarkController,
                showLandmarkError: _landmarkMissing,
                header: (text) => QuickReportSectionLabel(text),
                onLandmarkChanged: (_) {
                  if (_landmarkMissing) {
                    setState(() => _landmarkMissing = false);
                  }
                },
              ),
            ),

            const SizedBox(height: ZirenTokens.space20),

            // ── Describe what happened (voice) ─────────────────
            DemoAnchor(
              id: 'report.voice',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  QuickReportSectionLabel(t.quickDescribeWhatHappened),
                  const SizedBox(height: ZirenTokens.space8),
                  const VoiceReportControl(),
                ],
              ),
            ),

            const SizedBox(height: ZirenTokens.space20),

            // ── Typed message ───────────────────────────────────
            DemoAnchor(
              id: 'report.type',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  QuickReportSectionLabel(t.quickOrTypeMessage),
                  const SizedBox(height: ZirenTokens.space8),
                  TextField(
                    controller: _noteController,
                    maxLines: 3,
                    textInputAction: TextInputAction.done,
                    onChanged: (v) => p.setQuickNote(v),
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(hintText: t.quickNoteHint),
                  ),
                ],
              ),
            ),

            const SizedBox(height: ZirenTokens.space20),

            // ── Photo / video attachment ────────────────────────
            DemoAnchor(
              id: 'report.media',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  QuickReportSectionLabel(t.quickAttachPhotoVideo),
                  const SizedBox(height: ZirenTokens.space8),
                  MediaAttachmentField(
                    media: p.selectedMedia,
                    error: p.mediaError,
                    hint: t.quickMediaHint,
                    onAdd: (source, isVideo) async {
                      final service = p.mediaUploadService;
                      final file =
                          isVideo
                              ? await service.pickVideo(source: source)
                              : await service.pickPhoto(source: source);
                      if (file != null) p.addMedia(file);
                    },
                    onRemove: p.removeMedia,
                  ),
                ],
              ),
            ),

            if (p.submitError != null) ...[
              const SizedBox(height: ZirenTokens.space16),
              Container(
                padding: const EdgeInsets.all(ZirenTokens.space12),
                decoration: BoxDecoration(
                  color: ZirenTokens.systemErrorBg,
                  borderRadius: BorderRadius.circular(ZirenTokens.radius12),
                  border: Border.all(color: ZirenTokens.severityCriticalBorder),
                ),
                child: Text(
                  p.submitError!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: ZirenTokens.systemError,
                  ),
                ),
              ),
            ],

            const SizedBox(height: ZirenTokens.space24),
            DemoAnchor(
              id: 'report.review',
              child: SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  icon: const Icon(LucideIcons.arrow_right, size: 18),
                  label: Text(
                    t.quickReviewReportAction,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onPressed: canReview ? () => _goToReview(p) : null,
                ),
              ),
            ),
            const SizedBox(height: ZirenTokens.space12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  LucideIcons.shield,
                  size: 15,
                  color: ZirenTokens.textMuted,
                ),
                const SizedBox(width: ZirenTokens.space8),
                Expanded(
                  child: Text(
                    t.quickReviewWarning,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: ZirenTokens.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
