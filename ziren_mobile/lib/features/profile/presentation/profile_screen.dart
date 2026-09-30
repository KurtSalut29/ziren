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
import '../../../l10n/app_localizations.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Profile screen - a header card (avatar, name, email, verification and
/// address chips), the verification card while it still matters, and titled
/// groups of icon tiles.
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
///   1. Header card: avatar, name/email, verification + address chips
///   2. Verification card (in review / not started; hidden once verified)
///   3. Personal Information (name, email, phone, address)
///   4. Emergency Contact (contact name, contact number)
///   5. Safety & help (hotlines, help, safety guide, announcements)
///   6. Account (settings, log out)
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
        title: Text(
          AppLocalizations.of(context).navProfile,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: ZirenTokens.textPrimary,
          ),
        ),
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
    final verified = profile?.isVerifiedResident ?? false;
    final submitted = profile?.hasSubmittedEvidence ?? false;
    final address = _addressValue(profile);
    void edit() => context.push('/profile/settings');

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZirenTokens.space16,
        ZirenTokens.space4,
        ZirenTokens.space16,
        ZirenTokens.space32,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProfileHeroCard(
            avatar: EditableAvatar(
              displayName: displayName,
              avatarUrl: profile?.avatarUrl,
              busy: _uploadingAvatar,
              onTap: _changeAvatar,
              size: 92,
            ),
            displayName: displayName,
            subtitle: email,
            chips: [
              // Info-blue, never green: verification is an identity nudge,
              // not a severity or a completed action (see _VerificationCard).
              ProfileChip(
                label:
                    verified
                        ? t.profileChipVerified
                        : submitted
                        ? t.profileChipInReview
                        : t.profileChipNotVerified,
                color:
                    verified || submitted
                        ? ZirenTokens.systemInfo
                        : ZirenTokens.textMuted,
                icon:
                    verified
                        ? LucideIcons.badge_check
                        : submitted
                        ? LucideIcons.hourglass
                        : LucideIcons.shield,
              ),
              if (address != null)
                ProfileChip(
                  label: address,
                  color: ZirenTokens.textSecondary,
                  icon: LucideIcons.map_pin,
                ),
            ],
          ),

          // ── Verification ──────────────────────────────────────
          // Only while there is still something to know or do. Once verified,
          // the chip in the header says so; a card repeating it pushed the
          // resident's own details below the fold.
          if (!verified) ...[
            const SizedBox(height: ZirenTokens.space16),
            _VerificationCard(profile: profile),
          ],

          if (provider.status == ProfileStatus.error) ...[
            const SizedBox(height: ZirenTokens.space16),
            ProfileLoadError(
              message: provider.errorMessage ?? 'Could not load your profile.',
              onRetry: () => provider.loadProfile(force: true),
            ),
          ],
          const SizedBox(height: ZirenTokens.space24),

          // ── Personal information ──────────────────────────────
          ProfileGroup(
            title: t.profilePersonalInfo,
            children: [
              ProfileTile(
                icon: LucideIcons.user,
                label: t.labelNameProfile,
                value:
                    profile?.fullName.isNotEmpty == true
                        ? profile!.fullName
                        : t.profileNotSet,
                onTap: edit,
              ),
              ProfileTile(
                icon: LucideIcons.mail,
                label: t.labelEmailProfile,
                value: email.isNotEmpty ? email : t.profileNotSet,
                onTap: edit,
              ),
              ProfileTile(
                icon: LucideIcons.phone,
                label: t.labelPhone,
                value:
                    profile?.phoneNumber?.isNotEmpty == true
                        ? profile!.phoneNumber!
                        : t.profileNotSet,
                onTap: edit,
              ),
              ProfileTile(
                icon: LucideIcons.map_pin,
                label: t.profileAddress,
                value: address ?? t.profileNotSet,
                onTap: edit,
              ),
            ],
          ),
          const SizedBox(height: ZirenTokens.space24),

          // ── Emergency contact ─────────────────────────────────
          ProfileGroup(
            title: t.profileEmergencyContact,
            caption: t.emergencyWhoShort,
            children: [
              ProfileTile(
                icon: LucideIcons.contact,
                label: t.labelEmergencyContactName,
                value:
                    profile?.emergencyContactName?.isNotEmpty == true
                        ? profile!.emergencyContactName!
                        : t.profileNotSet,
                onTap: edit,
              ),
              ProfileTile(
                icon: LucideIcons.phone,
                label: t.labelEmergencyContactNumber,
                value:
                    profile?.emergencyContactNumber?.isNotEmpty == true
                        ? profile!.emergencyContactNumber!
                        : t.profileNotSet,
                onTap: edit,
              ),
            ],
          ),
          const SizedBox(height: ZirenTokens.space24),

          // ── Safety & help ─────────────────────────────────────
          //
          // Spec Sections 21, 22, 24 - reachable whether or not there is an
          // active incident, which is exactly the point of all of them: a
          // resident should be able to find a hotline number, a first-aid
          // step, or an official notice without needing anything from Ziren
          // to be working first.
          ProfileGroup(
            title: t.profileSafetyHelp,
            children: [
              ProfileTile(
                icon: LucideIcons.phone_call,
                label: t.hotlinesTitle,
                tone: ZirenTokens.systemSuccess,
                onTap: () => context.push('/hotlines'),
              ),
              ProfileTile(
                icon: LucideIcons.life_buoy,
                label: t.helpTitle,
                tone: ZirenTokens.systemInfo,
                onTap: () => context.push('/help'),
              ),
              ProfileTile(
                icon: LucideIcons.shield_plus,
                label: t.safetyGuideTitle,
                onTap: () => context.push('/safety-guide'),
              ),
              ProfileTile(
                icon: LucideIcons.megaphone,
                label: t.announcementsTitle,
                onTap: () => context.push('/announcements'),
              ),
            ],
          ),
          const SizedBox(height: ZirenTokens.space24),

          // ── Account ───────────────────────────────────────────
          ProfileGroup(
            title: t.profileAccount,
            children: [
              ProfileTile(
                icon: LucideIcons.settings,
                label: t.profileSettings,
                onTap: edit,
              ),
              ProfileTile(
                icon: LucideIcons.log_out,
                label: t.settingsLogOut,
                danger: true,
                onTap: () => _confirmLogout(context, auth),
              ),
            ],
          ),
        ],
      ),
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
      horizontalActions: true,
      actions: [
        ZirenDialogAction(label: t.settingsCancel, value: false),
        ZirenDialogAction(
          label: t.settingsLogOut,
          value: true,
          kind: ZirenActionKind.danger,
          icon: LucideIcons.log_out,
        ),
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
        borderRadius: BorderRadius.circular(18),
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
