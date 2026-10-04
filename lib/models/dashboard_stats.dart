import 'school_model.dart';

class DashboardStats {
  final int totalSchools;
  final int activeSchools;
  final int inactiveSchools;
  final int suspendedSchools;
  final int totalProducts;
  final int activeProducts;
  final int totalAssignments;
  final int activeAssignments;
  final int expiredSubscriptions;
  final List<SchoolModel> recentSchools;

  const DashboardStats({
    required this.totalSchools,
    required this.activeSchools,
    required this.inactiveSchools,
    required this.suspendedSchools,
    this.totalProducts = 0,
    this.activeProducts = 0,
    this.totalAssignments = 0,
    this.activeAssignments = 0,
    this.expiredSubscriptions = 0,
    required this.recentSchools,
  });

  factory DashboardStats.fromAggregates({
    required List<SchoolModel> schools,
    int totalProducts = 0,
    int activeProducts = 0,
    int totalAssignments = 0,
    int activeAssignments = 0,
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

    return DashboardStats(
      totalSchools: schools.length,
      activeSchools: active,
      inactiveSchools: inactive,
      suspendedSchools: suspended,
      totalProducts: totalProducts,
      activeProducts: activeProducts,
      totalAssignments: totalAssignments,
      activeAssignments: activeAssignments,
      expiredSubscriptions: expiredSubscriptions,
      recentSchools: recent,
    );
  }

  static const DashboardStats empty = DashboardStats(
    totalSchools: 0,
    activeSchools: 0,
    inactiveSchools: 0,
    suspendedSchools: 0,
    totalProducts: 0,
    activeProducts: 0,
    totalAssignments: 0,
    activeAssignments: 0,
    expiredSubscriptions: 0,
    recentSchools: [],
  );
}
