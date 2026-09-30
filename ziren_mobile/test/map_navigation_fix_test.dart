import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ziren/features/map/presentation/map_screen.dart';
import 'package:ziren/features/responder/presentation/incident_navigation_screen.dart';
import 'package:ziren/l10n/app_localizations.dart';
import 'package:ziren/shared/map/road_route.dart';

/// Tester's report, 2026-09-30:
///   1. The back arrow on the responder's Incident Map did nothing.
///   2. The responder's navigation map drew a straight line, with no pin at
///      either end.
void main() {
  group('back arrow on a map with nothing under it', () {
    Future<GoRouter> pumpMap(WidgetTester tester) async {
      final router = GoRouter(
        initialLocation: '/responder/map',
        routes: [
          GoRoute(
            path: '/responder/queue',
            builder: (_, __) => const Scaffold(body: Text('HOME')),
          ),
          // The Incident Map is the root of its own tab: nothing to pop.
          GoRoute(
            path: '/responder/map',
            builder:
                (_, __) => const Scaffold(
                  body: MapHeaderCard(
                    title: 'Incident Map',
                    showBack: true,
                    fallbackRoute: '/responder/queue',
                  ),
                ),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      return router;
    }

    testWidgets('goes to the fallback instead of doing nothing', (
      tester,
    ) async {
      await pumpMap(tester);
      expect(find.text('HOME'), findsNothing);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('still pops when there is a screen under it', (tester) async {
      final router = await pumpMap(tester);
      router.go('/responder/queue');
      await tester.pumpAndSettle();
      router.push('/responder/map');
      await tester.pumpAndSettle();
      expect(find.text('Incident Map'), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('Incident Map'), findsNothing);
    });
  });

  group('road route', () {
    // A small OSRM reply: three road points heading north, 250 m, 40 s.
    final osrm = jsonEncode({
      'code': 'Ok',
      'routes': [
        {
          'distance': 250.0,
          'duration': 40.0,
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              [124.4000, 11.5600],
              [124.4000, 11.5610],
              [124.4000, 11.5620],
            ],
          },
        },
      ],
    });

    test('parses the path, its length and its time', () async {
      Uri? asked;
      final client = MockClient((req) async {
        asked = req.url;
        return http.Response(osrm, 200);
      });
      final road = await RoadRoute.fetch(
        11.56,
        124.40,
        11.562,
        124.40,
        client: client,
      );
      expect(road, isNotNull);
      expect(road!.coordinates, hasLength(3));
      expect(road.coordinates.first, [124.4, 11.56]);
      expect(road.metres, 250);
      expect(road.seconds, 40);
      // Longitude first, as OSRM expects.
      expect(asked!.path, contains('124.4,11.56;124.4,11.562'));
    });

    test('every failure is null, so the caller falls back to the line', () async {
      for (final reply in [
        http.Response('down', 503),
        http.Response('not json', 200),
        http.Response(jsonEncode({'code': 'NoRoute', 'routes': []}), 200),
      ]) {
        final road = await RoadRoute.fetch(
          11.56,
          124.40,
          11.562,
          124.40,
          client: MockClient((_) async => reply),
        );
        expect(road, isNull, reason: reply.body);
      }
      final thrown = await RoadRoute.fetch(
        11.56,
        124.40,
        11.562,
        124.40,
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      expect(thrown, isNull);
    });

    test('the part already driven is cut off', () {
      final road = RoadRoute(
        coordinates: const [
          [124.4000, 11.5600],
          [124.4000, 11.5610],
          [124.4000, 11.5620],
        ],
        metres: 222,
        seconds: 40,
      );
      // Standing on the middle point.
      final rest = road.remainingFrom(11.5610, 124.4000);
      expect(rest.coordinates, hasLength(2));
      expect(rest.offRouteMetres, closeTo(0, 0.01));
      // One step of 0.001 degrees of latitude is about 110.6 m here.
      expect(rest.metres, closeTo(110.6, 1));

      // Off the road by roughly 200 m to the east.
      final off = road.remainingFrom(11.5610, 124.4018);
      expect(off.offRouteMetres, greaterThan(150));
    });
  });

  group('when to ask for a new road', () {
    final now = DateTime(2026, 9, 30, 12);

    test('asks at once when there is no road yet', () {
      expect(
        navNeedsRoute(
          haveRoad: false,
          offRouteMetres: null,
          lastAttempt: null,
          now: now,
        ),
        isTrue,
      );
    });

    test('does not ask again while the crew is on the road', () {
      expect(
        navNeedsRoute(
          haveRoad: true,
          offRouteMetres: 20,
          lastAttempt: now.subtract(const Duration(minutes: 5)),
          now: now,
        ),
        isFalse,
      );
    });

    test('asks again when the crew leaves the road', () {
      expect(
        navNeedsRoute(
          haveRoad: true,
          offRouteMetres: kNavOffRouteMetres + 50,
          lastAttempt: now.subtract(const Duration(minutes: 1)),
          now: now,
        ),
        isTrue,
      );
    });

    test('never hammers the server: one try per gap, even when it is down', () {
      expect(
        navNeedsRoute(
          haveRoad: false,
          offRouteMetres: null,
          lastAttempt: now.subtract(const Duration(seconds: 5)),
          now: now,
        ),
        isFalse,
      );
      expect(
        navNeedsRoute(
          haveRoad: false,
          offRouteMetres: null,
          lastAttempt: now.subtract(kNavRefetchGap),
          now: now,
        ),
        isTrue,
      );
    });
  });

  group('guidance panel', () {
    Future<void> pumpPanel(WidgetTester tester, {required bool byRoad}) =>
        tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Scaffold(
              body: NavGuidancePanel(
                address: null,
                distanceMetres: 2400,
                etaMinutes: 5,
                bearing: 45,
                byRoad: byRoad,
                onOpenExternal: () {},
              ),
            ),
          ),
        );

    testWidgets('a road route is labelled as one', (tester) async {
      await pumpPanel(tester, byRoad: true);
      expect(find.textContaining('by road'), findsOneWidget);
      expect(find.textContaining('straight'), findsNothing);
      expect(find.textContaining('follows the roads'), findsOneWidget);
    });

    testWidgets('the straight fallback still says it is not a road', (
      tester,
    ) async {
      await pumpPanel(tester, byRoad: false);
      expect(find.textContaining('straight-line distance'), findsOneWidget);
      expect(find.textContaining('not a road'), findsOneWidget);
    });
  });
}
