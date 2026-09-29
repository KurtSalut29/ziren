import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
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
      appBar: AppBar(title: Text(AppLocalizations.of(context).helpTitle)),
      body: HelpGuide(forResponder: forResponder),
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
  });

  final bool forResponder;
  final ScrollController? controller;
  final bool showIntro;
  final VoidCallback? beforeNavigate;

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
        ZirenTokens.space12,
        ZirenTokens.space16,
        ZirenTokens.space24,
      ),
      children: [
        if (widget.showIntro) ...[
          Container(
            padding: const EdgeInsets.all(ZirenTokens.space16),
            decoration: BoxDecoration(
              color: ZirenTokens.brandOrange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(ZirenTokens.radius16),
              border: Border.all(
                color: ZirenTokens.brandOrange.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                Image.asset(
                  'assets/images/mascot_help.png',
                  width: 44,
                  height: 44,
                ),
                const SizedBox(width: ZirenTokens.space12),
                Expanded(
                  child: Text(
                    widget.forResponder
                        ? t.helpIntroResponder
                        : t.helpIntroResident,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.4,
                      color: ZirenTokens.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: ZirenTokens.space16),
        ],
        for (var i = 0; i < topics.length; i++) ...[
          _TopicCard(
            topic: topics[i],
            open: _open == i,
            onToggle: () => setState(() => _open = _open == i ? null : i),
            onRoute: _go,
          ),
          const SizedBox(height: ZirenTokens.space10),
        ],
        const SizedBox(height: ZirenTokens.space8),
        OutlinedButton.icon(
          icon: Icon(
            LucideIcons.phone,
            size: 18,
            color: ZirenTokens.systemSuccess,
          ),
          label: Text(t.helpStillStuck),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            foregroundColor: ZirenTokens.textPrimary,
          ),
          onPressed: () => _go('/hotlines'),
        ),
      ],
    );
  }
}

class _TopicCard extends StatelessWidget {
  const _TopicCard({
    required this.topic,
    required this.open,
    required this.onToggle,
    required this.onRoute,
  });

  final HelpTopic topic;
  final bool open;
  final VoidCallback onToggle;
  final ValueChanged<String> onRoute;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ZirenTokens.surfaceCard,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ZirenTokens.radius16),
        side: BorderSide(
          color:
              open
                  ? ZirenTokens.brandOrange.withValues(alpha: 0.5)
                  : ZirenTokens.surfaceBorder,
          width: open ? 1.4 : 1,
        ),
      ),
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
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: ZirenTokens.brandOrange.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        topic.icon,
                        size: 19,
                        color: ZirenTokens.brandOrange,
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
                    Icon(
                      open ? LucideIcons.chevron_up : LucideIcons.chevron_down,
                      size: 18,
                      color: ZirenTokens.textMuted,
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
                ZirenTokens.space12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Divider(height: 1, color: ZirenTokens.surfaceBorder),
                  const SizedBox(height: ZirenTokens.space12),
                  for (var i = 0; i < topic.steps.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: ZirenTokens.space10,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: ZirenTokens.brandOrange,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: ZirenTokens.space10),
                          Expanded(
                            child: Text(
                              topic.steps[i],
                              style: TextStyle(
                                fontSize: 13.5,
                                height: 1.45,
                                color: ZirenTokens.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (topic.tip != null)
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.all(ZirenTokens.space10),
                      decoration: BoxDecoration(
                        color: ZirenTokens.systemInfo.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(
                          ZirenTokens.radius12,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
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
                                height: 1.4,
                                color: ZirenTokens.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (topic.route != null) ...[
                    const SizedBox(height: ZirenTokens.space12),
                    ElevatedButton.icon(
                      icon: const Icon(LucideIcons.arrow_right, size: 16),
                      label: Text(topic.routeLabel ?? ''),
                      onPressed: () => onRoute(topic.route!),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
