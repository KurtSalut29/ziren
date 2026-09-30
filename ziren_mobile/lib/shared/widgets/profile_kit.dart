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
/// 2026-09-30 redesign: the header became a card ([ProfileHeroCard]) and the
/// sections became titled groups of icon tiles ([ProfileGroup], [ProfileTile]),
/// the same card language as the Home screens. Both profiles still use exactly
/// these widgets.

// =============================================================================
// Header
// =============================================================================

/// One short fact in the strip along the bottom of a [ProfileHeroCard]:
/// a badge number, an approval state.
class ProfileFact {
  const ProfileFact({required this.label, required this.value, this.color});

  final String label;
  final String value;

  /// For a value whose colour carries meaning (approved green, pending amber).
  final Color? color;
}

/// The top of a profile: a card with a softly tinted band that the avatar sits
/// across, then the name, the email, a row of identity chips, and optionally a
/// strip of [facts].
///
/// The old header was a bare avatar and two lines of text floating on the page
/// background, above cards that looked like a settings list - so the one part
/// of the screen that is about the PERSON had the least structure. Putting it
/// in its own card, with the chips (verified, agency, on duty) where the eye
/// lands first, makes the identity the screen's anchor.
class ProfileHeroCard extends StatelessWidget {
  const ProfileHeroCard({
    super.key,
    required this.avatar,
    required this.displayName,
    required this.subtitle,
    this.chips = const [],
    this.facts = const [],
  });

  /// Usually an [EditableAvatar]; the card draws a ring of its own colour
  /// around it so it reads as lifted off the band.
  final Widget avatar;
  final String displayName;

  /// Usually the email: the line that identifies the account, not the person.
  final String subtitle;
  final List<Widget> chips;
  final List<ProfileFact> facts;

  static const double _band = 68;
  static const double _ring = 4;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: profileCardDecoration(radius: ZirenTokens.radius20),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.topCenter,
            children: [
              Container(
                height: _band,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      ZirenTokens.brandOrange.withValues(
                        alpha: ZirenTokens.isDark ? 0.30 : 0.22,
                      ),
                      ZirenTokens.brandOrange.withValues(
                        alpha: ZirenTokens.isDark ? 0.10 : 0.06,
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: _band - 48),
                child: Container(
                  padding: const EdgeInsets.all(_ring),
                  decoration: BoxDecoration(
                    color: ZirenTokens.surfaceCard,
                    shape: BoxShape.circle,
                  ),
                  child: avatar,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ZirenTokens.space20,
              ZirenTokens.space10,
              ZirenTokens.space20,
              0,
            ),
            child: Column(
              children: [
                Text(
                  displayName,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 21,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                    color: ZirenTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: ZirenTokens.space4),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: ZirenTokens.textMuted),
                ),
                if (chips.isNotEmpty) ...[
                  const SizedBox(height: ZirenTokens.space12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: ZirenTokens.space8,
                    runSpacing: ZirenTokens.space8,
                    children: chips,
                  ),
                ],
              ],
            ),
          ),
          if (facts.isEmpty)
            const SizedBox(height: ZirenTokens.space20)
          else ...[
            const SizedBox(height: ZirenTokens.space16),
            Divider(height: 1, color: ZirenTokens.surfaceBorder),
            IntrinsicHeight(
              child: Row(
                children: [
                  for (var i = 0; i < facts.length; i++) ...[
                    if (i > 0)
                      VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: ZirenTokens.surfaceBorder,
                      ),
                    Expanded(child: _FactCell(fact: facts[i])),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FactCell extends StatelessWidget {
  const _FactCell({required this.fact});

  final ProfileFact fact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ZirenTokens.space8,
        vertical: ZirenTokens.space12,
      ),
      child: Column(
        children: [
          Text(
            fact.value,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: fact.color ?? ZirenTokens.textPrimary,
            ),
          ),
          const SizedBox(height: ZirenTokens.space2),
          Text(
            fact.label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: ZirenTokens.textMuted),
          ),
        ],
      ),
    );
  }
}

/// The card surface every profile block shares: white, rounded, a hairline
/// border and a shadow faint enough to vanish in dark mode.
BoxDecoration profileCardDecoration({double radius = 18}) => BoxDecoration(
  color: ZirenTokens.surfaceCard,
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: ZirenTokens.surfaceBorder.withValues(alpha: 0.8)),
  boxShadow: [
    BoxShadow(
      color: Colors.black.withValues(alpha: ZirenTokens.isDark ? 0 : 0.03),
      blurRadius: 10,
      offset: const Offset(0, 3),
    ),
  ],
);

/// Two initials from a name, one if that is all there is.
String initialsOf(String name) {
  // First name + SURNAME ("Mark Anthony Reyes" -> MR), the same letters the
  // Home header shows, so one person never carries two different monograms.
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length >= 2 && parts.first.isNotEmpty && parts.last.isNotEmpty) {
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
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
// Groups and tiles
// =============================================================================

/// A small upper-case title, an optional sentence under it, and a card of
/// [ProfileTile]s separated by hairlines that start after the icon.
///
/// The title sits OUTSIDE the card, as on the Home screen's groups, so the
/// card holds only things you can read or press.
class ProfileGroup extends StatelessWidget {
  const ProfileGroup({
    super.key,
    required this.title,
    required this.children,
    this.caption,
  });

  final String title;
  final String? caption;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: ZirenTokens.space4,
            bottom: ZirenTokens.space8,
          ),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
              color: ZirenTokens.textSecondary,
            ),
          ),
        ),
        if (caption != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ZirenTokens.space4,
              0,
              ZirenTokens.space4,
              ZirenTokens.space10,
            ),
            child: Text(
              caption!,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: ZirenTokens.textSecondary,
              ),
            ),
          ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: profileCardDecoration(),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      indent: 62,
                      color: ZirenTokens.surfaceBorder.withValues(alpha: 0.7),
                    ),
                  children[i],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One line of a [ProfileGroup]: an icon in a tinted square, then either a
/// small label over a bold value (information) or a single label (a place to
/// go, an action), and a chevron when it can be pressed.
///
/// Label over value, not label-left / value-right: a long email or a station
/// with three numbers gets the whole width instead of wrapping into half a
/// row, and every value starts at the same x so the eye can run down them.
class ProfileTile extends StatelessWidget {
  const ProfileTile({
    super.key,
    required this.icon,
    required this.label,
    this.value,
    this.valueColor,
    this.tone,
    this.onTap,
    this.danger = false,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String label;

  /// A short line under a single-label row saying what it does
  /// ("Updates on your reports"). Ignored when there is a [value].
  final String? subtitle;

  /// Replaces the chevron: a Switch, a status word.
  final Widget? trailing;

  /// Null for a navigation or action row: then [label] is the main text.
  final String? value;
  final Color? valueColor;

  /// Tints the icon square. Null keeps it neutral; colour is for rows whose
  /// colour means something (call = green, agency hue, sign out = red).
  final Color? tone;
  final VoidCallback? onTap;

  /// A destructive action (Log out): red icon and red label, no chevron.
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final tint = danger ? ZirenTokens.systemError : tone;
    final iconColor = tint ?? ZirenTokens.textSecondary;
    final iconBg =
        tint == null
            ? ZirenTokens.surfaceRaised
            : tint.withValues(alpha: ZirenTokens.isDark ? 0.18 : 0.10);
    // An action row with nothing to do (Log out mid-save) is shown dimmed.
    final disabled = onTap == null && value == null && trailing == null;

    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            ZirenTokens.space12,
            ZirenTokens.space10,
            ZirenTokens.space12,
            ZirenTokens.space10,
          ),
          child: Opacity(
            opacity: disabled ? 0.5 : 1,
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 18, color: iconColor),
                ),
                const SizedBox(width: ZirenTokens.space12),
                Expanded(
                  child:
                      value == null
                          ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                label,
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  color:
                                      danger
                                          ? ZirenTokens.systemError
                                          : ZirenTokens.textPrimary,
                                ),
                              ),
                              if (subtitle != null) ...[
                                const SizedBox(height: ZirenTokens.space2),
                                Text(
                                  subtitle!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.3,
                                    color: ZirenTokens.textMuted,
                                  ),
                                ),
                              ],
                            ],
                          )
                          : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                label,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: ZirenTokens.textMuted,
                                ),
                              ),
                              const SizedBox(height: ZirenTokens.space2),
                              Text(
                                value!,
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14.5,
                                  height: 1.3,
                                  fontWeight: FontWeight.w700,
                                  color: valueColor ?? ZirenTokens.textPrimary,
                                ),
                              ),
                            ],
                          ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: ZirenTokens.space8),
                  trailing!,
                ] else if (onTap != null && !danger) ...[
                  const SizedBox(width: ZirenTokens.space8),
                  Icon(
                    LucideIcons.chevron_right,
                    size: 18,
                    color: ZirenTokens.textMuted,
                  ),
                ],
              ],
            ),
          ),
        ),
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
                    // Size and weight on the Text, not as the ButtonStyle's
                    // textStyle: that REPLACES the theme's label style, font
                    // family included, so the button fell back to the
                    // platform font instead of the app's.
                    label: Text(
                      AppLocalizations.of(context).actionRetry,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ZirenTokens.systemError,
                      side: BorderSide(
                        color: ZirenTokens.systemError.withValues(alpha: 0.4),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: ZirenTokens.space12,
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
