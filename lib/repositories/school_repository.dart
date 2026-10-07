import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_result.dart';
import '../models/dashboard_stats.dart';
import '../models/school_model.dart';
import '../models/school_provision_dto.dart';
import '../services/dashboard_service.dart';
import '../services/school_service.dart';

final schoolServiceProvider = Provider<SchoolService>((ref) => SchoolService());
final dashboardServiceProvider = Provider<DashboardService>((ref) {
  return DashboardService(schoolService: ref.watch(schoolServiceProvider));
});

final schoolRepositoryProvider = Provider<SchoolRepository>((ref) {
  return SchoolRepository(
    ref.watch(schoolServiceProvider),
    ref.watch(dashboardServiceProvider),
  );
});

class SchoolRepository {
  final SchoolService _schoolService;
  final DashboardService _dashboardService;

  SchoolRepository(this._schoolService, this._dashboardService);

  Future<ApiResult<List<SchoolModel>>> getSchools({
    String? searchQuery,
    SchoolStatus? statusFilter,
    int? page,
    int? pageSize,
  }) =>
      _schoolService.fetchSchools(
        searchQuery: searchQuery,
        statusFilter: statusFilter,
        page: page,
        pageSize: pageSize,
      );

  Future<ApiResult<int>> getSchoolsCount({
    String? searchQuery,
    SchoolStatus? statusFilter,
  }) =>
      _schoolService.fetchSchoolsCount(
        searchQuery: searchQuery,
        statusFilter: statusFilter,
      );

  Future<ApiResult<SchoolModel>> getSchoolDetails(String schoolId) =>
      _schoolService.fetchSchoolDetails(schoolId);

  Future<ApiResult<SchoolModel>> updateStatus(String schoolId, SchoolStatus status) =>
      _schoolService.updateSchoolStatus(schoolId: schoolId, newStatus: status);

  Future<ApiResult<SchoolModel>> updateSchool({
    required String schoolId,
    required String name,
    String? address,
    String? phone,
    String? email,
    String? logoUrl,
  }) =>
      _schoolService.updateSchool(
        schoolId: schoolId,
        name: name,
        address: address,
        phone: phone,
        email: email,
        logoUrl: logoUrl,
      );

  Future<ApiResult<SchoolModel>> createSchool({
    required String name,
    required String schoolCode,
    String? address,
    String? phone,
    String? email,
    String? logoUrl,
    SchoolStatus status = SchoolStatus.active,
  }) =>
      _schoolService.createSchool(
        name: name,
        schoolCode: schoolCode,
        address: address,
        phone: phone,
        email: email,
        logoUrl: logoUrl,
        status: status,
      );

  Future<ApiResult<SchoolModel>> provisionSchool(SchoolProvisionDto dto) =>
      _schoolService.provisionSchool(dto);

  Future<ApiResult<DashboardStats>> getDashboardStats() =>
      _dashboardService.fetchDashboardStats();
}
