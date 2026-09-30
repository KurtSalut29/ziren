import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../../core/config/accessibility_provider.dart';
import '../../../core/config/locale_provider.dart';
import '../../../core/utils/validators.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../../../shared/widgets/profile_kit.dart';
import '../../../shared/widgets/ziren_dialogs.dart';
import '../../../shared/widgets/ziren_text_field.dart';
import '../../../shared/widgets/ziren_toast.dart';
import '../../auth/domain/auth_provider.dart';
import '../../onboarding/domain/legal_documents.dart';
import '../../onboarding/presentation/legal_reader_screen.dart';
import '../domain/profile_model.dart';
import '../domain/profile_provider.dart';
import 'about_ziren_dialog.dart';
import 'change_password_screen.dart';
import 'help_faq_screen.dart';
import 'widgets/settings_form_kit.dart';

/// Settings & Profile - a navigation hub, not a form.
///
/// An account card at the top (who is signed in; opens the editor), then
/// titled groups in the Profile screens' card language:
///
///   Account        edit personal information, change password
///   Notifications  push on/off
///   Location       the real OS permission
///   Accessibility  appearance, text size, reduce motion, high contrast
///   Language
///   Help & support how to use Ziren, Help & FAQ, hotlines, voice check
///   About          about Ziren, terms of use, data privacy notice
///
/// Reachable at both `/profile/settings` (nested under the Profile tab) and
/// the flat `/settings` (the responder's) - this widget makes no assumption
/// about which parent route got it here.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _language = 'Filipino';
  bool _pushEnabled = true;
  bool _initialised = false;

  /// Wired to the real OS permission via permission_handler - the same
  /// package (and the same Permission.location call) SosProvider uses.
  bool _locationEnabled = true;

  /// What the app can actually render. Sourced from LocaleProvider rather
  /// than repeated here, so the picker cannot offer a language the app has no
  /// strings for.
  static const _languages = LocaleProvider.supportedLanguageNames;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<ProfileProvider>();
      // Only fetch if profile isn't loaded yet and nothing is in-flight
      if (provider.profile == null && !provider.isLoading) {
        await provider.loadProfile();
      }
      _populate();
    });
    _loadAppSettings();
  }

  void _populate() {
    final p = context.read<ProfileProvider>().profile;
    if (p == null || !mounted) return;
    // The picker shows the language the app is ACTUALLY using — the one this
    // person chose on this phone (at onboarding, or here) — never the one
    // written on the profile.
    //
    // It used to prefer the profile's `preferred_language` and push it into
    // LocaleProvider. That profile value is only written from this screen, so
    // an account that had once picked English here kept "English" on file
    // forever: a resident who then chose Filipino on the first screen, signed
    // in, and opened Settings saw "English" — and simply opening Settings
    // switched the whole app to English, undoing the choice they had just
    // made. Every phone asks for the language before sign-in, so the phone's
    // choice is always the newest explicit one; the profile only records it.
    final locale = context.read<LocaleProvider>();
    final current = locale.languageName;

    setState(() {
      _language = current;
      _pushEnabled = p.pushNotificationsEnabled;
      _initialised = true;
    });

    // Bring the profile into line when it disagrees (or has nothing), so
    // whatever reads it server-side speaks the same language as the phone.
    // Best effort and silent: the app already shows the right language, and
    // a failed write only means the profile lags until the next save.
    if (p.preferredLanguage != current) {
      _recordLanguageOnProfile();
    }
  }

  Future<void> _recordLanguageOnProfile() async {
    final provider = context.read<ProfileProvider>();
    final p = provider.profile;
    if (p == null) return;
    await provider.saveProfile(
      fullName: p.fullName,
      phoneNumber: p.phoneNumber,
      barangay: p.barangay,
      municipalityAddress: p.municipalityAddress,
      preferredLanguage: _language,
      pushNotificationsEnabled: p.pushNotificationsEnabled,
      emergencyContactName: p.emergencyContactName,
      emergencyContactNumber: p.emergencyContactNumber,
    );
  }

  Future<void> _loadAppSettings() async {
    // Real permission check - mirrors the granted/denied state Android or
    // iOS actually holds, not a locally-invented flag.
    bool locationGranted = true;
    try {
      final status = await Permission.location.status;
      locationGranted = status.isGranted;
    } catch (_) {
      // Platform channel unavailable (e.g. desktop test runner) - leave the
      // default of "on" rather than showing a misleading "off".
    }

    if (!mounted) return;
    setState(() => _locationEnabled = locationGranted);
  }

  /// Saves the hub's own settings (language, notifications) on top of the
  /// profile AS IT IS SAVED - never on top of half-typed edits.
  ///
  /// The editor used to share its text controllers with this screen, so
  /// editing a name, backing out without saving, and then flipping the
  /// notifications switch quietly saved the abandoned edit.
  Future<bool> _saveHubSettings() async {
    final provider = context.read<ProfileProvider>();
    final p = provider.profile;
    if (p == null) return false;
    final ok = await provider.saveProfile(
      fullName: p.fullName,
      phoneNumber: p.phoneNumber,
      barangay: p.barangay,
      municipalityAddress: p.municipalityAddress,
      preferredLanguage: _language,
      pushNotificationsEnabled: _pushEnabled,
      emergencyContactName: p.emergencyContactName,
      emergencyContactNumber: p.emergencyContactNumber,
    );
    if (!ok && mounted && provider.errorMessage != null) {
      ZirenToast.error(ScaffoldMessenger.of(context), provider.errorMessage!);
    }
    return ok;
  }

  Future<void> _toggleLocationServices(bool value) async {
    final t = AppLocalizations.of(context);
    if (value) {
      final result = await Permission.location.request();
      if (!mounted) return;
      setState(() => _locationEnabled = result.isGranted);
      if (!result.isGranted) {
        ZirenToast.notice(ScaffoldMessenger.of(context), t.settingsLocationDenied);
      }
      return;
    }

    // Neither Android nor iOS lets an app revoke its own permission grant -
    // only the system Settings app can do that. Rather than flip the switch
    // to a state the OS disagrees with, send the person to where the change
    // actually happens, then re-read the real status.
    final goToSettings = await showZirenDialog<bool>(
      context,
      icon: LucideIcons.map_pin_off,
      tone: ZirenTone.warning,
      title: t.settingsLocationOffTitle,
      message: t.settingsLocationOffBody,
      actions: [
        ZirenDialogAction(
          label: t.settingsOpenSystemSettings,
          value: true,
          kind: ZirenActionKind.primary,
          icon: LucideIcons.settings,
        ),
        ZirenDialogAction(label: t.settingsCancel, value: false),
      ],
    );
    if (goToSettings == true) {
      await openAppSettings();
    }
    final status = await Permission.location.status;
    if (!mounted) return;
    setState(() => _locationEnabled = status.isGranted);
  }

  Future<void> _pickLanguage() async {
    final t = AppLocalizations.of(context);
    final choice = await showZirenDialog<String>(
      context,
      icon: LucideIcons.languages,
      tone: ZirenTone.info,
      title: t.preferredLanguage,
      // Each language is a row you press, and the current one says so.
      body: Builder(
        builder:
            (dialogContext) => Column(
              children: [
                for (final l in _languages) ...[
                  ZirenOptionTile(
                    icon: LucideIcons.languages,
                    label: l,
                    selected: l == _language,
                    onTap: () => Navigator.of(dialogContext).pop(l),
                  ),
                  if (l != _languages.last)
                    const SizedBox(height: ZirenTokens.space10),
                ],
              ],
            ),
      ),
      actions: [ZirenDialogAction<String>(label: t.settingsCancel, value: '')],
    );
    if (choice == null || choice.isEmpty || choice == _language) return;
    setState(() => _language = choice);
    // Applied straight away. A language picker that only takes effect after
    // a separate Save reads as broken.
    if (!mounted) return;
    await context.read<LocaleProvider>().setLanguageName(choice);
    await _saveHubSettings();
  }

  Future<void> _togglePush(bool value) async {
    setState(() => _pushEnabled = value);
    final ok = await _saveHubSettings();
    // A switch that stays on after the save failed says something untrue.
    if (!ok && mounted) setState(() => _pushEnabled = !value);
  }

  void _openPersonalInfoEditor() {
    final p = context.read<ProfileProvider>().profile;
    if (p == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => PersonalInfoEditorScreen(
              profile: p,
              preferredLanguage: _language,
              pushNotificationsEnabled: _pushEnabled,
            ),
      ),
    );
  }

  void _openChangePassword() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
    );
  }

  bool get _isResponder =>
      context.read<AuthProvider>().userRole == 'responder';

  void _openHelpFaq() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HelpFaqScreen(forResponder: _isResponder),
      ),
    );
  }

  Future<void> _openLegalDoc(LegalDoc doc, String title) async {
    final languageCode = context.read<LocaleProvider>().locale.languageCode;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder:
            (_) => LegalReaderScreen(
              doc: doc,
              languageCode: languageCode,
              title: title,
            ),
      ),
    );
  }

  void _showAboutZiren() {
    final t = AppLocalizations.of(context);
    showAboutZirenDialog(
      context,
      onOpenTerms: () => _openLegalDoc(LegalDoc.terms, t.settingsAboutTerms),
      onOpenPrivacy:
          () => _openLegalDoc(LegalDoc.privacy, t.settingsAboutPrivacy),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProfileProvider>();
    final t = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      appBar: AppBar(
        backgroundColor: ZirenTokens.surfaceBase,
        title: Text(t.settingsScreenTitle),
      ),
      body:
          provider.isLoading && !_initialised
              ? const LoadingIndicator()
              : provider.errorMessage != null && !_initialised
              ? _buildErrorRetry(provider)
              : !_initialised
              ? const LoadingIndicator()
              : _buildHub(provider),
    );
  }

  Widget _buildErrorRetry(ProfileProvider provider) {
    return ListView(
      padding: const EdgeInsets.all(ZirenTokens.space16),
      children: [
        ProfileLoadError(
          message: provider.errorMessage ?? 'Could not load profile.',
          onRetry: () async {
            provider.clearError();
            await provider.loadProfile(force: true);
            _populate();
          },
        ),
      ],
    );
  }

  Widget _buildHub(ProfileProvider provider) {
    final t = AppLocalizations.of(context);
    final auth = context.watch<AuthProvider>();
    final p = provider.profile;
    final email = p?.email ?? auth.user?.email ?? '';
    final name =
        p?.fullName.isNotEmpty == true ? p!.fullName : email.split('@').first;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        ZirenTokens.space16,
        ZirenTokens.space4,
        ZirenTokens.space16,
        ZirenTokens.space32,
      ),
      children: [
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

        _AccountCard(
          name: name,
          email: email,
          avatarUrl: p?.avatarUrl,
          hint: t.settingsAccountCardHint,
          onTap: _openPersonalInfoEditor,
        ),
        const SizedBox(height: ZirenTokens.space24),

        // ── Account ──────────────────────────────────────────
        ProfileGroup(
          title: t.settingsSectionAccount,
          children: [
            ProfileTile(
              icon: LucideIcons.user_pen,
              label: t.settingsEditPersonalInfo,
              onTap: _openPersonalInfoEditor,
            ),
            ProfileTile(
              icon: LucideIcons.lock_keyhole,
              label: t.settingsChangePassword,
              onTap: _openChangePassword,
            ),
          ],
        ),
        const SizedBox(height: ZirenTokens.space24),

        // ── Notifications + location ─────────────────────────
        ProfileGroup(
          title: t.settingsSectionNotifications,
          children: [
            ProfileTile(
              icon: LucideIcons.bell,
              label: t.settingsNotificationPreferences,
              subtitle: t.settingsNotifDesc,
              trailing: Switch(
                value: _pushEnabled,
                onChanged: provider.isSaving ? null : _togglePush,
              ),
            ),
            ProfileTile(
              icon: LucideIcons.map_pin,
              label: t.settingsLocationServices,
              subtitle: t.settingsLocationDesc,
              trailing: Switch(
                value: _locationEnabled,
                onChanged: _toggleLocationServices,
              ),
            ),
          ],
        ),
        const SizedBox(height: ZirenTokens.space24),

        // ── Accessibility ────────────────────────────────────
        _SectionTitle(t.settingsSectionAccessibility),
        const _AccessibilityCard(),
        const SizedBox(height: ZirenTokens.space24),

        // ── Language ─────────────────────────────────────────
        ProfileGroup(
          title: t.settingsSectionLanguage,
          children: [
            ProfileTile(
              icon: LucideIcons.languages,
              label: t.preferredLanguage,
              value: _language,
              onTap: _pickLanguage,
            ),
          ],
        ),
        const SizedBox(height: ZirenTokens.space24),

        // ── Help & support ───────────────────────────────────
        ProfileGroup(
          title: t.settingsSectionHelpSupport,
          children: [
            ProfileTile(
              icon: LucideIcons.life_buoy,
              tone: ZirenTokens.systemInfo,
              label: t.helpTitle,
              onTap:
                  () => context.push(
                    _isResponder ? '/help?role=responder' : '/help',
                  ),
            ),
            ProfileTile(
              icon: LucideIcons.circle_question_mark,
              label: t.settingsHelpFaq,
              onTap: _openHelpFaq,
            ),
            ProfileTile(
              icon: LucideIcons.phone_call,
              tone: ZirenTokens.systemSuccess,
              label: t.hotlinesTitle,
              onTap: () => context.push('/hotlines'),
            ),
          ],
        ),
        const SizedBox(height: ZirenTokens.space24),

        // ── About ────────────────────────────────────────────
        ProfileGroup(
          title: t.settingsSectionAbout,
          children: [
            ProfileTile(
              icon: LucideIcons.info,
              label: t.settingsAboutZiren,
              onTap: _showAboutZiren,
            ),
            ProfileTile(
              icon: LucideIcons.file_text,
              label: t.settingsAboutTerms,
              onTap: () => _openLegalDoc(LegalDoc.terms, t.settingsAboutTerms),
            ),
            ProfileTile(
              icon: LucideIcons.shield_check,
              label: t.settingsAboutPrivacy,
              onTap:
                  () =>
                      _openLegalDoc(LegalDoc.privacy, t.settingsAboutPrivacy),
            ),
          ],
        ),
        const SizedBox(height: ZirenTokens.space20),
        Center(
          child: Text(
            'Ziren · ${t.settingsAboutVersion(kAppVersionLabel)}',
            style: TextStyle(fontSize: 12, color: ZirenTokens.textMuted),
          ),
        ),
      ],
    );
  }
}

// ── Account card ─────────────────────────────────────────────────

/// Who is signed in, at the top of Settings. Pressing it opens the editor -
/// the most common reason anyone opens Settings at all.
class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.name,
    required this.email,
    required this.avatarUrl,
    required this.hint,
    required this.onTap,
  });

  final String name;
  final String email;
  final String? avatarUrl;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: profileCardDecoration(radius: ZirenTokens.radius20),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(ZirenTokens.space16),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  clipBehavior: Clip.antiAlias,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: ZirenTokens.brandGradient,
                  ),
                  alignment: Alignment.center,
                  child:
                      url != null
                          ? Image.network(
                            url,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _Initials(name),
                          )
                          : _Initials(name),
                ),
                const SizedBox(width: ZirenTokens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          color: ZirenTokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: ZirenTokens.textMuted,
                        ),
                      ),
                      const SizedBox(height: ZirenTokens.space4),
                      Text(
                        hint,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: ZirenTokens.brandOrange,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  LucideIcons.chevron_right,
                  size: 20,
                  color: ZirenTokens.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Initials extends StatelessWidget {
  const _Initials(this.name);

  final String name;

  @override
  Widget build(BuildContext context) => Text(
    initialsOf(name),
    style: const TextStyle(
      fontSize: 19,
      fontWeight: FontWeight.w800,
      color: Colors.white,
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(
      left: ZirenTokens.space4,
      bottom: ZirenTokens.space8,
    ),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.0,
        color: ZirenTokens.textSecondary,
      ),
    ),
  );
}

// ── Accessibility card ───────────────────────────────────────────

/// Appearance, text size and the two switches in one card, so everything
/// about how the app LOOKS sits together.
class _AccessibilityCard extends StatelessWidget {
  const _AccessibilityCard();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final a11y = context.watch<AccessibilityProvider>();
    Widget rule() => Divider(
      height: 1,
      thickness: 1,
      indent: ZirenTokens.space16,
      endIndent: ZirenTokens.space16,
      color: ZirenTokens.surfaceBorder.withValues(alpha: 0.7),
    );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: profileCardDecoration(),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _AppearanceBlock(),
            rule(),
            const _TextSizeBlock(),
            rule(),
            ProfileTile(
              icon: LucideIcons.wind,
              label: t.settingsReduceMotion,
              subtitle: t.settingsReduceMotionDesc,
              trailing: Switch(
                value: a11y.reduceMotion,
                onChanged: a11y.setReduceMotion,
              ),
            ),
            Divider(
              height: 1,
              thickness: 1,
              indent: 62,
              color: ZirenTokens.surfaceBorder.withValues(alpha: 0.7),
            ),
            ProfileTile(
              icon: LucideIcons.contrast,
              label: t.settingsHighContrast,
              subtitle: t.settingsHighContrastDesc,
              trailing: Switch(
                value: a11y.highContrast,
                onChanged: a11y.setHighContrast,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlockHeader extends StatelessWidget {
  const _BlockHeader({required this.icon, required this.label, this.trailing});

  final IconData icon;
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: ZirenTokens.surfaceRaised,
            borderRadius: BorderRadius.circular(11),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 18, color: ZirenTokens.textSecondary),
        ),
        const SizedBox(width: ZirenTokens.space12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: ZirenTokens.textPrimary,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// A 3-way segmented control (System / Light / Dark), not a single "Dark
/// mode" switch - a resident whose phone already follows sunrise/sunset
/// should be able to say so, rather than picking one of the other two and
/// fighting it twice a day.
class _AppearanceBlock extends StatelessWidget {
  const _AppearanceBlock();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final a11y = context.watch<AccessibilityProvider>();

    final options = <(ThemeMode, IconData, String)>[
      (ThemeMode.system, LucideIcons.smartphone, t.appearanceSystem),
      (ThemeMode.light, LucideIcons.sun, t.appearanceLight),
      (ThemeMode.dark, LucideIcons.moon, t.appearanceDark),
    ];

    return Padding(
      padding: const EdgeInsets.all(ZirenTokens.space12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BlockHeader(
            icon: LucideIcons.palette,
            label: t.settingsAccessibilityAppearance,
          ),
          const SizedBox(height: ZirenTokens.space12),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: ZirenTokens.surfaceRaised,
              borderRadius: BorderRadius.circular(ZirenTokens.radius12),
            ),
            child: Row(
              children: [
                for (final option in options)
                  Expanded(
                    child: _AppearanceSegment(
                      selected: a11y.themeMode == option.$1,
                      icon: option.$2,
                      label: option.$3,
                      onTap: () => a11y.setThemeMode(option.$1),
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

class _AppearanceSegment extends StatelessWidget {
  const _AppearanceSegment({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZirenTokens.radius8),
        child: AnimatedContainer(
          duration: ZirenTokens.motionQuick,
          padding: const EdgeInsets.symmetric(vertical: ZirenTokens.space10),
          decoration: BoxDecoration(
            color: selected ? ZirenTokens.surfaceCard : Colors.transparent,
            borderRadius: BorderRadius.circular(ZirenTokens.radius8),
            border:
                selected
                    ? Border.all(
                      color: ZirenTokens.brandOrange.withValues(alpha: 0.6),
                      width: 1.4,
                    )
                    : null,
            boxShadow: selected ? ZirenTokens.shadowSm : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color:
                    selected ? ZirenTokens.brandOrange : ZirenTokens.textMuted,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color:
                      selected
                          ? ZirenTokens.textPrimary
                          : ZirenTokens.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Four named steps plus a live preview sentence - the preview is an
/// ordinary Text with no manual size math, so it grows through exactly the
/// same ambient TextScaler every other screen picks up (see main.dart's
/// MaterialApp.builder). The "Aa" glyphs on the step buttons are the one
/// deliberate exception: they are a fixed size chart ("this is what Large
/// looks like"), so they opt out of that same ambient scaling.
class _TextSizeBlock extends StatelessWidget {
  const _TextSizeBlock();

  String _label(AppLocalizations t, TextScaleStep step) => switch (step) {
    TextScaleStep.small => t.textSizeSmall,
    TextScaleStep.normal => t.textSizeDefault,
    TextScaleStep.large => t.textSizeLarge,
    TextScaleStep.extraLarge => t.textSizeExtraLarge,
  };

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final a11y = context.watch<AccessibilityProvider>();

    return Padding(
      padding: const EdgeInsets.all(ZirenTokens.space12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BlockHeader(
            icon: LucideIcons.case_sensitive,
            label: t.settingsAccessibilityTextSize,
            trailing: Text(
              _label(t, a11y.textScaleStep),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: ZirenTokens.brandOrange,
              ),
            ),
          ),
          const SizedBox(height: ZirenTokens.space12),
          Row(
            children: [
              for (final step in TextScaleStep.values)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: _TextSizeButton(
                      step: step,
                      selected: a11y.textScaleStep == step,
                      onTap: () => a11y.setTextScaleStep(step),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: ZirenTokens.space10),
          Container(
            padding: const EdgeInsets.all(ZirenTokens.space12),
            decoration: BoxDecoration(
              color: ZirenTokens.surfaceRaised,
              borderRadius: BorderRadius.circular(ZirenTokens.radius12),
            ),
            child: Text(
              t.textSizePreview,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: ZirenTokens.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TextSizeButton extends StatelessWidget {
  const _TextSizeButton({
    required this.step,
    required this.selected,
    required this.onTap,
  });

  final TextScaleStep step;
  final bool selected;
  final VoidCallback onTap;

  static const _glyphSize = {
    TextScaleStep.small: 13.0,
    TextScaleStep.normal: 16.0,
    TextScaleStep.large: 19.0,
    TextScaleStep.extraLarge: 22.0,
  };

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(ZirenTokens.radius12),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color:
              selected ? ZirenTokens.brandContainer : ZirenTokens.surfaceRaised,
          borderRadius: BorderRadius.circular(ZirenTokens.radius12),
          border: Border.all(
            color:
                selected ? ZirenTokens.brandOrange : ZirenTokens.surfaceBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        alignment: Alignment.center,
        // Fixed reference size - see the class doc comment above.
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.noScaling),
          child: Text(
            'Aa',
            style: TextStyle(
              fontSize: _glyphSize[step],
              fontWeight: FontWeight.w800,
              color:
                  selected
                      ? ZirenTokens.brandOrange
                      : ZirenTokens.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Personal info editor ─────────────────────────────────────────

/// "Edit personal information": name and phone, address, emergency contact.
///
/// Owns its own controllers, filled from the saved profile. It used to borrow
/// the hub's, which is how an abandoned edit got saved by the next switch
/// flipped on the hub. Leaving with unsaved changes asks first; a successful
/// save returns to Settings.
///
/// The Save button used to sit in the app bar as white text on the light app
/// bar - there, but invisible. It is now the pinned bar at the bottom.
class PersonalInfoEditorScreen extends StatefulWidget {
  const PersonalInfoEditorScreen({
    super.key,
    required this.profile,
    required this.preferredLanguage,
    required this.pushNotificationsEnabled,
    this.onSave,
  });

  final ProfileModel profile;
  final String preferredLanguage;
  final bool pushNotificationsEnabled;

  /// Injected by tests; defaults to [ProfileProvider.saveProfile]. Returns
  /// whether the save worked.
  final Future<bool> Function(Map<String, String> fields)? onSave;

  @override
  State<PersonalInfoEditorScreen> createState() =>
      _PersonalInfoEditorScreenState();
}

class _PersonalInfoEditorScreenState extends State<PersonalInfoEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.profile.fullName);
  late final _phone = TextEditingController(
    text: widget.profile.phoneNumber ?? '',
  );
  late final _barangay = TextEditingController(
    text: widget.profile.barangay ?? '',
  );
  late final _municipality = TextEditingController(
    text: widget.profile.municipalityAddress ?? '',
  );
  late final _ecName = TextEditingController(
    text: widget.profile.emergencyContactName ?? '',
  );
  late final _ecNumber = TextEditingController(
    text: widget.profile.emergencyContactNumber ?? '',
  );
  late final Map<TextEditingController, String> _initial = {
    for (final c in [_name, _phone, _barangay, _municipality, _ecName, _ecNumber])
      c: c.text,
  };
  bool _saving = false;

  /// Whether anything differs from what was loaded - held in state (not only
  /// computed) because PopScope reads it at build time: typing does not
  /// rebuild the screen, so a computed-only value left "leave without
  /// asking" in force after the first keystroke.
  bool _dirty = false;

  bool get _hasEdits => _initial.entries.any((e) => e.key.text != e.value);

  void _onEdited() {
    final now = _hasEdits;
    if (now != _dirty) setState(() => _dirty = now);
  }

  @override
  void initState() {
    super.initState();
    for (final c in _initial.keys) {
      c.addListener(_onEdited);
    }
  }

  @override
  void dispose() {
    for (final c in _initial.keys) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final fields = {
      'full_name': _name.text,
      'phone_number': _phone.text,
      'barangay': _barangay.text,
      'municipality_address': _municipality.text,
      'emergency_contact_name': _ecName.text,
      'emergency_contact_number': _ecNumber.text,
    };
    setState(() => _saving = true);
    final bool ok;
    if (widget.onSave != null) {
      ok = await widget.onSave!(fields);
    } else {
      final provider = context.read<ProfileProvider>();
      ok = await provider.saveProfile(
        fullName: _name.text,
        phoneNumber: _phone.text,
        barangay: _barangay.text,
        municipalityAddress: _municipality.text,
        preferredLanguage: widget.preferredLanguage,
        pushNotificationsEnabled: widget.pushNotificationsEnabled,
        emergencyContactName: _ecName.text,
        emergencyContactNumber: _ecNumber.text,
      );
      if (!ok && mounted && provider.errorMessage != null) {
        ZirenToast.error(messenger, provider.errorMessage!);
      }
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      for (final c in _initial.keys) {
        _initial[c] = c.text;
      }
      _dirty = false;
      ZirenToast.success(messenger, t.settingsProfileSaved);
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _confirmLeave() async {
    final t = AppLocalizations.of(context);
    final discard = await showZirenDialog<bool>(
      context,
      icon: LucideIcons.pencil_off,
      tone: ZirenTone.warning,
      title: t.settingsDiscardTitle,
      message: t.settingsDiscardBody,
      horizontalActions: true,
      actions: [
        ZirenDialogAction(label: t.settingsKeepEditing, value: false),
        ZirenDialogAction(
          label: t.settingsDiscard,
          value: true,
          kind: ZirenActionKind.danger,
        ),
      ],
    );
    if (discard == true && mounted) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        backgroundColor: ZirenTokens.surfaceBase,
        appBar: AppBar(
          backgroundColor: ZirenTokens.surfaceBase,
          title: Text(t.settingsEditPersonalInfo),
        ),
        bottomNavigationBar: SettingsSaveBar(
          label: t.settingsSaveChanges,
          icon: LucideIcons.check,
          busy: _saving,
          onPressed: _save,
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              ZirenTokens.space16,
              ZirenTokens.space4,
              ZirenTokens.space16,
              ZirenTokens.space24,
            ),
            children: [
              Padding(
                padding: const EdgeInsets.only(
                  left: ZirenTokens.space4,
                  bottom: ZirenTokens.space16,
                ),
                child: Text(
                  t.settingsEditorIntro,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.4,
                    color: ZirenTokens.textSecondary,
                  ),
                ),
              ),
              SettingsFormSection(
                title: t.settingsProfile,
                children: [
                  SettingsField(
                    label: t.fieldFullName,
                    child: ZirenTextField(
                      key: const Key('edit-name'),
                      label: '',
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      prefixIcon: const Icon(LucideIcons.user),
                      validator:
                          (v) =>
                              (v == null || v.trim().isEmpty)
                                  ? t.respProfileNameRequired
                                  : null,
                    ),
                  ),
                  SettingsField(
                    label: t.fieldMobileNumber,
                    child: ZirenTextField(
                      key: const Key('edit-phone'),
                      label: '',
                      hint: t.hintMobileShort,
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      prefixIcon: const Icon(LucideIcons.phone),
                      // Optional here, but if given it has to be dialable -
                      // it is the number a station calls back.
                      validator:
                          (v) =>
                              (v ?? '').trim().isEmpty
                                  ? null
                                  : Validators.phoneNumber(v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: ZirenTokens.space24),
              SettingsFormSection(
                title: t.settingsAddress,
                children: [
                  SettingsField(
                    label: t.fieldBarangaySettings,
                    child: ZirenTextField(
                      label: '',
                      hint: t.hintBarangayExample,
                      controller: _barangay,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      prefixIcon: const Icon(LucideIcons.house),
                    ),
                  ),
                  SettingsField(
                    label: t.fieldMunicipalitySettings,
                    child: ZirenTextField(
                      label: '',
                      hint: t.hintMunicipalityExample,
                      controller: _municipality,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      prefixIcon: const Icon(LucideIcons.map),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: ZirenTokens.space24),
              SettingsFormSection(
                title: t.settingsEmergencyContact,
                caption: t.emergencyWhoShort,
                children: [
                  SettingsField(
                    label: t.fieldContactName,
                    child: ZirenTextField(
                      key: const Key('edit-ec-name'),
                      label: '',
                      hint: t.hintContactName,
                      controller: _ecName,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      prefixIcon: const Icon(LucideIcons.contact),
                      validator:
                          (v) =>
                              ((v ?? '').trim().isEmpty &&
                                      _ecNumber.text.trim().isNotEmpty)
                                  ? t.regEmergencyNeedsName
                                  : null,
                    ),
                  ),
                  SettingsField(
                    label: t.fieldContactNumber,
                    child: ZirenTextField(
                      key: const Key('edit-ec-number'),
                      label: '',
                      hint: t.hintMobileShort,
                      controller: _ecNumber,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _save(),
                      prefixIcon: const Icon(LucideIcons.phone),
                      validator: (v) {
                        final number = (v ?? '').trim();
                        if (number.isEmpty) {
                          return _ecName.text.trim().isEmpty
                              ? null
                              : t.regEmergencyNeedsNumber;
                        }
                        final invalid = Validators.phoneNumber(number);
                        if (invalid != null) return invalid;
                        // The commonest mix-up: typing their OWN number here.
                        if (Validators.sameMobile(number, _phone.text)) {
                          return t.regEmergencySameAsYours;
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
