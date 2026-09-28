import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/theme/app_tokens.dart';
import '../../../incident_report/data/media_upload_service.dart';
import '../../domain/responder_provider.dart';
import 'incident_action_row.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Photograph the scene.
///
/// WHY THE CREW'S PHOTOS ARE NOT THE REPORTER'S PHOTOS
///
/// These upload to the same private bucket and then attach to
/// `scene_media_urls`, never `media_urls`. That separation is the whole value
/// of the feature: media_urls is what was known BEFORE anyone arrived — a
/// neighbour's photo of smoke — and scene_media_urls is what the crew
/// documented after. Merged into one list, an after-action review can no
/// longer tell which is which, and the archive quietly loses the distinction
/// between what was reported and what was found.
///
/// WHY THE UPLOAD IS DIRECT TO STORAGE
///
/// Same path the resident's attachments take: the file goes to Supabase
/// Storage from the handset and only the resulting PATH travels through the
/// API. A photo routed through FastAPI would be a multi-megabyte request from
/// the worst connection in the system.
///
/// OFFLINE. The upload itself needs a network and cannot be queued — there is
/// nowhere to put the bytes. What IS queued is the attach: if the upload
/// succeeds and the attach call fails, the path is held by
/// ResponderActionQueue and lands when signal returns. A crew in a dead spot
/// is told plainly rather than left with a spinner.
class SceneCaptureButton extends StatefulWidget {
  const SceneCaptureButton({
    super.key,
    required this.incidentId,
    required this.enabled,
  });

  final String incidentId;

  /// Only on scene. Photographing a fire from the truck two barangays away
  /// files evidence of somewhere the crew has not been.
  final bool enabled;

  @override
  State<SceneCaptureButton> createState() => _SceneCaptureButtonState();
}

class _SceneCaptureButtonState extends State<SceneCaptureButton> {
  final _media = MediaUploadService();
  bool _busy = false;
  int _attached = 0;

  Future<void> _capture() async {
    if (_busy) return;

    final file = await _media.pickPhoto(source: ImageSource.camera);
    if (file == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        _say(
          AppLocalizations.of(context).respSceneNotSignedIn,
          ZirenTokens.systemError,
        );
        return;
      }

      final path = await _media.uploadFile(
        file: File(file.path),
        userId: userId,
        incidentId: widget.incidentId,
      );
      if (!mounted) return;

      final ok = await context.read<ResponderProvider>().attachSceneMedia(
        widget.incidentId,
        [path],
      );
      if (!mounted) return;

      if (ok) {
        setState(() => _attached++);
        _say(
          AppLocalizations.of(context).respScenePhotoAdded,
          ZirenTokens.systemSuccess,
        );
      } else {
        _say(
          AppLocalizations.of(context).respScenePhotoNotAdded,
          ZirenTokens.systemError,
        );
      }
    } catch (e) {
      if (mounted) {
        // The upload is the part that genuinely cannot wait for signal — the
        // bytes have nowhere to be queued to. Saying so is better than a
        // generic failure, because the crew can decide to retry from the
        // station instead of standing in a dead spot pressing a button.
        _say(
          AppLocalizations.of(context).respScenePhotoUploadFailed,
          ZirenTokens.systemError,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _say(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return IncidentActionRow(
      icon: LucideIcons.camera,
      iconColor: ZirenTokens.brandOrange,
      busy: _busy,
      onTap: widget.enabled && !_busy ? _capture : null,
      label:
          _busy
              ? t.respSceneUploading
              : _attached == 0
              ? t.respSceneTakePhoto
              : t.respSceneAddMore(_attached),
      trailing:
          !widget.enabled
              ? ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 96),
                child: Text(
                  AppLocalizations.of(context).respSceneOnlyWhenOnScene,
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.3,
                    color: ZirenTokens.textMuted,
                  ),
                ),
              )
              : null,
    );
  }
}
