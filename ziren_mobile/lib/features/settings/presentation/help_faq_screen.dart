import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/profile_kit.dart';

/// Help & FAQ: common questions, one answer open at a time, then the ways to
/// get more help (the step-by-step guide, the station hotlines).
///
/// It used to be a bottom sheet of four questions in plain text, two of whose
/// answers were no longer true (it still sent residents to an SOS button and a
/// Report tab, and said a report was impossible without internet - the app now
/// shows the station hotlines then).
class HelpFaqScreen extends StatefulWidget {
  const HelpFaqScreen({super.key, this.forResponder = false});

  /// Opens the responder's version of the guide from the "Still need help?"
  /// row.
  final bool forResponder;

  @override
  State<HelpFaqScreen> createState() => _HelpFaqScreenState();
}

class _HelpFaqScreenState extends State<HelpFaqScreen> {
  int? _open = 0;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final entries = <(IconData, String, String)>[
      (LucideIcons.siren, t.settingsFaqReportQ, t.settingsFaqReportA),
      (LucideIcons.wifi_off, t.settingsFaqOfflineQ, t.settingsFaqOfflineA),
      (LucideIcons.building, t.settingsFaqAgencyQ, t.settingsFaqAgencyA),
      (LucideIcons.landmark, t.settingsFaqLandmarkQ, t.settingsFaqLandmarkA),
      (LucideIcons.map_pinned, t.settingsFaqElsewhereQ, t.settingsFaqElsewhereA),
      (LucideIcons.activity, t.settingsFaqTrackQ, t.settingsFaqTrackA),
      (LucideIcons.contact, t.settingsFaqAccountQ, t.settingsFaqAccountA),
      (LucideIcons.badge_check, t.settingsFaqVerifyQ, t.settingsFaqVerifyA),
    ];

    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      appBar: AppBar(
        backgroundColor: ZirenTokens.surfaceBase,
        title: Text(t.settingsHelpFaq),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          ZirenTokens.space16,
          ZirenTokens.space8,
          ZirenTokens.space16,
          ZirenTokens.space32,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: ZirenTokens.space4,
              bottom: ZirenTokens.space12,
            ),
            child: Text(
              t.faqIntro,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: ZirenTokens.textSecondary,
              ),
            ),
          ),
          for (var i = 0; i < entries.length; i++) ...[
            _FaqCard(
              icon: entries[i].$1,
              question: entries[i].$2,
              answer: entries[i].$3,
              open: _open == i,
              onToggle: () => setState(() => _open = _open == i ? null : i),
            ),
            const SizedBox(height: ZirenTokens.space10),
          ],
          const SizedBox(height: ZirenTokens.space16),
          ProfileGroup(
            title: t.faqStillNeedHelp,
            children: [
              ProfileTile(
                icon: LucideIcons.life_buoy,
                tone: ZirenTokens.systemInfo,
                label: t.helpTitle,
                onTap:
                    () => context.push(
                      widget.forResponder ? '/help?role=responder' : '/help',
                    ),
              ),
              ProfileTile(
                icon: LucideIcons.phone_call,
                tone: ZirenTokens.systemSuccess,
                label: t.hotlinesTitle,
                onTap: () => context.push('/hotlines'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FaqCard extends StatelessWidget {
  const _FaqCard({
    required this.icon,
    required this.question,
    required this.answer,
    required this.open,
    required this.onToggle,
  });

  final IconData icon;
  final String question;
  final String answer;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: ZirenTokens.motionBase,
      clipBehavior: Clip.antiAlias,
      decoration: profileCardDecoration().copyWith(
        border: Border.all(
          color:
              open
                  ? ZirenTokens.brandOrange.withValues(alpha: 0.45)
                  : ZirenTokens.surfaceBorder.withValues(alpha: 0.8),
          width: open ? 1.4 : 1,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              button: true,
              expanded: open,
              child: InkWell(
                onTap: onToggle,
                child: Padding(
                  padding: const EdgeInsets.all(ZirenTokens.space12),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color:
                              open
                                  ? ZirenTokens.brandOrange.withValues(
                                    alpha: 0.12,
                                  )
                                  : ZirenTokens.surfaceRaised,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          icon,
                          size: 18,
                          color:
                              open
                                  ? ZirenTokens.brandOrange
                                  : ZirenTokens.textSecondary,
                        ),
                      ),
                      const SizedBox(width: ZirenTokens.space12),
                      Expanded(
                        child: Text(
                          question,
                          style: TextStyle(
                            fontSize: 14.5,
                            height: 1.3,
                            fontWeight: FontWeight.w700,
                            color: ZirenTokens.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: ZirenTokens.space8),
                      AnimatedRotation(
                        turns: open ? 0.5 : 0,
                        duration: ZirenTokens.motionBase,
                        child: Icon(
                          LucideIcons.chevron_down,
                          size: 18,
                          color: ZirenTokens.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (open)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  62,
                  0,
                  ZirenTokens.space16,
                  ZirenTokens.space16,
                ),
                child: Text(
                  answer,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.5,
                    color: ZirenTokens.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
