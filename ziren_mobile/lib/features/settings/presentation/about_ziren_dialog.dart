import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/ziren_dialogs.dart';

/// The version shown in About and at the foot of Settings: name and build, as
/// in pubspec.yaml's `version: 1.0.0+8`. There is no package_info_plus
/// dependency to read it at runtime, so keep it in step by hand - testers
/// report bugs against a build, and "1.0.0" alone could not say which.
const String kAppVersionLabel = '1.0.0 (8)';

/// "About Ziren": what the app is, which version, and where to read the Terms of
/// Use and the Data Privacy Notice.
///
/// It used to be a stock alert dialog whose three choices - Terms of Use, Data
/// Privacy Notice, Cancel - were bare text buttons in a row. Nothing about a bare
/// word says it can be pressed, so nobody could tell they were links. Now the two
/// documents are rows you press (a bordered card, an icon, a chevron), everything
/// is centred, and there is one clearly-drawn Close button.
///
/// [onOpenTerms] and [onOpenPrivacy] are called AFTER the dialog has closed, so
/// the document opens over the screen the person came from and not over the
/// dialog.
Future<void> showAboutZirenDialog(
  BuildContext context, {
  required VoidCallback onOpenTerms,
  required VoidCallback onOpenPrivacy,
}) {
  final t = AppLocalizations.of(context);
  return showZirenDialog<void>(
    context,
    // The app's own icon, so this reads as "this app" at a glance.
    leading: ClipRRect(
      borderRadius: BorderRadius.circular(ZirenTokens.radius16),
      child: Image.asset(
        'assets/images/ziren_icon.png',
        width: 68,
        height: 68,
        fit: BoxFit.cover,
        semanticLabel: 'Ziren',
      ),
    ),
    title: 'Ziren',
    message: t.settingsAboutTagline,
    body: Builder(
      builder:
          (dialogContext) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ZirenTokens.space12,
                    vertical: ZirenTokens.space4,
                  ),
                  decoration: BoxDecoration(
                    color: ZirenTokens.surfaceRaised,
                    borderRadius: BorderRadius.circular(ZirenTokens.radius32),
                  ),
                  child: Text(
                    t.settingsAboutVersion(kAppVersionLabel),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: ZirenTokens.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: ZirenTokens.space16),
              // Who is on the other end of a report.
              Container(
                padding: const EdgeInsets.all(ZirenTokens.space12),
                decoration: BoxDecoration(
                  color: ZirenTokens.surfaceRaised,
                  borderRadius: BorderRadius.circular(ZirenTokens.radius16),
                ),
                child: Column(
                  children: [
                    // Wrap, not Row: on a 320dp phone with the system font
                    // turned up, three chips do not fit on one line.
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: ZirenTokens.space8,
                      runSpacing: ZirenTokens.space6,
                      children: [
                        for (final (label, icon, color) in [
                          ('BFP', LucideIcons.flame, ZirenTokens.agencyBFP),
                          ('PNP', LucideIcons.shield, ZirenTokens.agencyPNP),
                          ('MDRRMO', LucideIcons.shield_plus, ZirenTokens.agencyMDRRMO),
                        ])
                          _AgencyMark(label: label, icon: icon, color: color),
                      ],
                    ),
                    const SizedBox(height: ZirenTokens.space8),
                    Text(
                      t.aboutAgencies,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: ZirenTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: ZirenTokens.space16),
              ZirenOptionTile(
                icon: LucideIcons.file_text,
                label: t.settingsAboutTerms,
                onTap: () {
                  Navigator.of(dialogContext).pop();
                  onOpenTerms();
                },
              ),
              const SizedBox(height: ZirenTokens.space10),
              ZirenOptionTile(
                icon: LucideIcons.shield_check,
                label: t.settingsAboutPrivacy,
                onTap: () {
                  Navigator.of(dialogContext).pop();
                  onOpenPrivacy();
                },
              ),
            ],
          ),
    ),
    actions: [ZirenDialogAction<void>(label: t.actionClose, value: null)],
  );
}

class _AgencyMark extends StatelessWidget {
  const _AgencyMark({required this.label, required this.icon, required this.color});

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: ZirenTokens.isDark ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(ZirenTokens.radius32),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }
}
