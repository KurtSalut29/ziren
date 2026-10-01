import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../../shared/widgets/ziren_dialogs.dart';
import '../domain/demo_catalog.dart';
import '../domain/demo_models.dart';
import 'demo_launcher.dart';

/// The first time a NEW account reaches Home, Ziren — excited — says hi by
/// name and offers to demo the app: "Yes, show me" runs the Home demo,
/// "Maybe later" says where the demos live. Asked once per account, never on
/// a later sign-in.
///
/// "Once" is remembered on the account itself (Supabase user metadata, which
/// the user may write to their own record), so a second phone or a reinstall
/// does not ask again; and on the phone, so a choice made offline is not
/// asked twice while the account write waits for a connection.
///
/// "New" means created on or after [WelcomeDemo.since], the day this shipped:
/// accounts that were already using the app are not stopped by it.
abstract final class WelcomeDemo {
  static final DateTime since = DateTime.utc(2026, 10, 1);
  static const String metadataKey = 'ziren_welcome_demo';
  static String _prefsKey(String userId) => 'welcome_demo_done_$userId';

  /// Accounts already checked while the app has been open: Home is built
  /// again on every return to it, and must not ask again.
  static final Set<String> _checked = {};

  /// A build made with `--dart-define=ZIREN_PREVIEW_WELCOME=true` greets any
  /// account, once per launch, and remembers nothing — for showing the
  /// greeting on an account that is not new. Never set for a real build.
  static const bool _preview = bool.fromEnvironment('ZIREN_PREVIEW_WELCOME');

  /// Whether to greet this account. Pure: everything it needs is passed in.
  static bool shouldGreet({
    required String? createdAt,
    required Map<String, dynamic>? metadata,
    required bool doneOnThisPhone,
  }) {
    if (doneOnThisPhone) return false;
    if (metadata?[metadataKey] != null) return false;
    final created = createdAt == null ? null : DateTime.tryParse(createdAt);
    if (created == null) return false;
    return !created.toUtc().isBefore(since);
  }

  /// From Home, once it has drawn: greet the signed-in account if it is new
  /// and has not been greeted. [firstName] may be empty.
  static Future<void> maybeGreet(
    BuildContext context, {
    required bool responder,
    required String firstName,
  }) async {
    final User? user;
    try {
      user = Supabase.instance.client.auth.currentUser;
    } catch (_) {
      return; // Supabase not set up (tests, previews).
    }
    if (user == null || !_checked.add(user.id)) return;

    final prefs = await SharedPreferences.getInstance();
    final doneHere = prefs.getBool(_prefsKey(user.id)) ?? false;
    if (!_preview && doneHere && user.userMetadata?[metadataKey] == null) {
      // Chosen while offline last time: tell the account now.
      unawaited(_remember(user.id, prefs, 'synced'));
    }
    if (!_preview &&
        !shouldGreet(
          createdAt: user.createdAt,
          metadata: user.userMetadata,
          doneOnThisPhone: doneHere,
        )) {
      return;
    }

    // Let Home settle (Ziren fades in on the card first), then wait until
    // Home is what is on screen: nothing on top of it (a form, a sheet, a
    // demo) and not another tab — however long that takes, so a new user who
    // went straight to a report is greeted when they come back.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    while (true) {
      if (!context.mounted) {
        _checked.remove(user.id); // Home went away: ask on its next visit
        return;
      }
      if (_homeShowing(context)) break;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (!context.mounted) return;

    final start = await showWelcomeDemo(
      context,
      responder: responder,
      firstName: firstName,
    );
    if (!_preview) {
      unawaited(_remember(user.id, prefs, start ? 'demo' : 'later'));
    }
    if (start && context.mounted) {
      final DemoScript home =
          (responder ? DemoCatalog.responder() : DemoCatalog.resident()).first;
      await startDemo(context, home);
    }
  }

  /// Home is the top route and its tab is the one on screen (an offstage
  /// tab of the shell has its tickers turned off).
  static bool _homeShowing(BuildContext context) =>
      (ModalRoute.of(context)?.isCurrent ?? true) &&
      TickerMode.getNotifier(context).value;

  static Future<void> _remember(
    String userId,
    SharedPreferences prefs,
    String choice,
  ) async {
    await prefs.setBool(_prefsKey(userId), true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(
          data: {
            metadataKey: {
              'choice': choice,
              'at': DateTime.now().toUtc().toIso8601String(),
            },
          },
        ),
      );
    } catch (_) {
      // Offline: the phone remembers, and the account is told next time.
    }
  }
}

/// The greeting itself. Resolves to true for "Yes, show me"; false for
/// "Maybe later" or the back button.
Future<bool> showWelcomeDemo(
  BuildContext context, {
  required bool responder,
  required String firstName,
}) async {
  final t = AppLocalizations.of(context);
  final name = firstName.trim();
  final choice = await showZirenDialog<bool>(
    context,
    // Only the buttons answer: a stray tap beside the card is not "later".
    barrierDismissible: false,
    leading: const _ExcitedZiren(),
    title: name.isEmpty ? t.welcomeDemoTitleNoName : t.welcomeDemoTitle(name),
    message: responder ? t.welcomeDemoBodyResponder : t.welcomeDemoBodyResident,
    body: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(LucideIcons.info, size: 15, color: ZirenTokens.textMuted),
        ),
        const SizedBox(width: ZirenTokens.space6),
        Expanded(
          child: Text(
            t.welcomeDemoHint(t.helpButtonLabel),
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: ZirenTokens.textMuted,
            ),
          ),
        ),
      ],
    ),
    actions: [
      ZirenDialogAction(
        label: t.welcomeDemoStart,
        value: true,
        kind: ZirenActionKind.primary,
        icon: LucideIcons.play,
      ),
      ZirenDialogAction(label: t.welcomeDemoLater, value: false),
    ],
  );
  return choice ?? false;
}

/// Ziren, excited (from Demo_Mascots.png), on a soft brand glow: hops in,
/// then keeps a gentle bounce while the greeting is up. Still with "Remove
/// animations" on.
class _ExcitedZiren extends StatefulWidget {
  const _ExcitedZiren();

  @override
  State<_ExcitedZiren> createState() => _ExcitedZirenState();
}

class _ExcitedZirenState extends State<_ExcitedZiren>
    with TickerProviderStateMixin {
  late final AnimationController _hop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _hop.value = 1;
      _bob
        ..stop()
        ..value = 0;
    } else if (!_hop.isAnimating && _hop.value == 0) {
      _hop.forward().whenComplete(() {
        if (mounted) _bob.repeat();
      });
    }
  }

  @override
  void dispose() {
    _hop.dispose();
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      height: 150,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            bottom: 4,
            child: Container(
              width: 136,
              height: 136,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    ZirenTokens.brandOrange.withValues(
                      alpha: ZirenTokens.isDark ? 0.28 : 0.20,
                    ),
                    ZirenTokens.brandOrange.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: Listenable.merge([_hop, _bob]),
            builder: (context, child) {
              // In: rises from a little below and grows, overshooting once.
              final hop = Curves.easeOutBack.transform(_hop.value);
              final bob = -5 * math.sin(_bob.value * 2 * math.pi).abs();
              return Opacity(
                opacity: _hop.value.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(0, 24 * (1 - hop) + bob),
                  child: Transform.scale(
                    scale: 0.85 + 0.15 * hop,
                    alignment: Alignment.bottomCenter,
                    child: child,
                  ),
                ),
              );
            },
            child: Image.asset(
              DemoPose.excited.asset,
              height: 140,
              fit: BoxFit.contain,
              semanticLabel: 'Ziren',
            ),
          ),
        ],
      ),
    );
  }
}
