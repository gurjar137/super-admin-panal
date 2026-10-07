import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/super_admin_model.dart';
import '../../services/auth_service.dart';
import '../../services/supabase_service.dart';

/// Authoritative in-memory state tracking the verified Super Admin session.
/// Used by GoRouter as a [refreshListenable] to enforce the top-level route guard.
class AppAuthState extends ChangeNotifier {
  static AppAuthState? _instance;
  static AppAuthState get instance => _instance ??= AppAuthState._();

  AppAuthState._();

  bool _isInitialized = false;
  SuperAdminProfile? _currentProfile;
  StreamSubscription<AuthState>? _authSubscription;

  /// Whether initial startup session verification has completed.
  bool get isInitialized => _isInitialized;

  /// The authoritatively verified Super Admin profile from public.profiles.
  SuperAdminProfile? get currentProfile => _currentProfile;

  /// Strict authentication check:
  /// Profile must exist, must have role 'super_admin' or 'owner', and must have status 'active'.
  bool get isAuthenticated =>
      _currentProfile != null &&
      _currentProfile!.isSuperAdmin &&
      _currentProfile!.status.toLowerCase() == 'active';

  /// Initialize and verify existing session with the authoritative backend.
  Future<void> initialize({AuthService? authService}) async {
    final service = authService ?? AuthService();
    final client = SupabaseService.instance.client;

    // Listen to Supabase auth events (sign-out, session expiration, token refresh)
    if (client != null && _authSubscription == null) {
      try {
        _authSubscription = client.auth.onAuthStateChange.listen((data) {
          final event = data.event;
          debugPrint('[AppAuthState] Supabase AuthChangeEvent: $event');
          if (event == AuthChangeEvent.signedOut) {
            setUnauthenticated();
          }
        });
      } catch (e) {
        debugPrint('[AppAuthState] Warning: failed to attach auth state listener: $e');
      }
    }

    if (client == null || client.auth.currentSession == null) {
      _currentProfile = null;
      _isInitialized = true;
      notifyListeners();
      return;
    }

    try {
      final profile = await service.getActiveSuperAdminSession();
      if (profile != null) {
        _currentProfile = profile;
      } else {
        _currentProfile = null;
      }
    } catch (e) {
      debugPrint('[AppAuthState] Error verifying session on startup: $e');
      _currentProfile = null;
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// Update the active verified profile (called after successful login).
  void setProfile(SuperAdminProfile? profile) {
    _currentProfile = profile;
    _isInitialized = true;
    notifyListeners();
  }

  /// Invalidate the active profile and mark session unauthenticated (called on logout or failure).
  void setUnauthenticated() {
    _currentProfile = null;
    _isInitialized = true;
    notifyListeners();
  }

  /// Reset state for test isolation.
  void resetForTesting({
    bool isInitialized = true,
    SuperAdminProfile? profile,
  }) {
    _isInitialized = isInitialized;
    _currentProfile = profile;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _authSubscription = null;
    super.dispose();
  }
}
