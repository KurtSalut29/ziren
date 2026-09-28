import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/failures.dart';
import '../data/profile_repository.dart';
import 'profile_model.dart';

enum ProfileStatus { idle, loading, saving, error }

/// State manager for the Resident's profile and settings.
class ProfileProvider extends ChangeNotifier {
  ProfileProvider({ProfileRepository? repository})
    : _repo = repository ?? ProfileRepository();

  final ProfileRepository _repo;

  ProfileStatus _status = ProfileStatus.idle;
  ProfileModel? _profile;
  String? _errorMessage;

  /// Which account [_profile] was fetched for.
  ///
  /// Without this the provider will happily serve one person's profile to the
  /// next person who signs in on the same handset. That is exactly what
  /// happened: a new account showed the previous account's name beside its own
  /// email, because the name came from this cached profile while the email came
  /// from the live session. Three things had to line up for it to be visible —
  /// the cache was never cleared on sign-out, ProfileScreen only fetches when
  /// `profile == null` so a stale non-null value blocked the refetch, and that
  /// screen lives in an IndexedStack branch whose initState does not run again
  /// after a re-login. The identity check below closes it regardless of which
  /// of those is fixed elsewhere.
  String? _loadedForUserId;

  ProfileStatus get status => _status;

  /// The cached profile, but only if it belongs to whoever is signed in now.
  ///
  /// Returning null for someone else's profile is deliberate: null makes the
  /// UI fetch, whereas showing the wrong name on an emergency app is a
  /// correctness failure a dispatcher could act on.
  ProfileModel? get profile {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (_loadedForUserId != null && _loadedForUserId != currentUserId) {
      return null;
    }
    return _profile;
  }

  String? get errorMessage => _errorMessage;
  bool get isLoading => _status == ProfileStatus.loading;
  bool get isSaving => _status == ProfileStatus.saving;

  // ── Load ──────────────────────────────────────────────────

  /// [force] is for an explicit user action (pull to refresh, Retry). It only
  /// bypasses the in-flight guard below; it never skips the request itself.
  Future<void> loadProfile({bool force = false}) async {
    // Don't fire a second request if one is already in-flight
    if (!force && _status == ProfileStatus.loading) return;

    _status = ProfileStatus.loading;
    _errorMessage = null;
    notifyListeners();
    try {
      _profile = await _repo.getMyProfile();
      _loadedForUserId = Supabase.instance.client.auth.currentUser?.id;
      _status = ProfileStatus.idle;
    } on NetworkFailure catch (e) {
      _status = ProfileStatus.error;
      _errorMessage = e.message;
    } on ServerFailure catch (e) {
      _status = ProfileStatus.error;
      _errorMessage = e.message;
    } catch (_) {
      _status = ProfileStatus.error;
      _errorMessage = 'Could not load profile.';
    }
    notifyListeners();
  }

  // ── Save ──────────────────────────────────────────────────

  Future<bool> saveProfile({
    required String fullName,
    String? phoneNumber,
    String? barangay,
    String? municipalityAddress,
    String? preferredLanguage,
    required bool pushNotificationsEnabled,
    String? emergencyContactName,
    String? emergencyContactNumber,
  }) async {
    _status = ProfileStatus.saving;
    _errorMessage = null;
    notifyListeners();

    // Only send fields that differ from current profile
    final payload = <String, dynamic>{
      'full_name': fullName.trim(),
      'phone_number':
          phoneNumber?.trim().isEmpty == true ? null : phoneNumber?.trim(),
      'barangay': barangay?.trim().isEmpty == true ? null : barangay?.trim(),
      'municipality_address':
          municipalityAddress?.trim().isEmpty == true
              ? null
              : municipalityAddress?.trim(),
      'preferred_language': preferredLanguage,
      'push_notifications_enabled': pushNotificationsEnabled,
      'emergency_contact_name':
          emergencyContactName?.trim().isEmpty == true
              ? null
              : emergencyContactName?.trim(),
      'emergency_contact_number':
          emergencyContactNumber?.trim().isEmpty == true
              ? null
              : emergencyContactNumber?.trim(),
    };
    // Remove null values so PATCH only touches what's explicitly set
    payload.removeWhere((_, v) => v == null);

    try {
      _profile = await _repo.updateMyProfile(payload);
      _status = ProfileStatus.idle;
      notifyListeners();
      return true;
    } on NetworkFailure catch (e) {
      _status = ProfileStatus.error;
      _errorMessage = e.message;
    } on ServerFailure catch (e) {
      _status = ProfileStatus.error;
      _errorMessage = e.message;
    } catch (_) {
      _status = ProfileStatus.error;
      _errorMessage = 'Could not save profile.';
    }
    notifyListeners();
    return false;
  }

  // ── Avatar ────────────────────────────────────────────────

  /// Persist the storage path of a freshly-uploaded avatar (or `null` to
  /// remove one). The file itself is already in the private "avatars"
  /// bucket by the time this is called — see AvatarUploadService — this
  /// only tells the backend which object to hand out as a signed URL.
  Future<bool> updateAvatarPath(String? path) async {
    _status = ProfileStatus.saving;
    _errorMessage = null;
    notifyListeners();

    try {
      _profile = await _repo.updateMyProfile({'avatar_path': path});
      _status = ProfileStatus.idle;
      notifyListeners();
      return true;
    } on NetworkFailure catch (e) {
      _status = ProfileStatus.error;
      _errorMessage = e.message;
    } on ServerFailure catch (e) {
      _status = ProfileStatus.error;
      _errorMessage = e.message;
    } catch (_) {
      _status = ProfileStatus.error;
      _errorMessage = 'Could not update your profile picture.';
    }
    notifyListeners();
    return false;
  }

  /// Drop everything. Called when the signed-in account changes.
  void clear() {
    _profile = null;
    _loadedForUserId = null;
    _errorMessage = null;
    _status = ProfileStatus.idle;
    notifyListeners();
  }

  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }
}
