import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/failures.dart';
import 'id_upload_service.dart';

/// Result returned by [AuthRepository.login].
class LoginResult {
  const LoginResult({
    required this.user,
    required this.role,
    required this.approvalStatus,
  });
  final User user;
  final String role;
  final String approvalStatus;
}

/// All Supabase Auth calls are isolated here.
class AuthRepository {
  AuthRepository({SupabaseClient? client, IdUploadService? idUploads})
    : _client = client ?? Supabase.instance.client,
      _idUploads = idUploads ?? IdUploadService(client: client);

  final SupabaseClient _client;
  final IdUploadService _idUploads;

  /// Register a new Resident or Responder account.
  ///
  /// [municipality] and [barangayId] locate the user inside Biliran. They are
  /// required for both roles: for a resident they establish residency and
  /// improve dispatch routing, for a responder they also decide which
  /// municipal agency the account belongs to.
  ///
  /// Accessibility fields are optional and never block registration.
  Future<User> register({
    required String email,
    required String password,
    required String fullName,
    required String role,
    required String municipality,
    required String barangayId,
    String? agencyType,
    String? badgeId,
    String? phoneNumber,
    bool isPwd = false,
    String? pwdIdNumber,
    List<String> disabilityTypes = const [],
    String? accessibilityNotes,
    String preferredContactMode = 'any',
    String? validIdType,
    String? validIdNumber,
    File? validIdImage,
  }) async {
    // Resolve agency_id from agency_type + the responder's own municipality.
    String? agencyId;
    if (role == 'responder') {
      if (agencyType == null || badgeId == null || badgeId.trim().isEmpty) {
        throw const AuthFailure(
          'Agency and badge ID are required for Responders.',
        );
      }
      agencyId = await _resolveAgencyId(agencyType, municipality);
      if (agencyId == null) {
        throw AuthFailure(
          'No $agencyType office is registered for $municipality. '
          'Contact your administrator.',
        );
      }
    }

    try {
      final response = await _client.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': fullName,
          'role': role,
          'agency_id': agencyId,
          'badge_id': role == 'responder' ? badgeId!.trim() : null,
          'approval_status': role == 'responder' ? 'pending' : 'not_required',
        },
      );
      final user = response.user;
      if (user == null) throw const AuthFailure('Registration failed.');

      // Everything below is written after the trigger has created the profile
      // row. Note that role/approval_status are deliberately NOT sent here —
      // RLS freezes them, and the trigger is the only thing allowed to set
      // them (see migration 013).
      final profile = <String, dynamic>{
        'barangay_id': barangayId,
        'municipality_address': municipality,
        'is_pwd': isPwd,
        'disability_types': disabilityTypes,
        'preferred_contact_mode': preferredContactMode,
      };
      if (phoneNumber != null && phoneNumber.trim().isNotEmpty) {
        profile['phone_number'] = phoneNumber.trim();
      }
      if (isPwd && pwdIdNumber != null && pwdIdNumber.trim().isNotEmpty) {
        profile['pwd_id_number'] = pwdIdNumber.trim();
      }
      if (accessibilityNotes != null && accessibilityNotes.trim().isNotEmpty) {
        profile['accessibility_notes'] = accessibilityNotes.trim();
      }
      // Both or neither — a type with no number is not verifiable, and a
      // number with no type is meaningless. verification_level deliberately
      // stays 0 here: an admin raises it after checking the physical card,
      // and RLS blocks the client from setting it (migration 012).
      if (validIdType != null &&
          validIdNumber != null &&
          validIdNumber.trim().isNotEmpty) {
        profile['valid_id_type'] = validIdType;
        profile['valid_id_number'] = validIdNumber.trim();

        // The scan can only be uploaded now, not earlier: storage RLS scopes
        // writes to `<auth.uid()>/...`, so the session created by signUp above
        // must exist first.
        //
        // A failed upload must NOT fail registration. The ID is optional, the
        // number is already recorded, and losing an account over a dropped
        // connection on a rural signal would be a far worse outcome than an
        // admin having to ask for the photo again.
        if (validIdImage != null) {
          try {
            profile['valid_id_image_path'] = await _idUploads.uploadId(
              file: validIdImage,
              userId: user.id,
            );
          } catch (_) {
            // Intentionally swallowed — see above.
          }
        }
      }
      if (role == 'responder' && agencyId != null) {
        profile['agency_id'] = agencyId;
        profile['badge_id'] = badgeId!.trim();
      }

      await _client.from('users').update(profile).eq('id', user.id);

      return user;
    } on AuthException catch (e) {
      if (e.message.toLowerCase().contains('already registered')) {
        throw const AuthFailure('An account with this email already exists.');
      }
      throw AuthFailure(e.message);
    } catch (e) {
      if (e is AuthFailure) rethrow;
      throw const AuthFailure('Registration failed. Please try again.');
    }
  }

  /// Login and return user + role + approval_status.
  Future<LoginResult> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      final session = response.session;
      final user = response.user;
      if (session == null || user == null) {
        throw const AuthFailure('Login failed.');
      }

      // Fetch role and approval_status from public.users
      final profile =
          await _client
              .from('users')
              .select('role, approval_status')
              .eq('id', user.id)
              .single();

      return LoginResult(
        user: user,
        role: profile['role'] as String? ?? 'resident',
        approvalStatus: profile['approval_status'] as String? ?? 'not_required',
      );
    } on AuthException catch (_) {
      throw const AuthFailure('Invalid email or password.');
    } catch (e) {
      if (e is AuthFailure) rethrow;
      throw const AuthFailure('Login failed. Please try again.');
    }
  }

  /// Role and approval status for an existing session.
  ///
  /// Read straight from Supabase rather than through the FastAPI profile
  /// endpoint, deliberately. Role decides which shell the app opens into, so
  /// it has to resolve even when the backend is unreachable — a responder on a
  /// bad connection must still land in their queue rather than in the resident
  /// UI.
  ///
  /// Returns null if it cannot be determined; the caller keeps whatever it had.
  Future<({String role, String approvalStatus})?> fetchRoleAndStatus(
    String userId,
  ) async {
    try {
      final row =
          await _client
              .from('users')
              .select('role, approval_status')
              .eq('id', userId)
              .maybeSingle();
      if (row == null) return null;
      return (
        role: row['role'] as String? ?? 'resident',
        approvalStatus: row['approval_status'] as String? ?? 'not_required',
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> logout() async {
    await _client.auth.signOut();
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email);
    } catch (_) {
      // Swallow to prevent email enumeration
    }
  }

  User? get currentUser => _client.auth.currentUser;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  /// Looks up the agency_id for an [agencyType] (BFP/PNP/MDRRMO) in the
  /// responder's own [municipality].
  ///
  /// This used to hardcode `.eq('municipality', 'Naval')` with a comment
  /// saying the Agency Admin could correct it later. They could not: RLS
  /// scoped an admin's visibility to their own agency, so a Kawayan
  /// responder written into BFP Naval was invisible to the Kawayan admin,
  /// and the WITH CHECK on the Naval admin's policy pinned agency_id. The
  /// responder was stranded, silently, and seven of Biliran's eight
  /// municipalities could not onboard anyone. See migration 014.
  Future<String?> _resolveAgencyId(
    String agencyType,
    String municipality,
  ) async {
    try {
      final result =
          await _client
              .from('agencies')
              .select('id')
              .eq('agency_type', agencyType)
              .eq('municipality', municipality)
              .limit(1)
              .maybeSingle();
      return result?['id'] as String?;
    } catch (_) {
      return null;
    }
  }
}
