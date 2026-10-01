import 'package:flutter/widgets.dart';

import '../domain/demo_models.dart';
import 'demo_anchor.dart';
import 'demo_tour.dart';

/// Opens [script]'s screen and runs its tour there.
///
/// Uses the root navigator's context, which outlives the help sheet the demo
/// was chosen from (the sheet is closed before this runs).
Future<void> startDemo(BuildContext context, DemoScript script) async {
  final root = Navigator.of(context, rootNavigator: true).context;
  await script.open(root);

  // Wait for the screen to build: any of the script's anchors on screen means
  // it is up. A step whose part of the screen is not there today (no alerts,
  // an empty list) is still shown, from the middle of the screen.
  final anchors =
      script.screenAnchor != null
          ? {script.screenAnchor!}
          : script.steps.map((s) => s.anchor).whereType<String>().toSet();
  for (var i = 0; i < 30 && anchors.isNotEmpty; i++) {
    if (anchors.any(DemoAnchors.isMounted)) break;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  // The push transition settles before anything is measured.
  await Future<void>.delayed(const Duration(milliseconds: 350));
  if (!root.mounted) return;
  await showDemoTour(root, script);
}
