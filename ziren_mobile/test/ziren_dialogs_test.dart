import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ziren/features/notifications/domain/notification_provider.dart';
import 'package:ziren/features/notifications/presentation/notice_view.dart';
import 'package:ziren/features/notifications/presentation/widgets/status_update_sheet.dart';
import 'package:ziren/features/settings/presentation/about_ziren_dialog.dart';
import 'package:ziren/l10n/app_localizations.dart';
import 'package:ziren/shared/widgets/ziren_dialogs.dart';
import 'package:ziren/shared/widgets/ziren_photo_sheet.dart';

/// "I can't tell if these are clickable" - the About Ziren dialog's Terms of Use,
/// Data Privacy Notice and Cancel were bare words in a row.
///
/// Every dialog and sheet now built on [ZirenDialog] / [showZirenOptionSheet] must:
/// draw each choice as something pressable, centre it, resolve to what was pressed,
/// and never overflow - on the smallest phone still around, with the system font
/// turned up, in both languages.
const _sizes = <Size>[Size(320, 568), Size(360, 720), Size(412, 915)];
const _scales = <double>[1.0, 1.3, 2.0];
const _locales = <Locale>[Locale('en'), Locale('fil')];

/// audioplayers talks to a platform channel the moment a player exists; a widget
/// test has none, and the chime swallows its own failures, so a stub keeps the
/// (real) sheet testable.
void _stubAudio() {
  const channels = ['xyz.luan/audioplayers', 'xyz.luan/audioplayers.global'];
  for (final name in channels) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(name), (call) async => null);
  }
}

/// The progress rail pulses its active step forever, so `pumpAndSettle` would
/// never return on a notice that has one. A fixed pump is enough for a dialog to
/// finish opening (or closing).
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<BuildContext> _pump(
  WidgetTester tester, {
  Size size = const Size(360, 720),
  double scale = 1.0,
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder:
          (context, home) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: home!,
          ),
      home: Scaffold(
        body: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  return captured;
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    _stubAudio();
  });

  group('About Ziren', () {
    for (final size in _sizes) {
      for (final scale in _scales) {
        for (final locale in _locales) {
          testWidgets(
            'has no overflow @ ${size.width.toInt()}dp x$scale ${locale.languageCode}',
            (tester) async {
              final context = await _pump(tester, size: size, scale: scale, locale: locale);
              final t = AppLocalizations.of(context);
              showAboutZirenDialog(context, onOpenTerms: () {}, onOpenPrivacy: () {});
              await tester.pumpAndSettle();

              expect(tester.takeException(), isNull);
              expect(find.text('Ziren'), findsOneWidget);
              expect(find.text(t.settingsAboutTerms), findsOneWidget);
              expect(find.text(t.settingsAboutPrivacy), findsOneWidget);
              expect(find.text(t.actionClose), findsOneWidget);
            },
          );
        }
      }
    }

    testWidgets('the two documents are rows you can press, and each opens its own', (tester) async {
      final context = await _pump(tester);
      final t = AppLocalizations.of(context);
      var terms = 0;
      var privacy = 0;
      showAboutZirenDialog(context, onOpenTerms: () => terms++, onOpenPrivacy: () => privacy++);
      await tester.pumpAndSettle();

      // Pressable: each is a ZirenOptionTile, which is an InkWell with a chevron.
      expect(find.byType(ZirenOptionTile), findsNWidgets(2));
      expect(find.byIcon(Icons.chevron_right), findsNothing); // Lucide, not Material
      await tester.tap(find.text(t.settingsAboutTerms));
      await tester.pumpAndSettle();
      expect(terms, 1);
      expect(privacy, 0);
      expect(find.text('Ziren'), findsNothing, reason: 'it closes before the document opens');

      showAboutZirenDialog(context, onOpenTerms: () => terms++, onOpenPrivacy: () => privacy++);
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.settingsAboutPrivacy));
      await tester.pumpAndSettle();
      expect(privacy, 1);
    });

    testWidgets('everything is centred', (tester) async {
      final context = await _pump(tester);
      final t = AppLocalizations.of(context);
      showAboutZirenDialog(context, onOpenTerms: () {}, onOpenPrivacy: () {});
      await tester.pumpAndSettle();

      final dialog = tester.getRect(find.byType(ZirenDialog<void>));
      double cx(Finder f) => tester.getCenter(f).dx;
      // The title, the tagline and the Close button all sit on the dialog's middle.
      expect(cx(find.text('Ziren')), closeTo(dialog.center.dx, 2));
      expect(cx(find.text(t.settingsAboutTagline)), closeTo(dialog.center.dx, 2));
      expect(cx(find.text(t.actionClose)), closeTo(dialog.center.dx, 2));
      // ...and Close is a real button spanning the dialog's content, not a word.
      final close = tester.getRect(find.ancestor(of: find.text(t.actionClose), matching: find.byType(OutlinedButton)));
      expect(close.width, greaterThan(dialog.width * 0.7));
      expect(close.height, greaterThanOrEqualTo(48));
    });

    testWidgets('Close closes it', (tester) async {
      final context = await _pump(tester);
      final t = AppLocalizations.of(context);
      showAboutZirenDialog(context, onOpenTerms: () {}, onOpenPrivacy: () {});
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.actionClose));
      await tester.pumpAndSettle();
      expect(find.text('Ziren'), findsNothing);
    });

    testWidgets('a screen reader hears them as buttons', (tester) async {
      final handle = tester.ensureSemantics();
      final context = await _pump(tester);
      final t = AppLocalizations.of(context);
      showAboutZirenDialog(context, onOpenTerms: () {}, onOpenPrivacy: () {});
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.text(t.settingsAboutTerms)),
        matchesSemantics(label: t.settingsAboutTerms, isButton: true, hasTapAction: true),
      );
      handle.dispose();
    });
  });

  group('showZirenDialog', () {
    for (final size in _sizes) {
      for (final scale in _scales) {
        testWidgets('long copy and three actions do not overflow @ ${size.width.toInt()}dp x$scale', (tester) async {
          final context = await _pump(tester, size: size, scale: scale);
          showZirenDialog<int>(
            context,
            icon: Icons.warning,
            tone: ZirenTone.danger,
            title: 'Move this report to Trash and remove it from the dispatcher list?',
            message:
                'It will be moved to Trash and taken off the dispatcher\'s list. Reports in Trash are '
                'permanently deleted after 30 days. Do this only if help is no longer needed.',
            actions: const [
              ZirenDialogAction(label: 'Move to Trash', value: 1, kind: ZirenActionKind.danger),
              ZirenDialogAction(label: 'Keep the report and keep it on the list', value: 2, kind: ZirenActionKind.primary),
              ZirenDialogAction(label: 'Cancel', value: 3),
            ],
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('resolves to the action that was pressed', (tester) async {
      final context = await _pump(tester);
      final result = showZirenDialog<String>(
        context,
        title: 'Log out?',
        actions: const [
          ZirenDialogAction(label: 'Log out', value: 'out', kind: ZirenActionKind.danger),
          ZirenDialogAction(label: 'Cancel', value: 'stay'),
        ],
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();
      expect(await result, 'out');
    });

    testWidgets('an outside tap dismisses to null, not to an action', (tester) async {
      final context = await _pump(tester);
      final result = showZirenDialog<String>(
        context,
        title: 'Log out?',
        actions: const [ZirenDialogAction(label: 'Log out', value: 'out', kind: ZirenActionKind.danger)],
      );
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(await result, isNull);
    });

    testWidgets('every action is a button at least 48dp tall', (tester) async {
      final context = await _pump(tester);
      showZirenDialog<int>(
        context,
        title: 'Choose',
        actions: const [
          ZirenDialogAction(label: 'One', value: 1, kind: ZirenActionKind.primary),
          ZirenDialogAction(label: 'Two', value: 2),
        ],
      );
      await tester.pumpAndSettle();
      for (final label in ['One', 'Two']) {
        final button = find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));
        expect(button, findsOneWidget, reason: label);
        expect(tester.getSize(button).height, greaterThanOrEqualTo(48), reason: label);
      }
    });
  });

  group('showZirenOptionSheet', () {
    for (final size in _sizes) {
      for (final scale in _scales) {
        for (final locale in _locales) {
          testWidgets('photo source sheet has no overflow @ ${size.width.toInt()}dp x$scale ${locale.languageCode}', (tester) async {
            final context = await _pump(tester, size: size, scale: scale, locale: locale);
            showZirenPhotoSourceSheet(
              context,
              title: 'Add a photo or video',
              takePhoto: 'Take a photo',
              recordVideo: 'Record a video',
              chooseFromGallery: 'Choose from gallery',
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          });
        }
      }
    }

    testWidgets('resolves to the option pressed', (tester) async {
      final context = await _pump(tester);
      final result = showZirenPhotoSourceSheet(
        context,
        title: 'Add a photo',
        takePhoto: 'Take a photo',
        recordVideo: 'Record a video',
        chooseFromGallery: 'Choose from gallery',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Record a video'));
      await tester.pumpAndSettle();
      expect(await result, ZirenPhotoSource.video);
    });

    testWidgets('stills only when no video is offered', (tester) async {
      final context = await _pump(tester);
      showZirenPhotoSourceSheet(context, title: 'Add', takePhoto: 'Take a photo', chooseFromGallery: 'Gallery');
      await tester.pumpAndSettle();
      expect(find.byType(ZirenOptionTile), findsNWidgets(2));
    });

    testWidgets('Cancel resolves to null', (tester) async {
      final context = await _pump(tester);
      final t = AppLocalizations.of(context);
      final result = showZirenPhotoSourceSheet(context, title: 'Add', takePhoto: 'Take', chooseFromGallery: 'Gallery');
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.settingsCancel));
      await tester.pumpAndSettle();
      expect(await result, isNull);
    });

    testWidgets('the current choice in a list is marked', (tester) async {
      await _pump(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                ZirenOptionTile(icon: Icons.language, label: 'Filipino', selected: true, onTap: () {}),
                ZirenOptionTile(icon: Icons.language, label: 'English', onTap: () {}),
              ],
            ),
          ),
        ),
      );
      final handle = tester.ensureSemantics();
      expect(tester.getSemantics(find.text('Filipino')), matchesSemantics(label: 'Filipino', isButton: true, isSelected: true, hasTapAction: true));
      handle.dispose();
    });
  });

  group('the notice a resident is shown', () {
    AppNotification n(String status, {NotificationKind kind = NotificationKind.status, String? detail}) =>
        AppNotification(
          incidentId: 'inc-1',
          reportText: 'smoke',
          newStatus: status,
          receivedAt: DateTime.utc(2026, 9, 25),
          kind: kind,
          detail: detail,
          etaMinutes: status == 'dispatched' ? 7 : null,
          respondingAgency: status == 'dispatched' ? 'BFP Naval' : null,
        );

    final notices = <String, AppNotification>{
      'processing': n('processing'),
      'accepted': n('accepted', kind: NotificationKind.accepted),
      'dispatched': n('dispatched'),
      'en_route': n('en_route'),
      'arrived': n('arrived'),
      'resolved': n('resolved'),
      'cancelled': n('cancelled', kind: NotificationKind.cancelled, detail: 'Duplicate of another report that was already being handled by the station'),
      'rejected': n('rejected', kind: NotificationKind.rejected, detail: 'Unable to verify the location you gave'),
      'clarification': n('clarification_requested', kind: NotificationKind.clarification, detail: 'Which barangay, and which house is on fire? Please describe it.'),
      'message': n('message', kind: NotificationKind.message, detail: 'Please stay on the line. A crew is two minutes away.'),
    };

    for (final entry in notices.entries) {
      for (final size in _sizes) {
        for (final scale in const [1.0, 2.0]) {
          for (final locale in _locales) {
            testWidgets('${entry.key} has no overflow @ ${size.width.toInt()}dp x$scale ${locale.languageCode}', (tester) async {
              final context = await _pump(tester, size: size, scale: scale, locale: locale);
              StatusUpdateSheet.show(context, entry.value);
              await _settle(tester);
              expect(tester.takeException(), isNull);
              // Got it is always there.
              expect(find.text(AppLocalizations.of(context).notifStatusOk), findsOneWidget);
            });
          }
        }
      }
    }

    testWidgets('a question offers Reply now and resolves to the chat', (tester) async {
      final context = await _pump(tester);
      final t = AppLocalizations.of(context);
      final result = StatusUpdateSheet.show(context, notices['clarification']!);
      await _settle(tester);
      expect(find.text(t.notifReplyNow), findsOneWidget);
      await tester.tap(find.text(t.notifReplyNow));
      await _settle(tester);
      expect(await result, NoticeAction.openChat);
    });

    testWidgets('a cancellation quotes why and offers the report', (tester) async {
      final context = await _pump(tester);
      final t = AppLocalizations.of(context);
      final result = StatusUpdateSheet.show(context, notices['cancelled']!);
      await _settle(tester);
      expect(find.textContaining('Duplicate of another report'), findsOneWidget);
      await tester.tap(find.text(t.notifViewReport));
      await _settle(tester);
      expect(await result, NoticeAction.viewReport);
    });

    testWidgets('Got it dismisses', (tester) async {
      final context = await _pump(tester);
      final t = AppLocalizations.of(context);
      final result = StatusUpdateSheet.show(context, notices['arrived']!);
      await _settle(tester);
      await tester.tap(find.text(t.notifStatusOk));
      await _settle(tester);
      expect(await result, NoticeAction.dismiss);
    });

    testWidgets('an outside tap is a dismissal, not an action', (tester) async {
      final context = await _pump(tester);
      final result = StatusUpdateSheet.show(context, notices['resolved']!);
      await _settle(tester);
      await tester.tapAt(const Offset(4, 4));
      await _settle(tester);
      expect(await result, NoticeAction.dismiss);
    });
  });
}
