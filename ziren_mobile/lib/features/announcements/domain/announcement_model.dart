import '../../../l10n/app_localizations.dart';

/// One official broadcast from Super Admin (spec Section 24).
///
/// The backend (`GET /announcements/`) already filters to what applies to
/// the caller — active, not expired, and matching this resident's audience
/// (`all` or `resident`) — so this model carries only what is left to show,
/// not the targeting logic itself.
class AnnouncementModel {
  const AnnouncementModel({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.createdAt,
    this.expiresAt,
  });

  final String id;
  final String title;
  final String body;
  final String category;
  final DateTime createdAt;
  final DateTime? expiresAt;

  factory AnnouncementModel.fromJson(Map<String, dynamic> json) {
    return AnnouncementModel(
      id: json['id'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      category: json['category'] as String? ?? 'general',
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt:
          json['expires_at'] != null
              ? DateTime.parse(json['expires_at'] as String)
              : null,
    );
  }

  String categoryLabel(AppLocalizations t) {
    switch (category) {
      case 'maintenance':
        return t.announceCategoryMaintenance;
      case 'emergency':
        return t.announceCategoryEmergency;
      case 'service_interruption':
        return t.announceCategoryServiceInterruption;
      case 'feature':
        return t.announceCategoryFeature;
      case 'reminder':
        return t.announceCategoryReminder;
      default:
        return t.announceCategoryGeneral;
    }
  }
}
