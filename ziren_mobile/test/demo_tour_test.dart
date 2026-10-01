import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ziren/features/demo/domain/demo_catalog.dart';
import 'package:ziren/features/demo/domain/demo_models.dart';
import 'package:ziren/features/demo/presentation/demo_anchor.dart';
import 'package:ziren/features/demo/presentation/demo_tour.dart';

/// Every anchor id written into a screen under lib/, literal or in a const
/// list ('nav.home' and friends).
Set<String> _anchorIdsInSource() {
  final ids = <String>{};
  final idLiteral = RegExp(r"""id:\s*(?:const\s*)?['"]([a-z][\w.]*)['"]""");
  final ternary = RegExp(r"""\?\s*['"]([a-z][\w.]*)['"]\s*:""");
  final list = RegExp(r"""id:\s*const\s*\[([^\]]+)\]""");
  for (final f in Directory('lib').listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.dart')) continue;
    if (f.path.contains('${Platform.pathSeparator}demo${Platform.pathSeparator}')) continue;
    final src = f.readAsStringSync();
    if (!src.contains('DemoAnchor(')) continue;
    ids.addAll(idLiteral.allMatches(src).map((m) => m.group(1)!));
    ids.addAll(ternary.allMatches(src).map((m) => m.group(1)!));
    for (final m in list.allMatches(src)) {
      ids.addAll(
        RegExp(r"""['"]([a-z][\w.]*)['"]""").allMatches(m.group(1)!).map((x) => x.group(1)!),
      );
    }
  }
  return ids;
}

Widget _app(Widget home) => MaterialApp(
  locale: const Locale('fil'),
  supportedLocales: const [Locale('en'), Locale('fil')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: home,
);

DemoScript _script(List<DemoStep> steps) => DemoScript(
  id: 'test',
  icon: Icons.home,
  titleFil: 'Pagsubok',
  titleEn: 'Test',
  summaryFil: '',
  summaryEn: '',
  open: (_) async {},
  steps: steps,
);

class _Screen extends StatelessWidget {
  const _Screen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SizedBox(height: 120),
          DemoAnchor(
            id: 't.top',
            child: Container(height: 60, width: 200, color: Colors.orange),
          ),
          const Spacer(),
          DemoAnchor(
            id: 't.bottom',
            child: Container(height: 60, width: 200, color: Colors.blue),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

/// The tour waits a frame for a scroll to land before it measures, and its
/// mascot bobs forever, so pumpAndSettle never returns: pump a few frames.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  test('every anchor a demo points at exists in a screen', () {
    final inSource = _anchorIdsInSource();
    final missing = <String>[];
    for (final script in [...DemoCatalog.resident(), ...DemoCatalog.responder()]) {
      for (final id in [...script.steps.map((s) => s.anchor), script.screenAnchor]) {
        if (id != null && !inSource.contains(id)) missing.add('${script.id}: $id');
      }
    }
    expect(missing, isEmpty);
  });

  test('every demo has both languages on every step', () {
    for (final script in [...DemoCatalog.resident(), ...DemoCatalog.responder()]) {
      expect(script.titleFil, isNotEmpty);
      expect(script.titleEn, isNotEmpty);
      for (final step in script.steps) {
        expect(step.fil.trim(), isNotEmpty, reason: script.id);
        expect(step.en.trim(), isNotEmpty, reason: script.id);
        expect(step.fil, isNot(step.en), reason: '${script.id}: ${step.en}');
      }
    }
  });

  testWidgets('steps forward and back, points at the anchor, and ends', (tester) async {
    await tester.pumpWidget(_app(const _Screen()));
    final ctx = tester.element(find.byType(_Screen));
    var closed = false;
    final script = DemoScript(
      id: 'test',
      icon: Icons.home,
      titleFil: 'Pagsubok',
      titleEn: 'Test',
      summaryFil: '',
      summaryEn: '',
      open: (_) async {},
      close: (_) => closed = true,
      steps: const [
        DemoStep(anchor: 't.top', fil: 'Itaas', en: 'Top'),
        DemoStep(anchor: 't.bottom', fil: 'Ibaba', en: 'Bottom'),
        DemoStep(anchor: 't.nowhere', fil: 'Wala', en: 'Nowhere'),
      ],
    );
    showDemoTour(ctx, script);
    await tester.pump();
    await _settle(tester);

    expect(find.text('Itaas'), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);
    // Target in the top half: the bubble sits below it and the mascot points up.
    expect(
      find.byWidgetPredicate((w) => w is Image && w.key == const ValueKey(DemoPose.pointUp)),
      findsOneWidget,
    );

    await tester.tap(find.text('Susunod'));
    await _settle(tester);
    expect(find.text('Ibaba'), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => w is Image && w.key == const ValueKey(DemoPose.pointDown)),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Bumalik'));
    await _settle(tester);
    expect(find.text('Itaas'), findsOneWidget);

    await tester.tap(find.text('Susunod'));
    await _settle(tester);
    await tester.tap(find.text('Susunod'));
    await _settle(tester);
    // Nothing on screen to point at: said from the middle, at the user.
    expect(find.text('Wala'), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => w is Image && w.key == const ValueKey(DemoPose.pointYou)),
      findsOneWidget,
    );

    await tester.tap(find.text('Tapos na'));
    await _settle(tester);
    expect(find.text('Wala'), findsNothing);
    expect(closed, isTrue);
  });

  testWidgets('the screen under the tour cannot be tapped', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Center(
            child: DemoAnchor(
              id: 't.button',
              child: ElevatedButton(onPressed: () => tapped++, child: const Text('Ipadala')),
            ),
          ),
        ),
      ),
    );
    final ctx = tester.element(find.text('Ipadala'));
    showDemoTour(ctx, _script(const [DemoStep(anchor: 't.button', fil: 'Ito', en: 'This')]));
    await tester.pump();
    await _settle(tester);
    await tester.tapAt(tester.getCenter(find.text('Ipadala')));
    await tester.pump();
    expect(tapped, 0);
  });

  testWidgets('skip ends the tour from any step', (tester) async {
    await tester.pumpWidget(_app(const _Screen()));
    showDemoTour(
      tester.element(find.byType(_Screen)),
      _script(const [
        DemoStep(anchor: 't.top', fil: 'Una', en: 'First'),
        DemoStep(anchor: 't.bottom', fil: 'Ikalawa', en: 'Second'),
      ]),
    );
    await tester.pump();
    await _settle(tester);
    await tester.tap(find.text('Laktawan'));
    await _settle(tester);
    expect(find.text('Una'), findsNothing);
  });

  testWidgets('a tab kept offstage does not count as on screen', (tester) async {
    await tester.pumpWidget(
      _app(
        const Scaffold(
          body: Offstage(child: DemoAnchor(id: 't.hidden', child: SizedBox(width: 10, height: 10))),
        ),
      ),
    );
    expect(DemoAnchors.isMounted('t.hidden'), isFalse);
  });

  testWidgets('a part that draws nothing is explained from the middle', (tester) async {
    await tester.pumpWidget(
      _app(
        const Scaffold(
          body: Column(
            children: [
              SizedBox(height: 200),
              // An alerts card on a day with no alert: there, but empty.
              DemoAnchor(id: 't.empty', child: SizedBox(width: 300, height: 0)),
            ],
          ),
        ),
      ),
    );
    showDemoTour(
      tester.element(find.byType(Column)),
      _script(const [DemoStep(anchor: 't.empty', fil: 'Babala', en: 'Alert')]),
    );
    await tester.pump();
    await _settle(tester);
    expect(
      find.byWidgetPredicate((w) => w is Image && w.key == const ValueKey(DemoPose.pointYou)),
      findsOneWidget,
    );
  });

  testWidgets('opening a demo never waits for its screen to be closed', (tester) async {
    // A pushed route's future completes only when that route is popped; a
    // demo that returned it started its tour only after the user left.
    const paths = [
      '/home', '/my-reports', '/map', '/profile', '/notifications', '/hotlines',
      '/announcements', '/responder/queue', '/responder/reports', '/responder/map',
      '/responder/profile',
    ];
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        for (final path in paths)
          GoRoute(path: path, builder: (_, __) => Scaffold(body: Text(path))),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    final navContext = router.routerDelegate.navigatorKey.currentContext!;
    // The ones that need app providers (report, SOS, details, assignment) are
    // left out; they push as statements too.
    final simple = [...DemoCatalog.resident(), ...DemoCatalog.responder()].where(
      (d) => const {
        'resident.report', 'resident.sos', 'resident.reportDetail', 'responder.assignment',
      }.every((id) => id != d.id),
    );
    for (final script in simple) {
      var done = false;
      script.open(navContext).then((_) => done = true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(done, isTrue, reason: '${script.id} waits on its screen');
    }
  });

  testWidgets('ending a demo goes back to the Home it was started from', (tester) async {
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(path: '/home', builder: (_, __) => const Scaffold(body: Text('HOME'))),
        GoRoute(path: '/responder/queue', builder: (_, __) => const Scaffold(body: Text('RHOME'))),
        GoRoute(
          path: '/hotlines',
          builder: (_, __) => const Scaffold(body: DemoAnchor(id: 't.h', child: Text('HOTLINES'))),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        locale: const Locale('fil'),
        supportedLocales: const [Locale('en'), Locale('fil')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
      ),
    );
    final nav = router.routerDelegate.navigatorKey.currentContext!;
    for (final responder in [false, true]) {
      router.push('/hotlines');
      await _settle(tester);
      expect(find.text('HOTLINES'), findsOneWidget);
      final script = DemoScript(
        id: responder ? 'responder.test' : 'resident.test',
        icon: Icons.home,
        titleFil: 'T',
        titleEn: 'T',
        summaryFil: '',
        summaryEn: '',
        open: (_) async {},
        steps: const [DemoStep(anchor: 't.h', fil: 'Ito', en: 'This')],
      );
      showDemoTour(nav, script);
      await _settle(tester);
      await tester.tap(find.text('Tapos na'));
      await _settle(tester);
      expect(find.text('HOTLINES'), findsNothing);
      expect(find.text(responder ? 'RHOME' : 'HOME'), findsOneWidget);
    }
  });
}
