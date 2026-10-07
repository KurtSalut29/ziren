import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../l10n/app_localizations.dart';
import '../theme/app_tokens.dart';

/// The "Ziren code": four digits that tell an arriving crew who reported.
///
/// A teacher's question (2026-10-07): how does a responder recognise the
/// reporter on arrival - and what if their appearance is not what the crew
/// expects, a transgender reporter for example? Ziren does not identify anyone
/// by appearance or gender. The reporter's own report shows this code; the
/// assigned responder's shows the same digits and says to ask for them. No sex
/// or gender is shown to a crew anywhere in the app. See the backend's
/// app/core/meet_code.py.
class MeetCodeCard extends StatelessWidget {
  const MeetCodeCard({
    super.key,
    required this.code,
    required this.forResponder,
  });

  final String code;

  /// The crew's wording ("ask for it") rather than the reporter's ("tell it").
  final bool forResponder;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Container(
      key: const ValueKey('meet-code'),
      padding: const EdgeInsets.all(ZirenTokens.space16),
      decoration: BoxDecoration(
        color: ZirenTokens.brandSubtle,
        borderRadius: BorderRadius.circular(ZirenTokens.radius16),
        border: Border.all(
          color: ZirenTokens.brandOrange.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            forResponder ? LucideIcons.message_square : LucideIcons.key_round,
            size: 22,
            color:
                ZirenTokens.isDark
                    ? ZirenTokens.brandOrange
                    : ZirenTokens.brandActive,
          ),
          const SizedBox(width: ZirenTokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  forResponder
                      ? t.meetCodeTitleResponder
                      : t.meetCodeTitleReporter,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: ZirenTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: ZirenTokens.space6),
                Semantics(
                  label: t.meetCodeSemantics(code.split('').join(' ')),
                  excludeSemantics: true,
                  child: Text(
                    code,
                    style: TextStyle(
                      fontSize: 34,
                      height: 1.1,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 8,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color:
                          ZirenTokens.isDark
                              ? ZirenTokens.brandOrange
                              : ZirenTokens.brandActive,
                    ),
                  ),
                ),
                const SizedBox(height: ZirenTokens.space6),
                Text(
                  forResponder
                      ? t.meetCodeBodyResponder
                      : t.meetCodeBodyReporter,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
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
