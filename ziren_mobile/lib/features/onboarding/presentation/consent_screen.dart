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

/// Data Privacy Notice and Terms of Use, with a separate agreement for each.
///
/// Two checkboxes, not one
/// -----------------------
/// Bundling them into a single "I agree to the Terms and Privacy Policy" tick
/// is the common pattern and it is the wrong one here. They are different
/// agreements: the terms govern how the service may be used, the privacy
/// notice is consent to process personal data under RA 10173. A single tick
/// cannot evidence the second, and the second is the one a regulator asks
/// about.
///
/// Each checkbox stays disabled until its document has actually been opened
/// and scrolled through. The plain-language summary above them is what a
/// hurried person will really read, so it carries the four things that
/// genuinely change someone's decision — including the one no product wants
/// to lead with, that this app is not a replacement for calling 911.
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

    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  ZirenTokens.space24,
                  ZirenTokens.space32,
                  ZirenTokens.space24,
                  ZirenTokens.space24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      t.consentTitle,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
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

                    const SizedBox(height: ZirenTokens.space24),
                    _Summary(
                      title: t.consentSummaryTitle,
                      points: [
                        (LucideIcons.locate_fixed, t.consentSummaryLocation),
                        (
                          LucideIcons.share_2,
                          t.consentSummaryReporting,
                        ),
                        (LucideIcons.lock, t.consentSummaryPhotos),
                        (
                          LucideIcons.phone_call,
                          t.consentSummaryNotHotline,
                        ),
                      ],
                    ),

                    const SizedBox(height: ZirenTokens.space24),

                    _DocumentRow(
                      title: t.consentPrivacyTitle,
                      subtitle: t.consentPrivacySubtitle,
                      version: LegalDocuments.privacyVersion,
                      hasRead: _privacyRead,
                      readLabel: t.consentActionRead,
                      readBadge: t.consentBadgeRead,
                      onOpen:
                          () => _open(LegalDoc.privacy, t.consentPrivacyTitle),
                    ),
                    const SizedBox(height: ZirenTokens.space12),
                    _DocumentRow(
                      title: t.consentTermsTitle,
                      subtitle: t.consentTermsSubtitle,
                      version: LegalDocuments.termsVersion,
                      hasRead: _termsRead,
                      readLabel: t.consentActionRead,
                      readBadge: t.consentBadgeRead,
                      onOpen: () => _open(LegalDoc.terms, t.consentTermsTitle),
                    ),

                    const SizedBox(height: ZirenTokens.space24),

                    _AgreeCheck(
                      label: t.consentAgreePrivacy,
                      value: _privacyAgreed,
                      enabled: _privacyRead,
                      disabledHint: t.consentMustReadFirst,
                      onChanged: (v) => setState(() => _privacyAgreed = v),
                    ),
                    const SizedBox(height: ZirenTokens.space8),
                    _AgreeCheck(
                      label: t.consentAgreeTerms,
                      value: _termsAgreed,
                      enabled: _termsRead,
                      disabledHint: t.consentMustReadFirst,
                      onChanged: (v) => setState(() => _termsAgreed = v),
                    ),
                  ],
                ),
              ),
            ),

            Container(
              decoration: BoxDecoration(
                color: ZirenTokens.surfaceCard,
                border: Border(
                  top: BorderSide(color: ZirenTokens.surfaceBorder),
                ),
              ),
              padding: const EdgeInsets.all(ZirenTokens.space20),
              child: ZirenButton(
                label: t.consentContinue,
                isLoading: _busy,
                onPressed: _canContinue ? _continue : null,
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
  final List<(IconData, String)> points;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space20),
      decoration: BoxDecoration(
        color: ZirenTokens.surfaceCard,
        borderRadius: BorderRadius.circular(ZirenTokens.radius20),
        border: Border.all(color: ZirenTokens.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: ZirenTokens.textMuted,
            ),
          ),
          const SizedBox(height: ZirenTokens.space16),
          for (final (icon, text) in points)
            Padding(
              padding: const EdgeInsets.only(bottom: ZirenTokens.space12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 18, color: ZirenTokens.brandOrange),
                  const SizedBox(width: ZirenTokens.space12),
                  Expanded(
                    child: Text(
                      text,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: ZirenTokens.textSecondary,
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

// ── One document ──────────────────────────────────────────────

class _DocumentRow extends StatelessWidget {
  const _DocumentRow({
    required this.title,
    required this.subtitle,
    required this.version,
    required this.hasRead,
    required this.readLabel,
    required this.readBadge,
    required this.onOpen,
  });

  final String title;
  final String subtitle;
  final String version;
  final bool hasRead;
  final String readLabel;
  final String readBadge;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ZirenTokens.surfaceCard,
      borderRadius: BorderRadius.circular(ZirenTokens.radius16),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(ZirenTokens.radius16),
        child: Container(
          padding: const EdgeInsets.all(ZirenTokens.space16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ZirenTokens.radius16),
            border: Border.all(
              color:
                  hasRead
                      ? ZirenTokens.systemSuccess.withValues(alpha: 0.4)
                      : ZirenTokens.surfaceBorder,
            ),
          ),
          child: Row(
            children: [
              Icon(
                hasRead ? LucideIcons.circle_check_big : LucideIcons.file_text,
                size: 22,
                color:
                    hasRead ? ZirenTokens.systemSuccess : ZirenTokens.textMuted,
              ),
              const SizedBox(width: ZirenTokens.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
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
                  ],
                ),
              ),
              Text(
                hasRead ? readBadge : readLabel,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color:
                      hasRead
                          ? ZirenTokens.systemSuccess
                          : ZirenTokens.brandOrange,
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
          borderRadius: BorderRadius.circular(ZirenTokens.radius12),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: ZirenTokens.space8,
              horizontal: ZirenTokens.space4,
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
                    activeColor: ZirenTokens.brandOrange,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                          color:
                              enabled
                                  ? ZirenTokens.textPrimary
                                  : ZirenTokens.textMuted,
                        ),
                      ),
                      if (!enabled) ...[
                        const SizedBox(height: 2),
                        Text(
                          disabledHint,
                          style: TextStyle(
                            fontSize: 12,
                            color: ZirenTokens.textMuted,
                          ),
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
