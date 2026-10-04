import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/auth/recovery_session_state.dart';
import '../core/config/supabase_config.dart';

class SupabaseService {
  static SupabaseService? _instance;
  static SupabaseService get instance => _instance ??= SupabaseService._();

  SupabaseService._();

  bool _initialized = false;
  bool get isInitialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;

    if (!SupabaseConfig.isConfigured) {
      debugPrint('[SupabaseService] Configuration missing or incomplete.');
      return;
    }

    try {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        publishableKey: SupabaseConfig.publishableKey,
        authOptions: const FlutterAuthClientOptions(
          detectSessionInUri: false, // Authoritative single recovery processing in RecoverySessionState
        ),
      );
      _initialized = true;
      debugPrint('[SupabaseService] Initialized successfully with URL: ${SupabaseConfig.url}');

      // Authoritative startup recovery processor for Flutter web
      final client = Supabase.instance.client;
      await RecoverySessionState.processStartupRecovery(client);
    } catch (e) {
      debugPrint('[SupabaseService] Initialization failed: $e');
    }
  }

  SupabaseClient? get client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }
}
