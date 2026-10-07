import 'school_model.dart';

class DashboardStats {
  final int totalSchools;
  final int activeSchools;
  final int inactiveSchools;
  final int suspendedSchools;
  final int totalApps;
  final int activeApps;
  final int totalSubscriptions;
  final int activeSubscriptions;
  final int expiredSubscriptions;
  final List<SchoolModel> recentSchools;

  const DashboardStats({
    required this.totalSchools,
    required this.activeSchools,
    required this.inactiveSchools,
    required this.suspendedSchools,
    this.totalApps = 0,
    this.activeApps = 0,
    this.totalSubscriptions = 0,
    this.activeSubscriptions = 0,
    this.expiredSubscriptions = 0,
    required this.recentSchools,
  });

  factory DashboardStats.fromAggregates({
    required List<SchoolModel> schools,
    int? totalApps,
    int? activeApps,
    int? totalSubscriptions,
    int? activeSubscriptions,
    int expiredSubscriptions = 0,
  }) {
    int active = 0;
    int inactive = 0;
    int suspended = 0;

    for (final s in schools) {
      switch (s.status) {
        case SchoolStatus.active:
          active++;
          break;
        case SchoolStatus.inactive:
          inactive++;
          break;
        case SchoolStatus.suspended:
          suspended++;
          break;
      }
    }

    final sorted = List<SchoolModel>.from(schools)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final recent = sorted.take(5).toList();

    final resolvedTotalApps = totalApps ?? 0;
    final resolvedActiveApps = activeApps ?? 0;
    final resolvedTotalSubs = totalSubscriptions ?? 0;
    final resolvedActiveSubs = activeSubscriptions ?? 0;

    return DashboardStats(
      totalSchools: schools.length,
      activeSchools: active,
      inactiveSchools: inactive,
      suspendedSchools: suspended,
      totalApps: resolvedTotalApps,
      activeApps: resolvedActiveApps,
      totalSubscriptions: resolvedTotalSubs,
      activeSubscriptions: resolvedActiveSubs,
      expiredSubscriptions: expiredSubscriptions,
      recentSchools: recent,
    );
  }

  static const DashboardStats empty = DashboardStats(
    totalSchools: 0,
    activeSchools: 0,
    inactiveSchools: 0,
    suspendedSchools: 0,
    totalApps: 0,
    activeApps: 0,
    totalSubscriptions: 0,
    activeSubscriptions: 0,
    expiredSubscriptions: 0,
    recentSchools: [],
  );
}

