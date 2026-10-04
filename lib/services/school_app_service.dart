import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/network/api_result.dart';
import '../models/school_app_model.dart';
import 'supabase_service.dart';

class SchoolAppService {
  SupabaseClient? get _client => SupabaseService.instance.client;

  static const String _appColumns =
      'id, school_id, app_name, package_name, app_identifier, current_version, play_store_url, status, notes, created_at, updated_at, schools(name)';

  /// Fetch single dedicated app configured for a specific school (1 school -> 1 app)
  Future<ApiResult<SchoolAppModel?>> fetchAppBySchoolId(String schoolId) async {
    final client = _client;
    if (client == null) {
      return ApiResult.failure('Database service is uninitialized.');
    }

    try {
      final response = await client
          .from('school_management_apps')
          .select(_appColumns)
          .eq('school_id', schoolId)
          .maybeSingle();

      if (response == null) {
        return ApiResult.success(null);
      }

      return ApiResult.success(SchoolAppModel.fromJson(response));
    } catch (e) {
      debugPrint('[SchoolAppService] fetchAppBySchoolId error: $e');
      return ApiResult.failure(_formatErrorMessage(e), e);
    }
  }

  /// Fetch all school management apps or filtered by schoolId
  Future<ApiResult<List<SchoolAppModel>>> fetchSchoolApps({String? schoolId}) async {
    final client = _client;
    if (client == null) {
      return ApiResult.success([]);
    }

    try {
      var query = client.from('school_management_apps').select(_appColumns);

      if (schoolId != null) {
        query = query.eq('school_id', schoolId);
      }

      final response = await query.order('created_at', ascending: false);
      final List<dynamic> rawList = response as List<dynamic>;

      final list = rawList
          .map((item) => SchoolAppModel.fromJson(item as Map<String, dynamic>))
          .toList();

      return ApiResult.success(list);
    } catch (e) {
      debugPrint('[SchoolAppService] fetchSchoolApps notice: $e');
      return ApiResult.success([]);
    }
  }

  /// Fetch single dedicated school app by its app UUID
  Future<ApiResult<SchoolAppModel>> fetchAppDetails(String appId) async {
    final client = _client;
    if (client == null) {
      return ApiResult.failure('Database service is uninitialized.');
    }

    try {
      final response = await client
          .from('school_management_apps')
          .select(_appColumns)
          .eq('id', appId)
          .single();

      return ApiResult.success(SchoolAppModel.fromJson(response));
    } catch (e) {
      debugPrint('[SchoolAppService] fetchAppDetails error: $e');
      return ApiResult.failure(_formatErrorMessage(e), e);
    }
  }

  /// Create dedicated School Management App record for a school
  /// Guaranteed 1:1 relationship enforced by database UNIQUE(school_id)
  Future<ApiResult<SchoolAppModel>> createSchoolApp({
    required String schoolId,
    required String appName,
    String? packageName,
    String? appIdentifier,
    String? currentVersion,
    String? playStoreUrl,
    SchoolAppStatus status = SchoolAppStatus.active,
    String? notes,
  }) async {
    final client = _client;
    if (client == null) {
      return ApiResult.failure('Database service is uninitialized.');
    }

    final trimmedAppName = appName.trim();
    if (trimmedAppName.isEmpty) {
      return ApiResult.failure('App name is required.');
    }

    final trimmedIdentifier = (appIdentifier ?? '').trim().toUpperCase();
    if (trimmedIdentifier.isEmpty) {
      return ApiResult.failure('App identifier is required.');
    }

    final trimmedPackage = (packageName ?? '').trim().toLowerCase();
    if (trimmedPackage.isEmpty) {
      return ApiResult.failure('Android package name is required.');
    }
    if (!isValidPackageName(trimmedPackage)) {
      return ApiResult.failure('Invalid Android package name. Use reverse-domain format (e.g. com.company.schoolapp).');
    }

    final trimmedVersion = (currentVersion ?? '').trim().isNotEmpty ? currentVersion!.trim() : '1.0.0';
    if (!isValidVersion(trimmedVersion)) {
      return ApiResult.failure('Invalid version format. Use semantic versioning (e.g. 1.0.0).');
    }

    if (playStoreUrl != null && playStoreUrl.trim().isNotEmpty && !isValidPlayStoreUrl(playStoreUrl.trim())) {
      return ApiResult.failure('Invalid Play Store URL. Must begin with http:// or https://.');
    }

    final isIdUnique = await isAppIdentifierUnique(trimmedIdentifier);
    if (!isIdUnique) {
      return ApiResult.failure('The App Identifier "$trimmedIdentifier" is already assigned to another school.');
    }

    final isPkgUnique = await isPackageNameUnique(trimmedPackage);
    if (!isPkgUnique) {
      return ApiResult.failure('The Android package name "$trimmedPackage" is already registered to another school app.');
    }

    try {
      final payload = {
        'school_id': schoolId,
        'app_name': trimmedAppName,
        'package_name': trimmedPackage,
        'app_identifier': trimmedIdentifier,
        'current_version': trimmedVersion,
        if (playStoreUrl != null && playStoreUrl.trim().isNotEmpty)
          'play_store_url': playStoreUrl.trim(),
        'status': status.dbValue,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      };

      final inserted = await client
          .from('school_management_apps')
          .insert(payload)
          .select(_appColumns)
          .single();

      return ApiResult.success(SchoolAppModel.fromJson(inserted));
    } catch (e) {
      debugPrint('[SchoolAppService] createSchoolApp error: $e');
      return ApiResult.failure(_formatErrorMessage(e), e);
    }
  }

  /// Update dedicated app metadata (DO NOT allow changing school_id)
  Future<ApiResult<SchoolAppModel>> updateAppMetadata({
    required String appId,
    required String appName,
    String? packageName,
    String? appIdentifier,
    String? currentVersion,
    String? playStoreUrl,
    String? notes,
  }) async {
    final client = _client;
    if (client == null) {
      return ApiResult.failure('Database service is uninitialized.');
    }

    final trimmedAppName = appName.trim();
    if (trimmedAppName.isEmpty) {
      return ApiResult.failure('App name is required.');
    }

    final trimmedIdentifier = (appIdentifier ?? '').trim().toUpperCase();
    if (trimmedIdentifier.isEmpty) {
      return ApiResult.failure('App identifier is required.');
    }

    final trimmedPackage = (packageName ?? '').trim().toLowerCase();
    if (trimmedPackage.isEmpty) {
      return ApiResult.failure('Android package name is required.');
    }
    if (!isValidPackageName(trimmedPackage)) {
      return ApiResult.failure('Invalid Android package name. Use reverse-domain format (e.g. com.company.schoolapp).');
    }

    final trimmedVersion = (currentVersion ?? '').trim().isNotEmpty ? currentVersion!.trim() : '1.0.0';
    if (!isValidVersion(trimmedVersion)) {
      return ApiResult.failure('Invalid version format. Use semantic versioning (e.g. 1.0.0).');
    }

    if (playStoreUrl != null && playStoreUrl.trim().isNotEmpty && !isValidPlayStoreUrl(playStoreUrl.trim())) {
      return ApiResult.failure('Invalid Play Store URL. Must begin with http:// or https://.');
    }

    final isIdUnique = await isAppIdentifierUnique(trimmedIdentifier, excludeAppId: appId);
    if (!isIdUnique) {
      return ApiResult.failure('The App Identifier "$trimmedIdentifier" is already assigned to another school.');
    }

    final isPkgUnique = await isPackageNameUnique(trimmedPackage, excludeAppId: appId);
    if (!isPkgUnique) {
      return ApiResult.failure('The Android package name "$trimmedPackage" is already registered to another school app.');
    }

    try {
      final updateData = <String, dynamic>{
        'app_name': trimmedAppName,
        'package_name': trimmedPackage,
        'app_identifier': trimmedIdentifier,
        'current_version': trimmedVersion,
        'play_store_url': (playStoreUrl != null && playStoreUrl.trim().isNotEmpty) ? playStoreUrl.trim() : null,
        'notes': (notes != null && notes.trim().isNotEmpty) ? notes.trim() : null,
        'updated_at': DateTime.now().toIso8601String(),
      };

      final updated = await client
          .from('school_management_apps')
          .update(updateData)
          .eq('id', appId)
          .select(_appColumns)
          .single();

      return ApiResult.success(SchoolAppModel.fromJson(updated));
    } catch (e) {
      debugPrint('[SchoolAppService] updateAppMetadata error: $e');
      return ApiResult.failure(_formatErrorMessage(e), e);
    }
  }

  /// Toggle access state of an application (ACTIVE / INACTIVE)
  Future<ApiResult<SchoolAppModel>> toggleAppAccess({
    required String appId,
    required bool isActive,
  }) async {
    final client = _client;
    if (client == null) {
      return ApiResult.failure('Database service is uninitialized.');
    }

    try {
      final updated = await client
          .from('school_management_apps')
          .update({
            'status': isActive ? 'ACTIVE' : 'INACTIVE',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', appId)
          .select(_appColumns)
          .single();

      return ApiResult.success(SchoolAppModel.fromJson(updated));
    } catch (e) {
      debugPrint('[SchoolAppService] toggleAppAccess error: $e');
      return ApiResult.failure(_formatErrorMessage(e), e);
    }
  }

  /// Deterministically generate an app_identifier from a school name.
  /// Example: "ABC Public School" -> "ABC_PUBLIC_SCHOOL_APP"
  static String generateDefaultAppIdentifier(String schoolName) {
    final cleaned = schoolName
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');

    if (cleaned.isEmpty) {
      return 'SCHOOL_APP';
    }

    if (!cleaned.endsWith('_APP')) {
      return '${cleaned}_APP';
    }
    return cleaned;
  }

  /// Deterministically generate an Android package name from a school name.
  /// Example: "ABC Public School" -> "com.company.abcpublicschool"
  static String generateDefaultPackageName(String schoolName, {String prefix = 'com.company'}) {
    final cleaned = schoolName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '');

    final suffix = cleaned.isNotEmpty ? cleaned : 'schoolapp';
    return '$prefix.$suffix';
  }

  /// Validate reverse domain notation for Android package name.
  static bool isValidPackageName(String packageName) {
    final trimmed = packageName.trim();
    return RegExp(r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$').hasMatch(trimmed);
  }

  /// Validate release version string (e.g. 1.0.0 or 1.2).
  static bool isValidVersion(String version) {
    final trimmed = version.trim();
    return RegExp(r'^\d+(\.\d+)+(\+[0-9]+)?$').hasMatch(trimmed) ||
        RegExp(r'^\d+(\.\d+)*$').hasMatch(trimmed);
  }

  /// Validate Play Store or store URL.
  static bool isValidPlayStoreUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return true;
    final uri = Uri.tryParse(trimmed);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  /// Check if app_identifier is unique across other applications.
  Future<bool> isAppIdentifierUnique(String appIdentifier, {String? excludeAppId}) async {
    final client = _client;
    if (client == null) return true;

    try {
      final normalized = appIdentifier.trim().toUpperCase();
      var query = client
          .from('school_management_apps')
          .select('id')
          .eq('app_identifier', normalized);

      if (excludeAppId != null) {
        query = query.neq('id', excludeAppId);
      }

      final res = await query.maybeSingle();
      return res == null;
    } catch (_) {
      return true;
    }
  }

  /// Check if package_name is unique across other applications.
  Future<bool> isPackageNameUnique(String packageName, {String? excludeAppId}) async {
    final client = _client;
    if (client == null) return true;

    try {
      final normalized = packageName.trim().toLowerCase();
      var query = client
          .from('school_management_apps')
          .select('id')
          .eq('package_name', normalized);

      if (excludeAppId != null) {
        query = query.neq('id', excludeAppId);
      }

      final res = await query.maybeSingle();
      return res == null;
    } catch (_) {
      return true;
    }
  }

  String _formatErrorMessage(dynamic error) {
    if (error is PostgrestException) {
      if (error.code == '42501') {
        return 'Permission Denied: Super Admin privileges are required by Supabase RLS. Ensure the Super Admin migration SQL has been executed.';
      }
      if (error.code == '23505') {
        final detail = error.details?.toString().toLowerCase() ?? '';
        final message = error.message.toLowerCase();
        if (detail.contains('app_identifier') || message.contains('app_identifier')) {
          return 'The App Identifier is already assigned to another school. App Identifiers must be unique across all institutions.';
        }
        if (detail.contains('package_name') || message.contains('package_name')) {
          return 'The Android Package Name is already registered to another school app. Package names must be globally unique on Android.';
        }
        return 'A dedicated School Management App record already exists for this school. Only one app record per school is permitted.';
      }
      if (error.code == 'PGRST205' || error.message.contains('does not exist')) {
        return 'Table "school_management_apps" not found in Supabase. Please execute the SQL migration script first.';
      }
      return 'Supabase Error: ${error.message} (Code: ${error.code})';
    }
    return 'Operation failed: ${error.toString()}';
  }
}
