import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ziren/features/incident_report/domain/incident_model.dart';
import 'package:ziren/features/incident_report/domain/incident_provider.dart';
import 'package:ziren/features/incident_report/domain/landmark_index.dart';
import 'package:ziren/features/incident_report/domain/station_model.dart';
import 'package:ziren/features/incident_report/presentation/my_reports_screen.dart';
import 'package:ziren/features/incident_report/presentation/report_detail_screen.dart';
import 'package:ziren/features/incident_report/presentation/widgets/report_stage_track.dart';
import 'package:ziren/features/map/domain/map_provider.dart';
import 'package:ziren/features/map/presentation/map_screen.dart';
import 'package:ziren/features/sos/domain/sos_provider.dart';
import 'package:ziren/features/sos/presentation/sos_confirm_screen.dart';
import 'package:ziren/l10n/app_localizations.dart';
import 'package:ziren/shared/theme/app_tokens.dart';

import 'support/fake_sos_repository.dart';

/// My Reports and the map's floating chrome, redesigned 2026-09-30: what they
/// say, and goldens to look at (the map itself is a native view a widget test
/// cannot draw, so its header and station card are drawn over a plain fill).
///
/// Refresh the pictures with:
///   flutter test --update-goldens test/reports_map_design_test.dart

/// Serves My Reports a fixed history; never touches the network or GPS.
class _FakeIncidents extends IncidentProvider {
  _FakeIncidents(this._list);

  final List<IncidentModel> _list;

  @override
  List<IncidentModel> get myIncidents => _list;

  @override
  bool get loadingIncidents => false;

  @override
  String? get incidentsError => null;

  @override
  Position? get currentPosition => kNavalPosition();

  @override
  Future<void> loadMyIncidents() async {}

  @override
  Future<void> fetchLocation() async {}

  @override
  Future<IncidentFeedback?> fetchMyFeedback(String incidentId) async => null;
}

class _TestSos extends SosProvider {
  _TestSos({super.repository, super.landmarks});

  @override
  Future<void> initialize() async {}
}

// Fixed clock times, so the goldens do not change with the hour they run at;
// only the day is today's, which is what the Today / This week groups read.
final _today = DateTime.now();
final _morning = DateTime(_today.year, _today.month, _today.day, 8, 10);

// The report details screen prints the DATE itself, not "today". Its golden was
// taken with a report from the morning of whatever day the suite ran, so it
// failed on every other day (found 2026-10-01: three date labels, 502 pixels).
// One fixed morning keeps the picture the same whenever it runs.
final _detailMorning = DateTime(2026, 9, 30, 8, 10);

List<IncidentModel> _history() => [
  IncidentModel(
    id: 'a1',
    reportText: 'Fire — Nasusunog ang bahay sa tabi ng kapilya',
    status: 'dispatched',
    submittedVia: 'internet',
    createdAt: _morning.add(const Duration(minutes: 55)),
    locationAddress: 'Larrazabal, Naval',
    latitude: 11.5850,
    longitude: 124.4070,
    incidentCategory: 'fire',
  ),
  IncidentModel(
    id: 'a2',
    reportText: 'Medical — Nahimatay ang lolo',
    status: 'received',
    submittedVia: 'sos',
    createdAt: _morning,
    locationAddress: 'Caraycaray, Naval',
    incidentCategory: 'medical_trauma',
  ),
  IncidentModel(
    id: 'a3',
    reportText: 'Accident — Nagbanggaan ang motor at tricycle',
    status: 'resolved',
    submittedVia: 'internet',
    createdAt: _morning.subtract(const Duration(days: 3)),
    resolvedAt: _morning.subtract(const Duration(days: 3)),
    locationAddress: 'Atipolo, Naval',
    incidentCategory: 'vehicular',
  ),
];

Widget _app(Widget home, {List<ChangeNotifierProvider> providers = const []}) {
  final app = MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: const Locale('en'),
    theme: ThemeData(fontFamily: 'Roboto', useMaterial3: true),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );
  return providers.isEmpty ? app : MultiProvider(providers: providers, child: app);
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-publishable-key',
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        detectSessionInUri: false,
      ),
    );
    await _loadRealFonts();
  });

  group('My Reports', () {
    Future<void> pump(WidgetTester tester, List<IncidentModel> list) async {
      tester.view.physicalSize = const Size(1100, 2600);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          const MyReportsScreen(),
          providers: [
            ChangeNotifierProvider<IncidentProvider>.value(
              value: _FakeIncidents(list),
            ),
          ],
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('open reports show their named progress steps', (tester) async {
      await pump(tester, _history());
      // Two open reports, each with the four steps named under the bar; the
      // resolved one has no track — it is finished.
      expect(find.byType(ReportStageTrack), findsNWidgets(2));
      expect(find.text('Checking'), findsNWidgets(2));
      expect(find.text('On the way'), findsNWidgets(2));
      // The bare "Step 1 of 4" it replaced named nothing.
      expect(find.textContaining('of 4'), findsNothing);
    });

    testWidgets('each filter shows how many reports it holds', (tester) async {
      await pump(tester, _history());
      Finder chip(String label) => find.ancestor(
        of: find.text(label),
        matching: find.byType(GestureDetector),
      );
      expect(
        find.descendant(of: chip('All').first, matching: find.text('3')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: chip('Active').first, matching: find.text('2')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: chip('Resolved').first, matching: find.text('1')),
        findsOneWidget,
      );

      // The first "Resolved" is the filter; the other is a card's status.
      await tester.tap(find.text('Resolved').first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Accident'), findsOneWidget);
      expect(find.text('Fire'), findsNothing);
    });

    testWidgets('no reports at all offers to make one', (tester) async {
      await pump(tester, const []);
      expect(find.text('No reports yet'), findsOneWidget);
      expect(find.text('Report an Emergency'), findsOneWidget);
    });

    for (final dark in [false, true]) {
      testWidgets('golden${dark ? ' (dark)' : ''}', (tester) async {
        ZirenTokens.setMode(
          brightness: dark ? Brightness.dark : Brightness.light,
          highContrast: false,
        );
        addTearDown(
          () => ZirenTokens.setMode(
            brightness: Brightness.light,
            highContrast: false,
          ),
        );
        await pump(tester, _history());
        await expectLater(
          find.byType(MyReportsScreen),
          matchesGoldenFile('goldens/my_reports${dark ? '_dark' : ''}.png'),
        );
      });
    }
  });

  group('Report details', () {
    Future<void> pump(WidgetTester tester, IncidentModel incident) async {
      tester.view.physicalSize = const Size(1100, 3300);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          ReportDetailScreen(incident: incident),
          providers: [
            ChangeNotifierProvider<IncidentProvider>.value(
              value: _FakeIncidents([incident]),
            ),
          ],
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    final onTheWay = IncidentModel(
      id: '8f1c2d3e-4b5a-6978-8a9b-0c1d2e3fa4b7',
      reportText: 'Fire — Nasusunog ang bahay sa tabi ng kapilya',
      status: 'dispatched',
      submittedVia: 'internet',
      createdAt: _detailMorning,
      dispatchedAt: _detailMorning.add(const Duration(minutes: 4)),
      locationAddress: 'Larrazabal, Naval, Biliran',
      latitude: 11.5850,
      longitude: 124.4070,
      incidentCategory: 'fire',
      etaMinutes: 7,
      respondingAgency: 'BFP',
    );

    testWidgets('says what comes next and who is coming', (tester) async {
      await pump(tester, onTheWay);
      expect(find.byType(ReportStageTrack), findsOneWidget);
      expect(find.text('Next: Resolved'), findsOneWidget);
      expect(find.text('BFP is on the way — about 7 minutes'), findsOneWidget);
      // The last six of the id, as the dashboard and responder app print it.
      expect(find.text('INC-3FA4B7'), findsOneWidget);
      expect(find.text('Ziren app'), findsOneWidget);
      expect(find.byKey(const Key('report-chat')), findsOneWidget);
      // Past `received`, Trash is not offered: the server would refuse it.
      expect(find.byKey(const Key('report-trash')), findsNothing);
    });

    testWidgets('a report nobody has acted on can still be trashed', (
      tester,
    ) async {
      await pump(
        tester,
        IncidentModel(
          id: 'a2',
          reportText: 'Medical — Nahimatay ang lolo',
          status: 'received',
          submittedVia: 'sos',
          createdAt: _morning,
          incidentCategory: 'medical_trauma',
        ),
      );
      expect(find.text('Next: Checking'), findsOneWidget);
      expect(find.byKey(const Key('report-trash')), findsOneWidget);
      expect(find.byKey(const Key('report-chat')), findsOneWidget);
      expect(find.text('Emergency SOS'), findsOneWidget);
    });

    testWidgets('a resolved report offers a rating, not a chat', (
      tester,
    ) async {
      await pump(
        tester,
        IncidentModel(
          id: 'a3',
          reportText: 'Accident — Nagbanggaan ang motor at tricycle',
          status: 'resolved',
          submittedVia: 'internet',
          createdAt: _morning,
          resolvedAt: _morning.add(const Duration(hours: 1)),
          incidentCategory: 'vehicular',
        ),
      );
      await tester.pump();
      expect(find.byType(ReportStageTrack), findsNothing);
      expect(find.byKey(const Key('report-chat')), findsNothing);
      expect(find.text('Rate the Service'), findsOneWidget);
    });

    testWidgets('golden', (tester) async {
      await pump(tester, onTheWay);
      await expectLater(
        find.byType(ReportDetailScreen),
        matchesGoldenFile('goldens/report_detail.png'),
      );
    });
  });

  group('Map chrome', () {
    const naval = StationModel(
      id: 's1',
      agencyId: 'a0000001-0000-0000-0000-000000000001',
      agencyType: 'BFP',
      agencyName: 'Bureau of Fire Protection',
      name: 'BFP Naval Fire Station',
      municipality: 'Naval',
      latitude: 11.5610,
      longitude: 124.3970,
    );
    const others = [
      StationModel(
        id: 's2',
        agencyId: 'a0000001-0000-0000-0000-000000000002',
        agencyType: 'PNP',
        agencyName: 'Philippine National Police',
        name: 'PNP Naval Municipal Police Station',
        municipality: 'Naval',
      ),
      StationModel(
        id: 's3',
        agencyId: 'a0000001-0000-0000-0000-000000000003',
        agencyType: 'MDRRMO',
        agencyName: 'MDRRMO',
        name: 'MDRRMO Naval',
        municipality: 'Naval',
      ),
    ];

    Future<void> pump(WidgetTester tester, {bool pickerOpen = false}) async {
      tester.view.physicalSize = const Size(1100, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      final provider = MapProvider();
      await tester.pumpWidget(
        _app(
          Scaffold(
            // Stands in for the map tiles.
            backgroundColor: const Color(0xFFE8EDE4),
            body: Stack(
              children: [
                Positioned(
                  left: 12,
                  right: 12,
                  top: 40,
                  child: MapHeaderCard(
                    title: 'Nearby Emergency Stations',
                    subtitle: 'Stations on the map: 21',
                    showBack: false,
                    filters: MapAgencyFilters(provider: provider),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: MapStationCard(
                    station: naval,
                    isNearest: true,
                    distanceKm: 2.4,
                    onGetDirections: () {},
                    pickerOpen: pickerOpen,
                    onTogglePicker: () {},
                    otherStations: others,
                    distanceKmTo: (s) => s == null ? null : 3.1,
                    onSelectStation: (_) {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('station card names the nearest station and both actions', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('NEAREST STATION'), findsOneWidget);
      expect(find.text('BFP Naval Fire Station'), findsOneWidget);
      expect(find.text('2.4 km'), findsOneWidget);
      expect(find.text('Get directions'), findsOneWidget);
      // BFP Naval has hotlines in the bundled directory.
      expect(find.text('Call'), findsOneWidget);
      expect(find.text('Other stations (2)'), findsOneWidget);
    });

    testWidgets('golden', (tester) async {
      await pump(tester, pickerOpen: true);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/map_chrome.png'),
      );
    });
  });

  testWidgets('SOS confirm golden', (tester) async {
    tester.view.physicalSize = const Size(1100, 3200);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final p = _TestSos(
      repository: FakeSosRepository(() async => kSosResult),
      landmarks:
          () async => LandmarkIndex.fromPlaces(
            const [],
            unnamed: const [
              MapPlace(
                name: 'Basketball Court',
                kind: 'pitch',
                isLandmark: true,
                lat: 11.5837,
                lng: 124.4063,
              ),
            ],
          ),
    )..debugPosition = kNavalPosition();
    await p.detectLandmark();
    await tester.pumpWidget(
      _app(
        const SosConfirmScreen(),
        providers: [ChangeNotifierProvider<SosProvider>.value(value: p)],
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byType(SosConfirmScreen),
      matchesGoldenFile('goldens/sos_confirm.png'),
    );
  });
}

Future<void> _loadRealFonts() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  final candidates = <String>[
    if (flutterRoot != null) '$flutterRoot/bin/cache/artifacts/material_fonts',
    'C:/src/flutter/bin/cache/artifacts/material_fonts',
  ];
  for (final dir in candidates) {
    final regular = File('$dir/roboto-regular.ttf');
    final bold = File('$dir/roboto-bold.ttf');
    if (!regular.existsSync()) continue;
    final loader = FontLoader('Roboto');
    loader.addFont(regular.readAsBytes().then((b) => ByteData.view(b.buffer)));
    if (bold.existsSync()) {
      loader.addFont(bold.readAsBytes().then((b) => ByteData.view(b.buffer)));
    }
    await loader.load();
    break;
  }

  final pubCache =
      Platform.environment['PUB_CACHE'] ??
      '${Platform.environment['LOCALAPPDATA']}/Pub/Cache';
  final hosted = Directory('$pubCache/hosted/pub.dev');
  if (!hosted.existsSync()) return;
  final lucide =
      hosted
          .listSync()
          .whereType<Directory>()
          .where(
            (d) => d.path
                .split(RegExp(r'[\\/]'))
                .last
                .startsWith('flutter_lucide-'),
          )
          .map((d) => File('${d.path}/lib/fonts/lucide.ttf'))
          .where((f) => f.existsSync())
          .toList();
  if (lucide.isEmpty) return;
  final iconLoader = FontLoader('packages/flutter_lucide/lucide');
  iconLoader.addFont(
    lucide.last.readAsBytes().then((b) => ByteData.view(b.buffer)),
  );
  await iconLoader.load();
}
