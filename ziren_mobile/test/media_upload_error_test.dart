import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ziren/features/incident_report/data/media_upload_service.dart';

/// A photo the network could not carry must not be reported as a photo the
/// server refused. The provider stops a report for the second and sends the
/// report without the photo for the first; every failure used to arrive as the
/// second, so a resident with a photo attached and no data got "Upload failed"
/// and no report at all, even though the (much smaller) report on its own
/// might still have gone through.
void main() {
  group('isNetworkError', () {
    test('the network failing', () {
      expect(MediaUploadService.isNetworkError(const SocketException('x')), isTrue);
      expect(MediaUploadService.isNetworkError(TimeoutException('x')), isTrue);
      expect(MediaUploadService.isNetworkError(http.ClientException('x')), isTrue);
      expect(
        MediaUploadService.isNetworkError(const HandshakeException('x')),
        isTrue,
      );
    });

    test('the storage client keeping only the text of a transport error', () {
      expect(
        MediaUploadService.isNetworkError(
          Exception(
            'ClientException with SocketException: Failed host lookup: '
            "'trajycnqsgoplscpmjbj.supabase.co'",
          ),
        ),
        isTrue,
      );
      expect(
        MediaUploadService.isNetworkError(
          Exception('Connection reset by peer (OS Error, errno = 104)'),
        ),
        isTrue,
      );
    });

    test('Storage refusing the file is not the network', () {
      expect(
        MediaUploadService.isNetworkError(
          Exception('mime type audio/mp4 is not supported'),
        ),
        isFalse,
      );
      expect(
        MediaUploadService.isNetworkError(
          Exception('{"statusCode":"413","error":"Payload too large"}'),
        ),
        isFalse,
      );
      expect(
        MediaUploadService.isNetworkError(
          Exception('new row violates row-level security policy'),
        ),
        isFalse,
      );
    });
  });
}
