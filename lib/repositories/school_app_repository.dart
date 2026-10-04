import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_result.dart';
import '../models/school_app_model.dart';
import '../services/school_app_service.dart';

final schoolAppServiceProvider = Provider<SchoolAppService>((ref) => SchoolAppService());

final schoolAppRepositoryProvider = Provider<SchoolAppRepository>((ref) {
  return SchoolAppRepository(ref.watch(schoolAppServiceProvider));
});

class SchoolAppRepository {
  final SchoolAppService _service;

  SchoolAppRepository(this._service);

  Future<ApiResult<SchoolAppModel?>> getAppBySchoolId(String schoolId) =>
      _service.fetchAppBySchoolId(schoolId);

  Future<ApiResult<List<SchoolAppModel>>> getSchoolApps({String? schoolId}) =>
      _service.fetchSchoolApps(schoolId: schoolId);

  Future<ApiResult<SchoolAppModel>> getAppDetails(String appId) =>
      _service.fetchAppDetails(appId);

  Future<ApiResult<SchoolAppModel>> createSchoolApp({
    required String schoolId,
    required String appName,
    String? packageName,
    String? appIdentifier,
    String? currentVersion,
    String? playStoreUrl,
    SchoolAppStatus status = SchoolAppStatus.active,
    String? notes,
  }) =>
      _service.createSchoolApp(
        schoolId: schoolId,
        appName: appName,
        packageName: packageName,
        appIdentifier: appIdentifier,
        currentVersion: currentVersion,
        playStoreUrl: playStoreUrl,
        status: status,
        notes: notes,
      );

  Future<ApiResult<SchoolAppModel>> toggleAppAccess({
    required String appId,
    required bool isActive,
  }) =>
      _service.toggleAppAccess(appId: appId, isActive: isActive);

  Future<ApiResult<SchoolAppModel>> updateAppMetadata({
    required String appId,
    required String appName,
    String? packageName,
    String? appIdentifier,
    String? currentVersion,
    String? playStoreUrl,
    String? notes,
  }) =>
      _service.updateAppMetadata(
        appId: appId,
        appName: appName,
        packageName: packageName,
        appIdentifier: appIdentifier,
        currentVersion: currentVersion,
        playStoreUrl: playStoreUrl,
        notes: notes,
      );

  Future<bool> isAppIdentifierUnique(String appIdentifier, {String? excludeAppId}) =>
      _service.isAppIdentifierUnique(appIdentifier, excludeAppId: excludeAppId);

  Future<bool> isPackageNameUnique(String packageName, {String? excludeAppId}) =>
      _service.isPackageNameUnique(packageName, excludeAppId: excludeAppId);
}
