import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/network/api_result.dart';
import '../models/subscription_model.dart';
import 'supabase_service.dart';

class SubscriptionService {
  SupabaseClient? get _client => SupabaseService.instance.client;

  /// Fetch subscription for a dedicated School Management App by its ID
  Future<ApiResult<SubscriptionModel?>> fetchSubscriptionBySchoolAppId(String schoolAppId) async {
    final client = _client;
    if (client == null) {
      return ApiResult.success(null);
    }

    try {
      final response = await client
          .from('school_app_subscriptions')
          .select(
            'id, school_app_id, plan_name, status, start_date, end_date, notes, created_at, updated_at, school_management_apps(id, app_name, school_id, schools(id, name))',
          )
          .eq('school_app_id', schoolAppId)
          .maybeSingle();

      if (response == null) {
        return ApiResult.success(null);
      }

      return ApiResult.success(SubscriptionModel.fromJson(response));
    } catch (e) {
      debugPrint('[SubscriptionService] fetchSubscriptionBySchoolAppId: $e');
      return ApiResult.success(null);
    }
  }

  /// Fetch all school app subscriptions with school and app joins
  Future<ApiResult<List<SubscriptionModel>>> fetchAllSubscriptions() async {
    final client = _client;
    if (client == null) {
      return ApiResult.success([]);
    }

    try {
      final response = await client
          .from('school_app_subscriptions')
          .select(
            'id, school_app_id, plan_name, status, start_date, end_date, notes, created_at, updated_at, school_management_apps(id, app_name, school_id, schools(id, name))',
          )
          .order('created_at', ascending: false);

      final List<dynamic> rawList = response as List<dynamic>;
      final list = rawList
          .map((item) => SubscriptionModel.fromJson(item as Map<String, dynamic>))
          .toList();

      return ApiResult.success(list);
    } catch (e) {
      debugPrint('[SubscriptionService] fetchAllSubscriptions notice: $e');
      return ApiResult.success([]);
    }
  }

  /// Create a subscription for the dedicated School Management App.
  /// Strictly enforces the 1 subscription per app rule.
  Future<ApiResult<SubscriptionModel>> createSubscription({
    required String schoolAppId,
    required String planName,
    required DateTime startDate,
    required DateTime endDate,
    SubscriptionStatus status = SubscriptionStatus.active,
    String? notes,
  }) async {
    final client = _client;
    if (client == null) {
      return ApiResult.failure('Database service is uninitialized.');
    }

    try {
      // 1. Enforce 1-subscription-per-app check before inserting
      final existing = await client
          .from('school_app_subscriptions')
          .select('id')
          .eq('school_app_id', schoolAppId)
          .maybeSingle();

      if (existing != null) {
        return ApiResult.failure(
          'A subscription record already exists for this School Management App. Overlapping subscriptions are not allowed. Please edit or renew the existing subscription.',
        );
      }

      // 2. Validate dates
      if (endDate.isBefore(startDate)) {
        return ApiResult.failure('Subscription end date cannot be earlier than start date.');
      }

      final payload = {
        'school_app_id': schoolAppId,
        'plan_name': planName.trim(),
        'start_date': startDate.toIso8601String().split('T').first,
        'end_date': endDate.toIso8601String().split('T').first,
        'status': status.dbValue,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      };

      final response = await client
          .from('school_app_subscriptions')
          .insert(payload)
          .select(
            'id, school_app_id, plan_name, status, start_date, end_date, notes, created_at, updated_at, school_management_apps(id, app_name, school_id, schools(id, name))',
          )
          .single();

      final created = SubscriptionModel.fromJson(response);

      // 3. Post-write verification: Re-read to ensure persistence
      final verified = await client
          .from('school_app_subscriptions')
          .select('id, status')
          .eq('id', created.id)
          .maybeSingle();

      if (verified == null) {
        return ApiResult.failure('Subscription write could not be verified in Supabase.');
      }

      return ApiResult.success(created);
    } catch (e) {
      debugPrint('[SubscriptionService] createSubscription error: $e');
      return ApiResult.failure('Failed to create subscription: $e', e);
    }
  }

  /// Update subscription metadata and validity period
  Future<ApiResult<SubscriptionModel>> updateSubscription({
    required String subscriptionId,
    required String planName,
    required DateTime startDate,
    required DateTime endDate,
    String? notes,
  }) async {
    final client = _client;
    if (client == null) {
      return ApiResult.failure('Database service is uninitialized.');
    }

    try {
      if (endDate.isBefore(startDate)) {
        return ApiResult.failure('Subscription end date cannot be earlier than start date.');
      }

      final payload = {
        'plan_name': planName.trim(),
        'start_date': startDate.toIso8601String().split('T').first,
        'end_date': endDate.toIso8601String().split('T').first,
        'notes': notes?.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      final response = await client
          .from('school_app_subscriptions')
          .update(payload)
          .eq('id', subscriptionId)
          .select(
            'id, school_app_id, plan_name, status, start_date, end_date, notes, created_at, updated_at, school_management_apps(id, app_name, school_id, schools(id, name))',
          )
          .single();

      final updated = SubscriptionModel.fromJson(response);

      // Post-write verification
      final verified = await client
          .from('school_app_subscriptions')
          .select('id, plan_name, updated_at')
          .eq('id', subscriptionId)
          .maybeSingle();

      if (verified == null) {
        return ApiResult.failure('Subscription update verification failed in Supabase.');
      }

      return ApiResult.success(updated);
    } catch (e) {
      debugPrint('[SubscriptionService] updateSubscription error: $e');
      return ApiResult.failure('Failed to update subscription: $e', e);
    }
  }

  /// Update subscription status (Active / Suspended / Inactive / Expired)
  Future<ApiResult<SubscriptionModel>> updateSubscriptionStatus({
    required String subscriptionId,
    required SubscriptionStatus status,
  }) async {
    final client = _client;
    if (client == null) {
      return ApiResult.failure('Database service is uninitialized.');
    }

    try {
      final response = await client
          .from('school_app_subscriptions')
          .update({
            'status': status.dbValue,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', subscriptionId)
          .select(
            'id, school_app_id, plan_name, status, start_date, end_date, notes, created_at, updated_at, school_management_apps(id, app_name, school_id, schools(id, name))',
          )
          .single();

      final updated = SubscriptionModel.fromJson(response);

      // Post-write verification
      final verified = await client
          .from('school_app_subscriptions')
          .select('id, status')
          .eq('id', subscriptionId)
          .maybeSingle();

      if (verified == null || verified['status'] != status.dbValue) {
        return ApiResult.failure('Subscription status persistence could not be verified in Supabase.');
      }

      return ApiResult.success(updated);
    } catch (e) {
      debugPrint('[SubscriptionService] updateSubscriptionStatus error: $e');
      return ApiResult.failure('Failed to update subscription status: $e', e);
    }
  }

  /// Extend subscription validity
  Future<ApiResult<SubscriptionModel>> extendSubscription({
    required String subscriptionId,
    required DateTime newEndDate,
  }) async {
    final client = _client;
    if (client == null) {
      return ApiResult.failure('Database service is uninitialized.');
    }

    try {
      final response = await client
          .from('school_app_subscriptions')
          .update({
            'end_date': newEndDate.toIso8601String().split('T').first,
            'status': 'ACTIVE',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', subscriptionId)
          .select(
            'id, school_app_id, plan_name, status, start_date, end_date, notes, created_at, updated_at, school_management_apps(id, app_name, school_id, schools(id, name))',
          )
          .single();

      return ApiResult.success(SubscriptionModel.fromJson(response));
    } catch (e) {
      debugPrint('[SubscriptionService] extendSubscription error: $e');
      return ApiResult.failure('Failed to extend subscription: $e', e);
    }
  }
}
