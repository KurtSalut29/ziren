import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/profile_kit.dart';
import '../../demo/presentation/demo_launcher.dart';
import '../../demo/domain/demo_models.dart';
import '../../demo/presentation/demo_picker.dart';
import '../domain/help_content.dart';

/// "How to use Ziren": short, step-by-step topics, one open at a time.
///
/// [forResponder] picks the responder's topics (duty, accept, status,
/// distress …) instead of the resident's (report, hotlines, tracking …).
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key, this.forResponder = false});

  final bool forResponder;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      appBar: AppBar(
        backgroundColor: ZirenTokens.surfaceBase,
        title: Text(AppLocalizations.of(context).helpTitle),
      ),
      body: HelpWithDemo(
        forResponder: forResponder,
        // A demo opens its own screen; this page steps out of the way first.
        beforeDemo: () => Navigator.of(context).maybePop(),
      ),
    );
  }
}

/// Help with its two ways in: the written step-by-step guide (unchanged), or
/// a demo, where Ziren takes the user to a screen and shows it part by part.
/// Shared by the Help screen and the Home help sheet.
class HelpWithDemo extends StatefulWidget {
  const HelpWithDemo({
    super.key,
    this.forResponder = false,
    this.controller,
    this.showIntro = true,
    this.beforeNavigate,
    this.beforeDemo,
  });

  final bool forResponder;
  final ScrollController? controller;
  final bool showIntro;

  /// Runs before a guide topic opens another screen.
  final VoidCallback? beforeNavigate;

  /// Runs before a demo starts (the sheet closes; the Help page pops).
  final VoidCallback? beforeDemo;

  @override
  State<HelpWithDemo> createState() => _HelpWithDemoState();
}

class _HelpWithDemoState extends State<HelpWithDemo> {
  HelpMode _mode = HelpMode.steps;

  void _start(DemoScript script) {
    // Taken before the sheet or page goes: the root navigator outlives both.
    final root = Navigator.of(context, rootNavigator: true).context;
    widget.beforeDemo?.call();
    startDemo(root, script);
  }

  @override
  Widget build(BuildContext context) {
    final header = HelpModeSwitch(
      mode: _mode,
      onChanged: (m) => setState(() => _mode = m),
    );
    return _mode == HelpMode.steps
        ? HelpGuide(
          forResponder: widget.forResponder,
          controller: widget.controller,
          showIntro: widget.showIntro,
          beforeNavigate: widget.beforeNavigate,
          header: header,
        )
        : DemoPicker(
          forResponder: widget.forResponder,
          controller: widget.controller,
          header: header,
          onStart: _start,
        );
  }
}

/// The guide itself: intro, the topics (one open at a time) and the way out
/// to the hotlines. Shared by the Help screen and the Home help sheet.
///
/// [beforeNavigate] runs before a topic's "Try it" or the hotlines button
/// opens another screen - the sheet closes itself there, so the screen the
/// resident asked for is not hidden behind it.
class HelpGuide extends StatefulWidget {
  const HelpGuide({
    super.key,
    this.forResponder = false,
    this.controller,
    this.showIntro = true,
    this.beforeNavigate,
    this.header,
  });

  final bool forResponder;
  final ScrollController? controller;
  final bool showIntro;
  final VoidCallback? beforeNavigate;

  /// Drawn first in the list (the step-by-step / demo switch).
  final Widget? header;

  @override
  State<HelpGuide> createState() => _HelpGuideState();
}

class _HelpGuideState extends State<HelpGuide> {
  int? _open = 0;

  void _go(String route) {
    final router = GoRouter.of(context);
    widget.beforeNavigate?.call();
    router.push(route);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final topics =
        widget.forResponder
            ? HelpContent.responder(lang)
            : HelpContent.resident(lang);

    return ListView(
      controller: widget.controller,
      padding: const EdgeInsets.fromLTRB(
        ZirenTokens.space16,
        ZirenTokens.space8,
        ZirenTokens.space16,
        ZirenTokens.space32,
      ),
      children: [
        if (widget.header != null) ...[
          widget.header!,
          const SizedBox(height: ZirenTokens.space16),
        ],
        if (widget.showIntro) ...[
          _IntroCard(
            text:
                widget.forResponder
                    ? t.helpIntroResponder
                    : t.helpIntroResident,
          ),
          const SizedBox(height: ZirenTokens.space20),
        ],
        for (var i = 0; i < topics.length; i++) ...[
          _TopicCard(
            index: i + 1,
            topic: topics[i],
            open: _open == i,
            onToggle: () => setState(() => _open = _open == i ? null : i),
            onRoute: _go,
          ),
          const SizedBox(height: ZirenTokens.space10),
        ],
        const SizedBox(height: ZirenTokens.space10),
        _StillStuckCard(label: t.helpStillStuck, onTap: () => _go('/hotlines')),
      ],
    );
  }
}

/// The mascot and one sentence about what this guide is for.
class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        ZirenTokens.space12,
        ZirenTokens.space12,
        ZirenTokens.space16,
        ZirenTokens.space12,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ZirenTokens.brandOrange.withValues(
              alpha: ZirenTokens.isDark ? 0.22 : 0.14,
            ),
            ZirenTokens.brandOrange.withValues(
              alpha: ZirenTokens.isDark ? 0.08 : 0.04,
            ),
          ],
        ),
        borderRadius: BorderRadius.circular(ZirenTokens.radius20),
        border: Border.all(
          color: ZirenTokens.brandOrange.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        children: [
          Image.asset('assets/images/mascot_help.png', width: 64, height: 64),
          const SizedBox(width: ZirenTokens.space12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                fontWeight: FontWeight.w600,
                color: ZirenTokens.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Still stuck? Call a station" - the way out when the guide is not enough.
class _StillStuckCard extends StatelessWidget {
  const _StillStuckCard({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: profileCardDecoration(),
      child: Material(
        type: MaterialType.transparency,
        child: ProfileTile(
          icon: LucideIcons.phone_call,
          tone: ZirenTokens.systemSuccess,
          label: label,
          onTap: onTap,
        ),
      ),
    );
  }
}

class _TopicCard extends StatelessWidget {
  const _TopicCard({
    required this.index,
    required this.topic,
    required this.open,
    required this.onToggle,
    required this.onRoute,
  });

  final int index;
  final HelpTopic topic;
  final bool open;
  final VoidCallback onToggle;
  final ValueChanged<String> onRoute;

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
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color:
                              open
                                  ? ZirenTokens.brandOrange.withValues(
                                    alpha: 0.12,
                                  )
                                  : ZirenTokens.surfaceRaised,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          topic.icon,
                          size: 20,
                          color:
                              open
                                  ? ZirenTokens.brandOrange
                                  : ZirenTokens.textSecondary,
                        ),
                      ),
                      const SizedBox(width: ZirenTokens.space12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              topic.title,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                color: ZirenTokens.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              topic.summary,
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.35,
                                color: ZirenTokens.textSecondary,
                              ),
                            ),
                          ],
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
                  ZirenTokens.space12,
                  0,
                  ZirenTokens.space12,
                  ZirenTokens.space16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Divider(height: 1, color: ZirenTokens.surfaceBorder),
                    const SizedBox(height: ZirenTokens.space16),
                    for (var i = 0; i < topic.steps.length; i++)
                      _Step(
                        number: i + 1,
                        text: topic.steps[i],
                        last: i == topic.steps.length - 1,
                      ),
                    if (topic.tip != null) ...[
                      const SizedBox(height: ZirenTokens.space4),
                      Container(
                        padding: const EdgeInsets.all(ZirenTokens.space12),
                        decoration: BoxDecoration(
                          color: ZirenTokens.systemInfoBg,
                          borderRadius: BorderRadius.circular(
                            ZirenTokens.radius12,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              LucideIcons.lightbulb,
                              size: 16,
                              color: ZirenTokens.systemInfo,
                            ),
                            const SizedBox(width: ZirenTokens.space8),
                            Expanded(
                              child: Text(
                                topic.tip!,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.45,
                                  color: ZirenTokens.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (topic.route != null) ...[
                      const SizedBox(height: ZirenTokens.space12),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () => onRoute(topic.route!),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: ZirenTokens.brandOrange,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  topic.routeLabel ?? '',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: ZirenTokens.space8),
                              const Icon(LucideIcons.arrow_right, size: 17),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A numbered step, joined to the next by a thin line so the steps read as
/// one sequence rather than a list of separate facts.
class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text, required this.last});

  final int number;
  final String text;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 26,
            child: Column(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: const BoxDecoration(
                    color: ZirenTokens.brandOrange,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$number',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      color: ZirenTokens.brandOrange.withValues(alpha: 0.25),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: ZirenTokens.space12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                top: 3,
                bottom: last ? ZirenTokens.space12 : ZirenTokens.space16,
              ),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: ZirenTokens.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
