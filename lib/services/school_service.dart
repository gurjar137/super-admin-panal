import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/network/api_result.dart';
import '../models/school_model.dart';
import '../models/school_provision_dto.dart';
import 'supabase_service.dart';

class SchoolService {
  SupabaseClient? get _client => SupabaseService.instance.client;

  static const String _schoolColumns =
      'id, name, code, address, phone, email, logo_url, status, created_at, updated_at';

  /// Fetch all schools with optional search query and status filter
  Future<ApiResult<List<SchoolModel>>> fetchSchools({
    String? searchQuery,
    SchoolStatus? statusFilter,
  }) async {
    final client = _client;
    if (client == null) {
      return ApiResult.failure('Database service is uninitialized.');
    }

    try {
      var query = client.from('schools').select(_schoolColumns);

      if (statusFilter != null) {
        query = query.eq('status', statusFilter.dbValue);
      }

      final response = await query.order('created_at', ascending: false);

      final List<dynamic> rawList = response as List<dynamic>;
      List<SchoolModel> schools = rawList
          .map((item) => SchoolModel.fromJson(item as Map<String, dynamic>))
          .toList();

      // Attach assigned apps count and subscription summary for each school safely
      final enrichedSchools = <SchoolModel>[];
      for (final school in schools) {
        int appCount = 0;
        String? subSummary;

        try {
          final appsRes = await client.from('school_apps').select('id, status').eq('school_id', school.id);
          final appList = appsRes as List<dynamic>;
          appCount = appList.length;
          final activeCount = appList.where((a) => (a['status']?.toString().toUpperCase() ?? '') == 'ACTIVE').length;
          if (appCount > 0) {
            subSummary = '$activeCount/$appCount Active';
          }
        } catch (_) {}

        enrichedSchools.add(school.copyWith(
          assignedAppsCount: appCount,
          activeSubscriptionSummary: subSummary,
        ));
      }

      // In-memory filter for search query across name and code
      var finalSchools = enrichedSchools;
      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final queryLower = searchQuery.trim().toLowerCase();
        finalSchools = finalSchools.where((s) {
          return s.name.toLowerCase().contains(queryLower) ||
              s.schoolCode.toLowerCase().contains(queryLower) ||
              (s.email?.toLowerCase().contains(queryLower) ?? false);
        }).toList();
      }

      return ApiResult.success(finalSchools);
    } catch (e) {
      debugPrint('[SchoolService] fetchSchools error: $e');
      return ApiResult.failure(_formatErrorMessage(e, 'Failed to load schools'), e);
    }
  }

  /// Fetch single school details, including primary administrator summary
  Future<ApiResult<SchoolModel>> fetchSchoolDetails(String schoolId) async {
    final client = _client;
    if (client == null) {
      return ApiResult.failure('Database service is uninitialized.');
    }

    try {
      final schoolData = await client
          .from('schools')
          .select(_schoolColumns)
          .eq('id', schoolId)
          .single();

      var model = SchoolModel.fromJson(schoolData);

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

      // Attempt to fetch assigned apps count and subscription summary
      try {
        final appsRes = await client.from('school_apps').select('id, status').eq('school_id', schoolId);
        final appList = appsRes as List<dynamic>;
        final activeCount = appList.where((a) => (a['status']?.toString().toUpperCase() ?? '') == 'ACTIVE').length;
        model = model.copyWith(
          assignedAppsCount: appList.length,
          activeSubscriptionSummary: appList.isNotEmpty ? '$activeCount/${appList.length} Active Apps' : 'No Apps Assigned',
        );
      } catch (_) {}

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

      return ApiResult.success(SchoolModel.fromJson(insertedSchool));
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
