import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ziren/features/demo/presentation/welcome_demo.dart';
import 'package:ziren/l10n/app_localizations.dart';

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(1080, 2340);
    binding.platformDispatcher.views.first.devicePixelRatio = 2.7;
  });
  tearDown(() => TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first.resetPhysicalSize());
  group('who is greeted', () {
    test('a new account (made on or after the day this shipped) is greeted once', () {
      expect(
        WelcomeDemo.shouldGreet(createdAt: '2026-10-02T08:00:00Z', metadata: {}, doneOnThisPhone: false),
        isTrue,
      );
      expect(
        WelcomeDemo.shouldGreet(createdAt: '2026-10-01T00:00:00Z', metadata: null, doneOnThisPhone: false),
        isTrue,
      );
    });

    test('an account that was already using the app is not', () {
      expect(
        WelcomeDemo.shouldGreet(createdAt: '2026-09-20T08:00:00Z', metadata: {}, doneOnThisPhone: false),
        isFalse,
      );
    });

    test('once answered — on this phone or any other — never again', () {
      expect(
        WelcomeDemo.shouldGreet(
          createdAt: '2026-10-02T08:00:00Z',
          metadata: {WelcomeDemo.metadataKey: {'choice': 'later'}},
          doneOnThisPhone: false,
        ),
        isFalse,
      );
      expect(
        WelcomeDemo.shouldGreet(createdAt: '2026-10-02T08:00:00Z', metadata: {}, doneOnThisPhone: true),
        isFalse,
      );
    });

    test('no creation date: not greeted', () {
      expect(WelcomeDemo.shouldGreet(createdAt: null, metadata: {}, doneOnThisPhone: false), isFalse);
      expect(WelcomeDemo.shouldGreet(createdAt: 'garbage', metadata: {}, doneOnThisPhone: false), isFalse);
    });
  });

  group('the greeting', () {
    Future<bool?> open(WidgetTester tester, {required String lang, bool responder = false, String name = 'Kurt'}) async {
      bool? result;
      var done = false;
      await tester.pumpWidget(MaterialApp(
        locale: Locale(lang),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await showWelcomeDemo(context, responder: responder, firstName: name);
                  done = true;
                },
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      addTearDown(() => expect(done, isTrue, reason: 'the dialog was answered'));
      return result;
    }

    testWidgets('says hi by name and offers the demo, in Filipino', (tester) async {
      await open(tester, lang: 'fil');
      expect(find.text('Hi, Kurt!'), findsOneWidget);
      expect(find.textContaining('Gusto mo bang ipakita ko muna'), findsOneWidget);
      expect(find.text('Oo, ipakita mo'), findsOneWidget);
      expect(find.text('Mamaya na lang'), findsOneWidget);
      expect(find.textContaining('Magpatulong kay Ziren'), findsOneWidget); // where the demos live
      expect(find.image(const AssetImage('assets/images/demo/excited.png')), findsOneWidget);
      await tester.tap(find.text('Mamaya na lang'));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('and in English, with the responder wording', (tester) async {
      await open(tester, lang: 'en', responder: true);
      expect(find.text('Hi, Kurt!'), findsOneWidget);
      expect(find.textContaining('Welcome to the team!'), findsOneWidget);
      expect(find.textContaining('"Ask Ziren for help"'), findsOneWidget);
      await tester.tap(find.text('Maybe later'));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('no name yet: a plain hi', (tester) async {
      await open(tester, lang: 'en', name: '  ');
      expect(find.text('Hi there!'), findsOneWidget);
      await tester.tap(find.text('Maybe later'));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('"Yes, show me" answers true, "Maybe later" false', (tester) async {
      bool? answer;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async =>
                  answer = await showWelcomeDemo(context, responder: false, firstName: 'Kurt'),
              child: const Text('go'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Yes, show me'));
      await tester.pump(const Duration(seconds: 1));
      expect(answer, isTrue);

      await tester.tap(find.text('go'));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Maybe later'));
      await tester.pump(const Duration(seconds: 1));
      expect(answer, isFalse);
    });

    testWidgets('a tap beside the card does not answer it; the back button means later', (tester) async {
      bool? answer;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async =>
                  answer = await showWelcomeDemo(context, responder: false, firstName: 'Kurt'),
              child: const Text('go'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pump(const Duration(seconds: 1));
      await tester.tapAt(const Offset(8, 8));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Hi, Kurt!'), findsOneWidget);

      // What the phone's back button does: maybePop on the top route.
      await Navigator.of(tester.element(find.text('Hi, Kurt!'))).maybePop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Hi, Kurt!'), findsNothing);
      expect(answer, isFalse);
    });
  });
}
