import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_result.dart';
import '../models/school_provisioning_models.dart';
import '../services/school_provisioning_service.dart';

final schoolProvisioningServiceProvider = Provider<SchoolProvisioningService>((ref) {
  return SchoolProvisioningService();
});

final schoolProvisioningRepositoryProvider = Provider<SchoolProvisioningRepository>((ref) {
  return SchoolProvisioningRepository(ref.watch(schoolProvisioningServiceProvider));
});

class SchoolProvisioningRepository {
  final SchoolProvisioningService _service;

  SchoolProvisioningRepository(this._service);

  Future<ApiResult<void>> preflightConflictCheck(SchoolProvisioningRequest request) {
    return _service.preflightConflictCheck(request);
  }

  Future<ApiResult<SchoolProvisioningResult>> provisionSchool(SchoolProvisioningRequest request) {
    return _service.provisionSchool(request);
  }
}
