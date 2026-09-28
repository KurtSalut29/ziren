import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/locale_provider.dart';
import '../../../core/errors/failures.dart';
import '../../auth/data/id_upload_service.dart';
import '../../onboarding/domain/legal_documents.dart';
import '../domain/id_catalogue.dart';
import '../domain/registration_draft.dart';
import 'agency_id_upload_service.dart';

/// What happened after a submit.
class RegistrationOutcome {
  const RegistrationOutcome({
    required this.user,
    required this.evidenceUploaded,
    this.evidenceError,
  });

  final User user;

  /// False when the account was created but a photo did not make it up.
  /// The account is still valid and usable; the person is asked to re-upload
  /// from their profile later.
  final bool evidenceUploaded;
  final String? evidenceError;
}

/// Creates the account and writes everything the registration flow collected.
///
/// Ordering is forced by storage RLS
/// ---------------------------------
/// Photos are written to `<auth.uid()>/...`, so there is no session to
/// authorise them until signUp has returned. The account therefore always
/// exists before any evidence is uploaded, and that ordering cannot be
/// rearranged to make failure handling tidier.
///
/// Two updates, not one
/// --------------------
/// The profile write is split deliberately.
///
/// The first update carries identity, address and contact details — the things
/// dispatch actually needs. If that fails, registration failed, and the caller
/// says so.
///
/// The second carries the verification evidence, and its failure is caught and
/// reported without failing registration. This is the lesson from the bug this
/// flow replaces: the old code put optional ID fields in the same statement as
/// the essential ones, so a resident who filled in the optional section got a
/// hard failure and an orphaned auth account, while one who skipped it
/// registered fine. Optional data must never be able to destroy an account.
class RegistrationRepository {
  RegistrationRepository({
    SupabaseClient? client,
    IdUploadService? idUploads,
    AgencyIdUploadService? agencyUploads,
  }) : _client = client ?? Supabase.instance.client,
       _idUploads = idUploads ?? IdUploadService(client: client),
       _agencyUploads = agencyUploads ?? AgencyIdUploadService(client: client);

  final SupabaseClient _client;
  final IdUploadService _idUploads;
  final AgencyIdUploadService _agencyUploads;

  Future<RegistrationOutcome> submit(RegistrationDraft d) async {
    if (d.municipality == null || d.barangayId == null) {
      throw const AuthFailure('Please choose your municipality and barangay.');
    }

    String? agencyId;
    if (d.isResponder) {
      if (d.agencyType == null || d.badgeId.trim().isEmpty) {
        throw const AuthFailure(
          'Agency and badge ID are required for Responders.',
        );
      }
      agencyId = await _resolveAgencyId(d.agencyType!, d.municipality!);
      if (agencyId == null) {
        throw AuthFailure(
          'No ${d.agencyType} office is registered for ${d.municipality}. '
          'Contact your administrator.',
        );
      }
    }

    final User user;
    try {
      final response = await _client.auth.signUp(
        email: d.email.trim(),
        password: d.password,
        data: {
          'full_name': d.fullName,
          'role': d.role,
          'agency_id': agencyId,
          'badge_id': d.isResponder ? d.badgeId.trim() : null,
          // The trigger sets this regardless (migration 013). Sent for
          // clarity, not because it is trusted.
          'approval_status': d.isResponder ? 'pending' : 'not_required',
        },
      );
      final created = response.user;
      if (created == null) throw const AuthFailure('Registration failed.');
      user = created;
    } on AuthException catch (e) {
      if (e.message.toLowerCase().contains('already registered')) {
        throw const AuthFailure('An account with this email already exists.');
      }
      throw AuthFailure(e.message);
    }

    // ── Essential profile ───────────────────────────────────
    //
    // role and approval_status are deliberately absent: RLS freezes them and
    // the auth trigger is the only thing permitted to set them (migration 013).
    final core = <String, dynamic>{
      'first_name': _orNull(d.firstName),
      'middle_name': _orNull(d.middleName),
      'last_name': _orNull(d.lastName),
      'name_suffix': _orNull(d.nameSuffix),
      'date_of_birth': d.dateOfBirth?.toIso8601String().split('T').first,
      'sex': d.sex,
      'barangay_id': d.barangayId,
      'municipality_address': d.municipality,
      'purok_sitio': _orNull(d.purokSitio),
      'street_address': _orNull(d.streetAddress),
      ...accessibilityFields(d),
      'preferred_contact_mode': d.contactMode,
      // The language chosen during onboarding, carried onto the account.
      // Leaving this null is what let Settings later "resolve" the absence to
      // Filipino and undo an English choice.
      'preferred_language': await LocaleProvider.storedLanguageName(),
      'terms_accepted_at': DateTime.now().toUtc().toIso8601String(),
      'terms_version': LegalDocuments.termsVersion,
      'privacy_version': LegalDocuments.privacyVersion,
    };
    if (_orNull(d.phone) != null) core['phone_number'] = d.phone.trim();
    if (_orNull(d.emergencyContactName) != null) {
      core['emergency_contact_name'] = d.emergencyContactName.trim();
    }
    if (_orNull(d.emergencyContactNumber) != null) {
      core['emergency_contact_number'] = d.emergencyContactNumber.trim();
    }
    if (d.isResponder) {
      core['agency_id'] = agencyId;
      core['badge_id'] = d.badgeId.trim();
      core['rank_or_position'] = _orNull(d.rankOrPosition);
      core['unit_assignment'] = _orNull(d.unitAssignment);
      core['date_joined'] = d.dateJoined?.toIso8601String().split('T').first;
    }

    try {
      await _client.from('users').update(core).eq('id', user.id);
    } catch (e) {
      throw AuthFailure('Could not save your details. $e');
    }

    // ── Evidence — never allowed to fail the registration ───
    try {
      final evidence = await _uploadEvidence(d, user.id);
      if (evidence.isNotEmpty) {
        await _client.from('users').update(evidence).eq('id', user.id);
      }
      return RegistrationOutcome(user: user, evidenceUploaded: true);
    } catch (e) {
      debugPrint('RegistrationRepository: evidence step failed: $e');
      return RegistrationOutcome(
        user: user,
        evidenceUploaded: false,
        evidenceError: e.toString(),
      );
    }
  }

  Future<Map<String, dynamic>> _uploadEvidence(
    RegistrationDraft d,
    String userId,
  ) async {
    final out = <String, dynamic>{};

    if (!d.isResponder && d.validIdType != null) {
      out['valid_id_type'] = d.validIdType;
      out['residency_proof_type'] = IdCatalogue.residencyProofFor(
        d.validIdType,
      );
      if (_orNull(d.validIdNumber) != null) {
        out['valid_id_number'] = d.validIdNumber.trim();
        // Whether that number was typed, read off the card, or read and then
        // corrected. Only written alongside a number — a source with nothing
        // to describe is noise in the audit trail. See migration 023.
        if (d.idNumberSource != null) {
          out['id_number_source'] = d.idNumberSource;
        }
      }
      if (d.idChecks != null) out['id_checks'] = d.idChecks;
      if (d.idImagePath != null) {
        out['valid_id_image_path'] = await _idUploads.uploadId(
          file: File(d.idImagePath!),
          userId: userId,
        );
      }
    }

    if (d.isResponder && d.agencyIdImagePath != null) {
      out['agency_id_image_path'] = await _agencyUploads.upload(
        file: File(d.agencyIdImagePath!),
        userId: userId,
      );
    }

    if (d.selfiePath != null) {
      out['selfie_image_path'] = await _idUploads.uploadSelfie(
        file: File(d.selfiePath!),
        userId: userId,
      );
      // Client-asserted, and stored as such. See migration 020.
      out['liveness_asserted_at'] =
          (d.livenessAssertedAt ?? DateTime.now()).toUtc().toIso8601String();
      out['liveness_method'] = d.livenessMethod ?? 'none';

      // The ID/selfie comparison, in the same class of evidence as liveness
      // above: computed on the handset, therefore ADVISORY, and stored so an
      // admin can sort their queue by it. Nothing reading these columns is
      // permitted to raise verification_level — migration 023 says so at
      // length, and this is the only place that writes them.
      if (d.faceMatchVerdict != null) {
        out['face_match_verdict'] = d.faceMatchVerdict;
        out['face_match_score'] = d.faceMatchScore;
        out['face_match_model'] = d.faceMatchModel;
        out['face_match_checked_at'] =
            (d.faceMatchCheckedAt ?? DateTime.now()).toUtc().toIso8601String();
      }
    }

    if (d.skippedVerification && out.isEmpty) {
      out['residency_proof_type'] = 'none';
    }

    return out;
  }

  static String? _orNull(String s) => s.trim().isEmpty ? null : s.trim();

  /// The accessibility profile: how a crew should assist the person REPORTING.
  ///
  /// A responder never has one. The contact step hides these fields for a
  /// responder, but the draft keeps whatever was entered before the role was
  /// switched (resident, tick PWD, back to the role step, pick Responder), and
  /// sending it created responder accounts flagged as PWD. Decided here, the
  /// one place every submit passes through, so no screen state can leak it.
  @visibleForTesting
  static Map<String, dynamic> accessibilityFields(RegistrationDraft d) {
    if (d.isResponder) {
      return {'is_pwd': false, 'disability_types': <String>[]};
    }
    return {
      'is_pwd': d.isPwd,
      'disability_types': d.disabilities.toList(),
      if (d.isPwd && _orNull(d.pwdIdNumber) != null)
        'pwd_id_number': d.pwdIdNumber.trim(),
      if (_orNull(d.accessibilityNotes) != null)
        'accessibility_notes': d.accessibilityNotes.trim(),
    };
  }

  Future<String?> _resolveAgencyId(
    String agencyType,
    String municipality,
  ) async {
    try {
      final row =
          await _client
              .from('agencies')
              .select('id')
              .eq('agency_type', agencyType)
              .eq('municipality', municipality)
              .limit(1)
              .maybeSingle();
      return row?['id'] as String?;
    } catch (_) {
      return null;
    }
  }
}
