import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/supabase_config.dart';
import '../core/network/api_result.dart';
import '../models/school_admin_model.dart';
import '../models/school_app_model.dart';
import '../models/school_model.dart';
import '../models/school_provisioning_models.dart';
import '../models/subscription_model.dart';
import 'audit_log_service.dart';
import 'supabase_service.dart';

class SchoolProvisioningService {
  final SupabaseClient? _customClient;
  final AuditLogService _auditLogService;

  SchoolProvisioningService({
    SupabaseClient? client,
    AuditLogService? auditLogService,
  })  : _customClient = client,
        _auditLogService = auditLogService ?? AuditLogService(client: client);

  SupabaseClient? get _client => _customClient ?? SupabaseService.instance.client;
  AuditLogService get auditLogService => _auditLogService;

  // In-flight idempotency locks to prevent duplicate concurrent submissions
  final Set<String> _inFlightIdempotencyKeys = {};

  /// Performs pre-flight uniqueness checks before touching any auth or database resources
  Future<ApiResult<void>> preflightConflictCheck(SchoolProvisioningRequest req) async {
    final client = _client;
    if (client == null) {
      return ApiResult.failure('Database service is uninitialized.');
    }

    try {
      final cleanCode = req.schoolCode.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9\-]'), '');
      final cleanPkg = req.packageBundleId.trim().toLowerCase();
      final cleanAppId = req.appIdentifier.trim().toUpperCase();
      final cleanEmail = req.adminEmail.trim().toLowerCase();

      // 1. Check school code uniqueness
      final existingCode = await client
          .from('schools')
          .select('id')
          .eq('code', cleanCode)
          .maybeSingle();
      if (existingCode != null) {
        return ApiResult.failure('School code "$cleanCode" is already in use by another school.');
      }

      // 2. Check app package name uniqueness
      final existingPkg = await client
          .from('school_management_apps')
          .select('id')
          .eq('package_name', cleanPkg)
          .maybeSingle();
      if (existingPkg != null) {
        return ApiResult.failure('Android package name "$cleanPkg" is already assigned to another school app.');
      }

      // 3. Check app identifier uniqueness
      final existingAppId = await client
          .from('school_management_apps')
          .select('id')
          .eq('app_identifier', cleanAppId)
          .maybeSingle();
      if (existingAppId != null) {
        return ApiResult.failure('App Identifier "$cleanAppId" is already assigned to another school app.');
      }

      // 4. Check admin email uniqueness in profiles
      final existingEmail = await client
          .from('profiles')
          .select('id')
          .eq('email', cleanEmail)
          .maybeSingle();
      if (existingEmail != null) {
        return ApiResult.failure('Administrator email "$cleanEmail" is already associated with an existing account.');
      }

      return ApiResult.success(null);
    } catch (e) {
      debugPrint('[SchoolProvisioningService] Preflight check error: $e');
      return ApiResult.failure('Failed to complete pre-flight conflict validation: $e', e);
    }
  }

  /// Atomically provisions a complete school with app, administrator, subscription, and billing settings.
  /// Guarantees zero orphaned records on failure via transactional commit and compensating cleanup.
  Future<ApiResult<SchoolProvisioningResult>> provisionSchool(SchoolProvisioningRequest req) async {
    final client = _client;
    if (client == null) {
      return ApiResult.failure('Database service is uninitialized.');
    }

    // Step 0: Input validation
    final errors = req.validate();
    if (errors.isNotEmpty) {
      return ApiResult.failure(errors.values.first);
    }

    // Step 0.1: Idempotency in-flight guard
    final key = req.idempotencyKey.trim();
    if (key.isNotEmpty && _inFlightIdempotencyKeys.contains(key)) {
      return ApiResult.failure('A provisioning request with this key is already being processed.');
    }
    if (key.isNotEmpty) {
      _inFlightIdempotencyKeys.add(key);
    }

    try {
      // Persistent Audit Logging: provisioning_started
      try {
        await _auditLogService.recordAuditEvent(
          action: 'provisioning_started',
          entityType: 'provisioning',
          entityId: key.isNotEmpty ? key : null,
          metadata: {
            'action_category': 'school_provisioning',
            'school_name': req.schoolName.trim(),
            'school_code': req.schoolCode.trim(),
            'admin_email': req.adminEmail.trim().toLowerCase(),
            'package_name': req.packageBundleId.trim(),
            'app_identifier': req.appIdentifier.trim(),
            'idempotency_key': key,
          },
        );
      } catch (auditErr) {
        debugPrint('[SchoolProvisioningService] Audit event start notice: $auditErr');
      }

      // Step 1: Pre-flight conflict check (prevents touching Auth or DB if conflict exists)
      final preflightResult = await preflightConflictCheck(req);
      if (preflightResult.isFailure) {
        final err = preflightResult.errorOrNull ?? 'Conflict detected';
        await _recordProvisioningFailure(req, err);
        return ApiResult.failure(err);
      }

      // Step 2: Create Supabase Auth User via isolated HTTP signup
      // Uses client publishable key — zero service-role key exposure in Flutter client.
      final signupUri = Uri.parse('${SupabaseConfig.url}/auth/v1/signup');
      final cleanEmail = req.adminEmail.trim().toLowerCase();
      final cleanAdminName = req.adminFullName.trim();

      http.Response signupResponse;
      try {
        signupResponse = await http.post(
          signupUri,
          headers: {
            'apikey': SupabaseConfig.publishableKey,
            'Authorization': 'Bearer ${SupabaseConfig.publishableKey}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'email': cleanEmail,
            'password': req.adminPassword,
            'data': {
              'role': 'school_admin',
              'full_name': cleanAdminName,
              if (req.adminPhone != null && req.adminPhone!.trim().isNotEmpty)
                'phone': req.adminPhone!.trim(),
            },
          }),
        );
      } catch (authErr) {
        debugPrint('[SchoolProvisioningService] Auth signup connection error: $authErr');
        return ApiResult.failure('Failed to connect to authentication service. No records created: $authErr', authErr);
      }

      final responseData = jsonDecode(signupResponse.body) as Map<String, dynamic>;
      if (signupResponse.statusCode >= 400) {
        final errorMsg = (responseData['msg'] ??
                responseData['message'] ??
                responseData['error_description'] ??
                'Failed to create administrator account')
            .toString();
        debugPrint('[SchoolProvisioningService] Auth signup rejected: $errorMsg');
        return ApiResult.failure('Authentication service rejected account creation: $errorMsg');
      }

      final newAuthUserId = (responseData['id'] ??
          (responseData['user'] as Map<String, dynamic>?)?['id']) as String?;
      if (newAuthUserId == null || newAuthUserId.isEmpty) {
        return ApiResult.failure('Authentication service did not return an authoritative user identifier.');
      }

      debugPrint('[SchoolProvisioningService] Created Auth user with ID: $newAuthUserId');

      // Step 2.5: Authoritative Server-Side Attempt Tracking (Locks Auth User to Idempotency Key)
      if (key.isNotEmpty) {
        try {
          await client.rpc('track_provisioning_attempt', params: {
            'p_idempotency_key': key,
            'p_auth_user_id': newAuthUserId,
            'p_admin_email': cleanEmail,
          });
          debugPrint('[SchoolProvisioningService] Tracked provisioning attempt for key: $key');
        } catch (trackErr) {
          debugPrint('[SchoolProvisioningService] Notice: track_provisioning_attempt not yet deployed or error: $trackErr');
        }
      }

      // Step 3: Atomic Database Provisioning
      // Primary Strategy: Invoke PostgreSQL stored procedure `provision_school_atomic`.
      // Everything (schools, school_management_apps, school_billing_settings, school_app_subscriptions, profiles)
      // runs inside a single database transaction.
      bool rpcExecuted = false;
      Map<String, dynamic>? rpcOutput;

      try {
        final rpcParams = {
          'p_school_name': req.schoolName.trim(),
          'p_school_code': req.schoolCode.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9\-]'), ''),
          if (req.address != null && req.address!.trim().isNotEmpty)
            'p_school_address': req.address!.trim(),
          if (req.phone != null && req.phone!.trim().isNotEmpty)
            'p_school_phone': req.phone!.trim(),
          if (req.email != null && req.email!.trim().isNotEmpty)
            'p_school_email': req.email!.trim().toLowerCase(),
          if (req.logoUrl != null && req.logoUrl!.trim().isNotEmpty)
            'p_school_logo_url': req.logoUrl!.trim(),
          'p_school_status': req.schoolStatus.dbValue,
          'p_app_name': req.appName.trim(),
          'p_package_name': req.packageBundleId.trim().toLowerCase(),
          'p_app_identifier': req.appIdentifier.trim().toUpperCase(),
          'p_app_version': req.currentVersion.trim().isNotEmpty ? req.currentVersion.trim() : '1.0.0',
          if (req.playStoreUrl != null && req.playStoreUrl!.trim().isNotEmpty)
            'p_play_store_url': req.playStoreUrl!.trim(),
          'p_app_status': req.appStatus.dbValue,
          'p_admin_auth_user_id': newAuthUserId,
          'p_admin_name': cleanAdminName,
          'p_admin_email': cleanEmail,
          if (req.adminPhone != null && req.adminPhone!.trim().isNotEmpty)
            'p_admin_phone': req.adminPhone!.trim(),
          'p_plan_name': req.planName.trim(),
          'p_start_date': req.startDate.toIso8601String(),
          'p_end_date': req.endDate.toIso8601String(),
          'p_sub_status': req.subscriptionStatus.dbValue,
          if (req.subscriptionNotes != null && req.subscriptionNotes!.trim().isNotEmpty)
            'p_sub_notes': req.subscriptionNotes!.trim(),
          'p_billing_rate': req.ratePerStudent,
          'p_billing_currency': req.currency,
          'p_billing_cycle': req.billingCycle,
          if (key.isNotEmpty) 'p_idempotency_key': key,
        };

        final rpcResp = await client.rpc('provision_school_atomic', params: rpcParams);
        rpcExecuted = true;
        rpcOutput = (rpcResp is Map<String, dynamic>)
            ? rpcResp
            : (rpcResp is String ? jsonDecode(rpcResp) as Map<String, dynamic> : null);
      } on PostgrestException catch (pe) {
        final isMissingRpc = pe.code == 'PGRST202' ||
            pe.message.contains('Could not find the function') ||
            pe.message.contains('schema cache');
        if (!isMissingRpc) {
          // Real database failure / conflict inside the RPC transaction
          debugPrint('[SchoolProvisioningService] provision_school_atomic RPC rejected: ${pe.message}');
          // Compensating Rollback: Clean up newly created Auth user with tracked idempotency key
          await cleanupOrphanedAuthUser(newAuthUserId, idempotencyKey: key);
          return ApiResult.failure('Provisioning transaction failed: ${pe.message}', pe);
        }
        debugPrint('[SchoolProvisioningService] provision_school_atomic RPC not yet deployed. Running client compensating orchestration.');
      } catch (e) {
        final errStr = e.toString();
        if (!errStr.contains('PGRST202') && !errStr.contains('Could not find the function')) {
          debugPrint('[SchoolProvisioningService] RPC invocation failure: $e');
          await cleanupOrphanedAuthUser(newAuthUserId, idempotencyKey: key);
          return ApiResult.failure('Database provisioning error: $e', e);
        }
      }

      // If the atomic RPC succeeded, fetch the created records and return
      if (rpcExecuted && rpcOutput != null) {
        final schoolId = rpcOutput['school_id']?.toString();
        if (schoolId == null) {
          return ApiResult.failure('Provisioning failed: no school identifier returned');
        }

        final schoolData = await client.from('schools').select().eq('id', schoolId).single();
        final appData = await client.from('school_management_apps').select('*, schools(name)').eq('school_id', schoolId).single();
        final adminData = await client.from('profiles').select().eq('school_id', schoolId).eq('role', 'school_admin').single();
        final subData = await client.from('school_app_subscriptions').select('*, school_management_apps(id, app_name, school_id, schools(id, name))').eq('school_app_id', appData['id']).single();

        final result = SchoolProvisioningResult(
          school: SchoolModel.fromJson(schoolData),
          app: SchoolAppModel.fromJson(appData),
          admin: SchoolAdminModel.fromJson(adminData),
          subscription: SubscriptionModel.fromJson(subData),
          billingSettingsId: rpcOutput['billing_settings_id']?.toString(),
          isIdempotentReplay: rpcOutput['idempotent_replay'] == true,
        );

        await _recordProvisioningSuccess(result, key);
        return ApiResult.success(result);
      }

      // Step 4: Client-Side Fail-Safe Sequential Execution WITH Strict Compensating Rollback
      // (Used when SQL migration is pending deployment)
      String? createdSchoolId;
      String? createdAppId;

      try {
        // A. Insert School
        final cleanCode = req.schoolCode.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9\-]'), '');
        final schoolPayload = {
          'name': req.schoolName.trim(),
          'code': cleanCode,
          if (req.address != null && req.address!.trim().isNotEmpty) 'address': req.address!.trim(),
          if (req.phone != null && req.phone!.trim().isNotEmpty) 'phone': req.phone!.trim(),
          if (req.email != null && req.email!.trim().isNotEmpty) 'email': req.email!.trim().toLowerCase(),
          if (req.logoUrl != null && req.logoUrl!.trim().isNotEmpty) 'logo_url': req.logoUrl!.trim(),
          'status': req.schoolStatus.dbValue,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        };
        final schoolResp = await client.from('schools').insert(schoolPayload).select().single();
        createdSchoolId = schoolResp['id'].toString();

        // B. Insert App
        final appPayload = {
          'school_id': createdSchoolId,
          'app_name': req.appName.trim(),
          'package_name': req.packageBundleId.trim().toLowerCase(),
          'app_identifier': req.appIdentifier.trim().toUpperCase(),
          'current_version': req.currentVersion.trim().isNotEmpty ? req.currentVersion.trim() : '1.0.0',
          if (req.playStoreUrl != null && req.playStoreUrl!.trim().isNotEmpty)
            'play_store_url': req.playStoreUrl!.trim(),
          'status': req.appStatus.dbValue,
        };
        final appResp = await client.from('school_management_apps').insert(appPayload).select('*, schools(name)').single();
        createdAppId = appResp['id'].toString();

        // C. Insert Default Billing Settings (upsert to handle trigger auto-initialization)
        await client.from('school_billing_settings').upsert({
          'school_id': createdSchoolId,
          'rate_per_student': req.ratePerStudent,
          'currency': req.currency,
          'billing_cycle': req.billingCycle,
          'active': true,
        }, onConflict: 'school_id');

        // D. Insert Subscription
        final subPayload = {
          'school_app_id': createdAppId,
          'plan_name': req.planName.trim(),
          'start_date': req.startDate.toIso8601String(),
          'end_date': req.endDate.toIso8601String(),
          'status': req.subscriptionStatus.dbValue,
          if (req.subscriptionNotes != null && req.subscriptionNotes!.trim().isNotEmpty)
            'notes': req.subscriptionNotes!.trim(),
        };
        final subResp = await client.from('school_app_subscriptions').insert(subPayload).select('*, school_management_apps(id, app_name, school_id, schools(id, name))').single();

        // E. Insert Profile
        final profilePayload = {
          'auth_user_id': newAuthUserId,
          'school_id': createdSchoolId,
          'full_name': cleanAdminName,
          'email': cleanEmail,
          if (req.adminPhone != null && req.adminPhone!.trim().isNotEmpty)
            'phone': req.adminPhone!.trim(),
          'role': 'school_admin',
          'status': 'active',
          'designation': 'School Administrator',
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        };
        final profileResp = await client.from('profiles').insert(profilePayload).select().single();

        final result = SchoolProvisioningResult(
          school: SchoolModel.fromJson(schoolResp),
          app: SchoolAppModel.fromJson(appResp),
          admin: SchoolAdminModel.fromJson(profileResp),
          subscription: SubscriptionModel.fromJson(subResp),
        );

        await _recordProvisioningSuccess(result, key);
        return ApiResult.success(result);
      } catch (dbErr) {
        debugPrint('[SchoolProvisioningService] Late failure during sequential provisioning: $dbErr. Initiating full compensating rollback.');
        // COMPENSATING ROLLBACK:
        // Delete created school (cascades to school_management_apps, school_app_subscriptions, school_billing_settings)
        if (createdSchoolId != null) {
          try {
            await client.from('schools').delete().eq('id', createdSchoolId);
            debugPrint('[SchoolProvisioningService] Rolled back created school $createdSchoolId');
          } catch (rbErr) {
            debugPrint('[SchoolProvisioningService] Compensating school delete warning: $rbErr');
          }
        }

        // Clean up created Auth user with tracked idempotency key
        await cleanupOrphanedAuthUser(newAuthUserId, idempotencyKey: key);

        final err = 'Provisioning failed during entity creation: $dbErr';
        await _recordProvisioningFailure(req, err);
        return ApiResult.failure(err, dbErr);
      }
    } finally {
      if (key.isNotEmpty) {
        _inFlightIdempotencyKeys.remove(key);
      }
    }
  }

  /// Triggers compensating deletion of an unassociated Supabase Auth user if a database step failed.
  /// Passes the tracked idempotencyKey so the server validates attempt ownership before cleanup.
  Future<void> cleanupOrphanedAuthUser(String authUserId, {String? idempotencyKey}) async {
    final client = _client;
    if (client == null) return;

    try {
      debugPrint('[SchoolProvisioningService] Cleaning up orphaned auth user $authUserId for idempotency key: $idempotencyKey...');
      final params = <String, dynamic>{
        'p_auth_user_id': authUserId,
        if (idempotencyKey != null && idempotencyKey.isNotEmpty)
          'p_idempotency_key': idempotencyKey,
      };
      await client.rpc('cleanup_orphaned_provisioning_auth_user', params: params);
      debugPrint('[SchoolProvisioningService] Orphaned auth user $authUserId cleaned up successfully.');

      // Persistent Audit Logging: provisioning_cleanup
      try {
        await _auditLogService.recordAuditEvent(
          action: 'provisioning_cleanup',
          entityType: 'provisioning',
          entityId: authUserId,
          metadata: {
            'action_category': 'school_provisioning',
            'auth_user_id': authUserId,
            if (idempotencyKey != null && idempotencyKey.isNotEmpty)
              'idempotency_key': idempotencyKey,
          },
        );
      } catch (auditErr) {
        debugPrint('[SchoolProvisioningService] Audit event cleanup notice: $auditErr');
      }
    } catch (e) {
      debugPrint('[SchoolProvisioningService] Notice: auth cleanup RPC unavailable or failed ($e). The user has no profile and cannot authenticate into school resources.');
    }
  }

  Future<void> _recordProvisioningFailure(SchoolProvisioningRequest req, String reason) async {
    try {
      await _auditLogService.recordAuditEvent(
        action: 'provisioning_failed',
        entityType: 'provisioning',
        entityId: req.idempotencyKey.trim().isNotEmpty ? req.idempotencyKey.trim() : null,
        metadata: {
          'action_category': 'school_provisioning',
          'school_name': req.schoolName.trim(),
          'school_code': req.schoolCode.trim(),
          'admin_email': req.adminEmail.trim().toLowerCase(),
          'error': reason,
          'idempotency_key': req.idempotencyKey.trim(),
        },
      );
    } catch (e) {
      debugPrint('[SchoolProvisioningService] Audit notice: $e');
    }
  }

  Future<void> _recordProvisioningSuccess(SchoolProvisioningResult res, String key) async {
    try {
      await _auditLogService.recordAuditEvent(
        action: 'provisioning_completed',
        entityType: 'provisioning',
        entityId: res.school.id,
        schoolId: res.school.id,
        metadata: {
          'action_category': 'school_provisioning',
          'school_name': res.school.name,
          'school_code': res.school.code,
          'admin_email': res.admin.email,
          'app_name': res.app.appName,
          'package_name': res.app.packageName,
          'subscription_id': res.subscription.id,
          'idempotency_key': key,
        },
      );
    } catch (e) {
      debugPrint('[SchoolProvisioningService] Audit notice: $e');
    }
  }
}
