import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Ziren/features/incident_report/presentation/my_reports_screen.dart';
import 'package:Ziren/features/registration/domain/id_photo_check.dart';
import 'package:Ziren/features/registration/presentation/id_check_notice.dart';
import 'package:Ziren/features/registration/presentation/password_requirements.dart';
import 'package:Ziren/features/registration/presentation/registration_shell.dart';
import 'package:Ziren/l10n/app_localizations.dart';
import 'package:Ziren/shared/widgets/ziren_button.dart';

/// "RIGHT OVERFLOWED BY 14 PIXELS" - the yellow-and-black stripe testers saw
/// across the My Reports filter chips on their phones.
///
/// A RenderFlex overflow is a FlutterError in a widget test, so pumping each
/// widget at the sizes real phones have, in both languages and with the system
/// font turned up, and expecting no exception, is the regression test.
///
/// Sizes are logical pixels: 320 is the smallest phone still around (Galaxy
/// A03 Core / older iPhone SE), 360 is the most common Android width - the
/// tester's - and 412 a large one.
const _sizes = <Size>[Size(320, 640), Size(360, 720), Size(412, 915)];
const _scales = <double>[1.0, 1.3, 2.0];
const _locales = <Locale>[Locale('en'), Locale('fil')];

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  required double scale,
  required Locale locale,
  required Widget child,
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder:
          (context, home) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: home!,
          ),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pump();
}

void _everywhere(
  String name,
  Widget Function() build,
  Future<void> Function(WidgetTester tester)? extra,
) {
  for (final size in _sizes) {
    for (final scale in _scales) {
      for (final locale in _locales) {
        testWidgets(
          '$name @ ${size.width.toInt()}dp x$scale ${locale.languageCode}',
          (tester) async {
            await _pump(
              tester,
              size: size,
              scale: scale,
              locale: locale,
              child: build(),
            );
            expect(tester.takeException(), isNull);
            if (extra != null) await extra(tester);
          },
        );
      }
    }
  }
}

void main() {
  _everywhere(
    'My Reports filter chips',
    () => ReportFilterRow(active: ReportFilter.lahat, onChanged: (_) {}),
    (tester) async {
      // Every chip must still be there - wrapped, not dropped.
      expect(find.byType(GestureDetector), findsNWidgets(4));
    },
  );

  _everywhere(
    'registration field label with "Optional"',
    () => const RegField(
      label:
          'Taong tatawagan sa oras ng emergency, kapamilya o kaibigan man',
      optional: true,
      child: SizedBox(height: 40),
    ),
    null,
  );

  _everywhere(
    'password requirements panel',
    () => PasswordRequirements(controller: TextEditingController(text: 'Abc')),
    null,
  );

  _everywhere(
    'ZirenButton with an icon and a long label',
    () => ZirenButton(
      label: 'Ipadala ang ulat sa pinakamalapit na istasyon',
      icon: Icons.send,
      onPressed: () {},
    ),
    null,
  );

  for (final check in [
    IdPhotoCheck.notAnId,
    IdPhotoCheck.wrongType,
    IdPhotoCheck.typeUnconfirmed,
    IdPhotoCheck.noFace,
    IdPhotoCheck.numberMismatch,
  ]) {
    _everywhere(
      'ID refusal notice ($check)',
      () => Builder(
        builder:
            (context) => IdCheckNotice.blocking(
              context,
              check,
              chosenLabel: 'Senior Citizen ID',
              foundLabel: "Driver's License",
            ),
      ),
      null,
    );
  }
}
