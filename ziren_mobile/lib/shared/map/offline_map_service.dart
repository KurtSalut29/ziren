/// Serves the bundled Biliran vector tiles to MapLibre when there is no
/// internet, and decides which of the two Ziren map styles a screen should
/// load.
///
/// TODO 6C.1 (see the history comment on [kZirenMapStyle]) asked for an
/// mbtiles reader wired into MapLibre. This is it: the tiles in
/// `assets/map/biliran.mbtiles` are vector (pbf), so they cannot be handed
/// to MapLibre as a `tiles` URL template the way the raster satellite style
/// is — there is nothing on disk to point a URL at. MapLibre's native layer
/// only knows how to fetch tiles over HTTP, so this copies the asset to a
/// real file, opens it with `sqlite3`, and answers a tiny HTTP server bound
/// to `127.0.0.1` that reads each tile out of the database on request. The
/// style then points at that loopback server instead of a real host.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'ziren_map_style.dart';

class OfflineMapService {
  OfflineMapService._();

  static final OfflineMapService instance = OfflineMapService._();

  int? _port;
  Future<int>? _startingServer;

  /// Whichever style a map should load right now: the real satellite view
  /// if the internet is reachable, otherwise the offline vector style
  /// served from the copy of `biliran.mbtiles` on disk.
  ///
  /// A resident or responder standing in a dead zone gets the offline style
  /// immediately rather than a map that sits blank while raster tile
  /// requests time out one by one.
  Future<String> resolveStyle() async {
    if (await _isOnlineReachable()) return kZirenMapStyle;
    final port = await _ensureServerRunning();
    return buildOfflineStyle(port);
  }

  /// A short, cheap probe against the same host the satellite layer itself
  /// tiles from — not just "is the radio on". A phone can sit on a wifi or
  /// mobile network with no route to the internet at all, and a resident
  /// deciding whether the map needs offline mode does not care which layer
  /// of the network stack failed.
  ///
  /// 3s was the original budget but false-triggered offline mode on a real
  /// 2-bar 4G connection during 2026-09-14 field testing (Biliran has patchy
  /// coverage even where there IS a signal) — the tile loaded fine in a
  /// browser on the same phone, just slower than 3s. 8s still fails fast in
  /// an actual dead zone (that case returns near-instantly, no signal to
  /// wait on) while giving a weak-but-working connection room to answer.
  Future<bool> _isOnlineReachable() async {
    try {
      final uri = Uri.parse(
        'https://server.arcgisonline.com/ArcGIS/rest/services/'
        'World_Imagery/MapServer/tile/0/0/0',
      );
      final response = await http
          .head(uri)
          .timeout(const Duration(seconds: 8));
      return response.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  Future<int> _ensureServerRunning() {
    return _startingServer ??= _startServer();
  }

  Future<int> _startServer() async {
    final existingPort = _port;
    if (existingPort != null) return existingPort;

    final db = await _openDatabase();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = server.port;

    server.listen((request) => _handleTileRequest(request, db));
    return server.port;
  }

  Future<Database> _openDatabase() async {
    final supportDir = await getApplicationSupportDirectory();
    final file = File('${supportDir.path}/biliran.mbtiles');

    final assetBytes = await rootBundle.load('assets/map/biliran.mbtiles');
    // Re-copied whenever the size differs from the bundled asset, so a
    // future app update that ships a refreshed extract replaces the stale
    // one a previous install left on disk — the common case (same size) is
    // a single stat call, not a multi-megabyte copy on every launch.
    if (!await file.exists() ||
        await file.length() != assetBytes.lengthInBytes) {
      await file.writeAsBytes(
        assetBytes.buffer.asUint8List(
          assetBytes.offsetInBytes,
          assetBytes.lengthInBytes,
        ),
      );
    }

    return sqlite3.open(file.path);
  }

  void _handleTileRequest(HttpRequest request, Database db) {
    final segments = request.uri.pathSegments;
    // Expected shape: tiles/{z}/{x}/{y}.pbf
    if (segments.length != 4 || segments[0] != 'tiles') {
      request.response
        ..statusCode = HttpStatus.notFound
        ..close();
      return;
    }

    final z = int.tryParse(segments[1]);
    final x = int.tryParse(segments[2]);
    final yWithExt = segments[3];
    final dot = yWithExt.indexOf('.');
    final y = int.tryParse(dot == -1 ? yWithExt : yWithExt.substring(0, dot));
    if (z == null || x == null || y == null) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..close();
      return;
    }

    // MapLibre requests tiles XYZ-style (y = 0 at the north pole); MBTiles
    // stores rows TMS-style (y = 0 at the south pole) — the two count from
    // opposite edges of the same z-level grid. Flipped here, server-side,
    // rather than via the vector source's `"scheme": "tms"` style property:
    // that property is well-supported for raster sources but silently did
    // nothing for this vector one, so every request landed on the wrong row
    // and came back empty — a flat background with no shapes, no error
    // logged anywhere, because a 204 for a real-looking coordinate looks
    // exactly like a 204 for a coordinate past the coastline.
    final tmsRow = (1 << z) - 1 - y;

    final rows = db.select(
      'SELECT tile_data FROM tiles '
      'WHERE zoom_level = ? AND tile_column = ? AND tile_row = ?',
      [z, x, tmsRow],
    );

    if (rows.isEmpty) {
      // No tile at this coordinate (open water past the coastline, or past
      // the extract's bounds) — a 204 tells MapLibre this address is
      // legitimately empty, not broken.
      request.response
        ..statusCode = HttpStatus.noContent
        ..close();
      return;
    }

    final data = rows.first['tile_data'] as List<int>;
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.set(HttpHeaders.contentTypeHeader, 'application/x-protobuf')
      // MBTiles stores each tile gzip-compressed already — passed straight
      // through rather than decompressed and re-sent.
      ..headers.set(HttpHeaders.contentEncodingHeader, 'gzip')
      ..headers.set('Access-Control-Allow-Origin', '*')
      ..add(data)
      ..close();
  }
}
