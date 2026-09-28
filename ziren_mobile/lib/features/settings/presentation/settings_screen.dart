import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../../core/config/accessibility_provider.dart';
import '../../../core/config/locale_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../../../shared/widgets/ziren_card.dart';
import '../../../shared/widgets/ziren_dialogs.dart';
import '../../../shared/widgets/ziren_toast.dart';
import '../../onboarding/domain/legal_documents.dart';
import '../../onboarding/presentation/legal_reader_screen.dart';
import '../domain/profile_provider.dart';
import 'about_ziren_dialog.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Phase 10.5 — Resident settings & profile screen.
///
/// A navigation hub, not a form. The actual profile fields (name, phone,
/// barangay, municipality, emergency contact) live one level deeper, behind
/// "Edit personal information" — see [_PersonalInfoEditorScreen] below. This
/// screen only ever shows three grouped-row sections:
///
///   1. Profile      — edit personal info, change password, language,
///                      notification preferences
///   2. App Settings  — dark mode, location services, offline maps
///   3. Support       — help & FAQ, about Ziren, log out
///
/// Reachable at both `/profile/settings` (nested under the Profile tab) and
/// the flat `/settings` — this widget makes no assumption about which parent
/// route got it here.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _barangayCtrl = TextEditingController();
  final _municipalityCtrl = TextEditingController();
  final _ecNameCtrl = TextEditingController();
  final _ecNumberCtrl = TextEditingController();

  String _language = 'Filipino';
  bool _pushEnabled = true;
  bool _initialised = false;

  // ── App Settings (Phase 10.5 restyle additions) ──────────────
  //
  // Location services is wired to the real OS permission via
  // permission_handler — the same package (and the same Permission.location
  // call) that SosProvider already uses to get a fix for an SOS report.
  bool _locationEnabled = true;

  /// What the app can actually render. Sourced from LocaleProvider rather
  /// than repeated here, so the picker cannot offer a language the app has no
  /// strings for — which is exactly what it used to do: all four options were
  /// saved to the backend and none of them changed a single word on screen.
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
    _nameCtrl.text = p.fullName;
    _phoneCtrl.text = p.phoneNumber ?? '';
    _barangayCtrl.text = p.barangay ?? '';
    _municipalityCtrl.text = p.municipalityAddress ?? '';
    _ecNameCtrl.text = p.emergencyContactName ?? '';
    _ecNumberCtrl.text = p.emergencyContactNumber ?? '';
    // Does the profile actually record a language this build can render?
    //
    // A profile saved before the picker was narrowed may still hold 'Bisaya'
    // or 'Waray'; those are not renderable yet. And an account created through
    // the new registration flow has no language on file at all.
    final stored = p.preferredLanguage;
    final hasUsablePreference = _languages.contains(stored);

    final locale = context.read<LocaleProvider>();

    // NULL means "nobody has recorded a preference", NOT "Filipino". Treating
    // the two as the same is what silently undid the language chosen during
    // onboarding: preferred_language is never written at registration, so
    // simply opening this screen resolved NULL to Filipino and pushed it into
    // LocaleProvider, overwriting English on the device and persisting it.
    // With no preference on file the picker shows what the app is actually
    // using, and nothing is pushed anywhere.
    final resolved = hasUsablePreference ? stored! : locale.languageName;

    setState(() {
      _language = resolved;
      _pushEnabled = p.pushNotificationsEnabled;
      _initialised = true;
    });

    // Only a real, renderable preference may override the device. The profile
    // is still the source of truth across devices — it just has to have
    // something to say first.
    if (hasUsablePreference) {
      locale.syncFromProfile(resolved);
    }
  }

  Future<void> _loadAppSettings() async {
    // Real permission check — mirrors the granted/denied state Android or
    // iOS actually holds, not a locally-invented flag.
    bool locationGranted = true;
    try {
      final status = await Permission.location.status;
      locationGranted = status.isGranted;
    } catch (_) {
      // Platform channel unavailable (e.g. desktop test runner) — leave the
      // default of "on" rather than showing a misleading "off".
    }

    if (!mounted) return;
    setState(() {
      _locationEnabled = locationGranted;
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _barangayCtrl.dispose();
    _municipalityCtrl.dispose();
    _ecNameCtrl.dispose();
    _ecNumberCtrl.dispose();
    super.dispose();
  }

  /// Persists the whole profile bundle, including whatever the "Edit
  /// personal information" sub-screen currently holds in the shared
  /// controllers. Used both for that screen's explicit Save button
  /// (validated, with a confirmation snackbar) and for the hub's own
  /// immediately-applied toggles like language and notifications (silent,
  /// unvalidated — name is already known-good because it came from a loaded
  /// profile).
  Future<bool> _persistProfile({bool validate = false, bool silent = false}) async {
    if (validate && !(_formKey.currentState?.validate() ?? false)) return false;
    final ok = await context.read<ProfileProvider>().saveProfile(
      fullName: _nameCtrl.text,
      phoneNumber: _phoneCtrl.text,
      barangay: _barangayCtrl.text,
      municipalityAddress: _municipalityCtrl.text,
      preferredLanguage: _language,
      pushNotificationsEnabled: _pushEnabled,
      emergencyContactName: _ecNameCtrl.text,
      emergencyContactNumber: _ecNumberCtrl.text,
    );
    if (!mounted) return ok;
    if (ok && !silent) {
      ZirenToast.success(
        ScaffoldMessenger.of(context),
        AppLocalizations.of(context).settingsProfileSaved,
      );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.settingsLocationDenied)),
        );
      }
      return;
    }

    // Neither Android nor iOS lets an app revoke its own permission grant —
    // only the system Settings app can do that. Rather than flip the switch
    // to a state the OS disagrees with, send the resident to where the
    // change actually happens, then re-read the real status.
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
      // Each language is a row you press, and the current one says so. A bare
      // radio circle beside a word is easy to read as decoration.
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
    // a separate Save reads as broken, and the resident cannot tell whether
    // it worked.
    if (!mounted) return;
    await context.read<LocaleProvider>().setLanguageName(choice);
    await _persistProfile(silent: true);
  }

  Future<void> _togglePush(bool value) async {
    setState(() => _pushEnabled = value);
    await _persistProfile(silent: true);
  }

  void _openPersonalInfoEditor() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => _PersonalInfoEditorScreen(
              formKey: _formKey,
              nameCtrl: _nameCtrl,
              phoneCtrl: _phoneCtrl,
              barangayCtrl: _barangayCtrl,
              municipalityCtrl: _municipalityCtrl,
              ecNameCtrl: _ecNameCtrl,
              ecNumberCtrl: _ecNumberCtrl,
              onSave: () => _persistProfile(validate: true),
            ),
      ),
    );
  }

  void _showHelpFaq() {
    final t = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: ZirenTokens.surfaceOverlay,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ZirenTokens.radius20),
        ),
      ),
      builder: (sheetContext) {
        final entries = <(String, String)>[
          (t.settingsFaqReportQ, t.settingsFaqReportA),
          (t.settingsFaqOfflineQ, t.settingsFaqOfflineA),
          (t.settingsFaqAgencyQ, t.settingsFaqAgencyA),
          (t.settingsFaqAccountQ, t.settingsFaqAccountA),
        ];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(ZirenTokens.space20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.settingsHelpFaq,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: ZirenTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: ZirenTokens.space16),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: entries.length,
                    separatorBuilder:
                        (_, __) =>
                            const SizedBox(height: ZirenTokens.space16),
                    itemBuilder: (_, i) {
                      final (q, a) = entries[i];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            q,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: ZirenTokens.textPrimary,
                            ),
                          ),
                          const SizedBox(height: ZirenTokens.space4),
                          Text(
                            a,
                            style: TextStyle(
                              fontSize: 13,
                              color: ZirenTokens.textSecondary,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
      onOpenPrivacy: () => _openLegalDoc(LegalDoc.privacy, t.settingsAboutPrivacy),
    );
  }


  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProfileProvider>();
    final t = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      appBar: AppBar(title: Text(t.settingsScreenTitle)),
      body:
          provider.isLoading
              ? const LoadingIndicator()
              : provider.errorMessage != null && !_initialised
              ? _buildErrorRetry(provider)
              : !_initialised
              ? const LoadingIndicator()
              : _buildHub(provider),
    );
  }

  Widget _buildErrorRetry(ProfileProvider provider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ZirenTokens.space32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.cloud_off,
              size: 48,
              color: ZirenTokens.textMuted,
            ),
            const SizedBox(height: ZirenTokens.space16),
            Text(
              provider.errorMessage ?? 'Could not load profile.',
              textAlign: TextAlign.center,
              style: TextStyle(color: ZirenTokens.textMuted),
            ),
            const SizedBox(height: ZirenTokens.space16),
            ElevatedButton.icon(
              icon: const Icon(LucideIcons.refresh_cw, size: 18),
              label: const Text('Retry'),
              onPressed: () async {
                provider.clearError();
                await provider.loadProfile();
                _populate();
              },
            ),

            // Reachable even here on purpose. The speech check needs nothing
            // but the microphone, and being unable to run it because the
            // backend is unreachable would make it useless in exactly the
            // situation where someone is trying to work out what is broken.
            const SizedBox(height: ZirenTokens.space24),
            TextButton.icon(
              icon: const Icon(LucideIcons.mic, size: 18),
              label: const Text('Speech check'),
              onPressed: () => context.push('/speech-diagnostic'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHub(ProfileProvider provider) {
    final t = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(ZirenTokens.space16),
      children: [
        if (provider.errorMessage != null) ...[
          _ErrorBanner(message: provider.errorMessage!),
          const SizedBox(height: ZirenTokens.space12),
        ],

        // ── Account ──────────────────────────────────────────
        ZirenSectionLabel(t.settingsSectionAccount),
        ZirenGroupedRows(
          children: [
            _SettingsRow(
              icon: LucideIcons.user,
              label: t.settingsEditPersonalInfo,
              onTap: _openPersonalInfoEditor,
            ),
            _SettingsRow(
              icon: LucideIcons.lock,
              label: t.settingsChangePassword,
              onTap: () => context.push('/forgot-password'),
            ),
          ],
        ),

        const SizedBox(height: ZirenTokens.space24),

        // ── Notifications ────────────────────────────────────
        ZirenSectionLabel(t.settingsSectionNotifications),
        ZirenGroupedRows(
          children: [
            _SettingsRow(
              icon: LucideIcons.bell,
              label: t.settingsNotificationPreferences,
              trailing: Switch(value: _pushEnabled, onChanged: _togglePush),
            ),
          ],
        ),

        const SizedBox(height: ZirenTokens.space24),

        // ── Location ─────────────────────────────────────────
        ZirenSectionLabel(t.settingsSectionLocation),
        ZirenGroupedRows(
          children: [
            _SettingsRow(
              icon: LucideIcons.map_pin,
              label: t.settingsLocationServices,
              trailing: Switch(
                value: _locationEnabled,
                onChanged: _toggleLocationServices,
              ),
            ),
          ],
        ),

        const SizedBox(height: ZirenTokens.space24),

        // ── Accessibility ─────────────────────────────────────
        ZirenSectionLabel(t.settingsSectionAccessibility),
        const SizedBox(height: ZirenTokens.space8),
        const _AppearanceCard(),
        const SizedBox(height: ZirenTokens.space12),
        const _TextSizeCard(),
        const SizedBox(height: ZirenTokens.space12),
        ZirenGroupedRows(
          children: [
            _SettingsRow(
              icon: LucideIcons.wind,
              label: t.settingsReduceMotion,
              trailing: Consumer<AccessibilityProvider>(
                builder:
                    (_, a11y, __) => Switch(
                      value: a11y.reduceMotion,
                      onChanged: a11y.setReduceMotion,
                    ),
              ),
            ),
            _SettingsRow(
              icon: LucideIcons.contrast,
              label: t.settingsHighContrast,
              trailing: Consumer<AccessibilityProvider>(
                builder:
                    (_, a11y, __) => Switch(
                      value: a11y.highContrast,
                      onChanged: a11y.setHighContrast,
                    ),
              ),
            ),
          ],
        ),

        const SizedBox(height: ZirenTokens.space24),

        // ── Language ─────────────────────────────────────────
        ZirenSectionLabel(t.settingsSectionLanguage),
        ZirenGroupedRows(
          children: [
            _SettingsRow(
              icon: LucideIcons.languages,
              label: t.preferredLanguage,
              value: _language,
              onTap: _pickLanguage,
            ),
          ],
        ),

        const SizedBox(height: ZirenTokens.space24),

        // ── Help & Support ───────────────────────────────────
        ZirenSectionLabel(t.settingsSectionHelpSupport),
        ZirenGroupedRows(
          children: [
            _SettingsRow(
              icon: LucideIcons.circle_question_mark,
              label: t.settingsHelpFaq,
              onTap: _showHelpFaq,
            ),
          ],
        ),

        const SizedBox(height: ZirenTokens.space24),

        // ── About ────────────────────────────────────────────
        ZirenSectionLabel(t.settingsSectionAbout),
        ZirenGroupedRows(
          children: [
            _SettingsRow(
              icon: LucideIcons.info,
              label: t.settingsAboutZiren,
              onTap: _showAboutZiren,
            ),
          ],
        ),

        const SizedBox(height: ZirenTokens.space32),
      ],
    );
  }
}

// ── Settings row ──────────────────────────────────────────────

/// One row inside a [ZirenGroupedRows] section: leading icon, label, and
/// either a trailing value preview + chevron (navigable row) or a supplied
/// trailing widget such as a [Switch] (inline-toggle row).
class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.label,
    this.value,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: ZirenTokens.minTouchTarget,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ZirenTokens.space16,
            vertical: ZirenTokens.space8,
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: ZirenTokens.textMuted),
              const SizedBox(width: ZirenTokens.space12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: ZirenTokens.textPrimary,
                  ),
                ),
              ),
              if (trailing != null)
                trailing!
              else ...[
                if (value != null) ...[
                  Text(
                    value!,
                    style: TextStyle(fontSize: 13, color: ZirenTokens.textMuted),
                  ),
                  const SizedBox(width: ZirenTokens.space4),
                ],
                Icon(
                  LucideIcons.chevron_right,
                  size: 20,
                  color: ZirenTokens.textMuted,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Error banner ──────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space12),
      decoration: BoxDecoration(
        color: ZirenTokens.systemErrorBg,
        borderRadius: BorderRadius.circular(ZirenTokens.radius8),
        border: Border.all(
          color: ZirenTokens.systemError.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.circle_alert,
            size: 16,
            color: ZirenTokens.systemError,
          ),
          const SizedBox(width: ZirenTokens.space8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, color: ZirenTokens.systemError),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Appearance card ──────────────────────────────────────────────

/// A 3-way segmented control (System / Light / Dark), not a single "Dark
/// mode" switch — a resident whose phone already follows sunrise/sunset
/// should be able to say so, rather than picking one of the other two and
/// fighting it twice a day.
class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final a11y = context.watch<AccessibilityProvider>();

    final options = <(ThemeMode, IconData, String)>[
      (ThemeMode.system, LucideIcons.smartphone, t.appearanceSystem),
      (ThemeMode.light, LucideIcons.sun, t.appearanceLight),
      (ThemeMode.dark, LucideIcons.moon, t.appearanceDark),
    ];

    return ZirenCard(
      padding: const EdgeInsets.all(ZirenTokens.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.palette,
                size: 18,
                color: ZirenTokens.textMuted,
              ),
              const SizedBox(width: ZirenTokens.space8),
              Flexible(child: Text(
                t.settingsAccessibilityAppearance,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: ZirenTokens.textPrimary,
                ),
              )),
            ],
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(ZirenTokens.radius8),
      child: AnimatedContainer(
        duration: ZirenTokens.motionQuick,
        padding: const EdgeInsets.symmetric(vertical: ZirenTokens.space10),
        decoration: BoxDecoration(
          color: selected ? ZirenTokens.brandOrange : Colors.transparent,
          borderRadius: BorderRadius.circular(ZirenTokens.radius8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? ZirenTokens.textInverse : ZirenTokens.textMuted,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color:
                    selected ? ZirenTokens.textInverse : ZirenTokens.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Text size card ───────────────────────────────────────────────

/// Four named steps plus a live preview sentence — the preview is an
/// ordinary Text with no manual size math, so it grows through exactly the
/// same ambient TextScaler every other screen picks up (see main.dart's
/// MaterialApp.builder). The "Aa" glyphs on the step buttons are the one
/// deliberate exception: they are a fixed size chart ("this is what Large
/// looks like"), so they opt out of that same ambient scaling — letting it
/// apply there would make all four buttons grow together and erase the very
/// size difference they exist to show.
class _TextSizeCard extends StatelessWidget {
  const _TextSizeCard();

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

    return ZirenCard(
      padding: const EdgeInsets.all(ZirenTokens.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.case_sensitive,
                size: 18,
                color: ZirenTokens.textMuted,
              ),
              const SizedBox(width: ZirenTokens.space8),
              Text(
                t.settingsAccessibilityTextSize,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: ZirenTokens.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                _label(t, a11y.textScaleStep),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: ZirenTokens.brandOrange,
                ),
              ),
            ],
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
          const SizedBox(height: ZirenTokens.space12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(ZirenTokens.space12),
            decoration: BoxDecoration(
              color: ZirenTokens.surfaceRaised,
              borderRadius: BorderRadius.circular(ZirenTokens.radius8),
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
      borderRadius: BorderRadius.circular(ZirenTokens.radius8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: ZirenTokens.space10),
        decoration: BoxDecoration(
          color:
              selected ? ZirenTokens.brandContainer : ZirenTokens.surfaceRaised,
          borderRadius: BorderRadius.circular(ZirenTokens.radius8),
          border: Border.all(
            color:
                selected ? ZirenTokens.brandOrange : ZirenTokens.surfaceBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        alignment: Alignment.center,
        // Fixed reference size — see the class doc comment above for why
        // this one Text deliberately ignores the ambient TextScaler.
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
                  selected ? ZirenTokens.brandOrange : ZirenTokens.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Personal info editor (pushed from "Edit personal information") ────

/// The original inline form, relocated one level deep behind a chevron so
/// the hub screen above can read as a navigation menu rather than a giant
/// form. Controllers and the form key are owned by [_SettingsScreenState]
/// and passed in, so name/phone/address/emergency-contact edits still save
/// through the exact same [ProfileProvider.saveProfile] call the hub's
/// quiet language/notification saves use.
class _PersonalInfoEditorScreen extends StatelessWidget {
  const _PersonalInfoEditorScreen({
    required this.formKey,
    required this.nameCtrl,
    required this.phoneCtrl,
    required this.barangayCtrl,
    required this.municipalityCtrl,
    required this.ecNameCtrl,
    required this.ecNumberCtrl,
    required this.onSave,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController nameCtrl;
  final TextEditingController phoneCtrl;
  final TextEditingController barangayCtrl;
  final TextEditingController municipalityCtrl;
  final TextEditingController ecNameCtrl;
  final TextEditingController ecNumberCtrl;
  final Future<bool> Function() onSave;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProfileProvider>();
    final t = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      appBar: AppBar(
        title: Text(t.settingsEditPersonalInfo),
        actions: [
          if (provider.isSaving)
            const Padding(
              padding: EdgeInsets.only(right: ZirenTokens.space16),
              child: LoadingIndicator(size: 20),
            )
          else
            TextButton(
              onPressed: onSave,
              child: const Text(
                'Save',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(ZirenTokens.space16),
          children: [
            // ── Section: Profile ──────────────────────────────
            _SectionHeader(label: t.settingsProfile, icon: LucideIcons.user),
            const SizedBox(height: ZirenTokens.space12),
            _field(
              controller: nameCtrl,
              label: t.fieldFullName,
              icon: LucideIcons.badge,
              validator:
                  (v) =>
                      (v == null || v.trim().isEmpty)
                          ? 'Name is required.'
                          : null,
            ),
            const SizedBox(height: ZirenTokens.space12),
            _field(
              controller: phoneCtrl,
              label: t.fieldMobileNumber,
              icon: LucideIcons.phone,
              keyboardType: TextInputType.phone,
              hint: t.hintMobileShort,
            ),

            const SizedBox(height: ZirenTokens.space24),

            // ── Section: Address ──────────────────────────────
            _SectionHeader(
              label: t.settingsAddress,
              icon: LucideIcons.map_pin,
            ),
            const SizedBox(height: ZirenTokens.space12),
            _field(
              controller: barangayCtrl,
              label: t.fieldBarangaySettings,
              icon: LucideIcons.house,
              hint: t.hintBarangayExample,
            ),
            const SizedBox(height: ZirenTokens.space12),
            _field(
              controller: municipalityCtrl,
              label: t.fieldMunicipalitySettings,
              icon: LucideIcons.map,
              hint: t.hintMunicipalityExample,
            ),

            const SizedBox(height: ZirenTokens.space24),

            // ── Section: Emergency Contact ────────────────────
            _SectionHeader(
              label: t.settingsEmergencyContact,
              icon: LucideIcons.siren,
            ),
            const SizedBox(height: ZirenTokens.space4),
            Text(
              t.emergencyWhoShort,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: ZirenTokens.textSecondary,
              ),
            ),
            const SizedBox(height: ZirenTokens.space12),
            _field(
              controller: ecNameCtrl,
              label: t.fieldContactName,
              icon: LucideIcons.user,
              hint: t.hintContactName,
            ),
            const SizedBox(height: ZirenTokens.space12),
            _field(
              controller: ecNumberCtrl,
              label: t.fieldContactNumber,
              icon: LucideIcons.phone,
              hint: t.hintMobileShort,
              keyboardType: TextInputType.phone,
            ),

            const SizedBox(height: ZirenTokens.space32),

            ElevatedButton.icon(
              icon: const Icon(LucideIcons.save, size: 18),
              label: const Text('Save Profile'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: provider.isSaving ? null : onSave,
            ),

            const SizedBox(height: ZirenTokens.space32),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      style: TextStyle(fontSize: 15, color: ZirenTokens.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 18, color: ZirenTokens.textMuted),
        filled: true,
        fillColor: ZirenTokens.surfaceCard,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

// ── Section header (editor sub-screen only) ─────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: ZirenTokens.brandOrange),
        const SizedBox(width: ZirenTokens.space8),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: ZirenTokens.brandOrange,
          ),
        ),
        const SizedBox(width: ZirenTokens.space8),
        const Expanded(child: Divider()),
      ],
    );
  }
}
