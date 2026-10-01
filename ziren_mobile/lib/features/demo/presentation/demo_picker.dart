import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../../shared/theme/app_tokens.dart';
import '../domain/demo_catalog.dart';
import '../domain/demo_models.dart';

/// Help's two ways in: read the steps, or have Ziren show the screen.
enum HelpMode { steps, demo }

/// The choice at the top of Help between the written guide and the demos.
class HelpModeSwitch extends StatelessWidget {
  const HelpModeSwitch({
    super.key,
    required this.mode,
    required this.onChanged,
  });

  final HelpMode mode;
  final ValueChanged<HelpMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    final en = lang == 'en';
    return Row(
      children: [
        Expanded(
          child: _ModeCard(
            key: const Key('help-mode-steps'),
            icon: LucideIcons.list_ordered,
            title: en ? 'Step by step' : 'Hakbang-hakbang',
            caption: en ? 'Read the guides' : 'Basahin ang mga gabay',
            selected: mode == HelpMode.steps,
            onTap: () => onChanged(HelpMode.steps),
          ),
        ),
        const SizedBox(width: ZirenTokens.space10),
        Expanded(
          child: _ModeCard(
            key: const Key('help-mode-demo'),
            icon: LucideIcons.circle_play,
            title: 'Demo',
            caption: en ? 'Ziren shows you' : 'Ipapakita ni Ziren',
            selected: mode == HelpMode.demo,
            onTap: () => onChanged(HelpMode.demo),
          ),
        ),
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    super.key,
    required this.icon,
    required this.title,
    required this.caption,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String caption;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color:
            selected
                ? ZirenTokens.brandOrange.withValues(alpha: 0.10)
                : ZirenTokens.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZirenTokens.radius16),
          side: BorderSide(
            color:
                selected ? ZirenTokens.brandOrange : ZirenTokens.surfaceBorder,
            width: selected ? 1.6 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color:
                        selected
                            ? ZirenTokens.brandOrange
                            : ZirenTokens.brandOrange.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    icon,
                    size: 19,
                    color: selected ? Colors.white : ZirenTokens.brandOrange,
                  ),
                ),
                const SizedBox(width: ZirenTokens.space10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                          color: ZirenTokens.textPrimary,
                        ),
                      ),
                      Text(
                        caption,
                        maxLines: 2,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.25,
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
    );
  }
}

/// The list of screens Ziren can demonstrate for this role.
class DemoPicker extends StatelessWidget {
  const DemoPicker({
    super.key,
    required this.forResponder,
    required this.onStart,
    this.controller,
    this.header,
  });

  final bool forResponder;
  final ValueChanged<DemoScript> onStart;
  final ScrollController? controller;

  /// Drawn above the list (Help puts its mode switch here, so both modes
  /// scroll the same way).
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    final en = lang == 'en';
    final scripts =
        forResponder ? DemoCatalog.responder() : DemoCatalog.resident();
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(
        ZirenTokens.space16,
        ZirenTokens.space12,
        ZirenTokens.space16,
        ZirenTokens.space32,
      ),
      children: [
        if (header != null) ...[
          header!,
          const SizedBox(height: ZirenTokens.space16),
        ],
        _DemoIntro(
          text:
              en
                  ? 'Pick a screen. I will take you there and show you how to use it, one part at a time. Nothing is sent or changed.'
                  : 'Pumili ng screen. Dadalhin kita roon at ituturo ko kung paano ito gamitin, isa-isa. Walang maipapadala o mababago.',
        ),
        const SizedBox(height: ZirenTokens.space16),
        for (final s in scripts) ...[
          _DemoTile(
            script: s,
            lang: lang,
            enabled: s.available?.call(context) ?? true,
            onTap: () => onStart(s),
          ),
          const SizedBox(height: ZirenTokens.space10),
        ],
      ],
    );
  }
}

class _DemoIntro extends StatelessWidget {
  const _DemoIntro({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          width: 78,
          height: 92,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                ZirenTokens.brandOrange.withValues(alpha: 0.22),
                ZirenTokens.brandOrange.withValues(alpha: 0.0),
              ],
            ),
          ),
          alignment: Alignment.bottomCenter,
          child: Image.asset(
            DemoPose.pointRight.asset,
            height: 86,
            fit: BoxFit.contain,
            semanticLabel: 'Ziren',
          ),
        ),
        const SizedBox(width: ZirenTokens.space8),
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(bottom: ZirenTokens.space8),
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
            decoration: BoxDecoration(
              color: ZirenTokens.surfaceCard,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomRight: Radius.circular(18),
                bottomLeft: Radius.circular(6),
              ),
              border: Border.all(color: ZirenTokens.surfaceBorder),
              boxShadow: ZirenTokens.shadowSm,
            ),
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                fontWeight: FontWeight.w700,
                color: ZirenTokens.textPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DemoTile extends StatelessWidget {
  const _DemoTile({
    required this.script,
    required this.lang,
    required this.enabled,
    required this.onTap,
  });

  final DemoScript script;
  final String lang;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = enabled ? ZirenTokens.brandOrange : ZirenTokens.textMuted;
    final reason = enabled ? null : script.unavailable(lang);
    return Material(
      key: Key('demo-${script.id}'),
      color: ZirenTokens.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ZirenTokens.radius16),
        side: BorderSide(color: ZirenTokens.surfaceBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(ZirenTokens.space12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(ZirenTokens.radius12),
                ),
                alignment: Alignment.center,
                child: Icon(script.icon, size: 20, color: tone),
              ),
              const SizedBox(width: ZirenTokens.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      script.title(lang),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color:
                            enabled
                                ? ZirenTokens.textPrimary
                                : ZirenTokens.textMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      reason ?? script.summary(lang),
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color:
                            enabled
                                ? ZirenTokens.textSecondary
                                : ZirenTokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: ZirenTokens.space8),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color:
                      enabled
                          ? ZirenTokens.brandOrange
                          : ZirenTokens.surfaceBorder,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  enabled ? LucideIcons.play : LucideIcons.lock,
                  size: 15,
                  color: enabled ? Colors.white : ZirenTokens.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
