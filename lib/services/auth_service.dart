import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/auth/app_auth_state.dart';
import '../core/config/supabase_config.dart';
import '../core/network/api_result.dart';
import '../models/super_admin_model.dart';
import 'audit_log_service.dart';
import 'supabase_service.dart';

class AuthService {
  final SupabaseClient? _customClient;
  final AuditLogService _auditLogService;

  AuthService({
    SupabaseClient? client,
    AuditLogService? auditLogService,
  })  : _customClient = client,
        _auditLogService = auditLogService ?? AuditLogService(client: client);

  SupabaseClient? get _client => _customClient ?? SupabaseService.instance.client;
  AuditLogService get auditLogService => _auditLogService;

  /// Check current authenticated session and enforce Super Admin authorization
  Future<SuperAdminProfile?> getActiveSuperAdminSession() async {
    final client = _client;
    if (client == null) {
      AppAuthState.instance.setUnauthenticated();
      return null;
    }

    final session = client.auth.currentSession;
    if (session == null || client.auth.currentUser == null) {
      AppAuthState.instance.setUnauthenticated();
      return null;
    }

    final user = client.auth.currentUser!;
    try {
      final profileResult = await _verifySuperAdminRole(user.id, user.email ?? '');
      if (profileResult == null) {
        debugPrint('[AuthService] Current session does not have Super Admin privileges. Logging out.');
        await client.auth.signOut();
        AppAuthState.instance.setUnauthenticated();
        return null;
      }
      AppAuthState.instance.setProfile(profileResult);
      return profileResult;
    } catch (e) {
      debugPrint('[AuthService] Error verifying existing session: $e');
      AppAuthState.instance.setUnauthenticated();
      return null;
    }
  }

  /// Sign in with Email and Password, strictly checking Super Admin role
  Future<ApiResult<SuperAdminProfile>> signIn({
    required String email,
    required String password,
  }) async {
    final client = _client;
    if (client == null) {
      return ApiResult.failure('Database service is currently uninitialized.');
    }

    final trimmedEmail = email.trim().toLowerCase();
    if (trimmedEmail.isEmpty || password.isEmpty) {
      return ApiResult.failure('Please enter both your email address and password.');
    }

    try {
      final authResponse = await client.auth.signInWithPassword(
        email: trimmedEmail,
        password: password,
      );

      final session = authResponse.session;
      final user = authResponse.user;
      if (session == null || user == null) {
        return ApiResult.failure('Authentication failed: No active session returned.');
      }

      // STRICT MULTI-TENANT SECURITY:
      // Verify that this identity is a Super Administrator from the backend profiles table.
      final checkResult = await _checkSuperAdminAuthorization(user.id, user.email ?? trimmedEmail);

      if (checkResult.isFailure) {
        // Immediately revoke session
        await client.auth.signOut();
        AppAuthState.instance.setUnauthenticated();
        return ApiResult.failure(checkResult.errorOrNull ?? 'This account is not authorized for Super Admin access.');
      }

      final superAdmin = checkResult.dataOrNull;
      if (superAdmin == null) {
        await client.auth.signOut();
        AppAuthState.instance.setUnauthenticated();
        return ApiResult.failure('This account is not authorized for Super Admin access.');
      }

      AppAuthState.instance.setProfile(superAdmin);

      // Persistent Audit Logging: super_admin_login
      try {
        await _auditLogService.recordAuditEvent(
          action: 'super_admin_login',
          entityType: 'auth',
          entityId: superAdmin.authUserId,
          metadata: {
            'action_category': 'auth',
            'email': superAdmin.email,
            'role': superAdmin.role,
          },
        );
      } catch (auditErr) {
        debugPrint('[AuthService] Audit login notice: $auditErr');
      }

      return ApiResult.success(superAdmin);
    } on AuthException catch (e) {
      debugPrint('[AuthService] Supabase AuthException: ${e.message} (status: ${e.statusCode})');
      final message = e.message.toLowerCase();
      if (message.contains('invalid login credentials') || message.contains('invalid_grant')) {
        return ApiResult.failure('Email or password is incorrect.');
      }
      if (message.contains('email not confirmed')) {
        return ApiResult.failure('Email not confirmed. Please verify your email address.');
      }
      return ApiResult.failure('Authentication error: ${e.message}');
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('socketexception') || errStr.contains('network') || errStr.contains('failed host lookup')) {
        return ApiResult.failure('Network connection error. Please check your internet connection.');
      }
      return ApiResult.failure('An unexpected error occurred during sign in.');
    }
  }

  /// Check Super Admin role and status from public.profiles
  Future<ApiResult<SuperAdminProfile>> _checkSuperAdminAuthorization(String authUserId, String email) async {
    final client = _client;
    if (client == null) {
      return ApiResult.failure('Database service is uninitialized.');
    }

    try {
      // Query public.profiles where auth_user_id matches
      final response = await client
          .from('profiles')
          .select('id, auth_user_id, email, full_name, role, status, school_id, created_at')
          .eq('auth_user_id', authUserId)
          .maybeSingle();

      if (response != null) {
        final profile = SuperAdminProfile.fromJson(response);
        if (!profile.isSuperAdmin) {
          return ApiResult.failure('This account is not authorized for Super Admin access.');
        }
        if (profile.status.toLowerCase() != 'active') {
          return ApiResult.failure('This Super Admin account is inactive.');
        }
        return ApiResult.success(profile);
      }

      // Authoritative security: If no matching profile exists in public.profiles, access is denied.
      return ApiResult.failure('This account is not authorized for Super Admin access.');
    } catch (e) {
      debugPrint('[AuthService] Role check error: $e');
      return ApiResult.failure('Failed to verify Super Admin privileges: $e');
    }
  }

  /// Verify Super Admin identity strictly from public.profiles table
  Future<SuperAdminProfile?> _verifySuperAdminRole(String authUserId, String email) async {
    final res = await _checkSuperAdminAuthorization(authUserId, email);
    return res.dataOrNull;
  }

  /// Log out current user
  Future<void> signOut() async {
    final client = _client;
    if (client != null) {
      final user = client.auth.currentUser;
      if (user != null) {
        try {
          await _auditLogService.recordAuditEvent(
            action: 'super_admin_logout',
            entityType: 'auth',
            entityId: user.id,
            metadata: {
              'action_category': 'auth',
              'email': user.email,
            },
          );
        } catch (auditErr) {
          debugPrint('[AuthService] Audit logout notice: $auditErr');
        }
      }

      try {
        await client.auth.signOut();
      } catch (e) {
        debugPrint('[AuthService] SignOut error: $e');
      }
    }
    AppAuthState.instance.setUnauthenticated();
  }

  /// Request password reset email using isolated implicit client matching School/Admin App
  Future<ApiResult<void>> requestPasswordReset(String email) async {
    if (!SupabaseConfig.isConfigured) {
      return ApiResult.failure('Database service is uninitialized.');
    }
    final trimmedEmail = email.trim().toLowerCase();
    if (trimmedEmail.isEmpty) {
      return ApiResult.failure('Please enter your email address.');
    }

    try {
      final currentOrigin = kIsWeb ? Uri.base.origin : 'non-web';
      final appBaseUrl = const String.fromEnvironment('APP_BASE_URL');
      final redirectUrl = SupabaseConfig.passwordResetRedirectUrl;

      debugPrint('[AuthService] Current Uri.base.origin: $currentOrigin');
      debugPrint('[AuthService] APP_BASE_URL: ${appBaseUrl.isNotEmpty ? appBaseUrl : '(not configured)'}');
      debugPrint('[AuthService] Computed passwordResetRedirectUrl: $redirectUrl');
      debugPrint('[AuthService] Requesting password reset via isolated implicit client for: $trimmedEmail');

      // Isolated recovery client with AuthFlowType.implicit to generate standard implicit recovery tokens
      // (#access_token=...&type=recovery), eliminating cross-browser PKCE code-verifier dependency
      final recoveryClient = SupabaseClient(
        SupabaseConfig.url,
        SupabaseConfig.publishableKey,
        authOptions: const AuthClientOptions(
          authFlowType: AuthFlowType.implicit,
        ),
      );

      await recoveryClient.auth.resetPasswordForEmail(
        trimmedEmail,
        redirectTo: redirectUrl,
      );
      debugPrint('[AuthService] Password reset email dispatched successfully via implicit recovery.');

      // Persistent Audit Logging: password_reset_requested
      try {
        await _auditLogService.recordAuditEvent(
          action: 'password_reset_requested',
          entityType: 'auth',
          metadata: {
            'action_category': 'auth',
            'email': trimmedEmail,
          },
        );
      } catch (auditErr) {
        debugPrint('[AuthService] Audit password reset notice: $auditErr');
      }

      return ApiResult.success(null);
    } on AuthException catch (e) {
      debugPrint('[AuthService] resetPasswordForEmail AuthException: ${e.message}');
      final msg = e.message.toLowerCase();
      if (msg.contains('rate limit') || msg.contains('over_email_send_rate_limit')) {
        return ApiResult.failure('Password reset requested recently. Please wait a minute before requesting again.', e);
      }
      return ApiResult.failure(e.message, e);
    } catch (e) {
      debugPrint('[AuthService] resetPasswordForEmail unexpected error: $e');
      return ApiResult.failure('Failed to request password reset: $e', e);
    }
  }

  /// Update password for the currently authenticated recovery session
  Future<ApiResult<void>> updatePassword(String newPassword) async {
    final client = _client;
    if (client == null) {
      return ApiResult.failure('Database service is uninitialized.');
    }
    try {
      await client.auth.updateUser(UserAttributes(password: newPassword));
      return ApiResult.success(null);
    } on AuthException catch (e) {
      debugPrint('[AuthService] Update password AuthException: ${e.message}');
      return ApiResult.failure(e.message, e);
    } catch (e) {
      debugPrint('[AuthService] Update password unexpected error: $e');
      return ApiResult.failure('Failed to update password: $e', e);
    }
  }
}
