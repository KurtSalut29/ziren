import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/config/locale_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/ziren_button.dart';
import '../../auth/domain/auth_provider.dart';
import '../data/onboarding_repository.dart';
import '../domain/legal_documents.dart';
import 'legal_reader_screen.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'widgets/onboarding_kit.dart';

/// Data Privacy Notice and Terms of Use, with a separate agreement for each.
///
/// Two agreements, not one
/// -----------------------
/// Bundling them into a single "I agree to the Terms and Privacy Policy" tick
/// is the common pattern and it is the wrong one here. They are different
/// agreements: the terms govern how the service may be used, the privacy
/// notice is consent to process personal data under RA 10173. A single tick
/// cannot evidence the second, and the second is the one a regulator asks
/// about.
///
/// Each agreement stays disabled until its document has actually been opened
/// and scrolled through. The plain-language summary above them is what a
/// hurried person will really read, so it carries the four things that
/// genuinely change someone's decision — including the one no product wants
/// to lead with, that this app is not a replacement for calling 911.
///
/// Each document and its agreement share one card: open it, read it, agree —
/// in the order the card is read, with its state (to read / read / agreed)
/// written on it.
class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key});

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  final _repo = OnboardingRepository();

  bool _privacyRead = false;
  bool _termsRead = false;
  bool _privacyAgreed = false;
  bool _termsAgreed = false;
  bool _busy = false;

  bool get _canContinue => _privacyAgreed && _termsAgreed;

  Future<void> _open(LegalDoc doc, String title) async {
    final languageCode = context.read<LocaleProvider>().locale.languageCode;
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder:
            (_) => LegalReaderScreen(
              doc: doc,
              languageCode: languageCode,
              title: title,
            ),
      ),
    );
    if (!mounted) return;
    setState(() {
      if (doc == LegalDoc.privacy) {
        _privacyRead = true;
        // Reaching the end of the document and pressing its accept button
        // ticks the box directly — making them tap twice for the same
        // decision is friction with no meaning behind it.
        if (result == true) _privacyAgreed = true;
      } else {
        _termsRead = true;
        if (result == true) _termsAgreed = true;
      }
    });
  }

  Future<void> _continue() async {
    setState(() => _busy = true);

    final locale = context.read<LocaleProvider>().locale.languageCode;
    final auth = context.read<AuthProvider>();

    await _repo.markDeviceOnboarded();

    // Authenticated here means the shared-handset case: someone signed in on
    // a phone whose owner had already consented, so the device flag was set
    // but this account had agreed to nothing. Record it and send them on.
    if (auth.isAuthenticated) {
      await _repo.recordConsentForCurrentUser(locale: locale);
      if (!mounted) return;
      auth.navigateAfterAuth();
      return;
    }

    if (!mounted) return;
    context.go('/onboarding/welcome');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final agreed = (_privacyAgreed ? 1 : 0) + (_termsAgreed ? 1 : 0);

    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  ZirenTokens.space24,
                  ZirenTokens.space16,
                  ZirenTokens.space24,
                  ZirenTokens.space24,
                ),
                children: [
                  Row(
                    children: [
                      // Back to the language choice — someone who picked the
                      // wrong one should not be stuck reading it.
                      Padding(
                        padding: const EdgeInsets.only(
                          right: ZirenTokens.space8,
                        ),
                        child: IconButton(
                          key: const Key('consent-back'),
                          tooltip:
                              MaterialLocalizations.of(
                                context,
                              ).backButtonTooltip,
                          style: IconButton.styleFrom(
                            backgroundColor: ZirenTokens.surfaceCard,
                            side: BorderSide(color: ZirenTokens.surfaceBorder),
                          ),
                          icon: Icon(
                            LucideIcons.arrow_left,
                            size: 18,
                            color: ZirenTokens.textPrimary,
                          ),
                          onPressed: () => context.go('/onboarding/language'),
                        ),
                      ),
                      const Expanded(child: OnboardingSteps(step: 2)),
                    ],
                  ),
                  const SizedBox(height: ZirenTokens.space20),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: ZirenTokens.brandOrange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        LucideIcons.shield_check,
                        size: 28,
                        color: ZirenTokens.brandOrange,
                      ),
                    ),
                  ),
                  const SizedBox(height: ZirenTokens.space16),
                  Text(
                    t.consentTitle,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                      letterSpacing: -0.5,
                      color: ZirenTokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: ZirenTokens.space8),
                  Text(
                    t.consentSubtitle,
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.5,
                      color: ZirenTokens.textSecondary,
                    ),
                  ),

                  const SizedBox(height: ZirenTokens.space20),
                  _Summary(
                    title: t.consentSummaryTitle,
                    points: [
                      (
                        LucideIcons.locate_fixed,
                        ZirenTokens.systemInfo,
                        t.consentSummaryLocation,
                      ),
                      (
                        LucideIcons.share_2,
                        ZirenTokens.brandOrange,
                        t.consentSummaryReporting,
                      ),
                      (
                        LucideIcons.lock,
                        ZirenTokens.systemSuccess,
                        t.consentSummaryPhotos,
                      ),
                      (
                        LucideIcons.phone_call,
                        ZirenTokens.severityCritical,
                        t.consentSummaryNotHotline,
                      ),
                    ],
                  ),

                  const SizedBox(height: ZirenTokens.space20),
                  _AgreementCard(
                    key: const Key('consent-privacy'),
                    icon: LucideIcons.shield,
                    title: t.consentPrivacyTitle,
                    subtitle: t.consentPrivacySubtitle,
                    version: LegalDocuments.privacyVersion,
                    hasRead: _privacyRead,
                    agreed: _privacyAgreed,
                    agreeLabel: t.consentAgreePrivacy,
                    onOpen:
                        () => _open(LegalDoc.privacy, t.consentPrivacyTitle),
                    onAgree: (v) => setState(() => _privacyAgreed = v),
                  ),
                  const SizedBox(height: ZirenTokens.space12),
                  _AgreementCard(
                    key: const Key('consent-terms'),
                    icon: LucideIcons.file_text,
                    title: t.consentTermsTitle,
                    subtitle: t.consentTermsSubtitle,
                    version: LegalDocuments.termsVersion,
                    hasRead: _termsRead,
                    agreed: _termsAgreed,
                    agreeLabel: t.consentAgreeTerms,
                    onOpen: () => _open(LegalDoc.terms, t.consentTermsTitle),
                    onAgree: (v) => setState(() => _termsAgreed = v),
                  ),
                ],
              ),
            ),

            Container(
              decoration: BoxDecoration(
                color: ZirenTokens.surfaceCard,
                border: Border(
                  top: BorderSide(color: ZirenTokens.surfaceBorder),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(
                ZirenTokens.space20,
                ZirenTokens.space12,
                ZirenTokens.space20,
                ZirenTokens.space16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      for (var i = 0; i < 2; i++) ...[
                        if (i > 0) const SizedBox(width: 4),
                        Expanded(
                          child: AnimatedContainer(
                            duration: ZirenTokens.motionQuick,
                            height: 4,
                            decoration: BoxDecoration(
                              color:
                                  i < agreed
                                      ? ZirenTokens.systemSuccess
                                      : ZirenTokens.surfaceBorder,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: ZirenTokens.space10),
                      Text(
                        t.consentAgreedCount('$agreed'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color:
                              agreed == 2
                                  ? ZirenTokens.systemSuccess
                                  : ZirenTokens.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: ZirenTokens.space12),
                  ZirenButton(
                    key: const Key('consent-continue'),
                    label: t.consentContinue,
                    isLoading: _busy,
                    onPressed: _canContinue ? _continue : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Plain-language summary ────────────────────────────────────

class _Summary extends StatelessWidget {
  const _Summary({required this.title, required this.points});

  final String title;
  final List<(IconData, Color, String)> points;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space16),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        borderRadius: BorderRadius.circular(ZirenTokens.radius20),
        border: Border.all(color: ZirenTokens.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
              color: ZirenTokens.textSecondary,
            ),
          ),
          const SizedBox(height: ZirenTokens.space12),
          for (var i = 0; i < points.length; i++)
            Padding(
              padding: EdgeInsets.only(
                bottom: i == points.length - 1 ? 0 : ZirenTokens.space12,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: points[i].$2.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Icon(points[i].$1, size: 17, color: points[i].$2),
                  ),
                  const SizedBox(width: ZirenTokens.space12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        points[i].$3,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: ZirenTokens.textPrimary,
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

// ── One document and its agreement ────────────────────────────

class _AgreementCard extends StatelessWidget {
  const _AgreementCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.version,
    required this.hasRead,
    required this.agreed,
    required this.agreeLabel,
    required this.onOpen,
    required this.onAgree,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String version;
  final bool hasRead;
  final bool agreed;
  final String agreeLabel;
  final VoidCallback onOpen;
  final ValueChanged<bool> onAgree;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final (chip, chipColor) =
        agreed
            ? (t.consentAgreed, ZirenTokens.systemSuccess)
            : hasRead
            ? (t.consentBadgeRead, ZirenTokens.systemInfo)
            : (t.consentNeedsReading, ZirenTokens.brandOrange);

    return AnimatedContainer(
      duration: ZirenTokens.motionQuick,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        borderRadius: BorderRadius.circular(ZirenTokens.radius20),
        border: Border.all(
          color:
              agreed
                  ? ZirenTokens.systemSuccess.withValues(alpha: 0.55)
                  : ZirenTokens.surfaceBorder,
          width: agreed ? 1.5 : 1,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: onOpen,
              child: Padding(
                padding: const EdgeInsets.all(ZirenTokens.space16),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: chipColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        agreed ? LucideIcons.circle_check_big : icon,
                        size: 20,
                        color: chipColor,
                      ),
                    ),
                    const SizedBox(width: ZirenTokens.space12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              color: ZirenTokens.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$subtitle  ·  v$version',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: ZirenTokens.textMuted,
                            ),
                          ),
                          const SizedBox(height: ZirenTokens.space6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: chipColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(
                                ZirenTokens.radius32,
                              ),
                            ),
                            child: Text(
                              chip,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: chipColor,
                              ),
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
            Divider(height: 1, color: ZirenTokens.surfaceBorder),
            _AgreeCheck(
              label: agreeLabel,
              value: agreed,
              enabled: hasRead,
              disabledHint: t.consentMustReadFirst,
              onChanged: onAgree,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Agreement checkbox ────────────────────────────────────────

class _AgreeCheck extends StatelessWidget {
  const _AgreeCheck({
    required this.label,
    required this.value,
    required this.enabled,
    required this.disabledHint,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final bool enabled;
  final String disabledHint;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: value,
      enabled: enabled,
      label: enabled ? label : '$label. $disabledHint',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: enabled ? () => onChanged(!value) : null,
          child: Container(
            color:
                value
                    ? ZirenTokens.systemSuccess.withValues(alpha: 0.06)
                    : Colors.transparent,
            padding: const EdgeInsets.symmetric(
              vertical: ZirenTokens.space12,
              horizontal: ZirenTokens.space16,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: value,
                    onChanged: enabled ? (v) => onChanged(v ?? false) : null,
                    activeColor: ZirenTokens.systemSuccess,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
                const SizedBox(width: ZirenTokens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                          color:
                              enabled
                                  ? ZirenTokens.textPrimary
                                  : ZirenTokens.textMuted,
                        ),
                      ),
                      if (!enabled) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              LucideIcons.lock,
                              size: 12,
                              color: ZirenTokens.textMuted,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                disabledHint,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: ZirenTokens.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
