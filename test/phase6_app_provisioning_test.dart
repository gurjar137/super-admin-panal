import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_admin_app/core/config/supabase_config.dart';
import 'package:super_admin_app/models/school_app_model.dart';
import 'package:super_admin_app/models/school_model.dart';
import 'package:super_admin_app/models/subscription_model.dart';
import 'package:super_admin_app/services/school_app_service.dart';

void main() {
  group('Phase 6: SchoolAppService Generator & Validator Tests', () {
    test('generateDefaultAppIdentifier formats names deterministically and appends _APP', () {
      expect(
        SchoolAppService.generateDefaultAppIdentifier('ABC Public School'),
        'ABC_PUBLIC_SCHOOL_APP',
      );
      expect(
        SchoolAppService.generateDefaultAppIdentifier("St. Xavier's High School"),
        'ST_XAVIER_S_HIGH_SCHOOL_APP',
      );
      expect(
        SchoolAppService.generateDefaultAppIdentifier('Delhi Public School - DPS'),
        'DELHI_PUBLIC_SCHOOL_DPS_APP',
      );
      expect(
        SchoolAppService.generateDefaultAppIdentifier('SPRINGDALE_APP'),
        'SPRINGDALE_APP',
      );
      expect(
        SchoolAppService.generateDefaultAppIdentifier(''),
        'SCHOOL_APP',
      );
      expect(
        SchoolAppService.generateDefaultAppIdentifier('   '),
        'SCHOOL_APP',
      );
    });

    test('generateDefaultPackageName generates valid lowercase reverse-domain format', () {
      expect(
        SchoolAppService.generateDefaultPackageName('ABC Public School'),
        'com.company.abcpublicschool',
      );
      expect(
        SchoolAppService.generateDefaultPackageName("St. Xavier's High School"),
        'com.company.stxaviershighschool',
      );
      expect(
        SchoolAppService.generateDefaultPackageName('Green Valley', prefix: 'com.schoolos'),
        'com.schoolos.greenvalley',
      );
      expect(
        SchoolAppService.generateDefaultPackageName(''),
        'com.company.schoolapp',
      );
    });

    test('isValidPackageName strictly validates Android package naming rules', () {
      expect(SchoolAppService.isValidPackageName('com.company.abcschool'), isTrue);
      expect(SchoolAppService.isValidPackageName('in.gov.education.portal'), isTrue);
      expect(SchoolAppService.isValidPackageName('org.school_name.app'), isTrue);

      expect(SchoolAppService.isValidPackageName('com'), isFalse);
      expect(SchoolAppService.isValidPackageName('com.'), isFalse);
      expect(SchoolAppService.isValidPackageName('.com.app'), isFalse);
      expect(SchoolAppService.isValidPackageName('com..app'), isFalse);
      expect(SchoolAppService.isValidPackageName('com.company.SchoolApp'), isFalse);
      expect(SchoolAppService.isValidPackageName('com.company.school-app'), isFalse);
      expect(SchoolAppService.isValidPackageName(''), isFalse);
    });

    test('isValidVersion validates semantic versioning strings', () {
      expect(SchoolAppService.isValidVersion('1.0.0'), isTrue);
      expect(SchoolAppService.isValidVersion('2.1.0+4'), isTrue);
      expect(SchoolAppService.isValidVersion('0.9.12'), isTrue);

      expect(SchoolAppService.isValidVersion(''), isFalse);
      expect(SchoolAppService.isValidVersion('v1.0.0'), isFalse);
      expect(SchoolAppService.isValidVersion('beta'), isFalse);
    });

    test('isValidPlayStoreUrl accepts valid URLs or empty string', () {
      expect(
        SchoolAppService.isValidPlayStoreUrl(
          'https://play.google.com/store/apps/details?id=com.company.abcschool',
        ),
        isTrue,
      );
      expect(SchoolAppService.isValidPlayStoreUrl('http://example.com/app'), isTrue);
      expect(SchoolAppService.isValidPlayStoreUrl(''), isTrue);
      expect(SchoolAppService.isValidPlayStoreUrl('   '), isTrue);

      expect(SchoolAppService.isValidPlayStoreUrl('play.google.com/store'), isFalse);
      expect(SchoolAppService.isValidPlayStoreUrl('ftp://example.com/app'), isFalse);
    });
  });

  group('Phase 6: Developer Configuration & Credential Safety Tests', () {
    test('Developer configuration uses only safe publishable keys and no secrets', () {
      final app = SchoolAppModel(
        id: 'app-uuid-101',
        schoolId: 'sch-uuid-999',
        schoolName: 'Horizon Academy',
        appName: 'Horizon Academy App',
        appIdentifier: 'HORIZON_ACADEMY_APP',
        packageName: 'com.company.horizonacademy',
        currentVersion: '1.2.0',
        playStoreUrl: 'https://play.google.com/store/apps/details?id=com.company.horizonacademy',
        status: SchoolAppStatus.active,
        createdAt: DateTime.parse('2026-03-01T00:00:00Z'),
      );

      final config = {
        'SCHOOL_ID': app.schoolId,
        'APP_IDENTIFIER': app.appIdentifier,
        'APP_NAME': app.appName,
        'PACKAGE_NAME': app.packageName,
        'CURRENT_VERSION': app.currentVersion,
        'SUPABASE_URL': SupabaseConfig.url,
        'SUPABASE_ANON_KEY': SupabaseConfig.publishableKey,
      };

      final jsonString = const JsonEncoder.withIndent('  ').convert(config);

      // Verify essential properties are present
      expect(jsonString, contains('HORIZON_ACADEMY_APP'));
      expect(jsonString, contains('sch-uuid-999'));
      expect(jsonString, contains('com.company.horizonacademy'));
      expect(jsonString, contains('SUPABASE_URL'));
      expect(jsonString, contains('SUPABASE_ANON_KEY'));

      // CRITICAL: Verify NO backend secret keys or passwords leak
      expect(jsonString.toLowerCase(), isNot(contains('service_role')));
      expect(jsonString.toLowerCase(), isNot(contains('service_role_key')));
      expect(jsonString.toLowerCase(), isNot(contains('postgres_password')));
      expect(jsonString.toLowerCase(), isNot(contains('db_password')));
      expect(jsonString.toLowerCase(), isNot(contains('secret_key')));
    });

    test('SchoolAppModel maintains immutable schoolId association', () {
      final original = SchoolAppModel(
        id: 'app-1',
        schoolId: 'fixed-school-id',
        schoolName: 'Central High',
        appName: 'Central High App',
        appIdentifier: 'CENTRAL_HIGH_APP',
        packageName: 'com.company.centralhigh',
        status: SchoolAppStatus.active,
        createdAt: DateTime.now(),
      );

      // copyWith without schoolId maintains original schoolId
      final updated = original.copyWith(
        appName: 'Central High Mobile',
        currentVersion: '2.0.0',
      );

      expect(updated.schoolId, 'fixed-school-id');
      expect(updated.appName, 'Central High Mobile');
      expect(updated.currentVersion, '2.0.0');
    });
  });

  group('Phase 6: Operational Summary Status Logic Tests', () {
    test('School with active app and active subscription resolves to fully granted access', () {
      final school = SchoolModel(
        id: 'sch-1',
        schoolCode: 'SCH001',
        name: 'Grand Academy',
        status: SchoolStatus.active,
        createdAt: DateTime.now(),
      );

      final app = SchoolAppModel(
        id: 'app-1',
        schoolId: 'sch-1',
        appName: 'Grand Academy App',
        appIdentifier: 'GRAND_ACADEMY_APP',
        packageName: 'com.company.grandacademy',
        status: SchoolAppStatus.active,
        createdAt: DateTime.now(),
      );

      final subscription = SubscriptionModel(
        id: 'sub-1',
        schoolAppId: 'app-1',
        schoolId: 'sch-1',
        schoolName: 'Grand Academy',
        status: SubscriptionStatus.active,
        planName: 'Enterprise Annual',
        startDate: DateTime.now().subtract(const Duration(days: 10)),
        endDate: DateTime.now().add(const Duration(days: 90)),
        createdAt: DateTime.now(),
      );

      final isSchoolActive = school.status == SchoolStatus.active;
      final isAppActive = app.status == SchoolAppStatus.active;
      final isSubActive = subscription.status == SubscriptionStatus.active && subscription.isDateActive;
      final isGranted = isSchoolActive && isAppActive && isSubActive;

      expect(isGranted, isTrue);
    });

    test('School with inactive status or inactive app blocks access even with active subscription', () {
      final inactiveSchool = SchoolModel(
        id: 'sch-2',
        schoolCode: 'SCH002',
        name: 'Suspended Academy',
        status: SchoolStatus.suspended,
        createdAt: DateTime.now(),
      );

      final app = SchoolAppModel(
        id: 'app-2',
        schoolId: 'sch-2',
        appName: 'Suspended Academy App',
        appIdentifier: 'SUSPENDED_ACADEMY_APP',
        status: SchoolAppStatus.active,
        createdAt: DateTime.now(),
      );

      final subscription = SubscriptionModel(
        id: 'sub-2',
        schoolAppId: 'app-2',
        schoolId: 'sch-2',
        schoolName: 'Suspended Academy',
        status: SubscriptionStatus.active,
        planName: 'Annual',
        startDate: DateTime.now().subtract(const Duration(days: 10)),
        endDate: DateTime.now().add(const Duration(days: 30)),
        createdAt: DateTime.now(),
      );

      final isSchoolActive = inactiveSchool.status == SchoolStatus.active;
      final isAppActive = app.status == SchoolAppStatus.active;
      final isSubActive = subscription.status == SubscriptionStatus.active;
      final isGranted = isSchoolActive && isAppActive && isSubActive;

      expect(isGranted, isFalse);
    });
  });
}
