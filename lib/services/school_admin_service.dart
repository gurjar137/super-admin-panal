import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/supabase_config.dart';
import '../core/network/api_result.dart';
import '../models/school_admin_model.dart';
import 'audit_log_service.dart';
import 'supabase_service.dart';

class SchoolAdminService {
  final SupabaseClient? _customClient;
  final AuditLogService _auditLogService;

  SchoolAdminService({
    SupabaseClient? client,
    AuditLogService? auditLogService,
  })  : _customClient = client,
        _auditLogService = auditLogService ?? AuditLogService(client: client);

  SupabaseClient? get _client => _customClient ?? SupabaseService.instance.client;
  AuditLogService get auditLogService => _auditLogService;

  static const String _profileColumns =
      'id, auth_user_id, school_id, full_name, email, phone, role, status, designation, created_at, updated_at';

  /// Fetch the School Administrator for a given school
  Future<ApiResult<SchoolAdminModel?>> fetchSchoolAdmin(String schoolId) async {
    final client = _client;
    if (client == null) {
      return ApiResult.failure('Database service is uninitialized.');
    }

    try {
      final response = await client
          .from('profiles')
          .select(_profileColumns)
          .eq('school_id', schoolId)
          .eq('role', 'school_admin')
          .order('created_at', ascending: true)
          .maybeSingle();

      if (response == null) {
        return ApiResult.success(null);
      }

      return ApiResult.success(SchoolAdminModel.fromJson(response));
    } catch (e) {
      debugPrint('[SchoolAdminService] fetchSchoolAdmin error: $e');
      return ApiResult.failure('Failed to load school administrator: $e', e);
    }
  }

  /// Create a new School Administrator:
  /// 1. Validates inputs & prevents duplicates
  /// 2. Creates real Supabase Auth user via isolated HTTP signup
  /// 3. Creates authoritative record in public.profiles with role 'school_admin'
  Future<ApiResult<SchoolAdminModel>> createSchoolAdmin({
    required String schoolId,
    required String fullName,
    required String email,
    String? phone,
    required String password,
  }) async {
    final client = _client;
    if (client == null) {
      return ApiResult.failure('Database service is uninitialized.');
    }

    final trimmedName = fullName.trim();
    final trimmedEmail = email.trim().toLowerCase();
    final trimmedPhone = phone?.trim();

    // 1. Validation
    if (trimmedName.isEmpty) {
      return ApiResult.failure('Full name is required.');
    }
    if (trimmedEmail.isEmpty || !trimmedEmail.contains('@') || !trimmedEmail.contains('.')) {
      return ApiResult.failure('Please enter a valid email address.');
    }
    if (password.length < 6) {
      return ApiResult.failure('Password must be at least 6 characters.');
    }
    if (schoolId.trim().isEmpty) {
      return ApiResult.failure('School ID is missing.');
    }

    try {
      // 2. Duplicate Protection: Check if this school already has an active School Admin
      final existingAdmin = await client
          .from('profiles')
          .select('id, email, full_name, status')
          .eq('school_id', schoolId)
          .eq('role', 'school_admin')
          .eq('status', 'active')
          .maybeSingle();

      if (existingAdmin != null) {
        return ApiResult.failure('School Admin is already configured for this school.');
      }

      // 3. Duplicate Protection: Check if email is already registered in profiles
      final existingEmail = await client
          .from('profiles')
          .select('id, email')
          .eq('email', trimmedEmail)
          .maybeSingle();

      if (existingEmail != null) {
        return ApiResult.failure('This email address is already associated with an existing account.');
      }

      // 4. Secure Auth user creation via isolated HTTP POST to /auth/v1/signup
      // Prevents service-role exposure in client and prevents session hijacking
      final signupUri = Uri.parse('${SupabaseConfig.url}/auth/v1/signup');
      debugPrint('[SchoolAdminService] Creating Auth user via isolated HTTP for $trimmedEmail');

      final signupResponse = await http.post(
        signupUri,
        headers: {
          'apikey': SupabaseConfig.publishableKey,
          'Authorization': 'Bearer ${SupabaseConfig.publishableKey}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email': trimmedEmail,
          'password': password,
          'data': {
            'role': 'school_admin',
            'full_name': trimmedName,
            'school_id': schoolId,
            'must_change_password': true,
            if (trimmedPhone != null && trimmedPhone.isNotEmpty) 'phone': trimmedPhone,
          },
        }),
      );

      debugPrint('[SchoolAdminService] HTTP signup status: ${signupResponse.statusCode}');
      final responseData = jsonDecode(signupResponse.body) as Map<String, dynamic>;

      if (signupResponse.statusCode >= 400) {
        final errorMsg = (responseData['msg'] ??
                responseData['message'] ??
                responseData['error_description'] ??
                'Failed to create user account')
            .toString();
        final lower = errorMsg.toLowerCase();
        if (lower.contains('already registered') || lower.contains('already in use')) {
          return ApiResult.failure('This email is already registered. Please use another email.');
        } else if (lower.contains('weak')) {
          return ApiResult.failure('Password is too weak. Please choose a stronger password.');
        } else {
          return ApiResult.failure(errorMsg);
        }
      }

      final identities = (responseData['identities'] ??
          (responseData['user'] as Map<String, dynamic>?)?['identities']) as List?;
      if (identities != null && identities.isEmpty) {
        return ApiResult.failure('This email is already registered. Please use another email.');
      }

      final newAuthUserId = (responseData['id'] ??
          (responseData['user'] as Map<String, dynamic>?)?['id']) as String?;
      if (newAuthUserId == null || newAuthUserId.isEmpty) {
        return ApiResult.failure('Failed to obtain user ID from authentication service.');
      }

      debugPrint('[SchoolAdminService] Auth user successfully created with ID: $newAuthUserId');

      // 5. Authoritative Profile Creation in public.profiles
      final profilePayload = <String, dynamic>{
        'auth_user_id': newAuthUserId,
        'school_id': schoolId,
        'full_name': trimmedName,
        'email': trimmedEmail,
        if (trimmedPhone != null && trimmedPhone.isNotEmpty) 'phone': trimmedPhone,
        'role': 'school_admin', // Strictly hardcoded: cannot escalate to owner/super_admin
        'status': 'active',
        'designation': 'School Administrator',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      final inserted = await client
          .from('profiles')
          .insert(profilePayload)
          .select(_profileColumns)
          .single();

      final adminModel = SchoolAdminModel.fromJson(inserted);
      debugPrint('[SchoolAdminService] School Admin profile successfully created: ${adminModel.id}');

      // Persistent Audit Logging: admin_created
      try {
        await _auditLogService.recordAuditEvent(
          action: 'admin_created',
          entityType: 'admin',
          entityId: adminModel.id,
          schoolId: schoolId,
          metadata: {
            'action_category': 'school_admin',
            'admin_name': adminModel.fullName,
            'email': adminModel.email,
            'role': adminModel.role,
          },
        );
      } catch (auditErr) {
        debugPrint('[SchoolAdminService] Audit admin_created notice: $auditErr');
      }

      return ApiResult.success(adminModel);
    } catch (e) {
      debugPrint('[SchoolAdminService] createSchoolAdmin error: $e');
      return ApiResult.failure('Failed to create school administrator: $e', e);
    }
  }

  /// Update School Administrator metadata (full_name, phone)
  Future<ApiResult<SchoolAdminModel>> updateSchoolAdminProfile({
    required String profileId,
    required String fullName,
    String? phone,
  }) async {
    final client = _client;
    if (client == null) {
      return ApiResult.failure('Database service is uninitialized.');
    }

    final trimmedName = fullName.trim();
    if (trimmedName.isEmpty) {
      return ApiResult.failure('Full name cannot be empty.');
    }

    try {
      final updateData = <String, dynamic>{
        'full_name': trimmedName,
        'phone': phone?.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      final updated = await client
          .from('profiles')
          .update(updateData)
          .eq('id', profileId)
          .select(_profileColumns)
          .single();

      final updatedModel = SchoolAdminModel.fromJson(updated);

      // Persistent Audit Logging: admin_updated
      try {
        await _auditLogService.recordAuditEvent(
          action: 'admin_updated',
          entityType: 'admin',
          entityId: profileId,
          schoolId: updatedModel.schoolId,
          metadata: {
            'action_category': 'school_admin',
            'admin_name': updatedModel.fullName,
            'email': updatedModel.email,
          },
        );
      } catch (auditErr) {
        debugPrint('[SchoolAdminService] Audit admin_updated notice: $auditErr');
      }

      return ApiResult.success(updatedModel);
    } catch (e) {
      debugPrint('[SchoolAdminService] updateSchoolAdminProfile error: $e');
      return ApiResult.failure('Failed to update administrator profile: $e', e);
    }
  }

  /// Update School Administrator status ('active' <-> 'inactive')
  Future<ApiResult<SchoolAdminModel>> updateSchoolAdminStatus({
    required String profileId,
    required String newStatus,
  }) async {
    final client = _client;
    if (client == null) {
      return ApiResult.failure('Database service is uninitialized.');
    }

    final normalizedStatus = newStatus.trim().toLowerCase();
    if (normalizedStatus != 'active' && normalizedStatus != 'inactive') {
      return ApiResult.failure('Status must be ACTIVE or INACTIVE.');
    }

    try {
      final updateData = <String, dynamic>{
        'status': normalizedStatus,
        'updated_at': DateTime.now().toIso8601String(),
      };

      final updated = await client
          .from('profiles')
          .update(updateData)
          .eq('id', profileId)
          .select(_profileColumns)
          .single();

      final updatedModel = SchoolAdminModel.fromJson(updated);

      // Persistent Audit Logging: admin_deactivated or admin_reactivated
      try {
        final action = normalizedStatus == 'active' ? 'admin_reactivated' : 'admin_deactivated';
        await _auditLogService.recordAuditEvent(
          action: action,
          entityType: 'admin',
          entityId: profileId,
          schoolId: updatedModel.schoolId,
          metadata: {
            'action_category': 'school_admin',
            'admin_name': updatedModel.fullName,
            'email': updatedModel.email,
            'new_status': normalizedStatus,
          },
        );
      } catch (auditErr) {
        debugPrint('[SchoolAdminService] Audit admin status notice: $auditErr');
      }

      return ApiResult.success(updatedModel);
    } catch (e) {
      debugPrint('[SchoolAdminService] updateSchoolAdminStatus error: $e');
      return ApiResult.failure('Failed to update administrator status: $e', e);
    }
  }
}
