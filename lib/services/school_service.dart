import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/network/api_result.dart';
import '../models/school_model.dart';
import '../models/school_provision_dto.dart';
import 'audit_log_service.dart';
import 'supabase_service.dart';

class SchoolService {
  final SupabaseClient? _customClient;
  final AuditLogService _auditLogService;

  SchoolService({
    SupabaseClient? client,
    AuditLogService? auditLogService,
  })  : _customClient = client,
        _auditLogService = auditLogService ?? AuditLogService(client: client);

  SupabaseClient? get _client => _customClient ?? SupabaseService.instance.client;
  AuditLogService get auditLogService => _auditLogService;

  static const String _schoolColumns =
      'id, name, code, address, phone, email, logo_url, status, created_at, updated_at';

  static const String _schoolDirectoryJoinedColumns =
      'id, name, code, address, phone, email, logo_url, status, created_at, updated_at, '
      'school_management_apps(id, app_name, status, school_app_subscriptions(id, status, plan_name))';

  /// Helper to safely parse joined apps and subscription status from PostgREST payload
  static (int appCount, String? subSummary, String? appName) _parseJoinedAppData(dynamic rawAppsData) {
    if (rawAppsData == null) {
      return (0, null, null);
    }

    final List<dynamic> appsList;
    if (rawAppsData is List) {
      appsList = rawAppsData;
    } else if (rawAppsData is Map) {
      appsList = [rawAppsData];
    } else {
      return (0, null, null);
    }

    if (appsList.isEmpty) {
      return (0, null, null);
    }

    final appCount = appsList.length;
    int activeAppCount = 0;
    String? primaryAppName;

    for (final appEntry in appsList) {
      if (appEntry is! Map<String, dynamic>) continue;
      primaryAppName ??= appEntry['app_name']?.toString();

      final appStatus = (appEntry['status']?.toString().toUpperCase() ?? '');
      // Check if the app or its associated subscription is active
      bool isAppActive = appStatus == 'ACTIVE';

      final rawSubs = appEntry['school_app_subscriptions'];
      if (rawSubs != null) {
        final List<dynamic> subsList = rawSubs is List ? rawSubs : (rawSubs is Map ? [rawSubs] : []);
        final hasActiveSub = subsList.any((s) =>
            s is Map<String, dynamic> &&
            (s['status']?.toString().toUpperCase() ?? '') == 'ACTIVE');
        if (hasActiveSub) {
          isAppActive = true;
        }
      }

      if (isAppActive) {
        activeAppCount++;
      }
    }

    final subSummary = appCount > 0 ? '$activeAppCount/$appCount Active' : null;
    return (appCount, subSummary, primaryAppName);
  }

  /// Fetch schools with server-side search query, status filter, and pagination.
  /// Uses a single joined PostgREST query to fetch schools, their management apps,
  /// and subscriptions in 1 round trip with zero N+1 queries.
  Future<ApiResult<List<SchoolModel>>> fetchSchools({
    String? searchQuery,
    SchoolStatus? statusFilter,
    int? page,
    int? pageSize,
  }) async {
    final client = _client;
    if (client == null) {
      return ApiResult.failure('Database service is uninitialized.');
    }

    try {
      var query = client.from('schools').select(_schoolDirectoryJoinedColumns);

      if (statusFilter != null) {
        query = query.ilike('status', statusFilter.dbValue);
      }

      // Server-side search filter across name, code, and email evaluated BEFORE ordering and range
      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final term = searchQuery.trim().replaceAll(RegExp(r'[%_]'), '');
        if (term.isNotEmpty) {
          query = query.or('name.ilike.%$term%,code.ilike.%$term%,email.ilike.%$term%');
        }
      }

      // Stable ordering: created_at DESC with id DESC as tie-breaker
      final orderedQuery = query
          .order('created_at', ascending: false)
          .order('id', ascending: false);

      final PostgrestTransformBuilder finalQuery;
      if (page != null || pageSize != null) {
        final p = page ?? 0;
        final ps = pageSize ?? 25;
        final offset = p * ps;
        finalQuery = orderedQuery.range(offset, offset + ps - 1);
      } else {
        finalQuery = orderedQuery;
      }

      final response = await finalQuery;

      final List<dynamic> rawList = response as List<dynamic>;
      final List<SchoolModel> schools = rawList.map((item) {
        final schoolMap = item as Map<String, dynamic>;
        final model = SchoolModel.fromJson(schoolMap);

        final (appCount, subSummary, primaryAppName) =
            _parseJoinedAppData(schoolMap['school_management_apps']);

        return model.copyWith(
          assignedAppsCount: appCount,
          activeSubscriptionSummary: subSummary,
          appName: primaryAppName ?? model.appName,
        );
      }).toList();

      return ApiResult.success(schools);
    } catch (e) {
      debugPrint('[SchoolService] fetchSchools error: $e');
      return ApiResult.failure(_formatErrorMessage(e, 'Failed to load schools'), e);
    }
  }

  /// Fetches total count of schools matching optional search query and status filter
  /// Uses a lightweight PostgREST count request without downloading full table rows.
  Future<ApiResult<int>> fetchSchoolsCount({
    String? searchQuery,
    SchoolStatus? statusFilter,
  }) async {
    final client = _client;
    if (client == null) {
      return ApiResult.failure('Database service is uninitialized.');
    }

    try {
      var query = client.from('schools').select('id');

      if (statusFilter != null) {
        query = query.ilike('status', statusFilter.dbValue);
      }

      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final term = searchQuery.trim().replaceAll(RegExp(r'[%_]'), '');
        if (term.isNotEmpty) {
          query = query.or('name.ilike.%$term%,code.ilike.%$term%,email.ilike.%$term%');
        }
      }

      final res = await query.count(CountOption.exact);
      return ApiResult.success(res.count);
    } catch (e) {
      debugPrint('[SchoolService] fetchSchoolsCount error: $e');
      return ApiResult.failure(_formatErrorMessage(e, 'Failed to count schools'), e);
    }
  }

  /// Fetch single school details, including primary administrator summary
  /// and joined dedicated apps / subscriptions in a single unified query.
  Future<ApiResult<SchoolModel>> fetchSchoolDetails(String schoolId) async {
    final client = _client;
    if (client == null) {
      return ApiResult.failure('Database service is uninitialized.');
    }

    try {
      final schoolData = await client
          .from('schools')
          .select(_schoolDirectoryJoinedColumns)
          .eq('id', schoolId)
          .single();

      var model = SchoolModel.fromJson(schoolData);

      // Parse joined app and subscription info
      final (appCount, subSummary, primaryAppName) =
          _parseJoinedAppData(schoolData['school_management_apps']);

      model = model.copyWith(
        assignedAppsCount: appCount,
        activeSubscriptionSummary: appCount > 0
            ? '$subSummary Apps'
            : 'No Apps Assigned',
        appName: primaryAppName ?? model.appName,
      );

      // Attempt to fetch primary school administrator info from public.profiles
      try {
        final adminData = await client
            .from('profiles')
            .select('full_name, email, phone, designation')
            .eq('school_id', schoolId)
            .eq('role', 'school_admin')
            .limit(1)
            .maybeSingle();

        if (adminData != null) {
          model = model.copyWith(
            adminName: adminData['full_name']?.toString(),
            adminEmail: adminData['email']?.toString(),
            adminPhone: adminData['phone']?.toString(),
          );
        }
      } catch (adminErr) {
        debugPrint('[SchoolService] Admin profile lookup notice: $adminErr');
      }

      return ApiResult.success(model);
    } catch (e) {
      debugPrint('[SchoolService] fetchSchoolDetails error: $e');
      return ApiResult.failure(_formatErrorMessage(e, 'Failed to fetch school details'), e);
    }
  }

  /// Update school status (e.g. Activate / Deactivate / Suspend)
  Future<ApiResult<SchoolModel>> updateSchoolStatus({
    required String schoolId,
    required SchoolStatus newStatus,
  }) async {
    final client = _client;
    if (client == null) {
      return ApiResult.failure('Database service is uninitialized.');
    }

    try {
      final updatedData = await client
          .from('schools')
          .update({
            'status': newStatus.dbValue,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', schoolId)
          .select(_schoolColumns)
          .single();

      final updatedModel = SchoolModel.fromJson(updatedData);

      // Persistent Audit Logging (Record only after DB update succeeds)
      try {
        final effectiveAction = (newStatus == SchoolStatus.suspended)
            ? 'school_suspended'
            : (newStatus == SchoolStatus.inactive
                ? 'school_deactivated'
                : (newStatus == SchoolStatus.active ? 'school_reactivated' : 'school_status_changed'));

        await _auditLogService.recordAuditEvent(
          action: effectiveAction,
          entityType: 'school',
          entityId: schoolId,
          schoolId: schoolId,
          metadata: {
            'action_category': 'school_status_changed',
            'school_name': updatedModel.name,
            'school_code': updatedModel.code,
            'new_status': newStatus.dbValue,
            'status': newStatus.name,
          },
        );
      } catch (auditErr) {
        debugPrint('[SchoolService] Audit event logging notice: $auditErr');
      }

      return ApiResult.success(updatedModel);
    } catch (e) {
      debugPrint('[SchoolService] updateSchoolStatus error: $e');
      return ApiResult.failure(_formatErrorMessage(e, 'Failed to update status'), e);
    }
  }

  /// Update school profile metadata (name, address, phone, email, logoUrl)
  Future<ApiResult<SchoolModel>> updateSchool({
    required String schoolId,
    required String name,
    String? address,
    String? phone,
    String? email,
    String? logoUrl,
  }) async {
    final client = _client;
    if (client == null) {
      return ApiResult.failure('Database service is uninitialized.');
    }

    try {
      final updateData = <String, dynamic>{
        'name': name.trim(),
        'address': address?.trim(),
        'phone': phone?.trim(),
        'email': email?.trim().toLowerCase(),
        'logo_url': logoUrl?.trim().isNotEmpty == true ? logoUrl!.trim() : null,
        'updated_at': DateTime.now().toIso8601String(),
      };

      final updatedData = await client
          .from('schools')
          .update(updateData)
          .eq('id', schoolId)
          .select(_schoolColumns)
          .single();

      final updatedModel = SchoolModel.fromJson(updatedData);

      // Persistent Audit Logging (Record only after DB update succeeds)
      try {
        await _auditLogService.recordAuditEvent(
          action: 'school_updated',
          entityType: 'school',
          entityId: schoolId,
          schoolId: schoolId,
          metadata: {
            'school_name': updatedModel.name,
            'school_code': updatedModel.code,
            if (address != null) 'address': address.trim(),
            if (phone != null) 'phone': phone.trim(),
            if (email != null) 'email': email.trim().toLowerCase(),
          },
        );
      } catch (auditErr) {
        debugPrint('[SchoolService] Audit event logging notice: $auditErr');
      }

      return ApiResult.success(updatedModel);
    } catch (e) {
      debugPrint('[SchoolService] updateSchool error: $e');
      return ApiResult.failure(_formatErrorMessage(e, 'Failed to update school'), e);
    }
  }

  /// Create a new school in public.schools and return the generated school entity with UUID
  Future<ApiResult<SchoolModel>> createSchool({
    required String name,
    required String schoolCode,
    String? address,
    String? phone,
    String? email,
    String? logoUrl,
    SchoolStatus status = SchoolStatus.active,
  }) async {
    final client = _client;
    if (client == null) {
      return ApiResult.failure('Database service is uninitialized.');
    }

    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      return ApiResult.failure('School name is required.');
    }

    final normalizedCode = SchoolProvisionDto.normalizeCode(schoolCode);
    if (normalizedCode.isEmpty) {
      return ApiResult.failure('School code is required.');
    }

    try {
      final existingCode = await client
          .from('schools')
          .select('id')
          .eq('code', normalizedCode)
          .maybeSingle();

      if (existingCode != null) {
        return ApiResult.failure('School code "$normalizedCode" is already in use.');
      }

      final payload = <String, dynamic>{
        'name': trimmedName,
        'code': normalizedCode,
        if (address != null && address.trim().isNotEmpty) 'address': address.trim(),
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        if (email != null && email.trim().isNotEmpty) 'email': email.trim().toLowerCase(),
        if (logoUrl != null && logoUrl.trim().isNotEmpty) 'logo_url': logoUrl.trim(),
        'status': status.dbValue,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      final insertedSchool = await client
          .from('schools')
          .insert(payload)
          .select(_schoolColumns)
          .single();

      final createdModel = SchoolModel.fromJson(insertedSchool);

      // Persistent Audit Logging (Record only after DB insert succeeds)
      try {
        await _auditLogService.recordAuditEvent(
          action: 'school_created',
          entityType: 'school',
          entityId: createdModel.id,
          schoolId: createdModel.id,
          metadata: {
            'school_name': createdModel.name,
            'school_code': createdModel.code,
            'status': status.dbValue,
          },
        );
      } catch (auditErr) {
        debugPrint('[SchoolService] Audit event logging notice: $auditErr');
      }

      return ApiResult.success(createdModel);
    } catch (e) {
      debugPrint('[SchoolService] createSchool error: $e');
      return ApiResult.failure(_formatErrorMessage(e, 'Failed to create school'), e);
    }
  }

  /// Provision a brand new school and primary admin
  Future<ApiResult<SchoolModel>> provisionSchool(SchoolProvisionDto dto) async {
    final client = _client;
    if (client == null) {
      return ApiResult.failure('Database service is uninitialized.');
    }

    // Validate DTO
    final validationErrors = dto.validate();
    if (validationErrors.isNotEmpty) {
      return ApiResult.failure(validationErrors.values.first);
    }

    try {
      // 1. Check if school code already exists
      final normalizedCode = SchoolProvisionDto.normalizeCode(dto.schoolCode);
      final existingCode = await client
          .from('schools')
          .select('id')
          .eq('code', normalizedCode)
          .maybeSingle();

      if (existingCode != null) {
        return ApiResult.failure('School code "$normalizedCode" is already in use.');
      }

      // 2. Insert School Entity strictly using verified columns
      final schoolPayload = dto.toSchoolPayload();
      final insertedSchool = await client
          .from('schools')
          .insert(schoolPayload)
          .select(_schoolColumns)
          .single();

      final newSchool = SchoolModel.fromJson(insertedSchool);

      // 3. Insert Initial Admin profile in public.profiles using verified columns
      try {
        await client.from('profiles').insert({
          'school_id': newSchool.id,
          'full_name': dto.initialAdminName.trim(),
          'email': dto.initialAdminEmail.trim().toLowerCase(),
          'phone': dto.initialAdminPhone.trim(),
          'role': 'school_admin',
          'status': 'active',
          'designation': 'Primary Administrator',
        });
      } catch (profileErr) {
        debugPrint('[SchoolService] Initial admin profile creation notice: $profileErr');
      }

      return ApiResult.success(newSchool);
    } catch (e) {
      debugPrint('[SchoolService] provisionSchool error: $e');
      return ApiResult.failure(_formatErrorMessage(e, 'Failed to provision school'), e);
    }
  }

  String _formatErrorMessage(dynamic error, String defaultMsg) {
    final str = error.toString();
    if (str.contains('42501') || str.contains('row-level security')) {
      return 'Permission Denied (RLS): Active database user lacks Super Admin permissions. Please ensure supabase_super_admin_setup.sql policies are applied.';
    }
    return '$defaultMsg: $error';
  }
}
