import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../../../shared/widgets/profile_kit.dart';
import '../../auth/domain/auth_provider.dart';
import '../../settings/domain/profile_provider.dart';
import '../domain/responder_provider.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import '../../../shared/widgets/ziren_dialogs.dart';

/// The responder's profile.
///
/// WHY THIS WAS REBUILT
///
/// It did not look like the same product as the resident profile, and the
/// reason was structural rather than cosmetic. The resident screen opens with
/// a gradient avatar, then stacks titled cards whose rows read label-left /
/// value-right. This screen had no header at all — it began at a section
/// title — and dropped bare TextFormFields straight into the scroll view. So
/// it read as a settings form that happened to show a name, rather than as
/// somebody's profile.
///
/// The cause was that the resident's components were private to its own file,
/// so this screen was built by re-implementing them from memory. They now live
/// in shared/widgets/profile_kit.dart and BOTH screens use the same widgets,
/// which is the only version of this fix that survives the next screen.
///
/// WHAT IS DIFFERENT HERE, AND WHY
///
/// A resident's profile answers "who am I to this app". A responder's has to
/// answer "who am I ON DUTY": which unit, which badge, whether the agency has
/// approved me, and whether I am currently taking calls. That is why the
/// header carries an agency chip and a duty state, and why approval gets a
/// banner rather than a row — a responder whose account is still pending
/// cannot be dispatched at all, and that is the single most important fact on
/// the screen when it is true.
///
/// Contact is read-only here — name and phone changes go through Settings,
/// same as the resident side, rather than an in-place edit mode on this
/// screen.
class ResponderProfileScreen extends StatefulWidget {
  const ResponderProfileScreen({super.key});

  @override
  State<ResponderProfileScreen> createState() => _ResponderProfileScreenState();
}

class _ResponderProfileScreenState extends State<ResponderProfileScreen> {
  bool _uploadingAvatar = false;

  Future<void> _changeAvatar() async {
    setState(() => _uploadingAvatar = true);
    await pickAndUploadAvatar(context);
    if (mounted) setState(() => _uploadingAvatar = false);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<ProfileProvider>();
      if (provider.profile == null && !provider.isLoading) {
        await provider.loadProfile();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProfileProvider>();
    final profile = provider.profile;

    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      appBar: AppBar(
        backgroundColor: ZirenTokens.surfaceBase,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: AppLocalizations.of(context).hotlinesTitle,
            icon: const Icon(LucideIcons.phone_call),
            onPressed: () => context.push('/hotlines'),
          ),
          IconButton(
            tooltip: AppLocalizations.of(context).helpTitle,
            icon: const Icon(LucideIcons.life_buoy),
            onPressed: () => context.push('/help?role=responder'),
          ),
          IconButton(
            icon: const Icon(LucideIcons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: SafeArea(
        child:
            provider.isLoading && profile == null
                ? const LoadingIndicator()
                : RefreshIndicator(
                  // Pull to refresh, as on the resident profile. Without it a
                  // profile fetched once is frozen for the session: the Profile
                  // tab lives in an IndexedStack branch, so initState does not
                  // run again and a failed fetch could not be retried at all.
                  color: ZirenTokens.brandOrange,
                  onRefresh: () => provider.loadProfile(force: true),
                  child: _buildContent(context, provider),
                ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, ProfileProvider provider) {
    final t = AppLocalizations.of(context);
    final auth = context.watch<AuthProvider>();
    final responder = context.watch<ResponderProvider>();
    final p = provider.profile;
    final email = p?.email ?? auth.user?.email ?? '';

    if (p == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(ZirenTokens.space16),
        children: [
          ProfileLoadError(
            message: provider.errorMessage ?? 'Could not load your profile.',
            onRetry: () {
              provider.clearError();
              provider.loadProfile(force: true);
            },
          ),
        ],
      );
    }

    final displayName =
        p.fullName.isNotEmpty ? p.fullName : email.split('@').first;
    final agencyLabel = p.agencyName ?? p.agencyType;
    final approved = p.approvalStatus == 'approved';

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: [
        const SizedBox(height: ZirenTokens.space8),
        Center(
          child: EditableAvatar(
            displayName: displayName,
            avatarUrl: p.avatarUrl,
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
                style: TextStyle(fontSize: 13, color: ZirenTokens.textMuted),
              ),
              const SizedBox(height: ZirenTokens.space12),
              // Agency and duty state belong to the identity, not to a
              // section. Duty is read-only here on purpose — the toggle
              // lives on Home, and two controls for one state is how they
              // end up disagreeing.
              Wrap(
                alignment: WrapAlignment.center,
                spacing: ZirenTokens.space8,
                runSpacing: ZirenTokens.space8,
                children: [
                  if (agencyLabel != null)
                    ProfileChip(
                      label: agencyLabel,
                      color: _agencyColor(p.agencyType),
                      icon: _agencyIcon(p.agencyType),
                    ),
                  if (approved)
                    ProfileChip(
                      label: responder.isOnDuty ? t.respOnDuty : t.respOffDuty,
                      color:
                          responder.isOnDuty
                              ? ZirenTokens.systemSuccess
                              : ZirenTokens.textMuted,
                      icon:
                          responder.isOnDuty
                              ? LucideIcons.wifi
                              : LucideIcons.circle_slash,
                      filled: responder.isOnDuty,
                    ),
                ],
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
              // ── Approval ─────────────────────────────────────
              //
              // A banner rather than a row while it is unresolved. A responder
              // whose account is still pending cannot be dispatched to anything,
              // and burying that in the fifth line of a card would let somebody
              // sit through a shift believing they were on the roster.
              if (!approved) ...[
                _ApprovalBanner(status: p.approvalStatus),
                const SizedBox(height: ZirenTokens.space16),
              ],

              if (provider.errorMessage != null) ...[
                ProfileLoadError(
                  message: provider.errorMessage!,
                  onRetry: () {
                    provider.clearError();
                    provider.loadProfile(force: true);
                  },
                ),
                const SizedBox(height: ZirenTokens.space16),
              ],

              // ── Contact ──────────────────────────────────────
              //
              // Read-only. Name and phone changes go through Settings
              // (the same editor the resident side uses) rather than an
              // in-place edit mode on this screen.
              ProfileSection(
                title: t.respProfileContact,
                items: [
                  ProfileRow(
                    icon: LucideIcons.user,
                    label: t.respFieldName,
                    value: p.fullName.isNotEmpty ? p.fullName : '—',
                  ),
                  ProfileRow(
                    icon: LucideIcons.mail,
                    label: 'Email',
                    value: email.isNotEmpty ? email : '—',
                  ),
                  ProfileRow(
                    icon: LucideIcons.phone,
                    label: t.respFieldPhone,
                    value:
                        p.phoneNumber?.isNotEmpty == true
                            ? p.phoneNumber!
                            : '—',
                    last: true,
                  ),
                ],
              ),
              const SizedBox(height: ZirenTokens.space16),

              // ── Assignment ───────────────────────────────────
              //
              // The unit, not the UUID. This card used to render agencyId, and a
              // crew member cannot tell whether
              // "a0000001-0000-0000-0000-000000000001" is theirs — which made the
              // field worse than showing nothing at all.
              ProfileSection(
                title: t.respProfileAssignment,
                items: [
                  ProfileRow(
                    icon: LucideIcons.badge,
                    label: t.respProfileBadge,
                    value: p.badgeId ?? '—',
                  ),
                  ProfileRow(
                    icon: _agencyIcon(p.agencyType),
                    label: t.respProfileAgency,
                    value: agencyLabel ?? '—',
                    valueColor: _agencyColor(p.agencyType),
                  ),
                  ProfileRow(
                    icon: LucideIcons.map_pin,
                    label: t.respProfileMunicipality,
                    value: p.agencyMunicipality ?? '—',
                  ),
                  // Read-only "who do I call" info — Section 21. The responder
                  // cannot change their agency/station from here; this exists
                  // only so they never have to hunt for the station's own
                  // number during a shift.
                  if (p.agencyContactNumber?.isNotEmpty == true)
                    ProfileRow(
                      icon: LucideIcons.phone,
                      label: 'Station Contact',
                      value: p.agencyContactNumber!,
                    ),
                  ProfileRow(
                    icon: _approvalIcon(p.approvalStatus),
                    label: t.respProfileStatus,
                    value: _approvalLabel(p.approvalStatus),
                    valueColor: _approvalColor(p.approvalStatus),
                    last: true,
                  ),
                ],
              ),
              const SizedBox(height: ZirenTokens.space24),

              // ── Sign out ─────────────────────────────────────
              //
              // Outlined and error-coloured. Disabled mid-save: signing out while
              // a PATCH is in flight would tear the session down under the request
              // and lose the edit with no error worth showing.
              OutlinedButton.icon(
                onPressed:
                    provider.isSaving ? null : () => _confirmLogout(context),
                icon: const Icon(LucideIcons.log_out, size: 18),
                label: Text(t.respLogout),
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

  /// Confirm, then sign out and return to the login screen.
  ///
  /// The wording names the consequence that is specific to this role. A
  /// resident who signs out loses access to their own reports; a responder who
  /// signs out STOPS RECEIVING DISPATCH ALERTS, and on a phone that is the
  /// station's shift handset that is worth saying out loud before it happens
  /// rather than discovering it during a callout.
  ///
  /// Spec Section 26's "Additional Safety": a responder with an open
  /// assignment gets a sharper warning than an idle one, because signing out
  /// mid-call is a different mistake than signing out at the end of a shift
  /// — one strands a live emergency, the other loses nothing.
  Future<void> _confirmLogout(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final hasActiveAssignment =
        context.read<ResponderProvider>().queue.isNotEmpty;

    final l = AppLocalizations.of(context);
    final confirmed = await showZirenDialog<bool>(
      context,
      icon:
          hasActiveAssignment
              ? LucideIcons.triangle_alert
              : LucideIcons.log_out,
      tone: hasActiveAssignment ? ZirenTone.warning : ZirenTone.danger,
      title:
          hasActiveAssignment
              ? l.respActiveAssignmentTitle
              : l.respLogoutConfirm,
      message:
          hasActiveAssignment ? l.respActiveAssignmentBody : l.respLogoutBody,
      // With a call in hand, staying signed in is the one to press.
      actions: [
        if (hasActiveAssignment)
          ZirenDialogAction(
            label: l.respStaySignedIn,
            value: false,
            kind: ZirenActionKind.primary,
          ),
        ZirenDialogAction(
          label: l.respLogout,
          value: true,
          kind:
              hasActiveAssignment
                  ? ZirenActionKind.secondary
                  : ZirenActionKind.danger,
          icon: LucideIcons.log_out,
        ),
        if (!hasActiveAssignment)
          ZirenDialogAction(label: l.respCancel, value: false),
      ],
    );
    if (confirmed != true || !context.mounted) return;

    // The cached profile belongs to the account being signed out of.
    // ProfileProvider's getter already refuses to serve it to a different
    // user, but clearing it here means the next person to sign in on this
    // handset never has it in memory at all — which on a shared station phone
    // is the difference that matters.
    context.read<ProfileProvider>().clear();

    await auth.logout();
    if (context.mounted) context.go('/login');
  }

  // ── Vocabulary ────────────────────────────────────────────

  IconData _agencyIcon(String? type) => switch (type) {
    'BFP' => LucideIcons.flame,
    'PNP' => LucideIcons.shield,
    'MDRRMO' => LucideIcons.stethoscope,
    _ => LucideIcons.building,
  };

  /// The fixed agency hues from the design tokens. These are not decorative —
  /// a crew recognises their own colour before they read the word.
  Color _agencyColor(String? type) => switch (type) {
    'BFP' => ZirenTokens.agencyBFP,
    'PNP' => ZirenTokens.agencyPNP,
    'MDRRMO' => ZirenTokens.agencyMDRRMO,
    _ => ZirenTokens.textSecondary,
  };

  IconData _approvalIcon(String status) => switch (status) {
    'approved' => LucideIcons.badge_check,
    'rejected' => LucideIcons.circle_x,
    _ => LucideIcons.hourglass,
  };

  String _approvalLabel(String status) {
    final t = AppLocalizations.of(context);
    return switch (status) {
      'approved' => t.respApproved,
      'rejected' => t.respRejected,
      _ => t.respPending,
    };
  }

  Color _approvalColor(String status) => switch (status) {
    'approved' => ZirenTokens.systemSuccess,
    'rejected' => ZirenTokens.systemError,
    _ => ZirenTokens.systemWarning,
  };
}

// ── Approval banner ───────────────────────────────────────────

/// Shown only while the account is not approved.
///
/// An unapproved responder cannot be dispatched to anything, so this is not a
/// status line — it is the reason the rest of the app will appear to do
/// nothing. Saying it plainly is the difference between a responder who waits
/// and one who thinks the app is broken.
class _ApprovalBanner extends StatelessWidget {
  const _ApprovalBanner({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final rejected = status == 'rejected';
    final color =
        rejected ? ZirenTokens.systemError : ZirenTokens.systemWarning;
    final bg =
        rejected ? ZirenTokens.systemErrorBg : ZirenTokens.systemWarningBg;

    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(ZirenTokens.radius12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            rejected ? LucideIcons.circle_x : LucideIcons.hourglass,
            size: 20,
            color: color,
          ),
          const SizedBox(width: ZirenTokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rejected ? t.respRejectedTitle : t.respPendingTitle,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: ZirenTokens.space4),
                Text(
                  rejected ? t.respRejectedBody : t.respPendingBody,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: ZirenTokens.textSecondary,
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
