import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ziren/shared/theme/app_tokens.dart';
import 'package:ziren/shared/widgets/home_kit.dart';

/// Guards the fix for the entrance that only ever played once.
///
/// The dial lives in a StatefulShellRoute indexedStack branch, which is kept
/// alive across tab switches. The first version started its animation from
/// initState, so leaving Home and coming back never replayed it — the
/// animation ran once per app launch and was effectively invisible.
///
/// go_router mutes inactive branches' tickers, so TickerMode standing in for
/// "this tab is on screen" is what the real app does. These tests assert the
/// chips are away from their resting positions shortly after each arrival.
void main() {
  Widget harness({required bool visible, int replayToken = 0}) {
    return MaterialApp(
      home: Scaffold(
        body: TickerMode(
          enabled: visible,
          child: RadialActionDial(
            centerTitle: 'SOS',
            centerSubtitle: 'EMERGENCY',
            centerCaption: 'Hindi tiyak? Pindutin ito',
            onCenterTap: () {},
            replayToken: replayToken,
            actions: [
              for (var i = 0; i < 6; i++)
                QuickAction(
                  icon: Icons.circle,
                  label: 'Cat$i',
                  color: ZirenTokens.agencyBFP,
                  onTap: () {},
                ),
            ],
            facts: const [],
          ),
        ),
      ),
    );
  }

  /// Distance of the first chip from the centre of the dial.
  double chipOffset(WidgetTester tester) {
    final dial = tester.getCenter(find.byType(RadialActionDial));
    final chip = tester.getCenter(find.text('Cat0'));
    return (chip - dial).distance;
  }

  testWidgets('chips deploy outward on first arrival', (tester) async {
    await tester.pumpWidget(harness(visible: true));
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 120));
    final early = chipOffset(tester);

    await tester.pump(const Duration(milliseconds: 1500));
    final settled = chipOffset(tester);

    expect(
      early,
      lessThan(settled - 8),
      reason: 'chip should still be travelling outward early in the entrance',
    );
  });

  testWidgets('entrance replays when the tab becomes visible again',
      (tester) async {
    await tester.pumpWidget(harness(visible: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    final settled = chipOffset(tester);

    // Leave the tab, then come back.
    await tester.pumpWidget(harness(visible: false));
    await tester.pump();
    await tester.pumpWidget(harness(visible: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(
      chipOffset(tester),
      lessThan(settled - 8),
      reason: 'returning to the tab should restart the deployment',
    );
  });

  testWidgets('bumping replayToken restarts the entrance', (tester) async {
    await tester.pumpWidget(harness(visible: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    final settled = chipOffset(tester);

    await tester.pumpWidget(harness(visible: true, replayToken: 1));
    await tester.pump(const Duration(milliseconds: 120));

    expect(chipOffset(tester), lessThan(settled - 8));
  });
}
