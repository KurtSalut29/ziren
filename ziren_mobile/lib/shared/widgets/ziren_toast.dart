import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../theme/app_tokens.dart';
import 'ziren_dialogs.dart' show ZirenTone, ZirenToneColors;

/// One place a "that worked" or "that failed" message is shown.
///
/// A plain [SnackBar] is white text on a dark bar with nothing to say what kind
/// of message it is, and on the tabs it was drawn UNDER the floating bottom
/// navigation - a tester's screenshot of "Report moved to Trash." shows the words
/// cut off behind the nav. This one has an icon in the message's own colour,
/// wraps to two lines instead of clipping, and sits above the navigation bar.
///
/// SAY WHAT THE PERSON DID
///
/// The wording is the caller's, and the rule for it is the point of this helper
/// existing: a toast reports the action just taken, in its own terms - "Moved to
/// Trash. It will be permanently deleted in 30 days.", not "Report updated".
class ZirenToast {
  const ZirenToast._();

  /// How far above the bottom edge the tab shell's floating navigation reaches.
  /// Set by the shell while it is on screen; zero elsewhere.
  static double shellInset = 0;

  static void show(
    ScaffoldMessengerState messenger,
    String message, {
    IconData? icon,
    ZirenTone tone = ZirenTone.neutral,
    Duration duration = const Duration(seconds: 5),
  }) {
    // Colours are set here, not left to the theme: in dark mode the theme's
    // old bar was near-white behind white text, and this widget is what every
    // "that worked" message goes through.
    final color = tone == ZirenTone.neutral ? ZirenTokens.toastText : tone.color;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: duration,
          behavior: SnackBarBehavior.floating,
          backgroundColor: ZirenTokens.toastSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ZirenTokens.radius12),
            side: BorderSide(color: ZirenTokens.toastBorder),
          ),
          margin: EdgeInsets.fromLTRB(
            ZirenTokens.space16,
            0,
            ZirenTokens.space16,
            shellInset + ZirenTokens.space12,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: ZirenTokens.space16,
            vertical: ZirenTokens.space12,
          ),
          content: Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 16, color: color),
                ),
                const SizedBox(width: ZirenTokens.space12),
              ],
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.35,
                    color: ZirenTokens.toastText,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }

  /// A completed action.
  static void success(ScaffoldMessengerState m, String message, {IconData? icon}) =>
      show(m, message, icon: icon ?? LucideIcons.circle_check, tone: ZirenTone.success);

  /// Something for the person to notice, not an error.
  static void notice(ScaffoldMessengerState m, String message, {IconData? icon}) =>
      show(m, message, icon: icon ?? LucideIcons.info, tone: ZirenTone.info);

  /// The action did not happen.
  static void error(ScaffoldMessengerState m, String message) =>
      show(m, message, icon: LucideIcons.circle_alert, tone: ZirenTone.danger);
}
