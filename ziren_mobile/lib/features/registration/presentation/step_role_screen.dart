import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/theme/app_tokens.dart';
import '../../auth/presentation/widgets/auth_legal_note.dart';
import '../domain/registration_draft.dart';
import 'registration_shell.dart';
import '../../../l10n/app_localizations.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Step 1 — resident or responder.
///
/// It leads because it changes the shape of everything after it: responders
/// give agency details and an agency ID, residents give a personal ID and an
/// accessibility profile. Asking it later would mean re-asking questions.
class StepRoleScreen extends StatelessWidget {
  const StepRoleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final draft = context.watch<RegistrationDraft>();

    return RegistrationScaffold(
      step: RegStep.role,
      title: t.regRoleTitle,
      subtitle: t.regRoleSubtitle,
      onContinue: () => context.go(draft.next(RegStep.role)!.path),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RoleCard(
            label: t.roleResident,
            description: t.regRoleResidentBody,
            icon: LucideIcons.user,
            selected: !draft.isResponder,
            onTap: () {
              draft.role = 'resident';
              draft.commit();
            },
          ),
          const SizedBox(height: ZirenTokens.space12),
          _RoleCard(
            label: t.roleResponder,
            description: t.regRoleResponderBody,
            icon: LucideIcons.shield,
            selected: draft.isResponder,
            onTap: () {
              draft.role = 'responder';
              draft.commit();
            },
          ),

          // Registration ends by writing terms_accepted_at, so the documents
          // belong where the flow starts, not only in the onboarding screen
          // they passed through before this one.
          const SizedBox(height: ZirenTokens.space24),
          const AuthLegalNote(),
        ],
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.label,
    required this.description,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String description;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      selected: selected,
      label: '$label. $description',
      child: ExcludeSemantics(
        child: Material(
          color: selected ? ZirenTokens.brandSubtle : ZirenTokens.surfaceCard,
          borderRadius: BorderRadius.circular(ZirenTokens.radius20),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(ZirenTokens.radius20),
            child: Container(
              padding: const EdgeInsets.all(ZirenTokens.space20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(ZirenTokens.radius20),
                border: Border.all(
                  color:
                      selected
                          ? ZirenTokens.brandOrange
                          : ZirenTokens.surfaceBorder,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    icon,
                    size: 26,
                    color:
                        selected
                            ? ZirenTokens.brandOrange
                            : ZirenTokens.textMuted,
                  ),
                  const SizedBox(width: ZirenTokens.space16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color:
                                selected
                                    ? ZirenTokens.brandActive
                                    : ZirenTokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: ZirenTokens.space4),
                        Text(
                          description,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.45,
                            color: ZirenTokens.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
