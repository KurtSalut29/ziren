import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../../../shared/widgets/profile_kit.dart';
import '../../auth/domain/auth_provider.dart';
import '../../settings/domain/profile_provider.dart';
import '../domain/responder_provider.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import '../../../shared/widgets/ziren_dialogs.dart';
import '../../hotlines/domain/station_hotlines.dart';
import '../../demo/presentation/demo_anchor.dart';

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
///
/// 2026-09-30: restyled with the resident profile onto ProfileHeroCard /
/// ProfileGroup / ProfileTile. Badge and approval moved into the header's fact
/// strip; the station's number can be called from its row.
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
        title: Text(
          AppLocalizations.of(context).respProfileTitle,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: ZirenTokens.textPrimary,
          ),
        ),
        // Hotlines and Help used to be two unlabelled icons up here; they are
        // now named rows in "Safety & help" below. Settings stays as well as
        // having its own row, as on the resident profile.
        actions: [
          IconButton(
            tooltip: AppLocalizations.of(context).profileSettings,
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
    final stationNumbers = StationHotlines.parse(p.agencyContactNumber);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        ZirenTokens.space16,
        ZirenTokens.space4,
        ZirenTokens.space16,
        ZirenTokens.space32,
      ),
      children: [
        // Agency and duty state belong to the identity, so they are chips on
        // the header card. Duty is read-only here on purpose - the toggle
        // lives on Home, and two controls for one state is how they end up
        // disagreeing. Badge and approval are the two facts a responder is
        // asked for at a scene, so they get the strip.
        DemoAnchor(
          id: 'rprof.hero',
          child: ProfileHeroCard(
            avatar: EditableAvatar(
              displayName: displayName,
              avatarUrl: p.avatarUrl,
              busy: _uploadingAvatar,
              onTap: _changeAvatar,
              size: 92,
            ),
            displayName: displayName,
            subtitle: email,
            chips: [
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
            facts: [
              ProfileFact(label: t.respProfileBadge, value: p.badgeId ?? '—'),
              ProfileFact(
                label: t.respProfileStatus,
                value: _approvalLabel(p.approvalStatus),
                color: _approvalColor(p.approvalStatus),
              ),
            ],
          ),
        ),

        // ── Approval ─────────────────────────────────────────
        //
        // A banner as well as the fact while it is unresolved. A responder
        // whose account is still pending cannot be dispatched to anything, and
        // a word in a strip would let somebody sit through a shift believing
        // they were on the roster.
        if (!approved) ...[
          const SizedBox(height: ZirenTokens.space16),
          _ApprovalBanner(status: p.approvalStatus),
        ],

        if (provider.errorMessage != null) ...[
          const SizedBox(height: ZirenTokens.space16),
          ProfileLoadError(
            message: provider.errorMessage!,
            onRetry: () {
              provider.clearError();
              provider.loadProfile(force: true);
            },
          ),
        ],
        const SizedBox(height: ZirenTokens.space24),

        // ── Contact ──────────────────────────────────────────
        //
        // Read-only. Name and phone changes go through Settings (the same
        // editor the resident side uses) rather than an in-place edit mode.
        DemoAnchor(
          id: 'rprof.contact',
          child: ProfileGroup(
            title: t.respProfileContact,
            children: [
              ProfileTile(
                icon: LucideIcons.user,
                label: t.respFieldName,
                value: p.fullName.isNotEmpty ? p.fullName : '—',
              ),
              ProfileTile(
                icon: LucideIcons.mail,
                label: t.labelEmailProfile,
                value: email.isNotEmpty ? email : '—',
              ),
              ProfileTile(
                icon: LucideIcons.phone,
                label: t.respFieldPhone,
                value: p.phoneNumber?.isNotEmpty == true ? p.phoneNumber! : '—',
              ),
            ],
          ),
        ),
        const SizedBox(height: ZirenTokens.space24),

        // ── Station ──────────────────────────────────────────
        //
        // The unit, not the UUID: this card once rendered agencyId, and a crew
        // member cannot tell whether "a0000001-..." is theirs. The station's
        // own number is here so nobody hunts for it during a shift (Section
        // 21), and pressing it calls.
        DemoAnchor(
          id: 'rprof.station',
          child: ProfileGroup(
            title: t.profileStationSection,
            children: [
              ProfileTile(
                icon: _agencyIcon(p.agencyType),
                tone: _agencyColor(p.agencyType),
                label: t.respProfileAgency,
                value: agencyLabel ?? '—',
              ),
              ProfileTile(
                icon: LucideIcons.map_pin,
                label: t.respProfileMunicipality,
                value: p.agencyMunicipality ?? '—',
              ),
              if (stationNumbers.isNotEmpty)
                ProfileTile(
                  icon: LucideIcons.phone_call,
                  tone: ZirenTokens.systemSuccess,
                  label: t.profileStationContact,
                  value: stationNumbers
                      .map(
                        (n) =>
                            n.label == null
                                ? n.display
                                : '${n.label} ${n.display}',
                      )
                      .join('\n'),
                  onTap: () => _callStation(context, stationNumbers),
                ),
            ],
          ),
        ),
        const SizedBox(height: ZirenTokens.space24),

        // ── Safety & help ────────────────────────────────────
        DemoAnchor(
          id: 'rprof.help',
          child: ProfileGroup(
            title: t.profileSafetyHelp,
            children: [
              ProfileTile(
                icon: LucideIcons.phone_call,
                tone: ZirenTokens.systemSuccess,
                label: t.hotlinesTitle,
                onTap: () => context.push('/hotlines'),
              ),
              ProfileTile(
                icon: LucideIcons.life_buoy,
                tone: ZirenTokens.systemInfo,
                label: t.helpTitle,
                onTap: () => context.push('/help?role=responder'),
              ),
            ],
          ),
        ),
        const SizedBox(height: ZirenTokens.space24),

        // ── Account ──────────────────────────────────────────
        //
        // Log out is disabled mid-save: signing out while a PATCH is in flight
        // would tear the session down under the request and lose the edit
        // with no error worth showing.
        DemoAnchor(
          id: 'rprof.account',
          child: ProfileGroup(
            title: t.profileAccount,
            children: [
              ProfileTile(
                icon: LucideIcons.settings,
                label: t.profileSettings,
                onTap: () => context.push('/settings'),
              ),
              ProfileTile(
                icon: LucideIcons.log_out,
                label: t.respLogout,
                danger: true,
                onTap: provider.isSaving ? null : () => _confirmLogout(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// One number dials straight away; several (Globe, Smart, landline) ask
  /// which, since the right one depends on the caller's own network.
  Future<void> _callStation(
    BuildContext context,
    List<HotlineNumber> numbers,
  ) async {
    var pick = numbers.first;
    if (numbers.length > 1) {
      final chosen = await showZirenOptionSheet<HotlineNumber>(
        context,
        title: AppLocalizations.of(context).profileCallStation,
        options: [
          for (final n in numbers)
            ZirenSheetOption(
              icon: LucideIcons.phone,
              label: n.display,
              subtitle: n.label,
              value: n,
              tone: ZirenTone.success,
            ),
        ],
      );
      if (chosen == null) return;
      pick = chosen;
    }
    await launchUrl(pick.telUri);
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
  ///
  /// The dialog itself is the resident's, on purpose (tester's request,
  /// 2026-09-30): same icon, title and Cancel | Log out row. The open
  /// assignment used to turn it into a different dialog altogether, amber,
  /// retitled, with a stacked "Stay Signed In" button, which read as a
  /// second design rather than a warning. The warning is now a note inside
  /// the same dialog; Cancel is the "stay signed in".
  Future<void> _confirmLogout(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final confirmed = await showResponderLogoutDialog(
      context,
      hasActiveAssignment: context.read<ResponderProvider>().queue.isNotEmpty,
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

/// The responder's log-out confirmation. Public so a test can open it
/// without building the whole profile screen. See `_confirmLogout`.
@visibleForTesting
Future<bool?> showResponderLogoutDialog(
  BuildContext context, {
  required bool hasActiveAssignment,
}) {
  final l = AppLocalizations.of(context);
  return showZirenDialog<bool>(
    context,
    icon: LucideIcons.log_out,
    tone: ZirenTone.danger,
    title: l.respLogoutConfirm,
    message: l.respLogoutBody,
    body:
        hasActiveAssignment
            ? _ActiveAssignmentNote(text: l.respActiveAssignmentBody)
            : null,
    horizontalActions: true,
    actions: [
      ZirenDialogAction(label: l.settingsCancel, value: false),
      ZirenDialogAction(
        label: l.respLogout,
        value: true,
        kind: ZirenActionKind.danger,
        icon: LucideIcons.log_out,
      ),
    ],
  );
}

/// The open-assignment warning, inside the ordinary log-out dialog.
///
/// Amber, not red: red is reserved for critical severity (app_tokens.dart),
/// and this is a caution about the responder's own action.
class _ActiveAssignmentNote extends StatelessWidget {
  const _ActiveAssignmentNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('logout-active-assignment'),
      padding: const EdgeInsets.all(ZirenTokens.space10),
      decoration: BoxDecoration(
        color: ZirenTokens.systemWarningBg,
        borderRadius: BorderRadius.circular(ZirenTokens.radius12),
        border: Border.all(
          color: ZirenTokens.systemWarning.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            LucideIcons.triangle_alert,
            size: 16,
            color: ZirenTokens.systemWarning,
          ),
          const SizedBox(width: ZirenTokens.space8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: ZirenTokens.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
