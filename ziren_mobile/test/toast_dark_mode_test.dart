// Toasts and snackbars must be readable in both appearances.
//
// Tester screenshot 2026-10-05: in dark mode the responder's "You have accepted
// this. The dispatcher knows." was a blank white strip - the bar was
// textPrimary (near-white in dark) behind textInverse (always white).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ziren/shared/theme/app_tokens.dart';
import 'package:ziren/shared/widgets/ziren_toast.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  tearDown(() => ZirenTokens.setMode(brightness: Brightness.light, highContrast: false));

  for (final brightness in Brightness.values) {
    group('${brightness.name} mode', () {
      setUp(() => ZirenTokens.setMode(brightness: brightness, highContrast: false));

      test('toast words stand out from the bar (WCAG AA, 4.5:1)', () {
        expect(_contrast(ZirenTokens.toastText, ZirenTokens.toastSurface), greaterThanOrEqualTo(4.5));
      });

      testWidgets('ZirenToast paints readable text on its bar', (tester) async {
        await tester.pumpWidget(MaterialApp(
          // ZirenToast sets its own colours; AppTheme is not built here
          // because its Google Fonts would be fetched over the network.
          theme: ThemeData(brightness: brightness),
          home: Scaffold(body: Builder(builder: (context) {
            return TextButton(
              onPressed: () => ZirenToast.success(ScaffoldMessenger.of(context), 'You have accepted this.'),
              child: const Text('go'),
            );
          })),
        ));
        await tester.tap(find.text('go'));
        await tester.pump(const Duration(milliseconds: 500));

        final bar = tester.widget<SnackBar>(find.byType(SnackBar));
        final words = tester.widget<Text>(find.text('You have accepted this.'));
        expect(_contrast(words.style!.color!, bar.backgroundColor!), greaterThanOrEqualTo(4.5));
      });
    });
  }
}
