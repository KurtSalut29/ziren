import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../features/settings/domain/profile_model.dart';
import '../../features/settings/domain/profile_provider.dart';
import '../../l10n/app_localizations.dart';
import '../theme/app_tokens.dart';
import 'ziren_dialogs.dart';

/// "You cannot send reports until 12 October 2026" - or "until further notice".
///
/// One sentence, used by the Home banner, the dialog that stops a report being
/// started, and the notification that announces the suspension, so the three can
/// never say different dates.
String suspensionSentence(
  AppLocalizations t, {
  required DateTime? until,
  required bool indefinite,
}) {
  if (indefinite || until == null) return t.accountSuspendedIndefinite;
  return t.accountSuspendedUntil(_longDate(until.toLocal(), t.localeName));
}

/// "October 8, 2026" in the app's language.
///
/// The month names for a language are loaded by the app's localisation
/// delegates. Where they have not been - a notice built before the first frame,
/// a test - intl throws rather than falling back, and a date that cannot be
/// written must not take the whole notice down with it. English is always
/// there.
String _longDate(DateTime when, String locale) {
  try {
    return DateFormat.yMMMMd(locale).format(when);
  } catch (_) {
    return DateFormat.yMMMMd().format(when);
  }
}

/// Tells a suspended resident, on Home, that reports will be refused - and
/// gives them the hotlines instead.
///
/// WHY IT IS HERE AND NOT ONLY AN ERROR
///
/// The server refuses a suspended account's report. Without this the resident
/// would learn that at the END of the wizard, after describing an emergency and
/// pressing Send - the worst moment to be told the app will not help. So the app
/// says it first, where they start, and the one thing it offers is the thing
/// that still works: a phone call.
///
/// Draws nothing for an account in good standing, or while the profile is still
/// loading.
class SuspensionBanner extends StatelessWidget {
  const SuspensionBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileProvider>().profile;
    if (profile == null || !profile.isSuspended) return const SizedBox.shrink();
    final t = AppLocalizations.of(context);

    return Container(
      key: const Key('suspension-banner'),
      padding: const EdgeInsets.all(ZirenTokens.space16),
      decoration: BoxDecoration(
        color: ZirenTokens.systemWarning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(ZirenTokens.radius16),
        border: Border.all(
          color: ZirenTokens.systemWarning.withValues(alpha: 0.40),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.ban, size: 20, color: ZirenTokens.systemWarning),
          const SizedBox(width: ZirenTokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.accountSuspendedTitle,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: ZirenTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: ZirenTokens.space4),
                Text(
                  '${suspensionSentence(t, until: profile.suspendedUntil, indefinite: profile.suspensionIndefinite)} ${t.accountSuspendedHelp}',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: ZirenTokens.textSecondary,
                  ),
                ),
                const SizedBox(height: ZirenTokens.space8),
                TextButton(
                  onPressed: () => context.push('/hotlines'),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(t.accountOpenHotlines),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Stops a report being started by a suspended account.
///
/// Returns true when the resident was refused (and has been shown why, with the
/// hotlines one tap away); false when they may go on. An unknown profile is
/// never a refusal: if the app has not been told the account is suspended, the
/// report goes ahead and the server decides.
Future<bool> refuseIfSuspended(BuildContext context) async {
  final ProfileModel? profile = context.read<ProfileProvider>().profile;
  if (profile == null || !profile.isSuspended) return false;
  final t = AppLocalizations.of(context);

  final openHotlines = await showZirenDialog<bool>(
    context,
    icon: LucideIcons.ban,
    tone: ZirenTone.warning,
    title: t.accountSuspendedTitle,
    message:
        '${suspensionSentence(t, until: profile.suspendedUntil, indefinite: profile.suspensionIndefinite)} ${t.accountSuspendedHelp}',
    actions: [
      ZirenDialogAction(
        label: t.accountOpenHotlines,
        value: true,
        kind: ZirenActionKind.primary,
      ),
      ZirenDialogAction(label: t.notifStatusOk, value: false),
    ],
  );
  if (openHotlines == true && context.mounted) {
    await context.push('/hotlines');
  }
  return true;
}
