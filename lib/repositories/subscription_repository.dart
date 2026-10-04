import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_result.dart';
import '../models/subscription_model.dart';
import '../services/subscription_service.dart';

final subscriptionServiceProvider = Provider<SubscriptionService>((ref) => SubscriptionService());

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>((ref) {
  return SubscriptionRepository(ref.watch(subscriptionServiceProvider));
});

/// Riverpod family provider to fetch subscription for a specific school app
final schoolAppSubscriptionProvider =
    FutureProvider.family.autoDispose<SubscriptionModel?, String>((ref, schoolAppId) async {
  final repo = ref.watch(subscriptionRepositoryProvider);
  final result = await repo.getSubscriptionForApp(schoolAppId);
  if (result.isFailure) {
    throw Exception(result.errorOrNull ?? 'Failed to load app subscription');
  }
  return result.dataOrNull;
});

/// Riverpod provider for all subscriptions
final allSubscriptionsProvider =
    FutureProvider.autoDispose<List<SubscriptionModel>>((ref) async {
  final repo = ref.watch(subscriptionRepositoryProvider);
  final result = await repo.getAllSubscriptions();
  if (result.isFailure) {
    throw Exception(result.errorOrNull ?? 'Failed to load subscriptions');
  }
  return result.dataOrNull ?? [];
});

class SubscriptionRepository {
  final SubscriptionService _service;

  SubscriptionRepository(this._service);

  Future<ApiResult<SubscriptionModel?>> getSubscriptionForApp(String schoolAppId) =>
      _service.fetchSubscriptionBySchoolAppId(schoolAppId);

  Future<ApiResult<List<SubscriptionModel>>> getAllSubscriptions() =>
      _service.fetchAllSubscriptions();

  Future<ApiResult<List<SubscriptionModel>>> getSubscriptions({String? schoolId}) =>
      _service.fetchAllSubscriptions();

  Future<ApiResult<SubscriptionModel>> createSubscription({
    required String schoolAppId,
    required String planName,
    required DateTime startDate,
    required DateTime endDate,
    SubscriptionStatus status = SubscriptionStatus.active,
    String? notes,
  }) =>
      _service.createSubscription(
        schoolAppId: schoolAppId,
        planName: planName,
        startDate: startDate,
        endDate: endDate,
        status: status,
        notes: notes,
      );

  Future<ApiResult<SubscriptionModel>> updateSubscription({
    required String subscriptionId,
    required String planName,
    required DateTime startDate,
    required DateTime endDate,
    String? notes,
  }) =>
      _service.updateSubscription(
        subscriptionId: subscriptionId,
        planName: planName,
        startDate: startDate,
        endDate: endDate,
        notes: notes,
      );

  Future<ApiResult<SubscriptionModel>> updateStatus({
    required String subscriptionId,
    required SubscriptionStatus status,
  }) =>
      _service.updateSubscriptionStatus(
        subscriptionId: subscriptionId,
        status: status,
      );

  Future<ApiResult<SubscriptionModel>> extendSubscription({
    required String subscriptionId,
    required DateTime newEndDate,
  }) =>
      _service.extendSubscription(
        subscriptionId: subscriptionId,
        newEndDate: newEndDate,
      );

  Future<ApiResult<SubscriptionModel>> upsertSubscription({
    required String schoolId,
    required String productId,
    String? schoolAppId,
    required DateTime startDate,
    required DateTime endDate,
    SubscriptionStatus status = SubscriptionStatus.active,
    String planType = 'ANNUAL',
    String? notes,
  }) async {
    if (schoolAppId != null && schoolAppId.isNotEmpty) {
      return _service.createSubscription(
        schoolAppId: schoolAppId,
        planName: planType,
        startDate: startDate,
        endDate: endDate,
        status: status,
        notes: notes,
      );
    }
    return ApiResult.failure('School Management App ID is required to provision a subscription. Please configure from School Details screen.');
  }
}
