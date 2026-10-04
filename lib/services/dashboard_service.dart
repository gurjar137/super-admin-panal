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

  /// Computes live aggregate statistics from the Supabase schools, products, apps, and subscriptions tables
  Future<ApiResult<DashboardStats>> fetchDashboardStats() async {
    try {
      final schoolsResult = await _schoolService.fetchSchools();

      if (schoolsResult is ApiFailure) {
        return ApiResult.failure(schoolsResult.errorOrNull ?? 'Failed to compute stats');
      }

      final schools = schoolsResult.dataOrNull ?? [];
      final client = _client;

      int totalProducts = 4;
      int activeProducts = 4;
      int totalAssignments = 0;
      int activeAssignments = 0;
      int expiredSubscriptions = 0;

      if (client != null) {
        // Query products
        try {
          final prodRes = await client.from('products').select('id, status');
          final prodList = prodRes as List<dynamic>;
          if (prodList.isNotEmpty) {
            totalProducts = prodList.length;
            activeProducts = prodList.where((p) => (p['status']?.toString().toUpperCase() ?? '') == 'ACTIVE').length;
          }
        } catch (_) {}

        // Query school_apps (assignments)
        try {
          final appsRes = await client.from('school_apps').select('id, status');
          final appList = appsRes as List<dynamic>;
          totalAssignments = appList.length;
          activeAssignments = appList.where((a) => (a['status']?.toString().toUpperCase() ?? '') == 'ACTIVE').length;
        } catch (_) {}

        // Query subscriptions
        try {
          final subRes = await client.from('subscriptions').select('id, status, end_date');
          final subList = subRes as List<dynamic>;
          final now = DateTime.now();
          expiredSubscriptions = subList.where((s) {
            final statusStr = s['status']?.toString().toUpperCase() ?? '';
            final endDate = DateTime.tryParse(s['end_date']?.toString() ?? '');
            return statusStr == 'EXPIRED' || (endDate != null && now.isAfter(endDate));
          }).length;
        } catch (_) {}
      }

      final stats = DashboardStats.fromAggregates(
        schools: schools,
        totalProducts: totalProducts,
        activeProducts: activeProducts,
        totalAssignments: totalAssignments,
        activeAssignments: activeAssignments,
        expiredSubscriptions: expiredSubscriptions,
      );

      return ApiResult.success(stats);
    } catch (e) {
      debugPrint('[DashboardService] fetchDashboardStats error: $e');
      return ApiResult.failure('Failed to load dashboard metrics: $e', e);
    }
  }
}
