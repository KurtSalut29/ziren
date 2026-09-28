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
  /// credibility. It is NEVER a permission — an unverified resident can report
  /// an emergency exactly like anyone else (migration 012).
  final int verificationLevel;
  final String? validIdType;
  final String? residencyProofType;

  /// A short-lived signed URL into the private "avatars" bucket, minted
  /// fresh by the backend on every fetch — never a stored/cached value, and
  /// never the raw storage path. Null until the user uploads a picture; the
  /// UI falls back to initials.
  final String? avatarUrl;

  /// Has this account submitted anything for an admin to check?
  ///
  /// Distinguishes "skipped verification entirely" from "submitted and
  /// waiting", which the two need different prompts for.
  bool get hasSubmittedEvidence =>
      validIdType != null ||
      (residencyProofType != null && residencyProofType != 'none');

  bool get isVerifiedResident => verificationLevel >= 2;

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
    );
  }
}
