import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ziren/features/responder/presentation/widgets/responder_action_sheets.dart';
import 'package:ziren/l10n/app_localizations.dart';

/// Evaluator finding #36 (2026-10-05): in "What did you find?" the text around
/// "Number of people" did not line up. Each row's controls changed width with
/// its state ("Count" vs minus/number/plus/clear), so labels and numbers sat at
/// different positions row to row.
void main() {
  testWidgets('counted and not-yet-counted rows line up', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: const Scaffold(body: AfterActionSheet(categoryLabel: 'Fire')),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Handled on scene'));
    await tester.pumpAndSettle();

    // Count the first row (Injured); leave "Died" not counted.
    await tester.ensureVisible(find.text('Count').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Count').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Died'));
    await tester.pumpAndSettle();

    final injured = tester.getRect(find.text('Injured'));
    final died = tester.getRect(find.text('Died'));
    expect(injured.left, died.left, reason: 'labels start at the same x');
    final row = find.byWidgetPredicate((w) => w is SizedBox && w.height == 48);
    expect(
      tester.getSize(find.ancestor(of: find.text('Injured'), matching: row)).height,
      tester.getSize(find.ancestor(of: find.text('Died'), matching: row)).height,
      reason: 'every row is the same height',
    );

    // The right edge of each row's controls is the same, counted or not.
    final countButton = tester.getRect(find.widgetWithText(OutlinedButton, 'Count').first);
    final clear = tester.getRect(find.byTooltip(lookupAppLocalizations(const Locale('en')).respNotCounted));
    expect((countButton.right - clear.right).abs(), lessThan(1.0));
  });
}
