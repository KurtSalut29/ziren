import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/failures.dart';
import '../../features/settings/data/avatar_upload_service.dart';
import '../../features/settings/domain/profile_provider.dart';
import '../../l10n/app_localizations.dart';
import '../theme/app_tokens.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'ziren_dialogs.dart';

/// The visual language of a profile screen, in one place.
///
/// WHY THIS WAS EXTRACTED
///
/// There are two profiles in this app — the resident's and the responder's —
/// and they did not look like the same product. The resident's had a gradient
/// avatar, card sections with a titled header and a rule under it, and rows
/// that read label-left / value-right. The responder's had no header at all
/// and dropped bare TextFormFields into a ListView, so the screen read as a
/// settings form rather than as somebody's profile.
///
/// The cause was that the resident's components were private to its own file.
/// Anyone building the second screen had to re-implement them from memory,
/// and re-implementing a design from memory is how two screens drift. These
/// are now shared, so the two cannot disagree again without someone editing
/// this file on purpose.
///
/// Nothing here is new design work. It is the resident profile's existing
/// treatment, lifted verbatim so both screens are literally the same widgets.

// =============================================================================
// Header
// =============================================================================

/// Avatar, name, and a supporting line — the top of any profile.
///
/// The circle carries the brand gradient when there is no uploaded picture
/// yet (see [EditableAvatar] below for the version that can hold one) — an
/// empty grey circle on every account would be a permanent hole in the
/// design, and initials on brand always render and always look deliberate.
class ProfileAvatarHeader extends StatelessWidget {
  const ProfileAvatarHeader({
    super.key,
    required this.displayName,
    required this.subtitle,
    this.badge,
    this.trailing,
  });

  final String displayName;

  /// Usually the email. The one line that identifies the account rather than
  /// the person.
  final String subtitle;

  /// An optional chip under the name — agency and badge for a responder,
  /// nothing for a resident.
  final Widget? badge;

  /// An optional status line below everything, for a state that belongs to
  /// the identity rather than to a section: on duty, off duty, pending.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: ZirenTokens.brandGradient,
              border: Border.all(
                color: ZirenTokens.brandOrange.withValues(alpha: 0.4),
                width: 2,
              ),
            ),
            child: Center(
              child: Text(
                initialsOf(displayName),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: ZirenTokens.space12),
          Text(
            displayName,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: ZirenTokens.textPrimary,
            ),
          ),
          const SizedBox(height: ZirenTokens.space4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: ZirenTokens.textMuted),
          ),
          if (badge != null) ...[
            const SizedBox(height: ZirenTokens.space12),
            badge!,
          ],
          if (trailing != null) ...[
            const SizedBox(height: ZirenTokens.space8),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// Two initials from a name, one if that is all there is.
String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
  return name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
}

// =============================================================================
// Editable avatar
// =============================================================================

/// A circular avatar with a tappable camera badge for uploading a picture —
/// resident and responder share it, same as everything else in this file.
///
/// Purely a rendering widget: it shows [avatarUrl] when there is one,
/// initials otherwise, and reports taps through [onTap]. It knows nothing
/// about Supabase or HTTP, matching every other widget in this file — the
/// upload itself is [pickAndUploadAvatar] below.
class EditableAvatar extends StatelessWidget {
  const EditableAvatar({
    super.key,
    required this.displayName,
    required this.avatarUrl,
    required this.onTap,
    this.busy = false,
    this.size = 88,
  });

  final String displayName;
  final String? avatarUrl;
  final VoidCallback onTap;

  /// True while a pick-upload-save round trip is in flight, so the badge
  /// shows a spinner instead of the camera and cannot be tapped again.
  final bool busy;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ZirenTokens.surfaceRaised,
            // No border. It used to be a 3px white ring — painted on TOP of
            // the photo's own outer edge (a BoxDecoration's border draws
            // over the child, not around it), so it read as a bite taken
            // out of the picture on every side rather than as an accent.
            boxShadow: ZirenTokens.shadowSm,
          ),
          child:
              url != null
                  ? Image.network(
                    url,
                    fit: BoxFit.cover,
                    width: size,
                    height: size,
                    // A signed URL that has expired, or a network hiccup,
                    // must fall back to initials rather than the default
                    // broken-image icon — the account still has a name even
                    // when the photo cannot be fetched right now.
                    errorBuilder:
                        (_, __, ___) =>
                            _AvatarInitials(displayName: displayName, size: size),
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return _AvatarInitials(
                        displayName: displayName,
                        size: size,
                      );
                    },
                  )
                  : _AvatarInitials(displayName: displayName, size: size),
        ),
        Positioned(
          right: -2,
          bottom: -2,
          child: Material(
            color: ZirenTokens.surfaceCard,
            shape: CircleBorder(
              side: BorderSide(color: ZirenTokens.surfaceBorder),
            ),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: busy ? null : onTap,
              child: Padding(
                padding: const EdgeInsets.all(ZirenTokens.space6),
                child:
                    busy
                        ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(
                          LucideIcons.camera,
                          size: 14,
                          color: ZirenTokens.brandOrange,
                        ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AvatarInitials extends StatelessWidget {
  const _AvatarInitials({required this.displayName, required this.size});

  final String displayName;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: ZirenTokens.brandGradient,
      ),
      child: Center(
        child: Text(
          initialsOf(displayName),
          style: TextStyle(
            fontSize: size * 0.32,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet + pick + upload + persist, in one call. Both Profile screens
/// call this from their camera badge's onTap; neither implements any of it
/// itself, for the same reason the widgets above are shared rather than
/// duplicated per screen.
///
/// Returns once the round trip is done (successfully or not) — errors are
/// surfaced as a snackbar here rather than thrown, so the caller only needs
/// to manage a local busy flag around the call:
///
/// ```dart
/// setState(() => _uploadingAvatar = true);
/// await pickAndUploadAvatar(context);
/// if (mounted) setState(() => _uploadingAvatar = false);
/// ```
Future<void> pickAndUploadAvatar(BuildContext context) async {
  final t = AppLocalizations.of(context);
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) return;

  final choice = await showZirenOptionSheet<_AvatarSheetChoice>(
    context,
    title: t.avatarSheetTitle,
    options: [
      ZirenSheetOption(
        icon: LucideIcons.camera,
        label: t.reviewTakePhoto,
        value: _AvatarSheetChoice.camera,
        tone: ZirenTone.brand,
      ),
      ZirenSheetOption(
        icon: LucideIcons.images,
        label: t.reviewChooseFromGallery,
        value: _AvatarSheetChoice.gallery,
      ),
      ZirenSheetOption(
        icon: LucideIcons.trash,
        label: t.avatarRemovePhoto,
        value: _AvatarSheetChoice.remove,
        tone: ZirenTone.danger,
      ),
    ],
  );
  if (choice == null || !context.mounted) return;

  final service = AvatarUploadService();
  final provider = context.read<ProfileProvider>();

  if (choice == _AvatarSheetChoice.remove) {
    await service.deleteAll(userId);
    if (!context.mounted) return;
    final ok = await provider.updateAvatarPath(null);
    if (!ok && context.mounted) _showAvatarError(context, provider.errorMessage);
    return;
  }

  final source =
      choice == _AvatarSheetChoice.camera
          ? ImageSource.camera
          : ImageSource.gallery;
  final file = await service.pickAvatarPhoto(source: source);
  if (file == null || !context.mounted) return;

  try {
    final path = await service.upload(file: file, userId: userId);
    if (!context.mounted) return;
    final ok = await provider.updateAvatarPath(path);
    if (!ok && context.mounted) _showAvatarError(context, provider.errorMessage);
  } on Failure catch (e) {
    if (context.mounted) _showAvatarError(context, e.message);
  } catch (_) {
    if (context.mounted) _showAvatarError(context, null);
  }
}

void _showAvatarError(BuildContext context, String? message) {
  final t = AppLocalizations.of(context);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message ?? t.avatarUploadFailed),
      backgroundColor: ZirenTokens.systemError,
    ),
  );
}

enum _AvatarSheetChoice { camera, gallery, remove }

// =============================================================================
// Sections
// =============================================================================

/// A titled card. The unit a profile is built out of.
class ProfileSection extends StatelessWidget {
  const ProfileSection({
    super.key,
    required this.title,
    required this.items,
    this.action,
  });

  final String title;
  final List<Widget> items;

  /// An optional control on the title row — "Edit", usually.
  ///
  /// Lives in the section header rather than floating above the card, so the
  /// affordance is attached to the thing it edits. A page-level Edit button
  /// cannot say WHICH card it is about once there is more than one.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        borderRadius: BorderRadius.circular(ZirenTokens.radius12),
        border: Border.all(color: ZirenTokens.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              ZirenTokens.space16,
              action == null ? ZirenTokens.space12 : ZirenTokens.space4,
              action == null ? ZirenTokens.space16 : ZirenTokens.space8,
              action == null ? ZirenTokens.space8 : ZirenTokens.space4,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: ZirenTokens.textPrimary,
                  ),
                )),
                if (action != null) action!,
              ],
            ),
          ),
          Divider(height: 1, color: ZirenTokens.surfaceBorder),
          ...items,
        ],
      ),
    );
  }
}

/// One `icon · label · value` line inside a [ProfileSection].
class ProfileRow extends StatelessWidget {
  const ProfileRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.last = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  /// Drops the hairline under the final row, so the card does not end on a
  /// rule floating above its own rounded corner.
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZirenTokens.space16,
        vertical: ZirenTokens.space12,
      ),
      decoration: BoxDecoration(
        border:
            last
                ? null
                : Border(
                  bottom: BorderSide(
                    color: ZirenTokens.surfaceBorder,
                    width: 0.5,
                  ),
                ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: ZirenTokens.textMuted),
          const SizedBox(width: ZirenTokens.space12),
          // The LABEL sizes to its content and the VALUE takes what is left.
          //
          // Both used to be flexible — Expanded on the label, Flexible on the
          // value — which splits the row 50/50 regardless of what is in it. A
          // 13px email needs about 170 of the 346 available points and was
          // given 173, so it wrapped onto three lines while the word "Email"
          // sat alone in half the row. Labels here are one or two short words
          // and values are the part worth reading, so the space goes to the
          // value.
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: ZirenTokens.textSecondary,
            ),
          ),
          const SizedBox(width: ZirenTokens.space16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: valueColor ?? ZirenTokens.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// An editable line that keeps a row's geometry.
///
/// The responder profile used to put bare TextFormFields straight into the
/// scroll view, which is why it read as a form rather than a profile. This
/// keeps the field inside the card, on the same 16/12 padding and the same
/// hairline, so switching to edit mode changes what a row DOES without
/// changing what the screen IS.
class ProfileEditRow extends StatelessWidget {
  const ProfileEditRow({
    super.key,
    required this.icon,
    required this.label,
    required this.controller,
    this.hintText,
    this.keyboardType,
    this.validator,
    this.last = false,
  });

  final IconData icon;
  final String label;
  final TextEditingController controller;
  final String? hintText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        ZirenTokens.space16,
        ZirenTokens.space8,
        ZirenTokens.space16,
        ZirenTokens.space8,
      ),
      decoration: BoxDecoration(
        border:
            last
                ? null
                : Border(
                  bottom: BorderSide(
                    color: ZirenTokens.surfaceBorder,
                    width: 0.5,
                  ),
                ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: ZirenTokens.textMuted),
          const SizedBox(width: ZirenTokens.space12),
          Expanded(
            child: TextFormField(
              controller: controller,
              keyboardType: keyboardType,
              validator: validator,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: ZirenTokens.textPrimary,
              ),
              decoration: InputDecoration(
                labelText: label,
                hintText: hintText,
                labelStyle: TextStyle(
                  fontSize: 13,
                  color: ZirenTokens.textSecondary,
                ),
                isDense: true,
                // No box. The card already provides the container; an outlined
                // field inside a bordered card is two frames around one value.
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Failure
// =============================================================================

/// Shown when the profile fetch failed, in place of silently blank rows.
///
/// "Backend not running" and "genuinely has no barangay" used to look
/// identical — an em dash. They are very different problems and the person
/// should be able to tell them apart, and act on the one they can.
class ProfileLoadError extends StatelessWidget {
  const ProfileLoadError({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space16),
      decoration: BoxDecoration(
        color: ZirenTokens.systemErrorBg,
        borderRadius: BorderRadius.circular(ZirenTokens.radius12),
        border: Border.all(
          color: ZirenTokens.systemError.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            LucideIcons.cloud_off,
            size: 20,
            color: ZirenTokens.systemError,
          ),
          const SizedBox(width: ZirenTokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: ZirenTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: ZirenTokens.space8),
                SizedBox(
                  height: 32,
                  child: OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(LucideIcons.refresh_cw, size: 15),
                    label: const Text('Retry'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ZirenTokens.systemError,
                      side: BorderSide(
                        color: ZirenTokens.systemError.withValues(alpha: 0.4),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: ZirenTokens.space12,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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

// =============================================================================
// Chips
// =============================================================================

/// A small pill for a state that belongs to the identity: agency, duty,
/// approval.
class ProfileChip extends StatelessWidget {
  const ProfileChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.filled = false,
  });

  final String label;
  final Color color;
  final IconData? icon;

  /// Solid rather than tinted. Reserved for the one chip on the screen that
  /// carries operational weight — a crew's duty state — so it is not
  /// competing with three other pills for the same attention.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : color;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZirenTokens.space12,
        vertical: ZirenTokens.space6,
      ),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(ZirenTokens.radius32),
        border:
            filled ? null : Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: ZirenTokens.space6),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
