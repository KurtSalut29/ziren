import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../domain/id_name_match.dart';
import '../domain/registration_draft.dart';

/// Blocking: the typed name is not the name on the ID. Says which part, and
/// offers the two ways out: correct the name (back to the name step; the ID
/// step reads the card again on the way back) or photograph the card again.
class NameMismatchNotice extends StatelessWidget {
  const NameMismatchNotice({
    super.key,
    required this.match,
    required this.draft,
    required this.onRetake,
    required this.from,
  });

  /// The ID step this is shown on, to come back to once the name is fixed.
  final RegStep from;
  final IdNameMatch match;
  final RegistrationDraft draft;
  final VoidCallback onRetake;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    // A middle name typed as its initial gets its own sentence: "not found"
    // would leave the person guessing what to change.
    final middle = draft.middleName.trim();
    final middleInitial =
        match.missing.contains(NamePart.middle) &&
        IdNameMatch.isInitialOnly(middle);
    final parts = [
      for (final p in match.missing)
        if (!(middleInitial && p == NamePart.middle))
        switch (p) {
          NamePart.first => t.regNamePartFirst(draft.firstName.trim()),
          NamePart.middle => t.regNamePartMiddle(draft.middleName.trim()),
          NamePart.last => t.regNamePartLast(draft.lastName.trim()),
        },
    ].join(', ');
    return Container(
      key: const ValueKey('name-mismatch'),
      padding: const EdgeInsets.all(ZirenTokens.space16),
      decoration: BoxDecoration(
        color: ZirenTokens.systemWarningBg,
        borderRadius: BorderRadius.circular(ZirenTokens.radius12),
        border: Border.all(
          color: ZirenTokens.systemWarning.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.user_x,
                size: 18,
                color: ZirenTokens.systemWarning,
              ),
              const SizedBox(width: ZirenTokens.space8),
              Expanded(
                child: Text(
                  t.regNameMismatchTitle,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: ZirenTokens.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: ZirenTokens.space8),
          Text(
            [
              if (parts.isNotEmpty) t.regNameMismatchBody(parts),
              if (middleInitial) t.regMiddleInitialBody(middle),
            ].join('\n\n'),
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: ZirenTokens.textPrimary,
            ),
          ),
          const SizedBox(height: ZirenTokens.space12),
          Wrap(
            spacing: ZirenTokens.space8,
            runSpacing: ZirenTokens.space8,
            children: [
              FilledButton.icon(
                key: const ValueKey('fix-name'),
                onPressed: () {
                  draft.returnTo = from;
                  context.go(RegStep.personal.path);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: ZirenTokens.brandOrange,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(LucideIcons.pencil, size: 16),
                label: Text(t.regFixName),
              ),
              OutlinedButton.icon(
                onPressed: onRetake,
                icon: const Icon(LucideIcons.camera, size: 16),
                label: Text(t.regRetakeId),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
