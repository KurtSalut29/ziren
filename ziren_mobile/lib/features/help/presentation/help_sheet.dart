import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import 'help_screen.dart';

/// "How to use Ziren" as a modal over Home: the same guide as the Help screen,
/// in a tall sheet the resident can drag down or close, so reading the steps
/// never takes them away from the report button.
Future<void> showHelpSheet(BuildContext context, {bool forResponder = false}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: ZirenTokens.surfaceBase,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(ZirenTokens.radius24),
      ),
    ),
    builder:
        (sheetContext) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.88,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder:
              (_, controller) => _HelpSheetBody(
                forResponder: forResponder,
                controller: controller,
                onClose: () => Navigator.of(sheetContext).pop(),
              ),
        ),
  );
}

class _HelpSheetBody extends StatelessWidget {
  const _HelpSheetBody({
    required this.forResponder,
    required this.controller,
    required this.onClose,
  });

  final bool forResponder;
  final ScrollController controller;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      children: [
        const SizedBox(height: ZirenTokens.space10),
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: ZirenTokens.surfaceBorder,
            borderRadius: BorderRadius.circular(ZirenTokens.radius4),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            ZirenTokens.space16,
            ZirenTokens.space12,
            ZirenTokens.space8,
            ZirenTokens.space4,
          ),
          child: Row(
            children: [
              Image.asset(
                'assets/images/mascot_help.png',
                width: 52,
                height: 52,
              ),
              const SizedBox(width: ZirenTokens.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.helpTitle,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                        color: ZirenTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      forResponder ? t.helpIntroResponder : t.helpIntroResident,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: ZirenTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: t.helpSheetClose,
                onPressed: onClose,
                icon: Icon(LucideIcons.x, color: ZirenTokens.textSecondary),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: ZirenTokens.surfaceBorder),
        Expanded(
          child: HelpGuide(
            forResponder: forResponder,
            controller: controller,
            // The header above already says what this is.
            showIntro: false,
            beforeNavigate: onClose,
          ),
        ),
      ],
    );
  }
}
