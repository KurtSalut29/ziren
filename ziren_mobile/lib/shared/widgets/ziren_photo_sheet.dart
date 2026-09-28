import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import 'ziren_dialogs.dart';

/// Where a photo or video should come from.
enum ZirenPhotoSource { camera, video, gallery }

/// The "add a photo" sheet, once for every screen that asks for one - the report
/// form, the wizard's review step, the quick-report attachments and the ID
/// capture. It was three hand-copied lists of bare rows, one of them in English
/// only, none of them saying they were things to press. Pass [recordVideo] to
/// offer a video; leave it out for stills only.
Future<ZirenPhotoSource?> showZirenPhotoSourceSheet(
  BuildContext context, {
  required String title,
  required String takePhoto,
  String? recordVideo,
  required String chooseFromGallery,
}) {
  return showZirenOptionSheet<ZirenPhotoSource>(
    context,
    title: title,
    options: [
      ZirenSheetOption(
        icon: LucideIcons.camera,
        label: takePhoto,
        value: ZirenPhotoSource.camera,
        tone: ZirenTone.brand,
      ),
      if (recordVideo != null)
        ZirenSheetOption(
          icon: LucideIcons.video,
          label: recordVideo,
          value: ZirenPhotoSource.video,
          tone: ZirenTone.brand,
        ),
      ZirenSheetOption(
        icon: LucideIcons.images,
        label: chooseFromGallery,
        value: ZirenPhotoSource.gallery,
      ),
    ],
  );
}
