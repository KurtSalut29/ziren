import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../features/auth/domain/auth_provider.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../domain/incident_provider.dart';
import '../../../l10n/app_localizations.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'widgets/spoken_language_chip.dart';
import '../../../shared/widgets/ziren_photo_sheet.dart';

/// Step 2 of the report flow — free-text description.
/// Step 1 (station selection) must have been completed first;
/// the router enforces this via [IncidentProvider.hasStation].
class ReportFormScreen extends StatefulWidget {
  const ReportFormScreen({super.key});

  @override
  State<ReportFormScreen> createState() => _ReportFormScreenState();
}

class _ReportFormScreenState extends State<ReportFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final provider = context.read<IncidentProvider>();
    provider.fetchLocation();
    provider.initSpeech();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final provider = context.read<IncidentProvider>();
    final success = await provider.submitIncident(
      reportText: _textController.text,
    );
    if (!mounted) return;
    if (success) {
      _textController.clear();
      _showSuccessSheet();
    }
  }

  void _showSuccessSheet() {
    final t = AppLocalizations.of(context);
    final incident = context.read<IncidentProvider>().lastSubmitted;
    showModalBottomSheet(
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
                Icon(
                  LucideIcons.circle_check,
                  size: 64,
                  color: ZirenTokens.systemSuccess,
                ),
                const SizedBox(height: ZirenTokens.space16),
                Text(
                  t.formSubmittedTitle,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: ZirenTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: ZirenTokens.space8),
                Text(
                  'Your report has been received.\nReport ID: ${incident?.id.substring(0, 8)}...',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: ZirenTokens.textMuted),
                ),
                const SizedBox(height: ZirenTokens.space24),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    context.push('/my-reports');
                  },
                  child: Text(t.formTrackReport),
                ),
                const SizedBox(height: ZirenTokens.space8),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    context.read<IncidentProvider>()
                      ..resetSubmitStatus()
                      ..clearStation();
                    context.go('/home');
                  },
                  child: Text(t.actionBackToHome),
                ),
              ],
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final provider = context.watch<IncidentProvider>();

    // Guard — if somehow arrived here without a station, redirect
    if (!provider.hasStation) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.go('/select-station'),
      );
      return const SizedBox.shrink();
    }

    final station = provider.selectedStation!;

    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      appBar: AppBar(
        title: Text(t.formReportEmergency),
        leading: BackButton(
          onPressed: () {
            provider.clearStation();
            context.go('/select-station');
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.rotate_ccw),
            tooltip: t.formMyReports,
            onPressed: () => context.push('/my-reports'),
          ),
          IconButton(
            icon: const Icon(LucideIcons.log_out),
            tooltip: t.actionLogOutForm,
            onPressed: () => context.read<AuthProvider>().logout(),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(ZirenTokens.space16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Selected station banner ────────────────────
              _SelectedStationBanner(
                agencyType: station.agencyType,
                stationName: station.name,
                municipality: station.municipality,
                onChangeTap: () {
                  provider.clearStation();
                  context.go('/select-station');
                },
              ),
              const SizedBox(height: ZirenTokens.space16),

              // ── Location status ────────────────────────────
              _LocationStatus(provider: provider),
              const SizedBox(height: ZirenTokens.space8),

              // ── Phase 9: Coverage mismatch warning ────────
              if (provider.hasCoverageMismatch)
                _CoverageMismatchBanner(distanceKm: provider.distanceKm),
              if (provider.hasCoverageMismatch)
                const SizedBox(height: ZirenTokens.space8),

              const SizedBox(height: ZirenTokens.space8),

              // ── Report text ────────────────────────────────
              Form(
                key: _formKey,
                child: TextFormField(
                  controller: _textController,
                  maxLines: 7,
                  maxLength: 5000,
                  textInputAction: TextInputAction.newline,
                  style: TextStyle(
                    fontSize: 16,
                    color: ZirenTokens.textPrimary,
                  ),
                  decoration: InputDecoration(
                    labelText: t.formDescribe,
                    hintText: t.formDescribeHint,
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: ZirenTokens.surfaceCard,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return t.formDescribeRequired;
                    }
                    if (v.trim().length < 10) {
                      return t.formDescribeTooShort;
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: ZirenTokens.space8),

              // ── Speech-to-text ─────────────────────────────
              _SpeechButton(
                provider: provider,
                onResult: (text) {
                  _textController.text = text;
                  _textController.selection = TextSelection.fromPosition(
                    TextPosition(offset: text.length),
                  );
                },
              ),
              const SizedBox(height: ZirenTokens.space16),

              // ── Media attachments ──────────────────────────
              _MediaAttachmentSection(provider: provider),
              const SizedBox(height: ZirenTokens.space16),

              // ── Error banner ───────────────────────────────
              if (provider.submitError != null) ...[
                Container(
                  padding: const EdgeInsets.all(ZirenTokens.space12),
                  decoration: BoxDecoration(
                    color: ZirenTokens.systemErrorBg,
                    borderRadius: BorderRadius.circular(ZirenTokens.radius8),
                    border: Border.all(
                      color: ZirenTokens.systemError.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.circle_alert,
                        size: 16,
                        color: ZirenTokens.systemError,
                      ),
                      const SizedBox(width: ZirenTokens.space8),
                      Expanded(
                        child: Text(
                          provider.submitError!,
                          style: TextStyle(
                            color: ZirenTokens.systemError,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: ZirenTokens.space16),
              ],

              // ── Submit ─────────────────────────────────────
              provider.submitStatus == SubmitStatus.submitting
                  ? const LoadingIndicator()
                  : ElevatedButton.icon(
                    icon: const Icon(LucideIcons.send, size: 18),
                    label: Text(t.formSubmit),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ZirenTokens.brandOrange,
                      foregroundColor: ZirenTokens.textPrimary,
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: _submit,
                  ),

              const SizedBox(height: ZirenTokens.space16),
              Text(
                t.formSubmitNote,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: ZirenTokens.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Selected station banner ────────────────────────────────────

class _SelectedStationBanner extends StatelessWidget {
  const _SelectedStationBanner({
    required this.agencyType,
    required this.stationName,
    required this.municipality,
    required this.onChangeTap,
  });
  final String agencyType;
  final String stationName;
  final String municipality;
  final VoidCallback onChangeTap;

  Color get _color {
    switch (agencyType) {
      case 'BFP':
        return ZirenTokens.agencyBFP;
      case 'PNP':
        return ZirenTokens.agencyPNP;
      case 'MDRRMO':
        return ZirenTokens.agencyMDRRMO;
      default:
        return ZirenTokens.brandOrange;
    }
  }

  IconData get _icon {
    switch (agencyType) {
      case 'BFP':
        return LucideIcons.flame;
      case 'PNP':
        return LucideIcons.shield;
      case 'MDRRMO':
        return LucideIcons.triangle_alert;
      default:
        return LucideIcons.building;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZirenTokens.space12,
        vertical: ZirenTokens.space10,
      ),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(ZirenTokens.radius8),
        border: Border.all(color: _color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(_icon, size: 18, color: _color),
          const SizedBox(width: ZirenTokens.space8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stationName,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: _color,
                  ),
                ),
                Text(
                  municipality,
                  style: TextStyle(fontSize: 12, color: ZirenTokens.textMuted),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onChangeTap,
            style: TextButton.styleFrom(
              foregroundColor: _color,
              padding: EdgeInsets.zero,
              minimumSize: const Size(48, 32),
            ),
            child: Text(t.actionChangeForm, style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ── Location status chip ──────────────────────────────────────

class _LocationStatus extends StatelessWidget {
  const _LocationStatus({required this.provider});
  final IncidentProvider provider;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (provider.locationDenied) {
      return _chip(
        LucideIcons.map_pin_off,
        t.formNoLocation,
        ZirenTokens.systemWarning,
      );
    }
    if (provider.currentPosition == null) {
      return _chip(
        LucideIcons.locate,
        'Getting your location...',
        ZirenTokens.textMuted,
      );
    }
    final pos = provider.currentPosition!;
    return _chip(
      LucideIcons.map_pin,
      'Location captured: '
      '${pos.latitude.toStringAsFixed(5)}, '
      '${pos.longitude.toStringAsFixed(5)}',
      ZirenTokens.systemSuccess,
    );
  }

  Widget _chip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZirenTokens.space12,
        vertical: ZirenTokens.space8,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(ZirenTokens.radius8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: ZirenTokens.space8),
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 12, color: color)),
          ),
        ],
      ),
    );
  }
}

// ── Speech button ─────────────────────────────────────────────

class _SpeechButton extends StatelessWidget {
  const _SpeechButton({required this.provider, required this.onResult});
  final IncidentProvider provider;
  final ValueSetter<String> onResult;

  @override
  Widget build(BuildContext context) {
    if (!provider.speechAvailable) return const SizedBox.shrink();
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _micButton(t),
        const SizedBox(height: ZirenTokens.space8),
        // Which language the phone listens for (evaluator finding #22).
        SpokenLanguageChip(provider: provider),
      ],
    );
  }

  Widget _micButton(AppLocalizations t) {
    return OutlinedButton.icon(
      icon: Icon(
        provider.isListening ? LucideIcons.mic : LucideIcons.mic,
        color: provider.isListening ? ZirenTokens.brandOrange : null,
      ),
      label: Text(
        provider.isListening ? t.wizardListening : t.wizardSpeakDetails,
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor:
            provider.isListening
                ? ZirenTokens.brandOrange
                : ZirenTokens.textMuted,
        side: BorderSide(
          color:
              provider.isListening
                  ? ZirenTokens.brandOrange
                  : ZirenTokens.surfaceBorder,
        ),
        minimumSize: const Size.fromHeight(ZirenTokens.minTouchTarget),
      ),
      onPressed:
          () =>
              provider.isListening
                  ? provider.stopListening()
                  : provider.startListening(onResult: onResult),
    );
  }
}

// ── Media attachment section ──────────────────────────────────

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
    final choice = await showZirenPhotoSourceSheet(
      context,
      title: 'Add a photo or video',
      takePhoto: 'Take a photo',
      recordVideo: 'Record a video',
      chooseFromGallery: 'Choose from gallery',
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
    final media = provider.selectedMedia;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header ─────────────────────────────────
        Row(
          children: [
            Icon(
              LucideIcons.paperclip,
              size: 16,
              color: ZirenTokens.textSecondary,
            ),
            const SizedBox(width: ZirenTokens.space4),
            Text(
              'Attachments',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: ZirenTokens.textSecondary,
              ),
            ),
            const SizedBox(width: ZirenTokens.space4),
            Text(
              '(optional)',
              style: TextStyle(fontSize: 12, color: ZirenTokens.textMuted),
            ),
            const Spacer(),
            if (media.length < 5)
              TextButton.icon(
                icon: const Icon(LucideIcons.plus, size: 16),
                label: const Text('Add'),
                onPressed: () => _showPickerSheet(context),
                style: TextButton.styleFrom(
                  foregroundColor: ZirenTokens.brandOrange,
                  padding: EdgeInsets.zero,
                ),
              ),
          ],
        ),

        // ── Error ──────────────────────────────────────────
        if (provider.mediaError != null) ...[
          const SizedBox(height: ZirenTokens.space4),
          Text(
            provider.mediaError!,
            style: TextStyle(fontSize: 12, color: ZirenTokens.systemError),
          ),
        ],

        // ── Thumbnails ─────────────────────────────────────
        if (media.isNotEmpty) ...[
          const SizedBox(height: ZirenTokens.space8),
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
          ),
        ] else ...[
          const SizedBox(height: ZirenTokens.space4),
          Text(
            AppLocalizations.of(context).quickMediaHint,
            style: TextStyle(fontSize: 12, color: ZirenTokens.textMuted),
          ),
        ],
      ],
    );
  }
}

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
                    color: ZirenTokens.surfaceCard,
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

// ── Phase 9: Coverage mismatch warning ───────────────────────

class _CoverageMismatchBanner extends StatelessWidget {
  const _CoverageMismatchBanner({this.distanceKm});
  final double? distanceKm;

  @override
  Widget build(BuildContext context) {
    final distText =
        distanceKm != null
            ? ' (~${distanceKm!.toStringAsFixed(1)} km from station)'
            : '';

    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space12),
      decoration: BoxDecoration(
        color: ZirenTokens.systemWarningBg,
        borderRadius: BorderRadius.circular(ZirenTokens.radius8),
        border: Border.all(
          color: ZirenTokens.systemWarning.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            LucideIcons.map_pin_off,
            size: 18,
            color: ZirenTokens.systemWarning,
          ),
          const SizedBox(width: ZirenTokens.space8),
          Expanded(
            child: Text(
              'Your GPS location appears to be outside this station\'s '
              'coverage area$distText. You can still submit — a dispatcher '
              'will verify the routing.',
              style: TextStyle(
                fontSize: 12,
                color: ZirenTokens.systemWarning,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
