import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/theme/app_tokens.dart';
import '../domain/id_catalogue.dart';
import '../domain/registration_draft.dart';
import 'registration_shell.dart';
import '../../../l10n/app_localizations.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Step 5 (residents) — which document they are going to show.
///
/// The list is split into "proves you live in Biliran" and "proves who you
/// are", and the split is explained rather than implied. An LGU issues its IDs
/// only to its own residents, so a barangay ID settles residency outright; a
/// passport settles identity and says nothing about address. Someone choosing
/// between them should know which question they are answering, because it
/// changes how much follow-up an admin needs to do.
class StepIdTypeScreen extends StatelessWidget {
  const StepIdTypeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final d = context.watch<RegistrationDraft>();

    return RegistrationScaffold(
      step: RegStep.idType,
      title: t.regIdTypeTitle,
      subtitle: t.regIdTypeSubtitle,
      onContinue:
          d.validIdType == null
              ? null
              : () => context.go(d.next(RegStep.idType)!.path),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeader(
            title: t.regIdBestChoice,
            note: t.regIdProvesResidency,
            colour: ZirenTokens.systemSuccess,
          ),
          const SizedBox(height: ZirenTokens.space12),
          for (final option in IdCatalogue.lguIssued) ...[
            _IdTile(
              option: option,
              selected: d.validIdType == option.value,
              onTap: () {
                d.validIdType = option.value;
                d.residencyProofType = IdCatalogue.residencyProofFor(
                  option.value,
                );
                d.commit();
              },
            ),
            const SizedBox(height: ZirenTokens.space8),
          ],

          const SizedBox(height: ZirenTokens.space16),
          _SectionHeader(
            title: t.regIdAlsoAccepted,
            note: t.regIdIdentityOnly,
            colour: ZirenTokens.textMuted,
          ),
          const SizedBox(height: ZirenTokens.space12),
          for (final option in IdCatalogue.national) ...[
            _IdTile(
              option: option,
              selected: d.validIdType == option.value,
              onTap: () {
                d.validIdType = option.value;
                d.residencyProofType = IdCatalogue.residencyProofFor(
                  option.value,
                );
                d.commit();
              },
            ),
            const SizedBox(height: ZirenTokens.space8),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.note,
    required this.colour,
  });

  final String title;
  final String note;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.9,
            color: colour,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          note,
          style: TextStyle(fontSize: 12.5, color: ZirenTokens.textMuted),
        ),
      ],
    );
  }
}

/// One document in the list.
class _IdTile extends StatelessWidget {
  const _IdTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final IdOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: option.label,
      child: ExcludeSemantics(
        child: Material(
          color: selected ? ZirenTokens.brandSubtle : ZirenTokens.surfaceRaised,
          borderRadius: BorderRadius.circular(ZirenTokens.radius16),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(ZirenTokens.radius16),
            child: Container(
              padding: const EdgeInsets.all(ZirenTokens.space16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(ZirenTokens.radius16),
                border: Border.all(
                  color:
                      selected ? ZirenTokens.brandOrange : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          option.label,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w600,
                            color:
                                selected
                                    ? ZirenTokens.brandActive
                                    : ZirenTokens.textPrimary,
                          ),
                        ),
                        if (option.hint != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            option.hint!,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: ZirenTokens.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: ZirenTokens.space12),
                  Icon(
                    selected
                        ? LucideIcons.circle_check_big
                        : LucideIcons.circle,
                    size: 22,
                    color:
                        selected
                            ? ZirenTokens.brandOrange
                            : ZirenTokens.surfaceBorder,
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
