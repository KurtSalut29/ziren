import 'dart:math' as math;

import '../../incident_report/domain/incident_provider.dart';

/// One dialable number: "Globe 0955-723-6300".
class HotlineNumber {
  const HotlineNumber(this.display, {this.label});

  /// As written for people: "0955-723-6300", "(053) 500-9546".
  final String display;

  /// The network or line, when the station gave one: Globe, Smart, Landline.
  final String? label;

  /// What the phone dials: digits only (and a leading +), so "(053) 500-9546"
  /// becomes 0535009546 — a landline dialled from a mobile in the Philippines.
  String get dial {
    final plus = display.trim().startsWith('+') ? '+' : '';
    return plus + display.replaceAll(RegExp(r'[^0-9]'), '');
  }

  Uri get telUri => Uri(scheme: 'tel', path: dial);

  @override
  bool operator ==(Object other) => other is HotlineNumber && other.dial == dial;

  @override
  int get hashCode => dial.hashCode;
}

/// A station, or a unit that is not a Ziren agency (a town's Rural Health
/// Unit), and the numbers a resident can call it on.
class StationHotline {
  const StationHotline({
    required this.municipality,
    required this.agencyType,
    required this.name,
    required this.numbers,
    this.agencyId,
  });

  final String municipality;

  /// BFP, PNP, MDRRMO — or RHU, which is not a Ziren agency but is who a
  /// town sends for a medical emergency.
  final String agencyType;
  final String name;
  final List<HotlineNumber> numbers;

  /// The Ziren agency this belongs to; null for an RHU.
  final String? agencyId;

  StationHotline withNumbers(List<HotlineNumber> n) => StationHotline(
        municipality: municipality,
        agencyType: agencyType,
        name: name,
        numbers: n,
        agencyId: agencyId,
      );
}

/// The official hotline of every station in Biliran.
///
/// WHY A COPY LIVES IN THE APP
///
/// These numbers exist for the moment Ziren cannot reach its server — no
/// data, no signal for the internet, only enough for a call. A list fetched
/// from the server is exactly what is missing then, so the app ships its own.
/// The database (agencies.contact_number, migration 042) holds the same
/// numbers and is what the dashboard shows and an agency admin edits; when
/// the app is online and the database has a number, that wins (see
/// [directory]). Keep this list and migration 042 in step.
///
/// Supplied by the stations, 2026-09-30. Maripipi has no Ziren station.
class StationHotlines {
  StationHotlines._();

  static const List<StationHotline> bundled = [
    // ── Naval ─────────────────────────────────────────────
    StationHotline(
      municipality: 'Naval', agencyType: 'BFP', name: 'BFP Naval Station',
      agencyId: 'a0000001-0000-0000-0000-000000000001',
      numbers: [
        HotlineNumber('0955-723-6300', label: 'Globe'),
        HotlineNumber('0948-024-3466', label: 'Smart'),
        HotlineNumber('(053) 500-9546', label: 'Landline'),
      ],
    ),
    StationHotline(
      municipality: 'Naval', agencyType: 'PNP', name: 'PNP Naval Station',
      agencyId: 'a0000001-0000-0000-0000-000000000002',
      numbers: [HotlineNumber('0921-555-3961', label: 'Smart')],
    ),
    StationHotline(
      municipality: 'Naval', agencyType: 'MDRRMO', name: 'MDRRMO Naval',
      agencyId: 'a0000001-0000-0000-0000-000000000003',
      numbers: [HotlineNumber('0905-480-1417')],
    ),
    // ── Almeria ───────────────────────────────────────────
    StationHotline(
      municipality: 'Almeria', agencyType: 'BFP', name: 'BFP Almeria Station',
      agencyId: 'a0000002-0000-0000-0000-000000000001',
      numbers: [HotlineNumber('0927-733-2298', label: 'Globe')],
    ),
    StationHotline(
      municipality: 'Almeria', agencyType: 'PNP', name: 'PNP Almeria Station',
      agencyId: 'a0000002-0000-0000-0000-000000000002',
      numbers: [HotlineNumber('0928-830-7633', label: 'Smart')],
    ),
    StationHotline(
      municipality: 'Almeria', agencyType: 'MDRRMO', name: 'MDRRMO Almeria',
      agencyId: 'a0000002-0000-0000-0000-000000000003',
      numbers: [HotlineNumber('0936-721-6929')],
    ),
    // ── Biliran ───────────────────────────────────────────
    StationHotline(
      municipality: 'Biliran', agencyType: 'BFP', name: 'BFP Biliran Station',
      agencyId: 'a0000003-0000-0000-0000-000000000001',
      numbers: [HotlineNumber('0977-269-0942')],
    ),
    StationHotline(
      municipality: 'Biliran', agencyType: 'PNP', name: 'PNP Biliran Station',
      agencyId: 'a0000003-0000-0000-0000-000000000002',
      numbers: [HotlineNumber('0928-766-2020'), HotlineNumber('0998-847-9659')],
    ),
    StationHotline(
      municipality: 'Biliran', agencyType: 'MDRRMO', name: 'MDRRMO Biliran',
      agencyId: 'a0000003-0000-0000-0000-000000000003',
      numbers: [HotlineNumber('0963-118-2800')],
    ),
    StationHotline(
      municipality: 'Biliran', agencyType: 'RHU', name: 'RHU Biliran',
      numbers: [HotlineNumber('0995-404-8094')],
    ),
    // ── Cabucgayan ────────────────────────────────────────
    StationHotline(
      municipality: 'Cabucgayan', agencyType: 'BFP', name: 'BFP Cabucgayan Station',
      agencyId: 'a0000004-0000-0000-0000-000000000001',
      numbers: [HotlineNumber('0912-587-8288'), HotlineNumber('0917-320-6105')],
    ),
    StationHotline(
      municipality: 'Cabucgayan', agencyType: 'PNP', name: 'PNP Cabucgayan Station',
      agencyId: 'a0000004-0000-0000-0000-000000000002',
      numbers: [HotlineNumber('0977-819-6634'), HotlineNumber('0910-355-3511')],
    ),
    StationHotline(
      municipality: 'Cabucgayan', agencyType: 'MDRRMO', name: 'MDRRMO Cabucgayan',
      agencyId: 'a0000004-0000-0000-0000-000000000003',
      numbers: [HotlineNumber('0977-810-8015')],
    ),
    StationHotline(
      municipality: 'Cabucgayan', agencyType: 'RHU', name: 'RHU Cabucgayan',
      numbers: [HotlineNumber('0977-820-0499')],
    ),
    // ── Caibiran ──────────────────────────────────────────
    StationHotline(
      municipality: 'Caibiran', agencyType: 'BFP', name: 'BFP Caibiran Station',
      agencyId: 'a0000005-0000-0000-0000-000000000001',
      numbers: [HotlineNumber('0917-115-0372')],
    ),
    StationHotline(
      municipality: 'Caibiran', agencyType: 'PNP', name: 'PNP Caibiran Station',
      agencyId: 'a0000005-0000-0000-0000-000000000002',
      numbers: [HotlineNumber('0938-984-9929')],
    ),
    StationHotline(
      municipality: 'Caibiran', agencyType: 'MDRRMO', name: 'MDRRMO / EMS Caibiran',
      agencyId: 'a0000005-0000-0000-0000-000000000003',
      numbers: [HotlineNumber('0969-189-2388', label: 'MDRRMO/EMS')],
    ),
    // ── Culaba ────────────────────────────────────────────
    StationHotline(
      municipality: 'Culaba', agencyType: 'BFP', name: 'BFP Culaba Station',
      agencyId: 'a0000006-0000-0000-0000-000000000001',
      numbers: [HotlineNumber('0956-631-0409', label: 'Globe')],
    ),
    StationHotline(
      municipality: 'Culaba', agencyType: 'PNP', name: 'PNP Culaba Station',
      agencyId: 'a0000006-0000-0000-0000-000000000002',
      numbers: [HotlineNumber('0998-598-6558')],
    ),
    StationHotline(
      municipality: 'Culaba', agencyType: 'MDRRMO', name: 'MDRRMO Culaba',
      agencyId: 'a0000006-0000-0000-0000-000000000003',
      numbers: [HotlineNumber('0967-132-8850')],
    ),
    // ── Kawayan ───────────────────────────────────────────
    StationHotline(
      municipality: 'Kawayan', agencyType: 'BFP', name: 'BFP Kawayan Station',
      agencyId: 'a0000007-0000-0000-0000-000000000001',
      numbers: [
        HotlineNumber('0953-394-9486', label: 'Globe'),
        HotlineNumber('0929-168-8304', label: 'Smart'),
      ],
    ),
    StationHotline(
      municipality: 'Kawayan', agencyType: 'PNP', name: 'PNP Kawayan Station',
      agencyId: 'a0000007-0000-0000-0000-000000000002',
      numbers: [HotlineNumber('0999-187-9043')],
    ),
    StationHotline(
      municipality: 'Kawayan', agencyType: 'MDRRMO', name: 'MDRRMO Kawayan',
      agencyId: 'a0000007-0000-0000-0000-000000000003',
      numbers: [HotlineNumber('0917-137-5989')],
    ),
  ];

  /// Town centres (the poblacion, from the map extract), for "nearest first".
  static const Map<String, (double, double)> townCentres = {
    'Naval': (11.5618, 124.3965),
    'Almeria': (11.6203, 124.3817),
    'Kawayan': (11.6799, 124.3570),
    'Culaba': (11.6556, 124.5406),
    'Caibiran': (11.5723, 124.5813),
    'Cabucgayan': (11.4730, 124.5750),
    'Biliran': (11.4666, 124.4741),
  };

  /// Reads agencies.contact_number: numbers separated by ";" (or "|", a
  /// newline, or a "/" BETWEEN two numbers — never the one in a label like
  /// "MDRRMO/EMS"), each optionally prefixed "Label:". Anything without at
  /// least seven digits is dropped — a stray "N/A" must never become a Call
  /// button.
  static List<HotlineNumber> parse(String? raw) {
    if (raw == null) return const [];
    final out = <HotlineNumber>[];
    for (final part in raw.split(RegExp(r'[;\n|]|(?<=\d)\s*/\s*(?=[\d(+])'))) {
      var text = part.trim();
      if (text.isEmpty) continue;
      String? label;
      final colon = text.indexOf(':');
      if (colon > 0) {
        final head = text.substring(0, colon).trim();
        if (!RegExp(r'\d').hasMatch(head)) {
          label = head;
          text = text.substring(colon + 1).trim();
        }
      }
      if (text.replaceAll(RegExp(r'[^0-9]'), '').length < 7) continue;
      final n = HotlineNumber(text, label: label);
      if (!out.contains(n)) out.add(n);
    }
    return out;
  }

  /// The directory to show: [bundled], with any station whose number the
  /// database knows (keyed by agency id, from an online fetch) using that
  /// instead. A database value that parses to nothing is ignored.
  static List<StationHotline> directory({Map<String, String?> live = const {}}) {
    return [
      for (final h in bundled)
        () {
          final raw = h.agencyId == null ? null : live[h.agencyId];
          final parsed = parse(raw);
          return parsed.isEmpty ? h : h.withNumbers(parsed);
        }(),
    ];
  }

  /// Which units answer a category, most relevant first.
  ///
  /// Mirrors how Ziren routes a report (nearest_station.dart): fire to BFP,
  /// crime to PNP, medical / accident / calamity to MDRRMO. A medical call
  /// also lists the town's Rural Health Unit, and a road accident the police,
  /// who handle traffic incidents. "Other" lists everyone.
  static List<String> agencyTypesFor(IncidentCategory? category) => switch (category) {
        IncidentCategory.fire => const ['BFP'],
        IncidentCategory.domesticDisputeCrime => const ['PNP'],
        IncidentCategory.medicalTrauma => const ['MDRRMO', 'RHU'],
        IncidentCategory.vehicular => const ['MDRRMO', 'PNP'],
        IncidentCategory.floodLandslideCalamity => const ['MDRRMO'],
        IncidentCategory.other || null => const ['BFP', 'PNP', 'MDRRMO', 'RHU'],
      };

  /// [entries] narrowed to [category] and ordered nearest town first (when
  /// [lat]/[lng] are known), then by how relevant the unit is.
  static List<StationHotline> forCategory(
    List<StationHotline> entries,
    IncidentCategory? category, {
    double? lat,
    double? lng,
  }) {
    final types = agencyTypesFor(category);
    final picked = entries.where((h) => types.contains(h.agencyType)).toList();
    final order = nearestTowns(lat: lat, lng: lng);
    int townRank(String m) {
      final i = order.indexOf(m);
      return i < 0 ? order.length : i;
    }

    picked.sort((a, b) {
      final t = townRank(a.municipality).compareTo(townRank(b.municipality));
      if (t != 0) return t;
      return types.indexOf(a.agencyType).compareTo(types.indexOf(b.agencyType));
    });
    return picked;
  }

  /// Every town, nearest first. Alphabetical when the position is unknown.
  static List<String> nearestTowns({double? lat, double? lng}) {
    final towns = townCentres.keys.toList()..sort();
    if (lat == null || lng == null) return towns;
    double d((double, double) c) {
      // Equirectangular is plenty for ranking towns on one small island.
      final x = (c.$2 - lng) * math.cos((lat + c.$1) / 2 * math.pi / 180);
      final y = c.$1 - lat;
      return x * x + y * y;
    }

    towns.sort((a, b) => d(townCentres[a]!).compareTo(d(townCentres[b]!)));
    return towns;
  }
}
