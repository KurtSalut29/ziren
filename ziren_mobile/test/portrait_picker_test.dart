// The 2x2 ID photo picker, in both screens that collect identity evidence:
// a refused photo is never reported as accepted, and a photo accepted against
// one selfie is checked again when the selfie changes.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ziren/features/registration/data/face_match_client.dart';
import 'package:ziren/features/registration/data/portrait_check_service.dart';
import 'package:ziren/features/registration/domain/portrait_check.dart';
import 'package:ziren/features/registration/presentation/portrait_picker.dart';
import 'package:ziren/l10n/app_localizations.dart';

/// Answers from a script instead of ML Kit and the server.
class _FakeChecks extends PortraitCheckService {
  _FakeChecks(this.answer);

  PortraitResult Function(String? selfie) answer;
  final selfiesSeen = <String?>[];

  @override
  Future<PortraitResult> check({
    required String portraitPath,
    required String? selfiePath,
  }) async {
    selfiesSeen.add(selfiePath);
    return answer(selfiePath);
  }

  @override
  Future<void> dispose() async {}
}

const _facts = PortraitFacts(faceCount: 1, faceRatio: 0.2, yaw: 1, roll: 0);

PortraitResult _matched(String verdict) => PortraitResult(
  facts: _facts,
  match: FaceMatchResult(verdict: verdict, message: '', score: 0.7, model: 'm'),
  problem: judgePortraitMatch(verdict),
);

late String photo;

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  setUpAll(() {
    // A real (1 x 1 PNG) file, so Image.file has something to open.
    final dir = Directory.systemTemp.createTempSync('portrait_test');
    photo = '${dir.path}/2x2.png';
    File(photo).writeAsBytesSync(const [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
      0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
      0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ]);
  });

  testWidgets('empty: the guide, and both ways to add a photo', (tester) async {
    await tester.pumpWidget(_app(PortraitPicker(selfiePath: 's', onChanged: (_, __) {})));
    expect(find.text('Like a 2x2 ID photo'), findsOneWidget);
    expect(find.text('Plain background, like a white wall'), findsOneWidget);
    expect(find.text('Take a photo'), findsOneWidget);
    expect(find.text('Choose from gallery'), findsOneWidget);
  });

  testWidgets('someone else\'s face is refused, and never reported as accepted', (tester) async {
    final calls = <Map<String, dynamic>?>[];
    final fake = _FakeChecks((_) => _matched('no_match'));
    await tester.pumpWidget(_app(PortraitPicker(
      selfiePath: '/selfie.jpg',
      initialPath: photo, // kept from before, not yet checked
      service: fake,
      onChanged: (_, checks) => calls.add(checks),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Please use another photo'), findsOneWidget);
    expect(
      find.text('This does not look like the person in your selfie. Use a 2x2 photo of yourself.'),
      findsOneWidget,
    );
    expect(calls, everyElement(isNull));
  });

  testWidgets('a busy background is refused with its own reason', (tester) async {
    final fake = _FakeChecks(
      (_) => const PortraitResult(facts: _facts, problem: PortraitProblem.busyBackground),
    );
    await tester.pumpWidget(_app(PortraitPicker(
      selfiePath: '/selfie.jpg',
      initialPath: photo,
      service: fake,
      onChanged: (_, __) {},
    )));
    await tester.pumpAndSettle();
    expect(find.textContaining('The background must be plain'), findsOneWidget);
  });

  testWidgets('accepted: the checks to store come back with the verdict', (tester) async {
    Map<String, dynamic>? stored;
    final fake = _FakeChecks((_) => _matched('match'));
    await tester.pumpWidget(_app(PortraitPicker(
      selfiePath: '/selfie.jpg',
      initialPath: photo,
      service: fake,
      onChanged: (_, checks) => stored = checks,
    )));
    await tester.pumpAndSettle();
    expect(find.textContaining('the same face as your selfie'), findsOneWidget);
    expect(stored!['verdict'], 'match');
    expect(stored!['score'], 0.7);
    expect(stored!.containsKey('path'), isFalse); // added only once uploaded
  });

  testWidgets('"uncertain" is accepted for the administrator to look at', (tester) async {
    Map<String, dynamic>? stored;
    final fake = _FakeChecks((_) => _matched('uncertain'));
    await tester.pumpWidget(_app(PortraitPicker(
      selfiePath: '/selfie.jpg',
      initialPath: photo,
      service: fake,
      onChanged: (_, checks) => stored = checks,
    )));
    await tester.pumpAndSettle();
    expect(find.textContaining('An administrator will compare it'), findsOneWidget);
    expect(stored!['verdict'], 'uncertain');
  });

  testWidgets('a new selfie means the photo is checked again, against it', (tester) async {
    final calls = <Map<String, dynamic>?>[];
    final fake = _FakeChecks((s) => _matched(s == '/new.jpg' ? 'no_match' : 'match'));
    Widget build(String selfie) => _app(PortraitPicker(
      selfiePath: selfie,
      initialPath: photo,
      service: fake,
      onChanged: (_, checks) => calls.add(checks),
    ));
    await tester.pumpWidget(build('/old.jpg'));
    await tester.pumpAndSettle();
    expect(calls.last?['verdict'], 'match');

    await tester.pumpWidget(build('/new.jpg'));
    await tester.pumpAndSettle();
    expect(fake.selfiesSeen, ['/old.jpg', '/new.jpg']);
    expect(calls.last, isNull); // the old acceptance does not carry over
    expect(find.text('Please use another photo'), findsOneWidget);
  });

  testWidgets('an accepted photo from a resumed draft is not checked again', (tester) async {
    final fake = _FakeChecks((_) => _matched('match'));
    await tester.pumpWidget(_app(PortraitPicker(
      selfiePath: '/selfie.jpg',
      initialPath: photo,
      initialChecks: const {'verdict': 'match'},
      service: fake,
      onChanged: (_, __) {},
    )));
    await tester.pumpAndSettle();
    expect(fake.selfiesSeen, isEmpty);
    expect(find.textContaining('the same face as your selfie'), findsOneWidget);
  });

  testWidgets('removing the photo reports nothing on file', (tester) async {
    String? path = 'x';
    final fake = _FakeChecks((_) => _matched('match'));
    await tester.pumpWidget(_app(PortraitPicker(
      selfiePath: '/selfie.jpg',
      initialPath: photo,
      initialChecks: const {'verdict': 'match'},
      service: fake,
      onChanged: (p, _) => path = p,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('portrait-remove')));
    await tester.pumpAndSettle();
    expect(path, isNull);
    expect(find.text('Take a photo'), findsOneWidget);
  });
}
