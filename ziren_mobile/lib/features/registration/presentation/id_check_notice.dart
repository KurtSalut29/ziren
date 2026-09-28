import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../domain/id_photo_check.dart';

/// One line of feedback about the photographed ID.
///
/// Two kinds share this look. The BLOCKING ones ([IdCheckNotice.blocking]) say
/// what is wrong with the photo and how to fix it, and go with a disabled
/// Continue/Submit: a photo that cannot be an ID proves nothing and only fills
/// the review queue with junk. The ADVISORY ones (an expired card, a number that
/// does not fit the chosen type) are built directly and never block - an
/// expired barangay ID is still evidence of who someone is, and an admin
/// decides whether it is enough.
///
/// Either way the problem is found now, by the person holding the card, instead
/// of in three days by an admin who can only reject and wait.
class IdCheckNotice extends StatelessWidget {
  const IdCheckNotice({
    super.key,
    required this.icon,
    required this.tint,
    required this.bg,
    required this.text,
    this.title,
    this.footnote,
  });

  /// The notice for a photo that was not accepted. [check] must not be
  /// [IdPhotoCheck.ok], [IdPhotoCheck.none] or [IdPhotoCheck.checking].
  ///
  /// [canSkip] is whether the person can leave verification for later from
  /// here - true in the registration step ("I need help right now - skip
  /// this"), false on the Verify screen, which already IS the later step and
  /// where telling someone to "do it later from Settings" points at the page
  /// they are on.
  ///
  /// [chosenLabel] is the ID type the person picked ("Passport") and
  /// [foundLabel] the type the photo looks like when it is a different one
  /// ("Driver's License"); the messages name both so the person knows exactly
  /// what to change.
  factory IdCheckNotice.blocking(
    BuildContext context,
    IdPhotoCheck check, {
    bool canSkip = true,
    String? chosenLabel,
    String? foundLabel,
  }) {
    final t = AppLocalizations.of(context);
    final chosen = chosenLabel ?? 'ID';
    final found = foundLabel ?? 'different ID';
    // Refusals of the WHOLE document (not an ID, wrong ID) are stronger than
    // a photo that is merely hard to read, so they get the red treatment and
    // their own headline; everything else stays the amber "fix and retry".
    final refusal =
        check == IdPhotoCheck.notAnId ||
        check == IdPhotoCheck.wrongType ||
        check == IdPhotoCheck.typeUnconfirmed;
    return IdCheckNotice(
      icon: switch (check) {
        IdPhotoCheck.notAnId => LucideIcons.circle_x,
        IdPhotoCheck.wrongType => LucideIcons.badge_x,
        IdPhotoCheck.typeUnconfirmed => LucideIcons.id_card,
        IdPhotoCheck.noFace => LucideIcons.user_x,
        IdPhotoCheck.noNumber => LucideIcons.hash,
        IdPhotoCheck.numberMismatch => LucideIcons.pen_line,
        _ => LucideIcons.scan_line,
      },
      tint: refusal ? ZirenTokens.systemError : ZirenTokens.systemWarning,
      bg: refusal ? ZirenTokens.systemErrorBg : ZirenTokens.systemWarningBg,
      title: switch (check) {
        IdPhotoCheck.notAnId => t.idCheckNotAnIdTitle,
        IdPhotoCheck.wrongType => t.idCheckWrongTypeTitle(chosen),
        IdPhotoCheck.typeUnconfirmed => t.idCheckWrongTypeTitle(chosen),
        _ => t.idCheckTitle,
      },
      text: switch (check) {
        IdPhotoCheck.notAnId => t.idCheckNotAnId(chosen),
        IdPhotoCheck.wrongType => t.idCheckWrongType(chosen, found),
        IdPhotoCheck.typeUnconfirmed => t.idCheckTypeUnconfirmed(chosen),
        IdPhotoCheck.noFace => t.idCheckNoFace,
        IdPhotoCheck.noNumber => t.idCheckNoNumber,
        IdPhotoCheck.numberMismatch => t.idCheckNumberMismatch,
        _ => t.idCheckNoText,
      },
      // A wrong number is fixed by typing, not by photographing again.
      footnote:
          check == IdPhotoCheck.numberMismatch
              ? null
              : (canSkip ? t.idCheckRetakeHint : t.idCheckRetakeOnly),
    );
  }

  final IconData icon;
  final Color tint;
  final Color bg;
  final String text;
  final String? title;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ZirenTokens.space12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(ZirenTokens.radius12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: tint),
          const SizedBox(width: ZirenTokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: ZirenTokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: ZirenTokens.textSecondary,
                  ),
                ),
                if (footnote != null) ...[
                  const SizedBox(height: ZirenTokens.space6),
                  Text(
                    footnote!,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: ZirenTokens.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
