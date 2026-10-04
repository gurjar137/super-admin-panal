import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_result.dart';
import '../models/school_admin_model.dart';
import '../services/school_admin_service.dart';

final schoolAdminServiceProvider = Provider<SchoolAdminService>((ref) => SchoolAdminService());

final schoolAdminRepositoryProvider = Provider<SchoolAdminRepository>((ref) {
  return SchoolAdminRepository(ref.watch(schoolAdminServiceProvider));
});

/// Riverpod family provider to fetch the School Administrator for a specific school
final schoolAdminProvider =
    FutureProvider.family.autoDispose<SchoolAdminModel?, String>((ref, schoolId) async {
  final repo = ref.watch(schoolAdminRepositoryProvider);
  final result = await repo.getSchoolAdmin(schoolId);
  if (result.isFailure) {
    throw Exception(result.errorOrNull ?? 'Failed to load school administrator');
  }
  return result.dataOrNull;
});

class SchoolAdminRepository {
  final SchoolAdminService _service;

  SchoolAdminRepository(this._service);

  Future<ApiResult<SchoolAdminModel?>> getSchoolAdmin(String schoolId) =>
      _service.fetchSchoolAdmin(schoolId);

  Future<ApiResult<SchoolAdminModel>> createSchoolAdmin({
    required String schoolId,
    required String fullName,
    required String email,
    String? phone,
    required String password,
  }) =>
      _service.createSchoolAdmin(
        schoolId: schoolId,
        fullName: fullName,
        email: email,
        phone: phone,
        password: password,
      );

  Future<ApiResult<SchoolAdminModel>> updateSchoolAdminProfile({
    required String profileId,
    required String fullName,
    String? phone,
  }) =>
      _service.updateSchoolAdminProfile(
        profileId: profileId,
        fullName: fullName,
        phone: phone,
      );

  Future<ApiResult<SchoolAdminModel>> updateSchoolAdminStatus({
    required String profileId,
    required String newStatus,
  }) =>
      _service.updateSchoolAdminStatus(
        profileId: profileId,
        newStatus: newStatus,
      );
}
