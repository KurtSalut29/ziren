import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../shared/theme/app_tokens.dart';
import '../../../../l10n/app_localizations.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import '../../../../shared/widgets/ziren_photo_sheet.dart';

/// Photo/video attachment picker + thumbnail strip, shared by the
/// quick-report and wizard review screens.
///
/// State lives with the caller (IncidentProvider.selectedMedia) — this
/// widget is presentation only, the same pattern as the wizard review
/// screen's media section.
class MediaAttachmentField extends StatelessWidget {
  const MediaAttachmentField({
    super.key,
    required this.media,
    required this.error,
    required this.hint,
    required this.onAdd,
    required this.onRemove,
  });

  final List<File> media;
  final String? error;
  final String hint;
  final Future<void> Function(ImageSource source, bool isVideo) onAdd;
  final void Function(int index) onRemove;

  Future<void> _showPickerSheet(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final choice = await showZirenPhotoSourceSheet(
      context,
      title: t.quickAddPhoto,
      takePhoto: t.quickTakePhoto,
      recordVideo: t.quickRecordVideo,
      chooseFromGallery: t.quickChooseFromGallery,
    );
    if (choice == null) return;
    switch (choice) {
      case ZirenPhotoSource.camera:
        onAdd(ImageSource.camera, false);
      case ZirenPhotoSource.video:
        onAdd(ImageSource.camera, true);
      case ZirenPhotoSource.gallery:
        onAdd(ImageSource.gallery, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (media.isEmpty)
          OutlinedButton.icon(
            icon: const Icon(LucideIcons.camera, size: 18),
            label: Text(t.quickAddPhoto),
            onPressed: () => _showPickerSheet(context),
          )
        else ...[
          SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: media.length + (media.length < 5 ? 1 : 0),
              separatorBuilder:
                  (_, __) => const SizedBox(width: ZirenTokens.space8),
              itemBuilder: (_, i) {
                if (i == media.length) {
                  return _AddTile(onTap: () => _showPickerSheet(context));
                }
                return _MediaThumb(
                  file: media[i],
                  onRemove: () => onRemove(i),
                );
              },
            ),
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: ZirenTokens.space6),
          Text(
            error!,
            style: const TextStyle(fontSize: 12, color: ZirenTokens.systemError),
          ),
        ],
        // Always on screen, before and after a file is added: the limits are
        // what a resident needs to know BEFORE recording (findings #20, #21).
        const SizedBox(height: ZirenTokens.space6),
        Text(
          hint,
          style: TextStyle(fontSize: 12, color: ZirenTokens.textMuted),
        ),
      ],
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(ZirenTokens.radius8),
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: ZirenTokens.surfaceRaised,
          borderRadius: BorderRadius.circular(ZirenTokens.radius8),
          border: Border.all(color: ZirenTokens.surfaceBorder),
        ),
        child: Icon(
          LucideIcons.plus,
          color: ZirenTokens.textMuted,
          size: 26,
        ),
      ),
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
