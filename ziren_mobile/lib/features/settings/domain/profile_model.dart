/// Client-side model for the authenticated user's full profile.
/// Mirrors the FastAPI UserProfile response schema (Phase 10.5 fields included).
class ProfileModel {
  const ProfileModel({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.approvalStatus,
    required this.isVerified,
    this.agencyId,
    this.agencyType,
    this.agencyName,
    this.agencyMunicipality,
    this.agencyContactNumber,
    this.badgeId,
    this.phoneNumber,
    this.barangay,
    this.municipalityAddress,
    this.preferredLanguage,
    this.pushNotificationsEnabled = true,
    this.emergencyContactName,
    this.emergencyContactNumber,
    this.verificationLevel = 0,
    this.validIdType,
    this.residencyProofType,
    this.avatarUrl,
    this.warningCount = 0,
    this.suspendedUntil,
    this.reportingGraceEndsAt,
    this.reportingLockedByServer = false,
    this.verificationPending,
  });

  final String id;
  final String email;
  final String fullName;
  final String role;
  final String approvalStatus;
  final bool isVerified;
  final String? agencyId;

  /// BFP / PNP / MDRRMO, and the station's own name.
  ///
  /// The responder profile used to render agencyId — a UUID — where the
  /// unit belongs. A crew member cannot tell whether
  /// "a0000001-0000-0000-0000-000000000001" is theirs, so the field was
  /// worse than showing nothing.
  final String? agencyType;
  final String? agencyName;
  final String? agencyMunicipality;

  /// Read-only "who do I call" info for the responder's own station —
  /// Responder spec Section 21. Never editable from this model.
  final String? agencyContactNumber;
  final String? badgeId;
  final String? phoneNumber;
  final String? barangay;
  final String? municipalityAddress;
  final String? preferredLanguage;
  final bool pushNotificationsEnabled;
  final String? emergencyContactName;
  final String? emergencyContactNumber;

  /// Tiered trust: 0 unverified, 1 phone-verified, 2 resident-verified.
  ///
  /// Shown to the holder as progress and to a dispatcher as reporter
  /// credibility. Since 2026-10-08 it is also a permission once a resident's
  /// first week is over - see [reportingLocked].
  final int verificationLevel;
  final String? validIdType;
  final String? residencyProofType;

  /// A short-lived signed URL into the private "avatars" bucket, minted
  /// fresh by the backend on every fetch — never a stored/cached value, and
  /// never the raw storage path. Null until the user uploads a picture; the
  /// UI falls back to initials.
  final String? avatarUrl;

  /// Warnings an admin has put on this account for breaking the reporting
  /// rules. The third one suspends it.
  final int warningCount;

  /// When a suspension from reporting ends. A date in the past is not a
  /// suspension - the server never clears the column when one runs out - so
  /// read [isSuspended], not this.
  final DateTime? suspendedUntil;

  /// The end of an unverified resident's first week, when the server stops
  /// taking their reports until an administrator verifies them (backend
  /// app/core/resident_trust.py, GRACE_DAYS). Null once verified, and for
  /// staff.
  final DateTime? reportingGraceEndsAt;

  /// The server's own answer at the time the profile was read.
  final bool reportingLockedByServer;

  /// An unverified resident whose first week is over: the server refuses
  /// their reports. Read by the clock as well as from the server, because a
  /// profile loaded on day 6 is still on screen on day 8.
  bool get reportingLocked {
    if (role != 'resident' || isVerifiedResident) return false;
    if (reportingLockedByServer) return true;
    final ends = reportingGraceEndsAt;
    return ends != null && !DateTime.now().isBefore(ends);
  }

  /// Unverified, and still inside the first week.
  bool get inReportingGrace =>
      role == 'resident' &&
      !isVerifiedResident &&
      reportingGraceEndsAt != null &&
      !reportingLocked;

  /// Whole days left in the first week, counting today: 1 on the last day.
  int get graceDaysLeft {
    final ends = reportingGraceEndsAt;
    if (ends == null) return 0;
    final left = ends.difference(DateTime.now());
    if (left.isNegative) return 0;
    return (left.inHours / 24).ceil().clamp(1, 7);
  }

  /// Suspended from sending reports right now. Unlike [verificationLevel],
  /// this IS a permission: the server refuses a suspended account's report.
  bool get isSuspended =>
      suspendedUntil != null && suspendedUntil!.isAfter(DateTime.now());

  /// "Until further notice": stored as a date that never arrives.
  bool get suspensionIndefinite =>
      isSuspended && suspendedUntil!.year >= 9000;

  /// The server's answer to "is a submission waiting for an administrator"
  /// (an ID photo on file, no decision yet). Null from a server older than
  /// 2026-10-08.
  final bool? verificationPending;

  /// Is a submission waiting for an admin to check?
  ///
  /// Distinguishes "has not verified" from "submitted and waiting", which
  /// need different prompts. Read from the server when it says: a rejection
  /// leaves valid_id_type in place, so the old reading below kept a rejected
  /// resident on "in review" with no way to send their ID again.
  bool get hasSubmittedEvidence =>
      verificationPending ??
      (validIdType != null ||
          (residencyProofType != null && residencyProofType != 'none'));

  /// What an administrator's ID approval writes (backend
  /// app/core/resident_trust.py). NOT `is_verified`, which on a resident is an
  /// account-active switch.
  static const int verifiedLevel = 2;

  bool get isVerifiedResident => verificationLevel >= verifiedLevel;

  factory ProfileModel.fromJson(Map<String, dynamic> json) {
    return ProfileModel(
      id: json['id'] as String,
      email: json['email'] as String,
      fullName: json['full_name'] as String? ?? '',
      role: json['role'] as String? ?? 'resident',
      approvalStatus: json['approval_status'] as String? ?? 'not_required',
      isVerified: json['is_verified'] as bool? ?? false,
      agencyId: json['agency_id'] as String?,
      agencyType: json['agency_type'] as String?,
      agencyName: json['agency_name'] as String?,
      agencyMunicipality: json['agency_municipality'] as String?,
      agencyContactNumber: json['agency_contact_number'] as String?,
      badgeId: json['badge_id'] as String?,
      phoneNumber: json['phone_number'] as String?,
      barangay: json['barangay'] as String?,
      municipalityAddress: json['municipality_address'] as String?,
      preferredLanguage: json['preferred_language'] as String?,
      pushNotificationsEnabled:
          json['push_notifications_enabled'] as bool? ?? true,
      emergencyContactName: json['emergency_contact_name'] as String?,
      emergencyContactNumber: json['emergency_contact_number'] as String?,
      verificationLevel: json['verification_level'] as int? ?? 0,
      validIdType: json['valid_id_type'] as String?,
      residencyProofType: json['residency_proof_type'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      warningCount: (json['sos_warning_count'] as num?)?.toInt() ?? 0,
      suspendedUntil: DateTime.tryParse(
        json['sos_suspended_until'] as String? ?? '',
      ),
      reportingGraceEndsAt: DateTime.tryParse(
        json['reporting_grace_ends_at'] as String? ?? '',
      ),
      reportingLockedByServer: json['reporting_locked'] as bool? ?? false,
      verificationPending: json['verification_pending'] as bool?,
    );
  }

  ProfileModel copyWith({
    String? fullName,
    String? phoneNumber,
    String? barangay,
    String? municipalityAddress,
    String? preferredLanguage,
    bool? pushNotificationsEnabled,
    String? emergencyContactName,
    String? emergencyContactNumber,
    String? avatarUrl,
  }) {
    return ProfileModel(
      id: id,
      email: email,
      fullName: fullName ?? this.fullName,
      role: role,
      approvalStatus: approvalStatus,
      isVerified: isVerified,
      agencyId: agencyId,
      agencyType: agencyType,
      agencyName: agencyName,
      agencyMunicipality: agencyMunicipality,
      agencyContactNumber: agencyContactNumber,
      badgeId: badgeId,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      barangay: barangay ?? this.barangay,
      municipalityAddress: municipalityAddress ?? this.municipalityAddress,
      preferredLanguage: preferredLanguage ?? this.preferredLanguage,
      pushNotificationsEnabled:
          pushNotificationsEnabled ?? this.pushNotificationsEnabled,
      emergencyContactName: emergencyContactName ?? this.emergencyContactName,
      emergencyContactNumber:
          emergencyContactNumber ?? this.emergencyContactNumber,
      verificationLevel: verificationLevel,
      validIdType: validIdType,
      residencyProofType: residencyProofType,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      warningCount: warningCount,
      suspendedUntil: suspendedUntil,
      reportingGraceEndsAt: reportingGraceEndsAt,
      reportingLockedByServer: reportingLockedByServer,
      verificationPending: verificationPending,
    );
  }
}
