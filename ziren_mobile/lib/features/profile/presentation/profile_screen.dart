import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../features/auth/domain/auth_provider.dart';
import '../../../features/settings/domain/profile_model.dart';
import '../../../features/settings/domain/profile_provider.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/ziren_dialogs.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../../../shared/widgets/profile_kit.dart';
import '../../../shared/widgets/ziren_card.dart';
import '../../../l10n/app_localizations.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Profile screen — centered avatar + name/email, an in-page verification
/// card, and grouped info rows.
///
/// The photo hero banner this screen used to open with is gone — a plain
/// AppBar with a settings gear replaced it, and the avatar (now editable,
/// via `shared/widgets/profile_kit.dart`'s EditableAvatar) sits centered
/// above the name instead of overlapping a banner's bottom edge. The
/// responder profile mirrors this exactly, both drawing on the same shared
/// widgets, so the two cannot drift again without someone editing that file
/// on purpose.
///
/// Sections:
///   1. Avatar + name/email, centered
///   2. Verification card (verified / in review / not started)
///   3. Personal Information (name, email, phone, address)
///   4. Emergency Contact (contact name, contact number)
///   5. Safety (hotline directory, safety guide, announcements)
///   6. Log out
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _uploadingAvatar = false;

  Future<void> _changeAvatar() async {
    setState(() => _uploadingAvatar = true);
    await pickAndUploadAvatar(context);
    if (mounted) setState(() => _uploadingAvatar = false);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<ProfileProvider>();
      if (provider.profile == null) {
        provider.loadProfile();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final provider = context.watch<ProfileProvider>();

    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      appBar: AppBar(
        backgroundColor: ZirenTokens.surfaceBase,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.settings),
            onPressed: () => context.push('/profile/settings'),
          ),
        ],
      ),
      body: SafeArea(
        child:
            provider.isLoading
                ? const LoadingIndicator()
                // Pull to refresh. Without it a profile fetched once was
                // frozen for the life of the app session: the provider caches
                // per account and this screen only fetched from initState,
                // which does not run again because the Profile tab lives in an
                // IndexedStack branch. A fetch that failed, or that predated a
                // backend change, could not be retried at all — it just showed
                // dashes with no way to act on them.
                : RefreshIndicator(
                  color: ZirenTokens.brandOrange,
                  onRefresh: () => provider.loadProfile(force: true),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: _buildContent(context, auth, provider),
                  ),
                ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    AuthProvider auth,
    ProfileProvider provider,
  ) {
    final t = AppLocalizations.of(context);
    final profile = provider.profile;
    final email = auth.user?.email ?? '';
    final displayName =
        profile?.fullName.isNotEmpty == true
            ? profile!.fullName
            : email.split('@').first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: ZirenTokens.space8),
        Center(
          child: EditableAvatar(
            displayName: displayName,
            avatarUrl: profile?.avatarUrl,
            busy: _uploadingAvatar,
            onTap: _changeAvatar,
          ),
        ),
        const SizedBox(height: ZirenTokens.space12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: ZirenTokens.space16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
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
                email,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: ZirenTokens.textMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: ZirenTokens.space20),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: ZirenTokens.space16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Verification card ─────────────────────────────
              // Profile has no dismiss and no "not now" — this is where you
              // come to act on it, unlike the Home banner.
              _VerificationCard(profile: profile),
              const SizedBox(height: ZirenTokens.space20),

              if (provider.status == ProfileStatus.error) ...[
                ProfileLoadError(
                  message:
                      provider.errorMessage ?? 'Could not load your profile.',
                  onRetry: () => provider.loadProfile(force: true),
                ),
                const SizedBox(height: ZirenTokens.space16),
              ],

              // ── Personal information ───────────────────────────
              ZirenSectionLabel(t.profilePersonalInfo),
              ZirenGroupedRows(
                children: [
                  _InfoRow(
                    icon: LucideIcons.user,
                    label: t.labelNameProfile,
                    value:
                        profile?.fullName.isNotEmpty == true
                            ? profile!.fullName
                            : t.profileNotSet,
                    onTap: () => context.push('/profile/settings'),
                  ),
                  _InfoRow(
                    icon: LucideIcons.mail,
                    label: t.labelEmailProfile,
                    value: email.isNotEmpty ? email : t.profileNotSet,
                    onTap: () => context.push('/profile/settings'),
                  ),
                  _InfoRow(
                    icon: LucideIcons.phone,
                    label: t.labelPhone,
                    value:
                        profile?.phoneNumber?.isNotEmpty == true
                            ? profile!.phoneNumber!
                            : t.profileNotSet,
                    onTap: () => context.push('/profile/settings'),
                  ),
                  _InfoRow(
                    icon: LucideIcons.map_pin,
                    label: t.profileAddress,
                    value: _addressValue(profile) ?? t.profileNotSet,
                    onTap: () => context.push('/profile/settings'),
                  ),
                ],
              ),
              const SizedBox(height: ZirenTokens.space24),

              // ── Emergency contact ──────────────────────────────
              ZirenSectionLabel(t.profileEmergencyContact),
              Padding(
                padding: const EdgeInsets.only(
                  left: ZirenTokens.space4,
                  right: ZirenTokens.space4,
                  bottom: ZirenTokens.space8,
                ),
                child: Text(
                  t.emergencyWhoShort,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: ZirenTokens.textSecondary,
                  ),
                ),
              ),
              ZirenGroupedRows(
                children: [
                  _InfoRow(
                    icon: LucideIcons.map_pin,
                    label: t.labelEmergencyContactName,
                    value:
                        profile?.emergencyContactName?.isNotEmpty == true
                            ? profile!.emergencyContactName!
                            : t.profileNotSet,
                    onTap: () => context.push('/profile/settings'),
                  ),
                  _InfoRow(
                    icon: LucideIcons.phone,
                    label: t.labelEmergencyContactNumber,
                    value:
                        profile?.emergencyContactNumber?.isNotEmpty == true
                            ? profile!.emergencyContactNumber!
                            : t.profileNotSet,
                    onTap: () => context.push('/profile/settings'),
                  ),
                ],
              ),
              const SizedBox(height: ZirenTokens.space24),

              // ── Safety ──────────────────────────────────────────
              //
              // Spec Sections 21, 22, 24 — reachable whether or not there is
              // an active incident, which is exactly the point of all three:
              // a resident should be able to find a hotline number, a
              // first-aid step, or an official notice without needing
              // anything from Ziren to be working first. Not in the mockup's
              // visible panel, but real navigation that shouldn't disappear
              // in a restyle.
              _SafetySection(),
              const SizedBox(height: ZirenTokens.space24),

              // ── Log out ──────────────────────────────────────────
              OutlinedButton.icon(
                onPressed: () => _confirmLogout(context, auth),
                icon: const Icon(LucideIcons.log_out, size: 18),
                label: const Text('Log Out'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ZirenTokens.systemError,
                  side: BorderSide(
                    color: ZirenTokens.systemError.withValues(alpha: 0.5),
                  ),
                  minimumSize: const Size.fromHeight(52),
                ),
              ),

              const SizedBox(height: ZirenTokens.space32),
            ],
          ),
        ),
      ],
    );
  }

  /// Barangay + municipality, combined into the single "Address" row the
  /// mockup asks for. Null when neither is set, so the caller can fall back
  /// to the "Not set" copy instead of rendering an empty row.
  String? _addressValue(ProfileModel? profile) {
    final barangay = profile?.barangay?.trim();
    final municipality = profile?.municipalityAddress?.trim();
    final parts = [
      if (barangay != null && barangay.isNotEmpty) barangay,
      if (municipality != null && municipality.isNotEmpty) municipality,
    ];
    return parts.isEmpty ? null : parts.join(', ');
  }

  Future<void> _confirmLogout(BuildContext context, AuthProvider auth) async {
    final t = AppLocalizations.of(context);
    final confirmed = await showZirenDialog<bool>(
      context,
      icon: LucideIcons.log_out,
      tone: ZirenTone.danger,
      title: t.settingsLogOutConfirmTitle,
      message: t.settingsLogOutConfirmBody,
      actions: [
        ZirenDialogAction(
          label: t.settingsLogOut,
          value: true,
          kind: ZirenActionKind.danger,
          icon: LucideIcons.log_out,
        ),
        ZirenDialogAction(label: t.settingsCancel, value: false),
      ],
    );
    if (confirmed == true && context.mounted) {
      // The cached profile belongs to the account being signed out of;
      // clear it before logout so the next person on a shared handset
      // never sees it.
      context.read<ProfileProvider>().clear();
      await auth.logout();
      if (context.mounted) context.go('/login');
    }
  }
}


// =============================================================================
// Verification card
// =============================================================================

/// Verified / in-review / not-started, mirroring the state logic in
/// `VerificationBanner` — but always visible (no dismiss) and styled as a
/// standalone card rather than an inline strip, per the mockup.
///
/// Blue (systemInfo), never green or brand orange: verification is not a
/// severity signal and not a CTA button, and `VerificationBanner` already
/// establishes info-blue as this product's "identity nudge" colour.
class _VerificationCard extends StatelessWidget {
  const _VerificationCard({required this.profile});

  final ProfileModel? profile;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final p = profile;

    final bool verified = p?.isVerifiedResident ?? false;
    final bool submitted = p?.hasSubmittedEvidence ?? false;

    final IconData icon =
        verified
            ? LucideIcons.badge_check
            : submitted
            ? LucideIcons.hourglass
            : LucideIcons.shield_check;

    final String title =
        verified
            ? t.profileAccountVerified
            : submitted
            ? t.bannerInReview
            : t.bannerFinishVerifying;

    final String subtitle =
        verified
            ? t.profileAccountVerifiedBody
            : submitted
            ? t.bannerInReviewBody
            : t.bannerFinishBody;

    // Only the "hasn't started" state has anything left to do — in review
    // there's nothing to tap, and verified is a completed state.
    final bool showLearnMore = !verified && !submitted;

    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space16),
      decoration: BoxDecoration(
        color: ZirenTokens.systemInfoBg,
        borderRadius: BorderRadius.circular(ZirenTokens.radius20),
        border: Border.all(
          color: ZirenTokens.systemInfo.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 22, color: ZirenTokens.systemInfo),
              const SizedBox(width: ZirenTokens.space12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: ZirenTokens.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: ZirenTokens.space8),
              _OptionalPill(label: t.badgeOptional),
            ],
          ),
          const SizedBox(height: ZirenTokens.space8),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: ZirenTokens.textSecondary,
            ),
          ),
          if (showLearnMore) ...[
            const SizedBox(height: ZirenTokens.space8),
            InkWell(
              onTap: () => context.push('/profile/verify'),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t.profileVerifyLearnMore,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: ZirenTokens.brandOrange,
                    ),
                  ),
                  const SizedBox(width: ZirenTokens.space4),
                  const Icon(
                    LucideIcons.arrow_right,
                    size: 14,
                    color: ZirenTokens.brandOrange,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OptionalPill extends StatelessWidget {
  const _OptionalPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZirenTokens.space8,
        vertical: ZirenTokens.space2,
      ),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceRaised,
        borderRadius: BorderRadius.circular(ZirenTokens.radius32),
        border: Border.all(color: ZirenTokens.surfaceBorder),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: ZirenTokens.textMuted,
        ),
      ),
    );
  }
}

// =============================================================================
// Grouped info row
// =============================================================================

/// One `icon · label/value · chevron` row inside a [ZirenGroupedRows]
/// container — the mockup's Personal Information / Emergency Contact rows.
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ZirenTokens.space16,
          vertical: ZirenTokens.space12,
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: ZirenTokens.textMuted),
            const SizedBox(width: ZirenTokens.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: ZirenTokens.textMuted,
                    ),
                  ),
                  const SizedBox(height: ZirenTokens.space2),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: ZirenTokens.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              LucideIcons.chevron_right,
              size: 18,
              color: ZirenTokens.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Safety
// =============================================================================

/// Emergency Contacts, Safety Guide, and Announcements — three destinations
/// that exist independently of any active report (spec Sections 21, 22, 24).
class _SafetySection extends StatelessWidget {
  const _SafetySection();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
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
            padding: const EdgeInsets.fromLTRB(
              ZirenTokens.space16,
              ZirenTokens.space12,
              ZirenTokens.space16,
              ZirenTokens.space8,
            ),
            child: Text(
              t.profileSafetySection,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: ZirenTokens.textPrimary,
              ),
            ),
          ),
          Divider(height: 1, color: ZirenTokens.surfaceBorder),
          _SafetyRow(
            icon: LucideIcons.phone_call,
            label: t.hotlinesTitle,
            onTap: () => context.push('/hotlines'),
          ),
          _SafetyRow(
            icon: LucideIcons.life_buoy,
            label: t.helpTitle,
            onTap: () => context.push('/help'),
          ),
          _SafetyRow(
            icon: LucideIcons.shield_plus,
            label: t.safetyGuideTitle,
            onTap: () => context.push('/safety-guide'),
          ),
          _SafetyRow(
            icon: LucideIcons.megaphone,
            label: t.announcementsTitle,
            onTap: () => context.push('/announcements'),
            last: true,
          ),
        ],
      ),
    );
  }
}

class _SafetyRow extends StatelessWidget {
  const _SafetyRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.last = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
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
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: ZirenTokens.textPrimary,
                ),
              ),
            ),
            Icon(
              LucideIcons.chevron_right,
              size: 18,
              color: ZirenTokens.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
