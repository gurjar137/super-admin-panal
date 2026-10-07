import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/network/api_result.dart';
import '../models/dashboard_stats.dart';
import 'school_service.dart';
import 'supabase_service.dart';

class DashboardService {
  final SchoolService _schoolService;
  SupabaseClient? get _client => SupabaseService.instance.client;

  DashboardService({SchoolService? schoolService})
      : _schoolService = schoolService ?? SchoolService();

  /// Computes live aggregate statistics from canonical Supabase tables:
  /// schools, school_management_apps, and school_app_subscriptions.
  /// Uses lightweight PostgREST count requests instead of loading every row into memory.
  Future<ApiResult<DashboardStats>> fetchDashboardStats() async {
    final client = _client;
    if (client == null) {
      return ApiResult.failure('Database service is uninitialized.');
    }

    try {
      // 1. Fetch schools for tenant status distribution and recent onboardings
      final schoolsResult = await _schoolService.fetchSchools();
      if (schoolsResult is ApiFailure) {
        return ApiResult.failure(schoolsResult.errorOrNull ?? 'Failed to compute school metrics');
      }

      final schools = schoolsResult.dataOrNull ?? [];

      // 2. Query aggregate counts from public.school_management_apps
      // Using PostgREST head request with count: exact
      int totalApps = 0;
      int activeApps = 0;

      final totalAppsRes = await client
          .from('school_management_apps')
          .select('id')
          .count(CountOption.exact);
      totalApps = totalAppsRes.count;

      final activeAppsRes = await client
          .from('school_management_apps')
          .select('id')
          .eq('status', 'ACTIVE')
          .count(CountOption.exact);
      activeApps = activeAppsRes.count;

      // 3. Query aggregate counts from public.school_app_subscriptions
      int totalSubscriptions = 0;
      int activeSubscriptions = 0;
      int expiredSubscriptions = 0;

      final totalSubsRes = await client
          .from('school_app_subscriptions')
          .select('id')
          .count(CountOption.exact);
      totalSubscriptions = totalSubsRes.count;

      final activeSubsRes = await client
          .from('school_app_subscriptions')
          .select('id')
          .eq('status', 'ACTIVE')
          .count(CountOption.exact);
      activeSubscriptions = activeSubsRes.count;

      // Check expired subscriptions (status == 'EXPIRED' or end_date in past)
      // Using PostgREST query on canonical subscriptions table
      final nowIso = DateTime.now().toIso8601String().split('T').first;
      final expiredStatusRes = await client
          .from('school_app_subscriptions')
          .select('id')
          .or('status.eq.EXPIRED,end_date.lt.$nowIso')
          .count(CountOption.exact);
      expiredSubscriptions = expiredStatusRes.count;

      final stats = DashboardStats.fromAggregates(
        schools: schools,
        totalApps: totalApps,
        activeApps: activeApps,
        totalSubscriptions: totalSubscriptions,
        activeSubscriptions: activeSubscriptions,
        expiredSubscriptions: expiredSubscriptions,
      );

      return ApiResult.success(stats);
    } catch (e) {
      debugPrint('[DashboardService] fetchDashboardStats error: $e');
      return ApiResult.failure('Failed to load dashboard metrics: $e', e);
    }
  }
}

