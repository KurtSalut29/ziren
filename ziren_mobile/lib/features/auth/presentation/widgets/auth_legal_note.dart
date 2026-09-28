import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/config/locale_provider.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/theme/app_tokens.dart';
import '../../../onboarding/domain/legal_documents.dart';
import '../../../onboarding/presentation/legal_reader_screen.dart';

/// The line that closes an auth card: what the person is agreeing to, with
/// both documents one tap away.
///
/// A reminder, not a gate. Consent is taken properly during onboarding — two
/// separate checkboxes, each unlocked only by opening its document, because
/// the terms and the privacy notice are different agreements and RA 10173
/// asks about the second one specifically. This is here so the documents stay
/// reachable from the screen someone actually sits on, rather than only from a
/// flow they passed through once and cannot easily get back to.
///
/// Inline `Text.rich` rather than a row of buttons: the sentence has to wrap
/// as a sentence, and at this size a Wrap of separate widgets breaks in the
/// wrong places on a narrow phone.
class AuthLegalNote extends StatefulWidget {
  const AuthLegalNote({super.key});

  @override
  State<AuthLegalNote> createState() => _AuthLegalNoteState();
}

class _AuthLegalNoteState extends State<AuthLegalNote> {
  // Held as fields so they can be disposed. A TapGestureRecognizer built
  // inline in build() leaks one per rebuild.
  late final TapGestureRecognizer _terms;
  late final TapGestureRecognizer _privacy;

  @override
  void initState() {
    super.initState();
    _terms = TapGestureRecognizer()..onTap = () => _open(LegalDoc.terms);
    _privacy = TapGestureRecognizer()..onTap = () => _open(LegalDoc.privacy);
  }

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  void _open(LegalDoc doc) {
    final t = AppLocalizations.of(context);
    Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder:
            (_) => LegalReaderScreen(
              doc: doc,
              // The documents ship in both languages; showing the English one
              // to someone reading the app in Filipino would make the reminder
              // worse than useless.
              languageCode: context.read<LocaleProvider>().locale.languageCode,
              title:
                  doc == LegalDoc.terms
                      ? t.consentTermsTitle
                      : t.consentPrivacyTitle,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    final base = TextStyle(
      fontSize: 12,
      height: 1.5,
      color: ZirenTokens.textMuted,
    );
    // Underlined as well as darker: a link marked by colour alone is a
    // colour-only cue, and at 12px it is the easiest one to miss.
    final link = TextStyle(
      fontSize: 12,
      height: 1.5,
      fontWeight: FontWeight.w700,
      color: ZirenTokens.textSecondary,
      decoration: TextDecoration.underline,
      decorationColor: ZirenTokens.textMuted,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ZirenTokens.space8),
      child: Text.rich(
        TextSpan(
          style: base,
          children: [
            TextSpan(text: '${t.authLegalIntro} '),
            TextSpan(
              text: t.consentTermsTitle,
              style: link,
              recognizer: _terms,
              semanticsLabel: t.consentTermsTitle,
            ),
            TextSpan(text: ' ${t.authLegalAnd} '),
            TextSpan(
              text: t.consentPrivacyTitle,
              style: link,
              recognizer: _privacy,
              semanticsLabel: t.consentPrivacyTitle,
            ),
            const TextSpan(text: '.'),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
