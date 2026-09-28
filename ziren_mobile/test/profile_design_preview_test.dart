import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Ziren/shared/theme/app_tokens.dart';
import 'package:Ziren/shared/widgets/profile_kit.dart';

/// Renders both profiles from the shared kit and writes goldens.
///
/// A design preview, not a behavioural assertion. The real screens need a
/// Supabase session before they render anything, so the only way to LOOK at
/// them was to build and install the app — which is how the responder profile
/// drifted so far from the resident one without anybody noticing.
///
/// The two goldens are deliberately produced from the same widgets, so a
/// change that makes one of them look wrong makes it visible in the other.
///
/// Run with:
///   flutter test --update-goldens test/profile_design_preview_test.dart
/// then open the PNGs under test/goldens/.
void main() {
  setUpAll(_loadRealFonts);

  testWidgets('resident profile layout', (tester) async {
    tester.view.physicalSize = const Size(1100, 1700);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _frame(
        title: 'Profile',
        children: [
          const ProfileAvatarHeader(
            displayName: 'Kurt Michael Salut',
            subtitle: 'kurtsalut18@gmail.com',
          ),
          const SizedBox(height: ZirenTokens.space24),
          ProfileSection(
            title: 'Personal Information',
            items: const [
              ProfileRow(
                icon: Icons.person_rounded,
                label: 'Name',
                value: 'Kurt Michael Salut',
              ),
              ProfileRow(
                icon: Icons.email_rounded,
                label: 'Email',
                value: 'kurtsalut18@gmail.com',
              ),
              ProfileRow(
                icon: Icons.phone_rounded,
                label: 'Phone',
                value: '0917 555 0142',
                last: true,
              ),
            ],
          ),
          const SizedBox(height: ZirenTokens.space16),
          ProfileSection(
            title: 'Address',
            items: const [
              ProfileRow(
                icon: Icons.home_rounded,
                label: 'Barangay',
                value: 'Larrazabal',
              ),
              ProfileRow(
                icon: Icons.location_city_rounded,
                label: 'Municipality',
                value: 'Naval',
                last: true,
              ),
            ],
          ),
        ],
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/resident_profile.png'),
    );
  });

  testWidgets('responder profile layout', (tester) async {
    tester.view.physicalSize = const Size(1100, 2100);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _frame(
        title: 'Profile',
        children: [
          const ProfileAvatarHeader(
            displayName: 'Mark Anthony Reyes',
            subtitle: 'markanthonyreyes@gmail.com',
            badge: ProfileChip(
              label: 'BFP Naval Station',
              color: ZirenTokens.agencyBFP,
              icon: Icons.local_fire_department_rounded,
            ),
            trailing: ProfileChip(
              label: 'NAKA-DUTY',
              color: ZirenTokens.systemSuccess,
              icon: Icons.wifi_tethering_rounded,
              filled: true,
            ),
          ),
          const SizedBox(height: ZirenTokens.space24),
          ProfileSection(
            title: 'Contact',
            items: const [
              ProfileRow(
                icon: Icons.person_rounded,
                label: 'Pangalan',
                value: 'Mark Anthony Reyes',
              ),
              ProfileRow(
                icon: Icons.email_rounded,
                label: 'Email',
                value: 'markanthonyreyes@gmail.com',
              ),
              ProfileRow(
                icon: Icons.phone_rounded,
                label: 'Numero',
                value: '0917 555 0199',
                last: true,
              ),
            ],
          ),
          const SizedBox(height: ZirenTokens.space16),
          ProfileSection(
            title: 'Assignment',
            items: const [
              ProfileRow(
                icon: Icons.badge_rounded,
                label: 'Badge ID',
                value: 'BFP-2026-0042',
              ),
              ProfileRow(
                icon: Icons.local_fire_department_rounded,
                label: 'Ahensya',
                value: 'BFP Naval Station',
                valueColor: ZirenTokens.agencyBFP,
              ),
              ProfileRow(
                icon: Icons.place_rounded,
                label: 'Munisipyo',
                value: 'Naval',
              ),
              ProfileRow(
                icon: Icons.verified_rounded,
                label: 'Katayuan',
                value: 'Aprubado',
                valueColor: ZirenTokens.systemSuccess,
                last: true,
              ),
            ],
          ),
          const SizedBox(height: ZirenTokens.space16),
          ProfileSection(
            title: 'Ngayong shift',
            items: const [
              ProfileRow(
                icon: Icons.assignment_rounded,
                label: 'Nakatalaga ngayon',
                value: '1',
              ),
              ProfileRow(
                icon: Icons.cloud_off_rounded,
                label: 'Naka-antabay na ipadala',
                value: '2',
                valueColor: ZirenTokens.systemWarning,
                last: true,
              ),
            ],
          ),
          const SizedBox(height: ZirenTokens.space24),
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Mag-log out'),
            style: OutlinedButton.styleFrom(
              foregroundColor: ZirenTokens.systemError,
              side: BorderSide(
                color: ZirenTokens.systemError.withValues(alpha: 0.5),
              ),
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ],
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/responder_profile.png'),
    );
  });

  testWidgets('responder profile, edit mode', (tester) async {
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    final name = TextEditingController(text: 'Mark Anthony Reyes');
    final phone = TextEditingController(text: '0917 555 0199');
    addTearDown(name.dispose);
    addTearDown(phone.dispose);

    await tester.pumpWidget(
      _frame(
        title: 'Profile',
        children: [
          // The point of this golden: an editable row keeps the card's
          // geometry. The old screen dropped outlined TextFormFields into the
          // scroll view, which is what made it read as a settings form.
          ProfileSection(
            title: 'Contact',
            action: TextButton(
              onPressed: () {},
              style: TextButton.styleFrom(
                foregroundColor: ZirenTokens.brandOrange,
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: const Text('Save'),
            ),
            items: [
              ProfileEditRow(
                icon: Icons.person_rounded,
                label: 'Pangalan',
                controller: name,
              ),
              ProfileEditRow(
                icon: Icons.phone_rounded,
                label: 'Numero',
                controller: phone,
                hintText: '09xxxxxxxxx',
                keyboardType: TextInputType.phone,
                last: true,
              ),
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
      matchesGoldenFile('goldens/responder_profile_edit.png'),
    );
  });
}

Widget _frame({required String title, required List<Widget> children}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: ZirenTokens.surfaceBase,
      appBar: AppBar(
        title: Text(title),
        actions: [
          TextButton.icon(
            onPressed: () {},
            icon: const Icon(
              Icons.edit_outlined,
              size: 16,
              color: ZirenTokens.brandOrange,
            ),
            label: const Text(
              'Edit',
              style: TextStyle(
                color: ZirenTokens.brandOrange,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(ZirenTokens.space16),
          children: children,
        ),
      ),
    ),
  );
}

/// Load Roboto so the goldens show TEXT instead of boxes.
///
/// Flutter's test environment ships a placeholder font that draws every glyph
/// as a full-em square. That is fine for catching structural regressions and
/// actively misleading for reading a layout: a 26-character email measures
/// about twice its real width, so rows appear to wrap when the shipping app
/// would fit them on one line. A preview whose whole purpose is to be looked
/// at has to render what the phone renders.
///
/// Roboto ships inside the Flutter SDK, so nothing is added to pubspec. If the
/// cache is missing the fonts, the goldens still generate — with boxes — and
/// the test does not fail over a design preview.
Future<void> _loadRealFonts() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  final candidates = <String>[
    if (flutterRoot != null)
      '$flutterRoot/bin/cache/artifacts/material_fonts',
    'C:/src/flutter/bin/cache/artifacts/material_fonts',
  ];

  for (final dir in candidates) {
    final regular = File('$dir/roboto-regular.ttf');
    final bold = File('$dir/roboto-bold.ttf');
    if (!regular.existsSync()) continue;

    final loader = FontLoader('Roboto');
    loader.addFont(
      regular.readAsBytes().then((b) => ByteData.view(b.buffer)),
    );
    if (bold.existsSync()) {
      loader.addFont(bold.readAsBytes().then((b) => ByteData.view(b.buffer)));
    }
    await loader.load();

    // The icon font too, or every Icon renders as an empty square and the
    // preview cannot show whether the row icons read correctly.
    final icons = File('$dir/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      final iconLoader = FontLoader('MaterialIcons');
      iconLoader.addFont(
        icons.readAsBytes().then((b) => ByteData.view(b.buffer)),
      );
      await iconLoader.load();
    }
    return;
  }
}
