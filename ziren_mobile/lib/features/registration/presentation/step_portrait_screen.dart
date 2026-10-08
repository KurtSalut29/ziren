import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/registration_draft.dart';
import 'portrait_picker.dart';
import 'registration_shell.dart';

/// The 2x2 ID photo: the picture on the resident's Ziren ID card (user
/// request 2026-10-08). After the selfie, because the selfie - taken live,
/// through the liveness challenge - is what this photo's face is compared
/// with; see [PortraitPicker] and domain/portrait_check.dart.
class StepPortraitScreen extends StatelessWidget {
  const StepPortraitScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final d = context.watch<RegistrationDraft>();
    final accepted = d.portraitPath != null && d.portraitChecks != null;

    return RegistrationScaffold(
      step: RegStep.portrait,
      title: t.portraitStepTitle,
      subtitle: t.portraitStepSubtitle,
      onContinue:
          accepted ? () => context.go(d.next(RegStep.portrait)!.path) : null,
      child: PortraitPicker(
        selfiePath: d.selfiePath,
        initialPath: d.portraitPath,
        initialChecks: d.portraitChecks,
        onChanged: (path, checks) {
          d.portraitPath = path;
          d.portraitChecks = checks;
          d.commit();
        },
      ),
    );
  }
}
