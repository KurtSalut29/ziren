import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ziren/l10n/app_localizations.dart';
import 'package:ziren/shared/theme/app_tokens.dart';
import 'package:ziren/shared/widgets/home_kit.dart';
import 'package:ziren/shared/widgets/home_surface.dart';
import 'package:ziren/features/responder/domain/responder_incident_model.dart';
import 'package:ziren/features/responder/domain/responder_trends.dart';
import 'package:ziren/features/responder/presentation/responder_home_screen.dart';
import 'package:ziren/features/responder/presentation/responder_reports_screen.dart';
import 'package:ziren/features/responder/presentation/widgets/responder_charts.dart';
import 'package:ziren/features/responder/presentation/widgets/incoming_report_sheet.dart';
import 'package:ziren/features/responder/presentation/widgets/responder_kit.dart';

/// Renders the home kit with representative content and writes a golden.
///
/// This is a design preview, not an assertion about behaviour: it exists so
/// the layout can be looked at without a Supabase session, which the real
/// screen requires before it will render anything. Run with
/// `flutter test --update-goldens test/home_design_preview_test.dart` and
/// open the PNG under test/goldens/.
void main() {
  testWidgets('resident home layout', (tester) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        // Widgets under test read AppLocalizations.of(context); a bare
        // MaterialApp has no delegates, so that lookup returns null and throws.
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          backgroundColor: kHomeCanvas,
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                const DeliveryBand(
                  title: 'Walang internet',
                  detail: 'Hindi maipapadala ang ulat kung walang internet.',
                  icon: Icons.wifi_off_rounded,
                  tone: ZirenTokens.connectivityOffline,
                ),
                HomeIdentityHeader(
                  name: 'kurtsalut18',
                  hasUnread: true,
                  onBellTap: () {},
                  bellLabel: 'Notifications',
                  bellLabelUnread: 'Notifications, new items',
                ),
                RadialActionDial(
                  centerTitle: 'SOS',
                  centerSubtitle: 'EMERGENCY',
                  centerCaption: 'Hindi tiyak? Pindutin ito',
                  onCenterTap: () {},
                  actions: [
                    QuickAction(
                      icon: Icons.local_fire_department_rounded,
                      label: 'Sunog',
                      color: ZirenTokens.agencyBFP,
                      onTap: () {},
                    ),
                    QuickAction(
                      icon: Icons.medical_services_rounded,
                      label: 'Medikal',
                      color: ZirenTokens.agencyMDRRMO,
                      onTap: () {},
                    ),
                    QuickAction(
                      icon: Icons.local_police_rounded,
                      label: 'Krimen',
                      color: ZirenTokens.agencyPNP,
                      onTap: () {},
                    ),
                    QuickAction(
                      icon: Icons.more_horiz_rounded,
                      label: 'Iba pa',
                      color: ZirenTokens.textSecondary,
                      onTap: () {},
                    ),
                    QuickAction(
                      icon: Icons.water_rounded,
                      label: 'Kalamidad',
                      color: ZirenTokens.systemInfo,
                      onTap: () {},
                    ),
                    QuickAction(
                      icon: Icons.directions_car_rounded,
                      label: 'Aksidente',
                      color: ZirenTokens.severityHigh,
                      onTap: () {},
                    ),
                  ],
                  facts: const [
                    HeroFact(
                      icon: Icons.location_on_rounded,
                      label: 'Lokasyon',
                      value: 'Brgy. Caraycaray',
                      color: ZirenTokens.severityCritical,
                    ),
                    HeroFact(
                      icon: Icons.schedule_rounded,
                      label: 'Oras ngayon',
                      value: '12:33 PM',
                      color: ZirenTokens.severityCritical,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const HomeRule(),
                HomeSection(
                  title: 'MGA ULAT KO',
                  action: 'Lahat',
                  onAction: () {},
                  emptyText: 'Wala ka pang naipadalang ulat.',
                  children: [
                    HomeRow(
                      icon: Icons.description_rounded,
                      iconColor: ZirenTokens.statusDispatched,
                      title: 'Sunog sa Brgy. Caraycaray',
                      subtitle: '2h ang nakalipas',
                      trailingNote: 'Dispatched',
                      trailingColor: ZirenTokens.statusDispatched,
                      onTap: () {},
                    ),
                    HomeRow(
                      icon: Icons.description_rounded,
                      iconColor: ZirenTokens.statusResolved,
                      title: 'Aksidente sa kalsada',
                      subtitle: 'Kahapon',
                      trailingNote: 'Nalutas',
                      trailingColor: ZirenTokens.statusResolved,
                      onTap: () {},
                    ),
                  ],
                ),
                const HomeRule(),
                HomeSection(
                  title: 'MGA ABISO',
                  trailingCount: 2,
                  action: 'Lahat',
                  onAction: () {},
                  emptyText: 'Walang bagong abiso.',
                  children: [
                    HomeRow(
                      icon: Icons.campaign_rounded,
                      iconColor: ZirenTokens.brandOrange,
                      title: 'Na-dispatch na ang ulat mo',
                      subtitle: 'I-tap para tingnan',
                      onTap: () {},
                    ),
                  ],
                ),
                const HomeRule(),
                HomeSection(
                  title: 'LIGTAS NA LUGAR',
                  action: 'Mapa',
                  onAction: () {},
                  emptyText: 'Hindi pa nakukuha ang listahan.',
                  children: [
                    HomeRow(
                      icon: Icons.directions_run_rounded,
                      iconColor: ZirenTokens.agencyMDRRMO,
                      title: 'MDRRMO',
                      subtitle: '4 na istasyon',
                      onTap: () {},
                    ),
                    HomeRow(
                      icon: Icons.local_police_rounded,
                      iconColor: ZirenTokens.agencyPNP,
                      title: 'Pulisya',
                      subtitle: '6 na istasyon',
                      onTap: () {},
                    ),
                    HomeRow(
                      icon: Icons.local_fire_department_rounded,
                      iconColor: ZirenTokens.agencyBFP,
                      title: 'Bumbero',
                      subtitle: '3 istasyon',
                      onTap: () {},
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // The entrance starts in a post-frame callback, so settle one frame
    // first, then capture it part-way through and again once it has landed.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/resident_home_entrance.png'),
    );

    await tester.pump(const Duration(milliseconds: 1200));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/resident_home.png'),
    );
  });

  testWidgets('responder home layout', (tester) async {
    tester.view.physicalSize = const Size(1100, 3100);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        // Widgets under test read AppLocalizations.of(context); a bare
        // MaterialApp has no delegates, so that lookup returns null and throws.
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          backgroundColor: kHomeCanvas,
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                HomeIdentityHeader(
                  name: 'Paolo Reyes',
                  stateLabel: 'Naka-duty',
                  stateColor: ZirenTokens.connectivityOnline,
                  stateDetail: '#BFP-114',
                  hasUnread: true,
                  onBellTap: () {},
                  bellLabel: 'Notifications',
                  bellLabelUnread: 'Notifications, new items',
                  avatarColor: ZirenTokens.systemSuccess,
                ),
                // The ResQLink prototype's layout: duty as a row, then the
                // figure band. The big dial this replaced put the control a
                // responder touches twice a shift above the work they read
                // all of it.
                DutyStatusCard(
                  onDuty: true,
                  busy: false,
                  onChanged: (_) {},
                  displayName: 'Kart Michael',
                  rank: '#BFP-114',
                  agencyLabel: 'BFP Naval',
                  onTap: () {},
                ),
                const ResponderStatBand(
                  cells: [
                    ResponderStat(
                      icon: Icons.assignment_rounded,
                      value: '3',
                      label: 'Nakatalaga',
                      color: ZirenTokens.brandOrange,
                    ),
                    ResponderStat(
                      icon: Icons.warning_rounded,
                      value: '1',
                      label: 'Kritikal',
                      color: ZirenTokens.severityCritical,
                    ),
                    ResponderStat(
                      icon: Icons.check_circle_rounded,
                      value: '4',
                      label: 'Ngayon',
                      color: ZirenTokens.systemSuccess,
                    ),
                    ResponderStat(
                      icon: Icons.timer_rounded,
                      value: '9m',
                      label: 'Tugon',
                      color: ZirenTokens.statusProcessing,
                    ),
                  ],
                ),
                const HomeSectionHeading(
                  'Mga nakatalaga sa iyo',
                  action: 'Mapa',
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: kHomeGutter),
                  child: Column(
                    children: [
                      ResponderQueueCard(
                        rank: 1,
                        incident: _sample(
                          id: 'a1',
                          text:
                              'Sunog sa Balay — Tabang! Nagkasunog among balay, '
                              'daghan pa mi sulod!',
                          severity: 'critical',
                          place: 'Brgy. Larrazabal, Naval',
                          sos: true,
                        ),
                        color: ZirenTokens.severityCritical,
                        icon: ZirenTokens.severityCriticalIcon,
                        elapsed: '52m',
                        onTap: () {},
                      ),
                      const SizedBox(height: ZirenTokens.space10),
                      ResponderQueueCard(
                        rank: 2,
                        incident: _sample(
                          id: 'a2',
                          text:
                              'Aksidente sa Daan — nagbangga ang motor ug dyip',
                          severity: 'high',
                          place: 'Brgy. Caraycaray, Naval',
                        ),
                        color: ZirenTokens.severityHigh,
                        icon: ZirenTokens.severityHighIcon,
                        elapsed: '23m',
                        onTap: () {},
                      ),
                      const SizedBox(height: ZirenTokens.space10),
                      ResponderQueueCard(
                        rank: 3,
                        incident: _sample(
                          id: 'a3',
                          text: 'Baha sa may merkado, taas na ang tubig',
                          severity: 'medium',
                          place: 'Brgy. Poblacion, Naval',
                        ),
                        color: ZirenTokens.severityMedium,
                        icon: ZirenTokens.severityMediumIcon,
                        elapsed: '8m',
                        onTap: () {},
                      ),
                    ],
                  ),
                ),

                // ── The dashboard, folded into Home ──────────
                //
                // What used to be the Stats tab. Rendered here so the golden
                // covers the charts: a bar that grows the wrong way or a ring
                // that leaves a gap is invisible in a unit test and obvious in
                // an image.
                const HomeSectionHeading('On me now'),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: kHomeGutter),
                  child: Column(
                    children: [
                      ClosedPerDayChart(
                        days: [
                          for (final (i, n) in [
                            (0, 2),
                            (1, 0),
                            (2, 5),
                            (3, 3),
                            (4, 1),
                            (5, 0),
                            (6, 4),
                          ])
                            DayCount(day: DateTime(2026, 9, 1 + i), count: n),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const SeverityMixRing(
                        mix: {
                          'critical': 3,
                          'high': 6,
                          'medium': 4,
                          'low': 2,
                          'unscored': 1,
                        },
                        title: 'What you have closed',
                        emptyNote: 'Nothing closed yet.',
                      ),
                    ],
                  ),
                ),

                // One row from the Reports tab, in its closed state — the
                // muted tile is the thing worth seeing.
                const HomeSectionHeading('My reports'),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: kHomeGutter),
                  child: ReportRow(
                    incident: _sample(
                      id: 'a4',
                      text: 'Nawawalang bata sa may pantalan',
                      severity: 'medium',
                      place: 'Brgy. Atipolo, Naval',
                      status: 'resolved',
                      resolvedAt: DateTime(2026, 9, 6, 11, 15),
                    ),
                    onTap: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // Settle rather than a fixed pump: the charts animate in over ~700ms, and
    // a golden captured mid-growth would fail on any machine that scheduled
    // frames differently.
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/responder_home.png'),
    );
  });

  testWidgets('responder incoming report sheet', (tester) async {
    tester.view.physicalSize = const Size(1100, 1400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        // Widgets under test read AppLocalizations.of(context); a bare
        // MaterialApp has no delegates, so that lookup returns null and throws.
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          // The scrim the real sheet sits on, so the preview shows the
          // contrast a responder actually sees rather than a white card on
          // white.
          backgroundColor: Colors.black54,
          body: Align(
            alignment: Alignment.bottomCenter,
            child: IncomingReportSheet(
              incident: _sample(
                id: 'a9',
                text: 'Sunog sa Balay',
                severity: 'critical',
                place: 'Brgy. Larrazabal, Naval, Biliran',
                sos: true,
              ),
            ),
          ),
        ),
      ),
    );
    // A fixed pump, NOT pumpAndSettle: the dot pulses forever by design, and
    // settling on a repeating animation never returns.
    await tester.pump(const Duration(milliseconds: 600));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/responder_incoming_report.png'),
    );
  });
}

/// A queue row with only the fields the card draws. The model needs four.
ResponderIncidentModel _sample({
  required String id,
  required String text,
  required String severity,
  required String place,
  bool sos = false,
  String status = 'dispatched',
  DateTime? resolvedAt,
}) => ResponderIncidentModel(
  id: id,
  reportText: text,
  status: status,
  createdAt: DateTime(2026, 9, 6, 8, 30),
  severity: severity,
  locationAddress: place,
  sosFlag: sos,
  resolvedAt: resolvedAt,
);
