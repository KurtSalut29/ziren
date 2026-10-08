import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../features/settings/domain/profile_provider.dart';
import '../../l10n/app_localizations.dart';
import 'suspension_banner.dart';
import 'ziren_dialogs.dart';

/// Whether this account may start a report, asked before the report screen
/// opens. Returns true when it was refused (and told why, with the station
/// hotlines one tap away); false when it may go on.
///
/// Two reasons to refuse: a suspension, and a resident whose first 7 days are
/// over without an administrator verifying them (2026-10-07 verified-only,
/// softened 2026-10-08 to a first week; backend resident_trust.py). The server
/// enforces both (incident_standing.py); this only saves someone from filling
/// in a report that cannot be sent.
Future<bool> refuseReport(BuildContext context) async {
  if (await refuseIfSuspended(context)) return true;
  if (!context.mounted) return true;
  return refuseIfUnverified(context);
}

Future<bool> refuseIfUnverified(BuildContext context) async {
  final provider = context.read<ProfileProvider>();
  final profile = provider.profile;
  // Unknown or staff: not ours to refuse, the server decides.
  if (profile == null || profile.role != 'resident') return false;
  // Verified, or still in the first week: the Home banner counts the days.
  if (!profile.reportingLocked) return false;

  // Answer the tap at once from what is already known. This used to wait for
  // a fresh profile first (up to 6 s on a slow line), and a tap that shows
  // nothing for that long reads as a broken app (user report 2026-10-08).
  // The fresh check still runs, beside the dialog: if an administrator has
  // approved the account since it was loaded, the dialog closes itself and
  // the report goes on.
  BuildContext? dialogContext;
  var approved = false;
  // After the frame: the answer can land while the dialog is still building.
  void closeIfApproved() {
    if (!approved) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final d = dialogContext;
      // isCurrent: never pop whatever is under a dialog already closed.
      if (d != null && d.mounted && ModalRoute.of(d)?.isCurrent == true) {
        Navigator.of(d).pop('approved');
      }
    });
  }

  provider
      .loadProfile(force: true)
      .timeout(const Duration(seconds: 8))
      .then((_) {
        approved = provider.profile?.reportingLocked == false;
        closeIfApproved();
      })
      .catchError((_) {});

  final t = AppLocalizations.of(context);
  final submitted = profile.hasSubmittedEvidence;
  final choice = await showZirenDialog<String>(
    context,
    onOpen: (d) {
      dialogContext = d;
      closeIfApproved();
    },
    icon: submitted ? LucideIcons.hourglass : LucideIcons.shield_check,
    tone: ZirenTone.warning,
    title:
        submitted
            ? t.reportPendingVerificationTitle
            : t.reportNeedsVerificationTitle,
    message:
        submitted
            ? t.reportPendingVerificationBody
            : t.reportNeedsVerificationBody,
    actions: [
      ZirenDialogAction(
        label: t.accountOpenHotlines,
        value: 'hotlines',
        kind: ZirenActionKind.primary,
      ),
      if (!submitted)
        ZirenDialogAction(label: t.reportVerifyNow, value: 'verify'),
      ZirenDialogAction(label: t.notifStatusOk, value: 'ok'),
    ],
  );
  if (!context.mounted) return true;
  if (choice == 'approved') return false;
  if (choice == 'hotlines') {
    await context.push('/hotlines');
  } else if (choice == 'verify') {
    await context.push('/profile/verify');
  }
  return true;
}
