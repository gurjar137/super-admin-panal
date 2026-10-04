import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

/// Explicit lifecycle states for the password recovery flow
enum RecoveryStatus {
  idle,
  processing,
  authenticated,
  failed,
}

/// Pure URL normalizer for Supabase recovery links in Flutter Web hash-routing environments
Uri normalizeRecoveryUrl(String rawUrl) {
  if (rawUrl.contains('access_token=')) {
    final tokenIndex = rawUrl.indexOf('access_token=');
    final firstHashIndex = rawUrl.indexOf('#');
    if (firstHashIndex != -1 && tokenIndex > firstHashIndex) {
      final origin = Uri.parse(rawUrl).origin;
      final fragment = rawUrl.substring(tokenIndex);
      return Uri.parse('$origin/#$fragment');
    }
  } else if (rawUrl.contains('code=')) {
    final codeIndex = rawUrl.indexOf('code=');
    final origin = Uri.parse(rawUrl).origin;
    final queryOrFragment = rawUrl.substring(codeIndex);
    return Uri.parse('$origin/?$queryOrFragment');
  }
  return Uri.parse(rawUrl);
}

/// Global state tracking and SINGLE AUTHORITATIVE OWNER of PKCE code exchange
class RecoverySessionState {
  static RecoveryStatus status = RecoveryStatus.idle;
  static final ValueNotifier<RecoveryStatus> statusNotifier = ValueNotifier<RecoveryStatus>(RecoveryStatus.idle);

  static String? statusMessage;
  static String? errorMessage;

  static bool get isIdle => status == RecoveryStatus.idle;
  static bool get isProcessing => status == RecoveryStatus.processing;
  static bool get isAuthenticated => status == RecoveryStatus.authenticated;
  static bool get isFailed => status == RecoveryStatus.failed;

  static bool codeDetected = false;
  static bool exchangeAttempted = false;
  static bool exchangeSuccess = false;
  static int exchangeCount = 0;
  static bool recoveryEventReceived = false;
  static String recoveryMechanism = 'none'; // 'implicit', 'pkce', or 'none'

  // Safe parameter type detection (names only, NO secrets/tokens logged)
  static List<String> detectedParamNames = [];

  static bool get hasActiveSession {
    if (!SupabaseConfig.isConfigured) return false;
    try {
      final client = Supabase.instance.client;
      return client.auth.currentSession != null || client.auth.currentUser != null;
    } catch (_) {
      return false;
    }
  }

  /// Authoritative startup recovery processor.
  /// This is the SOLE OWNER of recovery session establishment via getSessionFromUrl across the entire application.
  static Future<void> processStartupRecovery(SupabaseClient client) async {
    if (!kIsWeb) return;
    // Strict idempotency: NEVER exchange code more than once
    if (exchangeCount > 0 || exchangeAttempted) {
      debugPrint('[RecoverySessionState] Recovery exchange already attempted ($exchangeCount). Skipping duplicate call.');
      return;
    }

    try {
      final uri = Uri.base;
      final rawUrl = uri.toString();

      // Safely inspect parameter names only (NO values)
      detectedParamNames.clear();
      if (rawUrl.contains('access_token=')) detectedParamNames.add('access_token');
      if (rawUrl.contains('refresh_token=')) detectedParamNames.add('refresh_token');
      if (rawUrl.contains('type=recovery') || rawUrl.contains('type=')) detectedParamNames.add('type');
      if (rawUrl.contains('code=')) detectedParamNames.add('code');
      if (rawUrl.contains('error=')) detectedParamNames.add('error');
      if (rawUrl.contains('error_description=')) detectedParamNames.add('error_description');

      // Check queryParameters, fragment, and raw URL for PKCE 'code'
      String? authCode = uri.queryParameters['code'];
      if (authCode == null || authCode.isEmpty) {
        final fragmentParams = Uri.splitQueryString(uri.fragment);
        authCode = fragmentParams['code'];
      }
      if (authCode == null || authCode.isEmpty) {
        final match = RegExp(r'[?&#]code=([^&#]+)').firstMatch(rawUrl);
        if (match != null) {
          authCode = Uri.decodeComponent(match.group(1)!);
        }
      }

      final hasAccessToken = rawUrl.contains('access_token=');
      final isRecoveryType = rawUrl.contains('type=recovery');

      codeDetected = hasAccessToken || isRecoveryType || rawUrl.contains('code=');

      if (!codeDetected) {
        if (hasActiveSession) {
          _updateStatus(RecoveryStatus.authenticated);
        } else {
          _updateStatus(RecoveryStatus.idle);
        }
        return;
      }

      // Mark exchange started - exactly once
      exchangeAttempted = true;
      exchangeCount = 1;
      _updateStatus(RecoveryStatus.processing, message: 'Verifying password reset link...');

      debugPrint('[RecoverySessionState] Single authoritative recovery processing started with parameter types: $detectedParamNames');

      // Proven School/Admin architecture: Implicit recovery via getSessionFromUrl
      recoveryMechanism = 'implicit';
      final normalizedUri = normalizeRecoveryUrl(rawUrl);
      debugPrint('[RecoverySessionState] Normalized recovery URL origin: ${normalizedUri.origin}');

      await client.auth.getSessionFromUrl(normalizedUri);

      // Verify active session after single recovery call
      if (hasActiveSession) {
        exchangeSuccess = true;
        recoveryEventReceived = true;
        errorMessage = null;
        _updateStatus(RecoveryStatus.authenticated);
        debugPrint('[RecoverySessionState] Single authoritative recovery processing SUCCEEDED! Active session verified.');
      } else {
        exchangeSuccess = false;
        errorMessage = 'Password reset link has expired or is invalid. Please request a new one.';
        _updateStatus(RecoveryStatus.failed);
        debugPrint('[RecoverySessionState] Recovery processing finished but no active session found.');
      }
    } on AuthException catch (e) {
      exchangeSuccess = false;
      errorMessage = 'Password reset link has expired or is invalid. Please request a new one.';
      _updateStatus(RecoveryStatus.failed);
      debugPrint('[RecoverySessionState AuthException]: ${e.message} (status: ${e.statusCode}, code: ${e.code})');
    } catch (e) {
      exchangeSuccess = false;
      errorMessage = 'Password reset link has expired or is invalid. Please request a new one.';
      _updateStatus(RecoveryStatus.failed);
      debugPrint('[RecoverySessionState Error]: $e');
    } finally {
      printSafeDiagnostics();
    }
  }

  static void onPasswordRecoveryEvent() {
    recoveryEventReceived = true;
    if (hasActiveSession) {
      _updateStatus(RecoveryStatus.authenticated);
    }
  }

  static void _updateStatus(RecoveryStatus newStatus, {String? message}) {
    status = newStatus;
    statusMessage = message;
    statusNotifier.value = newStatus;
  }

  @visibleForTesting
  static void resetForTesting({
    RecoveryStatus initialStatus = RecoveryStatus.idle,
    bool clearExchangeCount = true,
  }) {
    status = initialStatus;
    statusNotifier.value = initialStatus;
    statusMessage = null;
    errorMessage = null;
    if (clearExchangeCount) {
      exchangeAttempted = false;
      exchangeSuccess = false;
      exchangeCount = 0;
    }
    codeDetected = false;
    detectedParamNames.clear();
    recoveryMechanism = 'none';
    recoveryEventReceived = false;
  }

  static void printSafeDiagnostics() {
    final sessionActive = hasActiveSession;
    bool userExists = false;
    if (SupabaseConfig.isConfigured) {
      try {
        userExists = Supabase.instance.client.auth.currentUser != null;
      } catch (_) {}
    }

    debugPrint('========================================');
    debugPrint('=== SUPABASE RECOVERY SESSION DIAGNOSTICS ===');
    debugPrint('recovery status: ${status.name}');
    debugPrint('recovery parameter detected: $codeDetected');
    debugPrint('detected parameter names: $detectedParamNames');
    debugPrint('recovery mechanism: $recoveryMechanism');
    debugPrint('exchange attempted: $exchangeAttempted');
    debugPrint('exchange count: $exchangeCount');
    debugPrint('exchange success: $exchangeSuccess');
    debugPrint('session active: $sessionActive');
    debugPrint('currentUser exists: $userExists');
    debugPrint('PASSWORD_RECOVERY event/session ready: $recoveryEventReceived');
    debugPrint('========================================');
  }
}
