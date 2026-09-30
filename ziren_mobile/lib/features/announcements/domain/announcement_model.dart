import '../../../l10n/app_localizations.dart';

/// One official broadcast from a Provincial Admin (spec Section 24) - since
/// 2026-10-01 often a SAFETY ALERT: an evacuation order for two barangays, a
/// wind signal, a hazard warning, the all clear that ends one.
///
/// The backend (`GET /announcements/`) already filters to what applies to the
/// caller - active, not expired, aimed at their role AND their place - so this
/// model carries only what is left to show, not the targeting logic itself.
///
/// Every field added by migration 043 is optional: an older backend simply
/// does not send them, and the card falls back to a title and a message.
class AnnouncementModel {
  const AnnouncementModel({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.createdAt,
    this.expiresAt,
    this.details = const {},
    this.municipalities = const [],
    this.barangays = const [],
    this.asksResponse = false,
    this.issuer,
    this.isActive = true,
    this.isOpen = true,
    this.endedAt,
    this.endedByTitle,
    this.myResponse,
  });

  final String id;
  final String title;
  final String body;
  final String category;
  final DateTime createdAt;
  final DateTime? expiresAt;

  /// The facts of the kind: `signal`, `rainfall`, `hazard`, `centers`, `road`...
  final Map<String, dynamic> details;

  /// Where it applies. Empty = the whole province.
  final List<String> municipalities;

  /// Narrowed to these barangays (names), within [municipalities].
  final List<({String name, String municipality})> barangays;

  /// The resident is asked "are you safe?".
  final bool asksResponse;

  /// Which provincial office issued it: BFP, PNP or MDRRMO.
  final String? issuer;

  final bool isActive;

  /// Still taking answers: active and not expired. Only the single-alert read
  /// sends it; a list only ever holds open ones.
  final bool isOpen;

  final DateTime? endedAt;

  /// The all clear that ended this one.
  final String? endedByTitle;

  /// This resident's answer, when they have given one.
  final AlertResponse? myResponse;

  static const safetyCategories = {
    'evacuation', 'weather', 'hazard', 'road_closure', 'missing_person', 'all_clear', 'emergency',
  };

  bool get isSafety => safetyCategories.contains(category);

  /// Needs the resident to act or to know right now - drawn on Home.
  bool get isUrgent => isSafety && category != 'all_clear';

  bool get canAnswer => asksResponse && isActive && isOpen;

  List<Map<String, String>> get centers => [
    for (final c in (details['centers'] as List? ?? const []))
      if (c is Map && (c['name'] as String?)?.trim().isNotEmpty == true)
        {
          'name': (c['name'] as String).trim(),
          if ((c['place'] as String?)?.trim().isNotEmpty == true) 'place': (c['place'] as String).trim(),
        },
  ];

  String? detail(String key) {
    final v = details[key];
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  AnnouncementModel withResponse(AlertResponse? r) => AnnouncementModel(
    id: id,
    title: title,
    body: body,
    category: category,
    createdAt: createdAt,
    expiresAt: expiresAt,
    details: details,
    municipalities: municipalities,
    barangays: barangays,
    asksResponse: asksResponse,
    issuer: issuer,
    isActive: isActive,
    isOpen: isOpen,
    endedAt: endedAt,
    endedByTitle: endedByTitle,
    myResponse: r,
  );

  factory AnnouncementModel.fromJson(Map<String, dynamic> json) {
    DateTime? time(Object? v) =>
        v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;
    final details = json['details'];
    final endedBy = json['ended_by'];
    final mine = json['my_response'];
    return AnnouncementModel(
      id: json['id'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      category: json['category'] as String? ?? 'general',
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      expiresAt: time(json['expires_at']),
      details: details is Map ? Map<String, dynamic>.from(details) : const {},
      municipalities: [
        for (final m in (json['target_municipalities'] as List? ?? const []))
          if (m is String) m,
      ],
      barangays: [
        for (final b in (json['target_barangays'] as List? ?? const []))
          if (b is Map && b['name'] is String)
            (name: b['name'] as String, municipality: (b['municipality'] as String?) ?? ''),
      ],
      asksResponse: json['asks_response'] == true,
      issuer: json['issuer_agency_type'] as String?,
      isActive: json['is_active'] != false,
      isOpen: json['is_open'] is bool ? json['is_open'] as bool : json['is_active'] != false,
      endedAt: time(json['ended_at']),
      endedByTitle: endedBy is Map ? endedBy['title'] as String? : null,
      myResponse: mine is Map ? AlertResponse.fromJson(Map<String, dynamic>.from(mine)) : null,
    );
  }

  /// "Naval · Atipolo, Caraycaray" - or the words for "the whole province".
  String placeLine(AppLocalizations t) {
    if (municipalities.isEmpty) return t.annWholeProvince;
    return municipalities
        .map((m) {
          final picked = barangays.where((b) => b.municipality == m).map((b) => b.name).toList();
          return picked.isEmpty ? m : '$m · ${picked.join(', ')}';
        })
        .join('; ');
  }

  String categoryLabel(AppLocalizations t) => announcementKindLabel(t, category);
}

/// A resident's answer to a safety alert.
class AlertResponse {
  const AlertResponse({
    required this.status,
    this.note,
    this.respondedAt,
    this.handledAt,
  });

  /// `safe` or `need_help`.
  final String status;
  final String? note;
  final DateTime? respondedAt;

  /// When a station marked them reached.
  final DateTime? handledAt;

  bool get needsHelp => status == 'need_help';

  factory AlertResponse.fromJson(Map<String, dynamic> json) {
    DateTime? time(Object? v) =>
        v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;
    return AlertResponse(
      status: json['status'] as String? ?? 'safe',
      note: json['note'] as String?,
      respondedAt: time(json['responded_at']),
      handledAt: time(json['handled_at']),
    );
  }
}

/// The kind of announcement, in the resident's language. A kind this build has
/// never heard of reads as a plain announcement rather than as a raw key.
String announcementKindLabel(AppLocalizations t, String category) =>
    switch (category) {
      'evacuation' => t.annKindEvacuation,
      'weather' => t.annKindWeather,
      'hazard' => t.annKindHazard,
      'road_closure' => t.annKindRoadClosure,
      'missing_person' => t.annKindMissingPerson,
      'all_clear' => t.annKindAllClear,
      'emergency' => t.announceCategoryEmergency,
      'relief' => t.annKindRelief,
      'health' => t.annKindHealth,
      'drill' => t.annKindDrill,
      'utility' => t.annKindUtility,
      'maintenance' => t.announceCategoryMaintenance,
      'service_interruption' => t.announceCategoryServiceInterruption,
      'feature' => t.announceCategoryFeature,
      'reminder' => t.announceCategoryReminder,
      _ => t.announceCategoryGeneral,
    };
