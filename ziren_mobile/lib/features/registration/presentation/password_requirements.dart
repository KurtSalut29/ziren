import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../../core/utils/validators.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';

/// What a password has to contain, said outright, and ticked off as it is typed.
///
/// This used to be one line of small grey helper text under the field ("Min 8
/// characters, 1 uppercase, 1 number") that people did not read and so found
/// out about only when Continue refused them. It is now a panel that is always
/// on screen, whether or not the field has focus, and each rule turns into a
/// green tick the moment it is met.
///
/// The rules come from [Validators], the same functions the form validator
/// runs, so what is shown here and what is refused cannot drift apart.
class PasswordRequirements extends StatelessWidget {
  const PasswordRequirements({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final text = value.text;
        final rules = <({String label, bool met})>[
          (
            label: t.passwordReqLength(Validators.passwordMinLength),
            met: Validators.passwordHasMinLength(text),
          ),
          (
            label: t.passwordReqUpper,
            met: Validators.passwordHasUppercase(text),
          ),
          (
            label: t.passwordReqNumber,
            met: Validators.passwordHasNumber(text),
          ),
        ];

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(ZirenTokens.space12),
          decoration: BoxDecoration(
            color: ZirenTokens.systemInfoBg,
            borderRadius: BorderRadius.circular(ZirenTokens.radius12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.passwordReqTitle,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: ZirenTokens.textPrimary,
                ),
              ),
              const SizedBox(height: ZirenTokens.space6),
              for (final rule in rules)
                _Rule(label: rule.label, met: rule.met),
            ],
          ),
        );
      },
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.label, required this.met});

  final String label;
  final bool met;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      value: met ? 'done' : 'not yet',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                met ? LucideIcons.circle_check : LucideIcons.circle,
                size: 16,
                color: met ? ZirenTokens.systemSuccess : ZirenTokens.textMuted,
              ),
              const SizedBox(width: ZirenTokens.space8),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    fontWeight: met ? FontWeight.w600 : FontWeight.w500,
                    color:
                        met
                            ? ZirenTokens.textPrimary
                            : ZirenTokens.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
