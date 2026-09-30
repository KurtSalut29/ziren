import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../l10n/app_localizations.dart';
import '../theme/app_tokens.dart';

/// One look for every confirmation, notice and choice in the app.
///
/// WHY THIS EXISTS
///
/// The app's dialogs were Material's stock [AlertDialog]: a left-aligned title,
/// and the choices as bare text buttons crowded onto the right of the last line.
/// A bare text button is a word with no shape - nothing about it says it can be
/// pressed - and "Terms of Use", "Data Privacy Notice" and "Cancel" sitting in a
/// row read as three captions, not three things to tap. A tester could not tell
/// whether they were clickable.
///
/// Every choice here is drawn as something you press: a filled or outlined
/// button, full width, at least 48 logical pixels tall, or - where the choice is
/// "go and read this" - a bordered row with an icon and a chevron. Everything is
/// centred, and it scrolls instead of overflowing on a small screen or a large
/// system font.
///
/// TONE
///
/// Colour follows the app's rules: red only for something destructive or
/// dangerous, brand orange for the action the screen wants, green for a
/// completed or resolving action, blue for information.
enum ZirenTone { brand, danger, success, info, warning, neutral }

extension ZirenToneColors on ZirenTone {
  Color get color => switch (this) {
    ZirenTone.brand => ZirenTokens.brandOrange,
    ZirenTone.danger => ZirenTokens.systemError,
    ZirenTone.success => ZirenTokens.systemSuccess,
    ZirenTone.info => ZirenTokens.systemInfo,
    ZirenTone.warning => ZirenTokens.systemWarning,
    ZirenTone.neutral => ZirenTokens.textSecondary,
  };
}

/// How prominent an action is. Exactly one [primary] or [danger] per dialog is
/// the norm; the rest are [secondary] (an outlined button).
enum ZirenActionKind { primary, danger, success, secondary }

class ZirenDialogAction<T> {
  const ZirenDialogAction({
    required this.label,
    required this.value,
    this.kind = ZirenActionKind.secondary,
    this.icon,
  });

  final String label;

  /// What the dialog resolves to when this is pressed.
  final T value;
  final ZirenActionKind kind;
  final IconData? icon;
}

/// Show a dialog: an optional icon (or [leading] widget) in a tinted circle, a
/// centred title and message, an optional [body], and stacked full-width
/// actions. Resolves to the pressed action's value, or null if dismissed.
///
/// [horizontalActions] lays two short actions side by side instead, in the
/// order given (put Cancel first so the confirming action sits on the right).
/// Only for short labels: each button gets half the width.
Future<T?> showZirenDialog<T>(
  BuildContext context, {
  IconData? icon,
  Widget? leading,
  ZirenTone tone = ZirenTone.brand,
  Color? accent,
  required String title,
  String? message,
  Widget? body,
  required List<ZirenDialogAction<T>> actions,
  bool horizontalActions = false,
  bool barrierDismissible = true,
}) {
  // showGeneralDialog rather than showDialog: a plain dialog route has no
  // room to blur what is behind it, and this app's one dialog primitive is
  // worth a deliberate arrival rather than the stock instant fade.
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: ZirenTokens.motionEntrance,
    pageBuilder:
        (dialogContext, animation, secondaryAnimation) => ZirenDialog<T>(
          icon: icon,
          leading: leading,
          tone: tone,
          accent: accent,
          title: title,
          message: message,
          body: body,
          actions: actions,
          horizontalActions: horizontalActions,
        ),
    transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: ZirenTokens.curveStandard);
      return AnimatedBuilder(
        animation: curved,
        // A blur this small (max 4px) is a hint of depth, not a filter
        // effect — cheap enough to run for the life of a short confirm
        // dialog on the modest hardware this app's responders actually
        // carry into the field.
        builder:
            (context, dialogChild) => BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 4 * curved.value, sigmaY: 4 * curved.value),
              child: FadeTransition(
                opacity: curved,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
                  child: dialogChild,
                ),
              ),
            ),
        child: child,
      );
    },
  );
}

class ZirenDialog<T> extends StatelessWidget {
  const ZirenDialog({
    super.key,
    this.icon,
    this.leading,
    this.tone = ZirenTone.brand,
    this.accent,
    required this.title,
    this.message,
    this.body,
    required this.actions,
    this.horizontalActions = false,
  });

  final IconData? icon;
  final Widget? leading;
  final ZirenTone tone;

  /// An exact colour for the icon and the main button, when a tone is not
  /// specific enough (a notice takes the colour of its own status).
  final Color? accent;
  final String title;
  final String? message;
  final Widget? body;
  final List<ZirenDialogAction<T>> actions;
  final bool horizontalActions;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? tone.color;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: ZirenTokens.space16,
        vertical: ZirenTokens.space24,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Container(
          decoration: BoxDecoration(
            color: ZirenTokens.surfaceOverlay,
            borderRadius: BorderRadius.circular(ZirenTokens.radius24),
            border: Border.all(color: ZirenTokens.surfaceBorder),
            boxShadow: ZirenTokens.shadowLg,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              ZirenTokens.space24,
              ZirenTokens.space24,
              ZirenTokens.space24,
              ZirenTokens.space20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (leading != null)
                  Center(child: leading)
                else if (icon != null)
                  Center(
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: ZirenTokens.isDark ? 0.18 : 0.28),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Icon(icon, color: color, size: 28),
                    ),
                  ),
                if (leading != null || icon != null)
                  const SizedBox(height: ZirenTokens.space16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 19,
                    height: 1.25,
                    fontWeight: FontWeight.w800,
                    color: ZirenTokens.textPrimary,
                  ),
                ),
                if (message != null && message!.isNotEmpty) ...[
                  const SizedBox(height: ZirenTokens.space8),
                  Text(
                    message!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.45,
                      color: ZirenTokens.textSecondary,
                    ),
                  ),
                ],
                if (body != null) ...[
                  const SizedBox(height: ZirenTokens.space16),
                  body!,
                ],
                const SizedBox(height: ZirenTokens.space20),
                if (horizontalActions)
                  Row(
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(width: ZirenTokens.space10),
                        Expanded(
                          child: _ActionButton<T>(action: actions[i], accent: color),
                        ),
                      ],
                    ],
                  )
                else
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(height: ZirenTokens.space10),
                    _ActionButton<T>(action: actions[i], accent: color),
                  ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton<T> extends StatelessWidget {
  const _ActionButton({required this.action, required this.accent});

  final ZirenDialogAction<T> action;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      action.label,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(ZirenTokens.radius12),
    );
    const size = Size.fromHeight(50);
    void pop() => Navigator.of(context).pop(action.value);

    Widget filled(Color bg) {
      final style = ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: Colors.white,
        minimumSize: size,
        elevation: 0,
        shape: shape,
      );
      return action.icon == null
          ? ElevatedButton(onPressed: pop, style: style, child: label)
          : ElevatedButton.icon(
            onPressed: pop,
            style: style,
            icon: Icon(action.icon, size: 18),
            label: label,
          );
    }

    switch (action.kind) {
      case ZirenActionKind.primary:
        return filled(
          accent == ZirenTokens.systemError ? ZirenTokens.brandOrange : accent,
        );
      case ZirenActionKind.danger:
        return filled(ZirenTokens.systemError);
      case ZirenActionKind.success:
        return filled(ZirenTokens.systemSuccess);
      case ZirenActionKind.secondary:
        final style = OutlinedButton.styleFrom(
          foregroundColor: ZirenTokens.textPrimary,
          minimumSize: size,
          shape: shape,
          side: BorderSide(color: ZirenTokens.surfaceBorder, width: 1.4),
        );
        return action.icon == null
            ? OutlinedButton(onPressed: pop, style: style, child: label)
            : OutlinedButton.icon(
              onPressed: pop,
              style: style,
              icon: Icon(action.icon, size: 18),
              label: label,
            );
    }
  }
}

/// A row that is obviously pressable: a bordered card with an icon in a tinted
/// circle, a label, and a chevron (or a tick when it is the current choice).
///
/// Used wherever the choice is "go and read this" or "pick one of these" - the
/// links in About Ziren, the language list, the photo-source sheets.
class ZirenOptionTile extends StatelessWidget {
  const ZirenOptionTile({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    this.onTap,
    this.tone = ZirenTone.neutral,
    this.selected = false,
    this.showChevron = true,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;
  final ZirenTone tone;

  /// The current choice in a list of alternatives: brand border and a tick.
  final bool selected;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final color = tone == ZirenTone.neutral ? ZirenTokens.textSecondary : tone.color;
    final danger = tone == ZirenTone.danger;
    return Semantics(
      button: true,
      selected: selected,
      label: subtitle == null ? label : '$label. $subtitle',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: selected
            ? ZirenTokens.brandOrange.withValues(alpha: 0.07)
            : ZirenTokens.surfaceCard,
        borderRadius: BorderRadius.circular(ZirenTokens.radius16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(ZirenTokens.radius16),
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(
              horizontal: ZirenTokens.space12,
              vertical: ZirenTokens.space10,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ZirenTokens.radius16),
              border: Border.all(
                color: selected
                    ? ZirenTokens.brandOrange
                    : danger
                    ? ZirenTokens.systemError.withValues(alpha: 0.45)
                    : ZirenTokens.surfaceBorder,
                width: selected ? 1.6 : 1.2,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 18, color: color),
                ),
                const SizedBox(width: ZirenTokens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: danger
                              ? ZirenTokens.systemError
                              : ZirenTokens.textPrimary,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.3,
                            color: ZirenTokens.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (selected)
                  const Icon(
                    LucideIcons.circle_check,
                    size: 20,
                    color: ZirenTokens.brandOrange,
                  )
                else if (showChevron && onTap != null)
                  Icon(
                    LucideIcons.chevron_right,
                    size: 18,
                    color: ZirenTokens.textMuted,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One entry of [showZirenOptionSheet].
class ZirenSheetOption<T> {
  const ZirenSheetOption({
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
    this.tone = ZirenTone.neutral,
  });

  final IconData icon;
  final String label;
  final T value;
  final String? subtitle;
  final ZirenTone tone;
}

/// A bottom sheet of choices: a centred title, one [ZirenOptionTile] per option
/// and a full-width Cancel. Resolves to the chosen option's value, or null.
Future<T?> showZirenOptionSheet<T>(
  BuildContext context, {
  required String title,
  String? message,
  required List<ZirenSheetOption<T>> options,
  String? cancelLabel,
}) {
  final cancel = cancelLabel ?? AppLocalizations.of(context).settingsCancel;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: ZirenTokens.surfaceOverlay,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(ZirenTokens.radius24),
      ),
    ),
    builder:
        (sheetContext) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              ZirenTokens.space20,
              ZirenTokens.space12,
              ZirenTokens.space20,
              ZirenTokens.space16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: ZirenTokens.surfaceBorder,
                      borderRadius: BorderRadius.circular(ZirenTokens.radius4),
                    ),
                  ),
                ),
                const SizedBox(height: ZirenTokens.space16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: ZirenTokens.textPrimary,
                  ),
                ),
                if (message != null && message.isNotEmpty) ...[
                  const SizedBox(height: ZirenTokens.space4),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.4,
                      color: ZirenTokens.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: ZirenTokens.space16),
                for (final option in options) ...[
                  ZirenOptionTile(
                    icon: option.icon,
                    label: option.label,
                    subtitle: option.subtitle,
                    tone: option.tone,
                    onTap: () => Navigator.of(sheetContext).pop(option.value),
                  ),
                  const SizedBox(height: ZirenTokens.space10),
                ],
                const SizedBox(height: ZirenTokens.space4),
                OutlinedButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ZirenTokens.textPrimary,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(ZirenTokens.radius12),
                    ),
                    side: BorderSide(
                      color: ZirenTokens.surfaceBorder,
                      width: 1.4,
                    ),
                  ),
                  child: Text(
                    cancel,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
  );
}
