import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ziren/features/incident_report/data/media_upload_service.dart';
import 'package:ziren/features/incident_report/presentation/widgets/media_attachment_field.dart';
import 'package:ziren/l10n/app_localizations.dart';

/// Evaluator findings #20 and #21 (2026-10-05): a video over 50 MB was refused
/// only after Submit. The limits are now on the form, before and after a file
/// is added, and a file is checked the moment it is chosen.
void main() {
  test('the per-file limit is 50 MB, checked by size alone', () {
    expect(MediaUploadService.maxSizeMb, 50);
    expect(MediaUploadService.exceedsLimit(50 * 1024 * 1024), isFalse);
    expect(MediaUploadService.exceedsLimit(50 * 1024 * 1024 + 1), isTrue);
    expect(MediaUploadService.maxVideoLength, const Duration(minutes: 2));
  });

  testWidgets('the limits stay visible after a file is attached', (tester) async {
    Future<void> pump(List<File> media) => tester.pumpWidget(MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: MediaAttachmentField(
              media: media,
              error: null,
              hint: 'Up to 5 files, 50 MB each, videos up to 2 minutes.',
              onAdd: (ImageSource s, bool v) async {},
              onRemove: (_) {},
            ),
          ),
        ));

    await pump(const []);
    expect(find.textContaining('50 MB'), findsOneWidget);
    await pump([File('does-not-exist.jpg')]);
    await tester.pump();
    expect(find.textContaining('50 MB'), findsOneWidget, reason: 'not only on an empty field');
  });

  test('the English and Filipino hints state size, count and video length', () {
    final en = lookupAppLocalizations(const Locale('en'));
    final fil = lookupAppLocalizations(const Locale('fil'));
    for (final t in [en, fil]) {
      expect(t.quickMediaHint, contains('50 MB'));
      expect(t.quickMediaHint, contains('5'));
      expect(t.quickMediaHint, contains('2'));
      expect(t.mediaTooLarge('72', '50'), allOf(contains('72'), contains('50')));
    }
  });
}
