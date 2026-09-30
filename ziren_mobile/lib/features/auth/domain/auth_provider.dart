import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/failures.dart';
import '../../onboarding/data/onboarding_repository.dart';
import '../data/auth_repository.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

/// ChangeNotifier holding auth state for the whole app.
///
/// Navigation contract:
///   - Login / register → router.go() called here after success
///   - Logout           → router.go('/login') called here, no refreshListenable
///   - Token refresh    → handled silently, no navigation
///
/// GoRouter does NOT use refreshListenable on this provider.
/// All navigation is imperative to avoid the !_debugLocked race condition
/// that occurs when notifyListeners() fires during a mid-frame navigation.
class AuthProvider extends ChangeNotifier {
  AuthProvider({AuthRepository? repository, OnboardingRepository? onboarding})
    : _repo = repository ?? AuthRepository(),
      _onboarding = onboarding ?? OnboardingRepository() {
    final existing = _repo.currentUser;
    if (existing != null) {
      _user = existing;
      _status = AuthStatus.authenticated;
    } else {
      _status = AuthStatus.unauthenticated;
    }
    _repo.authStateChanges.listen(_onAuthStateChange);
  }

  final AuthRepository _repo;
  final OnboardingRepository _onboarding;

  // Injected after router is created in main.dart
  GoRouter? _router;
  void setRouter(GoRouter router) => _router = router;

  AuthStatus _status = AuthStatus.unknown;
  User? _user;
  String? _userRole;
  String? _approvalStatus;
  String? _errorMessage;
  bool _isLoading = false;

  AuthStatus get status => _status;
  User? get user => _user;
  String? get userRole => _userRole;
  String? get approvalStatus => _approvalStatus;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _status == AuthStatus.authenticated;

  bool get isPendingApproval =>
      _status == AuthStatus.authenticated &&
      _userRole == 'responder' &&
      _approvalStatus == 'pending';

  bool get isRejected =>
      _status == AuthStatus.authenticated &&
      _userRole == 'responder' &&
      _approvalStatus == 'rejected';

  // ── Auth state stream (Supabase) ─────────────────────────

  void _onAuthStateChange(AuthState state) {
    if (state.event == AuthChangeEvent.signedIn) {
      // Only update user object; role is set by login() after the profile fetch
      _user = state.session?.user;
      if (_status != AuthStatus.authenticated) {
        _status = AuthStatus.authenticated;
        notifyListeners();
      }
    } else if (state.event == AuthChangeEvent.signedOut) {
      // Only handle if we haven't already processed this in logout()
      if (_status == AuthStatus.authenticated) {
        _clearAuthState();
        navigateToLogin();
      }
    }
  }

  /// Re-establish role and approval status for a session restored from disk.
  ///
  /// The constructor can only recover the Supabase user synchronously; role
  /// lives in `public.users` and needs a round trip. Until this runs,
  /// [userRole] is null, and that is not cosmetic: [navigateAfterAuth] falls
  /// through its role checks to the final else and sends everyone to /home. An
  /// approved responder restarting the app therefore landed in the resident
  /// shell, and a pending one skipped /pending-approval altogether. The
  /// profile screen showing "Role —" was the same bug wearing a smaller hat.
  ///
  /// Called by SplashScreen before it decides where to go.
  Future<void> restoreSession() async {
    final user = _repo.currentUser;
    if (user == null) return;
    _user = user;
    _status = AuthStatus.authenticated;
    if (_userRole != null) return;

    final result = await _repo.fetchRoleAndStatus(user.id);
    if (result == null) return;
    _userRole = result.role;
    _approvalStatus = result.approvalStatus;
    notifyListeners();
  }

  // ── Public API ────────────────────────────────────────────

  /// Adopt the session created by [RegistrationRepository] and route onward.
  ///
  /// The new registration flow owns its own submit — it has to, because the
  /// account must exist before storage RLS will accept the ID and selfie
  /// uploads, and that ordering does not fit behind a single `register()`
  /// call. By the time this runs Supabase already holds a valid session; this
  /// only brings the provider's own state into line with it and navigates.

  Future<void> adoptRegisteredSession({required String role}) async {
    _user = _repo.currentUser;
    _userRole = role;
    _approvalStatus = role == 'responder' ? 'pending' : 'not_required';
    _status = AuthStatus.authenticated;
    _errorMessage = null;

    // The person consented on the way in, so attach the record to the account
    // they just created. Best-effort; see OnboardingRepository.
    await _onboarding.recordConsentForCurrentUser();

    notifyListeners();
    navigateAfterAuth();
  }

  Future<bool> login({required String email, required String password}) async {
    _setLoading(true);
    try {
      final result = await _repo.login(email: email, password: password);
      _user = result.user;
      _userRole = result.role;
      _approvalStatus = result.approvalStatus;
      _status = AuthStatus.authenticated;
      _errorMessage = null;
      notifyListeners();

      // The device flag suppresses onboarding for everyone who uses this
      // handset, including someone who has never seen it. Phones get shared
      // here, so the account's own record is what decides.
      if (!await _onboarding.hasAccountConsented()) {
        _router?.go('/onboarding/consent');
        return true;
      }

      navigateAfterAuth();
      return true;
    } on AuthFailure catch (e) {
      _errorMessage = e.message;
      notifyListeners();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> logout() async {
    _clearAuthState();
    try {
      await _repo.logout();
    } catch (_) {
      // Ignore — local state already cleared
    }
  }

  Future<void> sendPasswordReset(String email) async {
    await _repo.sendPasswordReset(email);
  }

  /// See [AuthRepository.changePassword]. Throws [WrongPasswordFailure],
  /// [SamePasswordFailure] or [AuthFailure]; the screen words each one.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => _repo.changePassword(
    currentPassword: currentPassword,
    newPassword: newPassword,
  );

  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }

  // ── Internal helpers ──────────────────────────────────────

  void _clearAuthState() {
    _user = null;
    _userRole = null;
    _approvalStatus = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  /// Navigate after a successful login / register.
  /// Also called by SplashScreen on warm restart when already authenticated.
  void navigateAfterAuth() {
    final router = _router;
    if (router == null) return;
    if (isPendingApproval) {
      router.go('/pending-approval');
    } else if (isRejected) {
      router.go('/account-rejected');
    } else if (_userRole == 'agency_admin' || _userRole == 'provincial_admin') {
      router.go('/dashboard-only');
    } else if (_userRole == 'responder') {
      // Approved Responders go to their own queue shell
      router.go('/responder/queue');
    } else {
      router.go('/home');
    }
  }

  /// Navigate to login — replaces the entire stack so back can't return to app.
  void navigateToLogin() {
    _router?.go('/login');
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
