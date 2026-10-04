import 'package:flutter/foundation.dart';
import '../../routing/app_routes.dart';

/// Supabase configuration for Super Admin application.
/// Connects to the central shared Supabase project (project ref: hnvjenkeimzkdgkuwbeb)
/// used by School/Admin, Teacher, Parent, and Super Admin applications.
class SupabaseConfig {
  static const String _envUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _envKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const String _envAppBaseUrl = String.fromEnvironment('APP_BASE_URL');

  // Central School Management Supabase project reference: hnvjenkeimzkdgkuwbeb
  static const String _fallbackUrl = 'https://hnvjenkeimzkdgkuwbeb.supabase.co';
  static const String _fallbackPublishableKey = 'sb_publishable_19M-FirlFuK29VbdO1d87g_bNOysJwZ';

  static String get url {
    final raw = (_envUrl.isNotEmpty ? _envUrl : _fallbackUrl).trim();
    return raw.replaceAll(RegExp(r'/rest/v1/?$'), '').replaceAll(RegExp(r'/+$'), '');
  }

  static String get publishableKey =>
      (_envKey.isNotEmpty ? _envKey : _fallbackPublishableKey).trim();

  static bool get isConfigured =>
      url.isNotEmpty &&
      publishableKey.isNotEmpty &&
      !url.contains('YOUR_SUPABASE_PROJECT_ID') &&
      !publishableKey.contains('YOUR_SUPABASE_PUBLISHABLE_KEY');

  /// Dynamic redirect URL for Password Reset.
  /// In Web development and production, resolves the current running origin
  /// (e.g. http://localhost:54321 or https://admin.schoolos.com).
  /// Supabase appends #access_token=...&type=recovery to this origin, which supabase_flutter
  /// natively receives and exchanges for a valid recovery session.
  static String get passwordResetRedirectUrl {
    String base;
    if (_envAppBaseUrl.isNotEmpty) {
      base = _envAppBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    } else if (kIsWeb) {
      String origin = '';
      try {
        origin = Uri.base.origin;
      } catch (_) {}
      if (origin.isNotEmpty && origin != 'null') {
        base = origin;
      } else {
        base = 'http://localhost:50000';
      }
    } else {
      base = 'http://localhost:50000';
    }
    return '$base/#${AppRoutes.updatePassword}';
  }
}

