import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ziren/shared/widgets/ziren_spine.dart';

/// The rail under a report: what has happened, what has not, and - for a report
/// that was cancelled or not accepted - where it stopped.
///
/// A stopped step used to be drawn as a hollow circle, the same picture as a step
/// still to come, so a cancelled report showed a rail that looked as if nothing
/// had ever happened to it.
Widget _host(List<SpineNode> nodes) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: ZirenSpine(nodes: nodes))),
);

void main() {
  testWidgets('a stopped step carries a cross', (tester) async {
    await tester.pumpWidget(
      _host(const [
        SpineNode(title: 'Received', state: SpineState.halted),
        SpineNode(title: 'Being reviewed'),
        SpineNode(title: 'Resolved'),
      ]),
    );
    expect(find.byIcon(LucideIcons.x), findsOneWidget);
    expect(find.byIcon(LucideIcons.check), findsNothing);
  });

  testWidgets('a step still to come stays hollow and unmarked', (tester) async {
    await tester.pumpWidget(
      _host(const [
        SpineNode(title: 'Received', state: SpineState.done),
        SpineNode(title: 'Being reviewed'),
      ]),
    );
    expect(find.byIcon(LucideIcons.check), findsOneWidget);
    expect(find.byIcon(LucideIcons.x), findsNothing);
  });

  testWidgets('a step given its own icon keeps it, stopped or not', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const [
        SpineNode(
          title: 'Received',
          state: SpineState.halted,
          icon: LucideIcons.flag,
        ),
      ]),
    );
    expect(find.byIcon(LucideIcons.flag), findsOneWidget);
    expect(find.byIcon(LucideIcons.x), findsNothing);
  });
}
