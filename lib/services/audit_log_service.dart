import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/network/api_result.dart';
import '../models/super_admin_audit_log_model.dart';
import 'supabase_service.dart';

class AuditLogService {
  final SupabaseClient? _customClient;

  AuditLogService({SupabaseClient? client}) : _customClient = client;

  SupabaseClient? get _client => _customClient ?? SupabaseService.instance.client;

  /// Records an administrative audit event via server-side SECURITY DEFINER RPC.
  /// Authoritative actor identity is derived server-side via auth.uid() and profiles.
  Future<ApiResult<String>> recordAuditEvent({
    required String action,
    required String entityType,
    String? entityId,
    String? schoolId,
    Map<String, dynamic>? metadata,
  }) async {
    final client = _client;
    if (client == null) {
      return ApiResult.failure('Database service is not initialized');
    }

    try {
      final response = await client.rpc(
        'record_super_admin_audit_event',
        params: {
          'p_action': action.trim(),
          'p_entity_type': entityType.trim(),
          'p_entity_id': entityId,
          'p_school_id': schoolId,
          'p_metadata': metadata ?? <String, dynamic>{},
        },
      );

      final logId = response?.toString() ?? '';
      return ApiResult.success(logId);
    } catch (e) {
      debugPrint('[AuditLogService] Failed to record audit event $action: $e');
      return ApiResult.failure(e.toString());
    }
  }

  /// Fetches paginated audit logs ordered newest first.
  Future<ApiResult<List<SuperAdminAuditLogModel>>> fetchAuditLogs({
    int limit = 50,
    int offset = 0,
    String? actionFilter,
    String? schoolIdFilter,
    String? entityTypeFilter,
  }) async {
    final client = _client;
    if (client == null) {
      return ApiResult.failure('Database service is not initialized');
    }

    try {
      var query = client
          .from('super_admin_audit_logs')
          .select('*');

      if (actionFilter != null && actionFilter.trim().isNotEmpty) {
        query = query.eq('action', actionFilter.trim());
      }
      if (schoolIdFilter != null && schoolIdFilter.trim().isNotEmpty) {
        query = query.eq('school_id', schoolIdFilter.trim());
      }
      if (entityTypeFilter != null && entityTypeFilter.trim().isNotEmpty) {
        query = query.eq('entity_type', entityTypeFilter.trim());
      }

      final response = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      final list = (response as List<dynamic>)
          .map((item) => SuperAdminAuditLogModel.fromJson(item as Map<String, dynamic>))
          .toList();

      return ApiResult.success(list);
    } catch (e) {
      debugPrint('[AuditLogService] Error fetching audit logs: $e');
      return ApiResult.failure(e.toString());
    }
  }
}
