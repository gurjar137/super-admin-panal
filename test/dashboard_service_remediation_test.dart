import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_admin_app/models/dashboard_stats.dart';
import 'package:super_admin_app/models/school_model.dart';
import 'package:super_admin_app/services/dashboard_service.dart';

void main() {
  group('SUPER ADMIN P2 #3 — Dashboard Stale Metrics & Obsolete Table Remediation Tests', () {
    test('1. Static verification: dashboard_service.dart contains zero hardcoded product metrics', () {
      final file = File('lib/services/dashboard_service.dart');
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();

      // Ensure hardcoded 4 is never assigned
      expect(content.contains('totalProducts = 4'), isFalse);
      expect(content.contains('activeProducts = 4'), isFalse);
      expect(content.contains('totalProducts = 0'), isFalse);
    });

    test('2. Static verification: dashboard_service.dart contains zero queries against obsolete products table', () {
      final file = File('lib/services/dashboard_service.dart');
      final content = file.readAsStringSync();

      expect(content.contains(".from('products')"), isFalse);
      expect(content.contains('.from("products")'), isFalse);
    });

    test('3. Static verification: dashboard_service.dart contains zero queries against obsolete school_apps table', () {
      final file = File('lib/services/dashboard_service.dart');
      final content = file.readAsStringSync();

      expect(content.contains(".from('school_apps')"), isFalse);
      expect(content.contains('.from("school_apps")'), isFalse);
    });

    test('4. Static verification: dashboard_service.dart contains zero queries against obsolete subscriptions table', () {
      final file = File('lib/services/dashboard_service.dart');
      final content = file.readAsStringSync();

      expect(content.contains(".from('subscriptions')"), isFalse);
      expect(content.contains('.from("subscriptions")'), isFalse);
    });

    test('5. Static verification: dashboard_service.dart uses canonical tables and count queries', () {
      final file = File('lib/services/dashboard_service.dart');
      final content = file.readAsStringSync();

      expect(content.contains(".from('school_management_apps')"), isTrue);
      expect(content.contains(".from('school_app_subscriptions')"), isTrue);
      expect(content.contains('CountOption.exact'), isTrue);
    });

    test('6. DashboardStats correctly aggregates total and active school metrics', () {
      final schools = [
        SchoolModel(
          id: '1',
          schoolCode: 'SCH-01',
          name: 'Active School 1',
          status: SchoolStatus.active,
          createdAt: DateTime(2026, 1, 1),
        ),
        SchoolModel(
          id: '2',
          schoolCode: 'SCH-02',
          name: 'Active School 2',
          status: SchoolStatus.active,
          createdAt: DateTime(2026, 1, 2),
        ),
        SchoolModel(
          id: '3',
          schoolCode: 'SCH-03',
          name: 'Inactive School',
          status: SchoolStatus.inactive,
          createdAt: DateTime(2026, 1, 3),
        ),
        SchoolModel(
          id: '4',
          schoolCode: 'SCH-04',
          name: 'Suspended School',
          status: SchoolStatus.suspended,
          createdAt: DateTime(2026, 1, 4),
        ),
      ];

      final stats = DashboardStats.fromAggregates(
        schools: schools,
        totalApps: 3,
        activeApps: 3,
        totalSubscriptions: 3,
        activeSubscriptions: 3,
        expiredSubscriptions: 0,
      );

      expect(stats.totalSchools, equals(4));
      expect(stats.activeSchools, equals(2));
      expect(stats.inactiveSchools, equals(1));
      expect(stats.suspendedSchools, equals(1));
      expect(stats.recentSchools.length, equals(4));
      expect(stats.recentSchools.first.schoolCode, equals('SCH-04'));
    });

    test('7. DashboardStats correctly aggregates app and subscription metrics', () {
      final stats = DashboardStats.fromAggregates(
        schools: [],
        totalApps: 8,
        activeApps: 7,
        totalSubscriptions: 10,
        activeSubscriptions: 9,
        expiredSubscriptions: 1,
      );

      expect(stats.totalApps, equals(8));
      expect(stats.activeApps, equals(7));
      expect(stats.totalSubscriptions, equals(10));
      expect(stats.activeSubscriptions, equals(9));
      expect(stats.expiredSubscriptions, equals(1));
    });

    test('8. Empty database state does not crash DashboardStats', () {
      final stats = DashboardStats.empty;
      expect(stats.totalSchools, equals(0));
      expect(stats.activeSchools, equals(0));
      expect(stats.totalApps, equals(0));
      expect(stats.activeApps, equals(0));
      expect(stats.totalSubscriptions, equals(0));
      expect(stats.activeSubscriptions, equals(0));
      expect(stats.expiredSubscriptions, equals(0));
      expect(stats.recentSchools, isEmpty);
    });

    test('9. Recent schools list is sorted descending by creation date up to 5 items', () {
      final schools = List.generate(
        10,
        (i) => SchoolModel(
          id: '$i',
          schoolCode: 'SCH-0$i',
          name: 'School $i',
          status: SchoolStatus.active,
          createdAt: DateTime(2026, 1, i + 1),
        ),
      );

      final stats = DashboardStats.fromAggregates(
        schools: schools,
        totalApps: 10,
        activeApps: 10,
      );

      expect(stats.recentSchools.length, equals(5));
      expect(stats.recentSchools.first.schoolCode, equals('SCH-09'));
      expect(stats.recentSchools.last.schoolCode, equals('SCH-05'));
    });

    test('10. Uninitialized database service returns controlled failure instead of fabricating metrics', () async {
      final dashboardService = DashboardService();
      final result = await dashboardService.fetchDashboardStats();

      expect(result.isFailure, isTrue);
      expect(result.dataOrNull, isNull);
      expect(result.errorOrNull, contains('Database service is uninitialized'));
    });
  });
}
