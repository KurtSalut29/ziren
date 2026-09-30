import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ziren/l10n/app_localizations.dart';
import 'package:ziren/shared/theme/app_tokens.dart';
import 'package:ziren/shared/widgets/profile_kit.dart';

/// Renders both profiles from the shared kit and writes goldens.
///
/// A design preview, not a behavioural assertion. The real screens need a
/// Supabase session before they render anything, so the only way to LOOK at
/// them was to build and install the app — which is how the responder profile
/// drifted so far from the resident one without anybody noticing.
///
/// Each golden is laid out the way its screen composes the kit (hero card,
/// then titled groups of tiles), so a change to a shared widget shows up in
/// both. The resident one is also drawn in dark mode, because the preview
/// tests used to render light only and that is how a dark-mode defect hid.
///
/// Run with:
///   flutter test --update-goldens test/profile_design_preview_test.dart
/// then open the PNGs under test/goldens/.
void main() {
  setUpAll(_loadRealFonts);

  for (final dark in [false, true]) {
    testWidgets('resident profile layout${dark ? ' (dark)' : ''}', (tester) async {
      ZirenTokens.setMode(
        brightness: dark ? Brightness.dark : Brightness.light,
        highContrast: false,
      );
      addTearDown(
        () => ZirenTokens.setMode(brightness: Brightness.light, highContrast: false),
      );
      tester.view.physicalSize = const Size(1100, 3900);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _frame(
          title: 'Profile',
          children: [
            ProfileHeroCard(
              avatar: EditableAvatar(
                displayName: 'Kurt Michael Salut',
                avatarUrl: null,
                onTap: () {},
                size: 92,
              ),
              displayName: 'Kurt Michael Salut',
              subtitle: 'kurtsalut18@gmail.com',
              chips: [
                ProfileChip(
                  label: 'Not verified',
                  color: ZirenTokens.textMuted,
                  icon: LucideIcons.shield,
                ),
                ProfileChip(
                  label: 'Larrazabal, Naval',
                  color: ZirenTokens.textSecondary,
                  icon: LucideIcons.map_pin,
                ),
              ],
            ),
            const SizedBox(height: ZirenTokens.space24),
            ProfileGroup(
              title: 'Personal Info',
              children: [
                ProfileTile(icon: LucideIcons.user, label: 'Name', value: 'Kurt Michael Salut', onTap: () {}),
                ProfileTile(icon: LucideIcons.mail, label: 'Email', value: 'kurtsalut18@gmail.com', onTap: () {}),
                ProfileTile(icon: LucideIcons.phone, label: 'Phone', value: '0917 555 0142', onTap: () {}),
                ProfileTile(icon: LucideIcons.map_pin, label: 'Address', value: 'Larrazabal, Naval', onTap: () {}),
              ],
            ),
            const SizedBox(height: ZirenTokens.space24),
            ProfileGroup(
              title: 'Emergency Contact',
              caption: 'Someone we can call if you cannot answer. Not you.',
              children: [
                ProfileTile(icon: LucideIcons.contact, label: 'Contact name', value: 'Ana Salut', onTap: () {}),
                ProfileTile(icon: LucideIcons.phone, label: 'Contact number', value: '0918 555 0101', onTap: () {}),
              ],
            ),
            const SizedBox(height: ZirenTokens.space24),
            ProfileGroup(
              title: 'Safety & help',
              children: [
                ProfileTile(
                  icon: LucideIcons.phone_call,
                  label: 'Emergency hotlines',
                  tone: ZirenTokens.systemSuccess,
                  onTap: () {},
                ),
                ProfileTile(
                  icon: LucideIcons.life_buoy,
                  label: 'How to use Ziren',
                  tone: ZirenTokens.systemInfo,
                  onTap: () {},
                ),
                ProfileTile(icon: LucideIcons.shield_plus, label: 'Safety guide', onTap: () {}),
                ProfileTile(icon: LucideIcons.megaphone, label: 'Announcements', onTap: () {}),
              ],
            ),
            const SizedBox(height: ZirenTokens.space24),
            ProfileGroup(
              title: 'Account',
              children: [
                ProfileTile(icon: LucideIcons.settings, label: 'Settings', onTap: () {}),
                ProfileTile(icon: LucideIcons.log_out, label: 'Log out', danger: true, onTap: () {}),
              ],
            ),
          ],
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(dark ? 'goldens/resident_profile_dark.png' : 'goldens/resident_profile.png'),
      );
    });
  }

  testWidgets('responder profile layout', (tester) async {
    tester.view.physicalSize = const Size(1100, 4700);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _frame(
        title: 'Profile',
        children: [
          ProfileHeroCard(
            avatar: EditableAvatar(
              displayName: 'Mark Anthony Reyes',
              avatarUrl: null,
              onTap: () {},
              size: 92,
            ),
            displayName: 'Mark Anthony Reyes',
            subtitle: 'responder@ziren.test',
            chips: const [
              ProfileChip(
                label: 'BFP Naval Station',
                color: ZirenTokens.agencyBFP,
                icon: LucideIcons.flame,
              ),
              ProfileChip(
                label: 'NAKA-DUTY',
                color: ZirenTokens.systemSuccess,
                icon: LucideIcons.wifi,
                filled: true,
              ),
            ],
            facts: const [
              ProfileFact(label: 'Badge ID', value: 'BFP-2026-0042'),
              ProfileFact(label: 'Katayuan', value: 'Aprubado', color: ZirenTokens.systemSuccess),
            ],
          ),
          const SizedBox(height: ZirenTokens.space24),
          const ProfileGroup(
            title: 'Contact',
            children: [
              ProfileTile(icon: LucideIcons.user, label: 'Pangalan', value: 'Mark Anthony Reyes'),
              ProfileTile(icon: LucideIcons.mail, label: 'Email', value: 'responder@ziren.test'),
              ProfileTile(icon: LucideIcons.phone, label: 'Numero', value: '0917 555 0199'),
            ],
          ),
          const SizedBox(height: ZirenTokens.space24),
          ProfileGroup(
            title: 'Istasyon',
            children: [
              const ProfileTile(
                icon: LucideIcons.flame,
                tone: ZirenTokens.agencyBFP,
                label: 'Ahensya',
                value: 'BFP Naval Station',
              ),
              const ProfileTile(icon: LucideIcons.map_pin, label: 'Munisipyo', value: 'Naval'),
              ProfileTile(
                icon: LucideIcons.phone_call,
                tone: ZirenTokens.systemSuccess,
                label: 'Numero ng istasyon',
                value: 'Globe 0955-723-6300\nSmart 0948-024-3466\nLandline (053) 500-9546',
                onTap: () {},
              ),
            ],
          ),
          const SizedBox(height: ZirenTokens.space24),
          ProfileGroup(
            title: 'Kaligtasan at tulong',
            children: [
              ProfileTile(
                icon: LucideIcons.phone_call,
                tone: ZirenTokens.systemSuccess,
                label: 'Mga hotline pang-emergency',
                onTap: () {},
              ),
              ProfileTile(
                icon: LucideIcons.life_buoy,
                tone: ZirenTokens.systemInfo,
                label: 'Paano gamitin ang Ziren',
                onTap: () {},
              ),
            ],
          ),
          const SizedBox(height: ZirenTokens.space24),
          ProfileGroup(
            title: 'Account',
            children: [
              ProfileTile(icon: LucideIcons.settings, label: 'Mga setting', onTap: () {}),
              // Mid-save: no onTap, so the row is dimmed.
              const ProfileTile(icon: LucideIcons.log_out, label: 'Mag-log out', danger: true),
            ],
          ),
          const SizedBox(height: ZirenTokens.space16),
          ProfileLoadError(message: 'Could not reach the server.', onRetry: () {}),
        ],
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/responder_profile.png'),
    );
  });
}

Widget _frame({required String title, required List<Widget> children}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      appBar: AppBar(
        backgroundColor: ZirenTokens.surfaceBase,
        title: Text(
          title,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: ZirenTokens.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () {},
            icon: Icon(LucideIcons.settings, color: ZirenTokens.textPrimary),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            ZirenTokens.space16,
            ZirenTokens.space4,
            ZirenTokens.space16,
            ZirenTokens.space32,
          ),
          children: children,
        ),
      ),
    ),
  );
}

/// Load Roboto and the Lucide icon font so the goldens show TEXT and ICONS
/// instead of boxes.
///
/// Flutter's test environment ships a placeholder font that draws every glyph
/// as a full-em square. That is fine for catching structural regressions and
/// actively misleading for reading a layout: a 26-character email measures
/// about twice its real width, so rows appear to wrap when the shipping app
/// would fit them on one line. A preview whose whole purpose is to be looked
/// at has to render what the phone renders.
///
/// Roboto ships inside the Flutter SDK and Lucide in the pub cache, so nothing
/// is added to pubspec. If either is missing, the goldens still generate —
/// with boxes — and the test does not fail over a design preview.
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
          .where((d) => d.path.split(RegExp(r'[\\/]')).last.startsWith('flutter_lucide-'))
          .map((d) => File('${d.path}/lib/fonts/lucide.ttf'))
          .where((f) => f.existsSync())
          .toList();
  if (lucide.isEmpty) return;
  final iconLoader = FontLoader('packages/flutter_lucide/lucide');
  iconLoader.addFont(lucide.last.readAsBytes().then((b) => ByteData.view(b.buffer)));
  await iconLoader.load();
}
