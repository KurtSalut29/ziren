import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// The router shape the resident app uses, cut down to what matters: a tab shell
// (StatefulShellRoute.indexedStack with its own navigator key per branch) and
// full-screen routes that live OUTSIDE it.
//
// Two real bugs came from this shape:
//   * Emergency Contacts -> "Find on the Map" did `context.push('/map')`, and
//     the screen came up blank.
//   * My Reports -> "View on map" did `context.push('/map?incidentId=..')`.
// /map is a branch of the shell, and pushing it builds a second copy of the
// shell that claims the same navigator keys as the one already mounted.
//
// Reproduced while writing this: `router.push('/map')` over the shell throws
//   Failed assertion: '_dependents.isEmpty': is not true
//   (building _FocusInheritedScope, in InheritedElement.debugDeactivated)
// and leaves the element tree corrupt - every later test in the same isolate
// fails with it too, which is why the broken call is not kept here as a test of
// its own. On a phone the same corruption shows as a blank pushed screen and a
// Map tab that no longer takes a tap. These tests pin the two safe ways in.

// Fresh keys per router. A key that fails to unmount in one test (which is the
// point of the first test) would otherwise poison every test after it.
GoRouter _router() {
  final rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');
  final homeKey = GlobalKey<NavigatorState>(debugLabel: 'home');
  final mapKey = GlobalKey<NavigatorState>(debugLabel: 'map');
  return _build(rootKey, homeKey, mapKey);
}

GoRouter _build(
  GlobalKey<NavigatorState> rootKey,
  GlobalKey<NavigatorState> homeKey,
  GlobalKey<NavigatorState> mapKey,
) => GoRouter(
  navigatorKey: rootKey,
  initialLocation: '/home',
  routes: [
    StatefulShellRoute.indexedStack(
      parentNavigatorKey: rootKey,
      builder:
          (context, state, shell) =>
              Scaffold(body: shell, appBar: AppBar(title: const Text('shell'))),
      branches: [
        StatefulShellBranch(
          navigatorKey: homeKey,
          routes: [
            GoRoute(
              path: '/home',
              builder: (_, __) => const Center(child: Text('HOME')),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: mapKey,
          routes: [
            GoRoute(
              path: '/map',
              builder: (_, __) => const Center(child: Text('MAP TAB')),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/contacts',
      builder: (_, __) => const Scaffold(body: Center(child: Text('CONTACTS'))),
    ),
    GoRoute(
      path: '/report-map/:incidentId',
      builder:
          (_, state) => Scaffold(
            body: Center(
              child: Text('REPORT MAP ${state.pathParameters['incidentId']}'),
            ),
          ),
    ),
  ],
);

Future<GoRouter> _open(WidgetTester tester) async {
  final router = _router();
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  // Contacts is pushed OVER the shell, the way the app reaches it.
  router.push('/contacts');
  await tester.pumpAndSettle();
  expect(find.text('CONTACTS'), findsOneWidget);
  return router;
}

void main() {
  testWidgets('go(/map) lands on the Map tab cleanly', (tester) async {
    final router = await _open(tester);

    router.go('/map');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('MAP TAB'), findsOneWidget);
    expect(find.text('CONTACTS'), findsNothing);
  });

  testWidgets('a focused-report map outside the shell pushes and pops', (
    tester,
  ) async {
    final router = await _open(tester);

    router.push('/report-map/abc-123');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('REPORT MAP abc-123'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('CONTACTS'), findsOneWidget);
  });
}
