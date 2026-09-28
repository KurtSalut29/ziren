import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/theme/app_tokens.dart';
import '../domain/incident_category_style.dart';
import '../domain/incident_provider.dart';
import '../../../l10n/app_localizations.dart';
import 'incident_labels.dart';
import 'widgets/media_attachment_field.dart';
import 'widgets/quick_report_kit.dart';
import 'widgets/voice_report_control.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

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

  // Set once, to the exact string that was auto-filled. Compared against the
  // live controller text (not just "did we auto-fill at some point") so the
  // verify-this hint below the field disappears the moment a resident
  // actually edits it, rather than nagging about a suggestion they've
  // already dealt with.
  String? _autoFilledLandmark;

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
    p.setLandmarkNote(_landmarkController.text);
    p.setQuickNote(_noteController.text);
    context.push('/report/quick/review');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final p = context.watch<IncidentProvider>();
    final category = p.incidentCategory;
    final locating = p.currentPosition == null && !p.locationDenied;

    // A category is required to get here at all — Home always sets one
    // before pushing this route. If it is somehow missing, there is
    // nothing this screen can usefully show.
    if (category == null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.go('/home'),
      );
      return const SizedBox.shrink();
    }

    final color = IncidentCategoryStyle.color(category);
    final bg = IncidentCategoryStyle.background(category);
    final canReview = p.currentPosition != null || p.locationDenied;

    // Auto-fill the landmark the moment OSM has one to offer, same as
    // location — but only once, only into an empty field (a resident who
    // has already typed something, or already cleared a suggestion they
    // didn't want, keeps deciding that for themselves), and only on a GPS
    // fix good enough to trust without a human glance first. A landmark
    // built from an imprecise fix compounds two guesses — the position and
    // Nominatim's pick from it — so an imprecise fix still gets the
    // suggestion chip below, just not the silent auto-fill.
    final suggestion = p.nearbyLandmark;
    if (suggestion != null &&
        p.locationIsPrecise &&
        _autoFilledLandmark == null &&
        _landmarkController.text.trim().isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _landmarkController.text = suggestion;
          _autoFilledLandmark = suggestion;
        });
      });
    }

    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      appBar: AppBar(
        title: Text(t.quickFlowTitle(IncidentLabels.categoryShort(t, category))),
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
            Container(
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

            const SizedBox(height: ZirenTokens.space20),

            // ── Location ─────────────────────────────────────
            QuickReportSectionLabel(t.quickYourLocationAuto),
            const SizedBox(height: ZirenTokens.space8),
            QuickReportCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    LucideIcons.map_pin,
                    size: 18,
                    color: ZirenTokens.brandOrange,
                  ),
                  const SizedBox(width: ZirenTokens.space10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          p.locationDenied
                              ? t.quickLocationOff
                              : locating
                              ? t.quickSearching
                              : (p.locationAddress ?? t.quickCoordinatesFound),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: ZirenTokens.textPrimary,
                            height: 1.35,
                          ),
                        ),
                        if (!locating &&
                            !p.locationDenied &&
                            p.locationAccuracyM != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            t.quickAccuracy(p.locationAccuracyM!.round()),
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  p.locationIsPrecise
                                      ? ZirenTokens.textMuted
                                      : ZirenTokens.systemWarning,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (locating)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (!p.locationDenied)
                    GestureDetector(
                      onTap: () => p.fetchLocation(),
                      child: Icon(
                        LucideIcons.refresh_cw,
                        size: 20,
                        color: ZirenTokens.textMuted,
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: ZirenTokens.space20),

            // ── Landmark ───────────────────────────────────────
            QuickReportSectionLabel(t.quickLandmark),
            const SizedBox(height: ZirenTokens.space8),
            TextField(
              controller: _landmarkController,
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.sentences,
              // Only to keep the "auto-filled, please check" hint below in
              // sync as the resident types — nothing here needs saving on
              // every keystroke; _goToReview reads the controller directly.
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: t.quickLandmarkHint,
                prefixIcon: const Icon(
                  LucideIcons.map_pin,
                  size: 20,
                ),
              ),
            ),
            if (_autoFilledLandmark != null &&
                _landmarkController.text == _autoFilledLandmark)
              Padding(
                padding: const EdgeInsets.only(top: ZirenTokens.space6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      LucideIcons.sparkles,
                      size: 13,
                      color: ZirenTokens.textMuted,
                    ),
                    const SizedBox(width: ZirenTokens.space6),
                    Expanded(
                      child: Text(
                        'Auto-filled from nearby map data — check it\'s correct before sending.',
                        style: TextStyle(fontSize: 11.5, color: ZirenTokens.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
            if (p.nearbyLandmark != null &&
                _landmarkController.text.trim().isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: ZirenTokens.space8),
                child: ActionChip(
                  avatar: const Icon(LucideIcons.map_pin_plus, size: 16),
                  label: Text(p.nearbyLandmark!),
                  onPressed:
                      () => setState(
                        () => _landmarkController.text = p.nearbyLandmark!,
                      ),
                ),
              ),

            const SizedBox(height: ZirenTokens.space20),

            // ── Describe what happened (voice) ─────────────────
            QuickReportSectionLabel(t.quickDescribeWhatHappened),
            const SizedBox(height: ZirenTokens.space8),
            const VoiceReportControl(),

            const SizedBox(height: ZirenTokens.space20),

            // ── Typed message ───────────────────────────────────
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

            const SizedBox(height: ZirenTokens.space20),

            // ── Photo / video attachment ────────────────────────
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
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                icon: const Icon(LucideIcons.arrow_right, size: 18),
                label: Text(
                  t.quickReviewReportAction,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                onPressed: canReview ? () => _goToReview(p) : null,
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
