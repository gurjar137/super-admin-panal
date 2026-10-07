import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_result.dart';
import '../models/super_admin_audit_log_model.dart';
import '../services/audit_log_service.dart';

final auditLogServiceProvider = Provider<AuditLogService>((ref) => AuditLogService());

final auditLogRepositoryProvider = Provider<AuditLogRepository>((ref) {
  return AuditLogRepository(ref.watch(auditLogServiceProvider));
});

class AuditLogFilter {
  final String? action;
  final String? schoolId;
  final String? entityType;
  final int page;
  final int pageSize;

  const AuditLogFilter({
    this.action,
    this.schoolId,
    this.entityType,
    this.page = 0,
    this.pageSize = 50,
  });

  AuditLogFilter copyWith({
    String? action,
    String? schoolId,
    String? entityType,
    int? page,
    int? pageSize,
    bool clearAction = false,
    bool clearSchool = false,
    bool clearEntityType = false,
  }) {
    return AuditLogFilter(
      action: clearAction ? null : (action ?? this.action),
      schoolId: clearSchool ? null : (schoolId ?? this.schoolId),
      entityType: clearEntityType ? null : (entityType ?? this.entityType),
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
    );
  }
}

final auditLogFilterProvider = StateProvider<AuditLogFilter>((ref) => const AuditLogFilter());

final auditLogsProvider = FutureProvider.autoDispose<List<SuperAdminAuditLogModel>>((ref) async {
  final filter = ref.watch(auditLogFilterProvider);
  final repo = ref.watch(auditLogRepositoryProvider);

  final result = await repo.getAuditLogs(
    offset: filter.page * filter.pageSize,
    limit: filter.pageSize,
    actionFilter: filter.action,
    schoolIdFilter: filter.schoolId,
    entityTypeFilter: filter.entityType,
  );

  if (result.isSuccess) {
    return result.dataOrNull ?? [];
  } else {
    throw Exception(result.errorOrNull ?? 'Failed to load audit logs');
  }
});

class AuditLogRepository {
  final AuditLogService _service;

  AuditLogRepository(this._service);

  Future<ApiResult<String>> recordEvent({
    required String action,
    required String entityType,
    String? entityId,
    String? schoolId,
    Map<String, dynamic>? metadata,
  }) {
    return _service.recordAuditEvent(
      action: action,
      entityType: entityType,
      entityId: entityId,
      schoolId: schoolId,
      metadata: metadata,
    );
  }

  Future<ApiResult<List<SuperAdminAuditLogModel>>> getAuditLogs({
    int limit = 50,
    int offset = 0,
    String? actionFilter,
    String? schoolIdFilter,
    String? entityTypeFilter,
  }) {
    return _service.fetchAuditLogs(
      limit: limit,
      offset: offset,
      actionFilter: actionFilter,
      schoolIdFilter: schoolIdFilter,
      entityTypeFilter: entityTypeFilter,
    );
  }
}
