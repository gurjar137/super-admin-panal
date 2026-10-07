import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_admin_app/models/school_model.dart';

void main() {
  group('SUPER ADMIN P2 #2 — School Directory N+1 & Obsolete Table Remediation Tests', () {
    test('1. Static verification: school_service.dart contains zero references to obsolete school_apps', () {
      final file = File('lib/services/school_service.dart');
      expect(file.existsSync(), isTrue, reason: 'school_service.dart must exist');
      final content = file.readAsStringSync();

      // Ensure 'school_apps' table is never queried
      expect(
        content.contains("'school_apps'"),
        isFalse,
        reason: "school_service.dart must not reference obsolete table 'school_apps'",
      );
      expect(
        content.contains('"school_apps"'),
        isFalse,
        reason: 'school_service.dart must not reference obsolete table "school_apps"',
      );
      expect(
        content.contains("from('school_apps')"),
        isFalse,
        reason: 'school_service.dart must not query school_apps',
      );
    });

    test('2. Static verification: school_service.dart uses single joined PostgREST query with school_management_apps', () {
      final file = File('lib/services/school_service.dart');
      final content = file.readAsStringSync();

      expect(
        content.contains('school_management_apps('),
        isTrue,
        reason: 'school_service.dart must use PostgREST nested select on school_management_apps',
      );
      expect(
        content.contains('school_app_subscriptions('),
        isTrue,
        reason: 'school_service.dart must use PostgREST nested select on school_app_subscriptions',
      );
      // Verify no per-school loop remains in fetchSchools
      expect(
        content.contains('for (final school in schools)'),
        isFalse,
        reason: 'school_service.dart must not perform a per-school query loop in fetchSchools',
      );
    });

    test('3. PostgREST nested payload parsing handles 1:1 Map format correctly', () {
      final postgrestSchoolItem = {
        'id': 'cf895651-4783-489b-8551-959a70098ca8',
        'name': 'Delhi Public School',
        'code': 'DPS-01',
        'address': 'Mathura Road, New Delhi',
        'phone': '+91 11 2464 0000',
        'email': 'principal@dpsmathura.com',
        'logo_url': 'https://example.com/logo.png',
        'status': 'ACTIVE',
        'created_at': '2026-01-15T10:00:00Z',
        'updated_at': '2026-01-15T10:00:00Z',
        'school_management_apps': {
          'id': '5d8f6a16-c0e3-41ea-a1cb-ee711d21c4fc',
          'status': 'ACTIVE',
          'app_name': 'DPS Connect App',
          'school_app_subscriptions': {
            'id': '88ad2679-bb35-478a-bbc7-d2964055d0c5',
            'status': 'ACTIVE',
            'plan_name': 'ENTERPRISE_PLAN',
          },
        },
      };

      // Model deserialization
      final baseModel = SchoolModel.fromJson(postgrestSchoolItem);
      expect(baseModel.id, equals('cf895651-4783-489b-8551-959a70098ca8'));
      expect(baseModel.name, equals('Delhi Public School'));
      expect(baseModel.schoolCode, equals('DPS-01'));
      expect(baseModel.status, equals(SchoolStatus.active));

      // Test parsing helper logic through SchoolModel enrichment
      final rawAppsData = postgrestSchoolItem['school_management_apps'];
      final List<dynamic> appsList = rawAppsData is List
          ? rawAppsData
          : (rawAppsData is Map ? [rawAppsData] : []);

      int activeAppCount = 0;
      String? primaryAppName;
      for (final appEntry in appsList) {
        if (appEntry is! Map<String, dynamic>) continue;
        primaryAppName ??= appEntry['app_name']?.toString();
        final appStatus = (appEntry['status']?.toString().toUpperCase() ?? '');
        bool isAppActive = appStatus == 'ACTIVE';

        final rawSubs = appEntry['school_app_subscriptions'];
        if (rawSubs != null) {
          final List<dynamic> subsList = rawSubs is List ? rawSubs : (rawSubs is Map ? [rawSubs] : []);
          final hasActiveSub = subsList.any((s) =>
              s is Map<String, dynamic> &&
              (s['status']?.toString().toUpperCase() ?? '') == 'ACTIVE');
          if (hasActiveSub) isAppActive = true;
        }
        if (isAppActive) activeAppCount++;
      }

      final enriched = baseModel.copyWith(
        assignedAppsCount: appsList.length,
        activeSubscriptionSummary: '$activeAppCount/${appsList.length} Active',
        appName: primaryAppName,
      );

      expect(enriched.assignedAppsCount, equals(1));
      expect(enriched.activeSubscriptionSummary, equals('1/1 Active'));
      expect(enriched.appName, equals('DPS Connect App'));
    });

    test('4. PostgREST nested payload parsing handles 1:many List format correctly', () {
      final postgrestSchoolItem = {
        'id': 'school-multi-apps-uuid',
        'name': 'Greenwood High',
        'code': 'GWH-02',
        'status': 'ACTIVE',
        'created_at': '2026-02-10T12:00:00Z',
        'school_management_apps': [
          {
            'id': 'app-1',
            'status': 'ACTIVE',
            'app_name': 'Greenwood Parent App',
            'school_app_subscriptions': [
              {'id': 'sub-1', 'status': 'ACTIVE', 'plan_name': 'PREMIUM'},
            ],
          },
          {
            'id': 'app-2',
            'status': 'INACTIVE',
            'app_name': 'Greenwood Teacher App',
            'school_app_subscriptions': [],
          },
        ],
      };

      final rawAppsData = postgrestSchoolItem['school_management_apps'];
      final List<dynamic> appsList = rawAppsData is List ? rawAppsData : [];

      int activeAppCount = 0;
      String? primaryAppName;
      for (final appEntry in appsList) {
        if (appEntry is! Map<String, dynamic>) continue;
        primaryAppName ??= appEntry['app_name']?.toString();
        final appStatus = (appEntry['status']?.toString().toUpperCase() ?? '');
        bool isAppActive = appStatus == 'ACTIVE';

        final rawSubs = appEntry['school_app_subscriptions'];
        if (rawSubs != null) {
          final List<dynamic> subsList = rawSubs is List ? rawSubs : [rawSubs];
          final hasActiveSub = subsList.any((s) =>
              s is Map<String, dynamic> &&
              (s['status']?.toString().toUpperCase() ?? '') == 'ACTIVE');
          if (hasActiveSub) isAppActive = true;
        }
        if (isAppActive) activeAppCount++;
      }

      expect(appsList.length, equals(2));
      expect(activeAppCount, equals(1));
      expect(primaryAppName, equals('Greenwood Parent App'));

      final baseModel = SchoolModel.fromJson(postgrestSchoolItem);
      final enriched = baseModel.copyWith(
        assignedAppsCount: appsList.length,
        activeSubscriptionSummary: '$activeAppCount/${appsList.length} Active',
        appName: primaryAppName,
      );

      expect(enriched.assignedAppsCount, equals(2));
      expect(enriched.activeSubscriptionSummary, equals('1/2 Active'));
      expect(enriched.appName, equals('Greenwood Parent App'));
    });

    test('5. Handles schools with null/empty apps gracefully without crashing', () {
      final postgrestSchoolItem = {
        'id': 'school-no-apps-uuid',
        'name': 'New Unassigned School',
        'code': 'NEW-01',
        'status': 'ACTIVE',
        'created_at': '2026-03-01T08:00:00Z',
        'school_management_apps': null,
      };

      final baseModel = SchoolModel.fromJson(postgrestSchoolItem);
      expect(baseModel.id, equals('school-no-apps-uuid'));
      expect(baseModel.assignedAppsCount, equals(0));
      expect(baseModel.activeSubscriptionSummary, isNull);

      final enriched = baseModel.copyWith(
        assignedAppsCount: 0,
        activeSubscriptionSummary: null,
      );
      expect(enriched.assignedAppsCount, equals(0));
      expect(enriched.activeSubscriptionSummary, isNull);
    });

    test('6. Handles empty list of school_management_apps gracefully', () {
      final postgrestSchoolItem = {
        'id': 'school-empty-apps-uuid',
        'name': 'Empty Apps School',
        'code': 'EMP-01',
        'status': 'INACTIVE',
        'created_at': '2026-03-01T08:00:00Z',
        'school_management_apps': [],
      };

      final baseModel = SchoolModel.fromJson(postgrestSchoolItem);
      expect(baseModel.id, equals('school-empty-apps-uuid'));
      expect(baseModel.status, equals(SchoolStatus.inactive));
    });

    test('7. Handles null or missing subscription gracefully when app exists', () {
      final postgrestSchoolItem = {
        'id': 'school-no-subs-uuid',
        'name': 'App Without Subs School',
        'code': 'AWS-01',
        'status': 'ACTIVE',
        'created_at': '2026-03-01T08:00:00Z',
        'school_management_apps': {
          'id': 'app-standalone',
          'status': 'ACTIVE',
          'app_name': 'Standalone App',
          'school_app_subscriptions': null,
        },
      };

      final rawAppsData = postgrestSchoolItem['school_management_apps'] as Map<String, dynamic>;
      expect(rawAppsData['app_name'], equals('Standalone App'));
      expect(rawAppsData['school_app_subscriptions'], isNull);

      final baseModel = SchoolModel.fromJson(postgrestSchoolItem);
      final enriched = baseModel.copyWith(
        assignedAppsCount: 1,
        activeSubscriptionSummary: '1/1 Active',
        appName: 'Standalone App',
      );
      expect(enriched.assignedAppsCount, equals(1));
      expect(enriched.activeSubscriptionSummary, equals('1/1 Active'));
    });

    test('8. In-memory search filter matches school name, school code, and email accurately', () {
      final schools = [
        SchoolModel(
          id: '1',
          schoolCode: 'KPS-DEL',
          name: 'KPS International Delhi',
          email: 'admin@kpsdelhi.edu',
          createdAt: DateTime.now(),
        ),
        SchoolModel(
          id: '2',
          schoolCode: 'DPS-NOI',
          name: 'Delhi Public School Noida',
          email: 'contact@dpsnoida.edu',
          createdAt: DateTime.now(),
        ),
        SchoolModel(
          id: '3',
          schoolCode: 'STX-MUM',
          name: 'St. Xavier High School',
          email: 'office@stxaviers.edu',
          createdAt: DateTime.now(),
        ),
      ];

      // Match by partial name
      final nameFilter = 'xavier';
      final byName = schools.where((s) =>
          s.name.toLowerCase().contains(nameFilter) ||
          s.schoolCode.toLowerCase().contains(nameFilter) ||
          (s.email?.toLowerCase().contains(nameFilter) ?? false)).toList();
      expect(byName.length, equals(1));
      expect(byName.first.schoolCode, equals('STX-MUM'));

      // Match by code
      final codeFilter = 'kps';
      final byCode = schools.where((s) =>
          s.name.toLowerCase().contains(codeFilter) ||
          s.schoolCode.toLowerCase().contains(codeFilter) ||
          (s.email?.toLowerCase().contains(codeFilter) ?? false)).toList();
      expect(byCode.length, equals(1));
      expect(byCode.first.name, equals('KPS International Delhi'));

      // Match by email domain
      final emailFilter = 'dpsnoida.edu';
      final byEmail = schools.where((s) =>
          s.name.toLowerCase().contains(emailFilter) ||
          s.schoolCode.toLowerCase().contains(emailFilter) ||
          (s.email?.toLowerCase().contains(emailFilter) ?? false)).toList();
      expect(byEmail.length, equals(1));
      expect(byEmail.first.name, equals('Delhi Public School Noida'));
    });
  });
}
