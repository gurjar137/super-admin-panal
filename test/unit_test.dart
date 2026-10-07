import 'package:flutter_test/flutter_test.dart';
import 'package:super_admin_app/models/dashboard_stats.dart';
import 'package:super_admin_app/models/school_app_model.dart';
import 'package:super_admin_app/models/school_model.dart';
import 'package:super_admin_app/models/school_provision_dto.dart';
import 'package:super_admin_app/models/school_app_access_result.dart';
import 'package:super_admin_app/models/subscription_model.dart';
import 'package:super_admin_app/models/super_admin_model.dart';

void main() {
  group('SchoolModel Tests', () {
    test('Correctly parses from JSON with verified Supabase columns', () {
      final json = {
        'id': 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
        'code': 'SCH001',
        'name': 'Greenwood International',
        'address': 'Ring Road Campus',
        'phone': '+91 99999 88888',
        'email': 'contact@greenwood.edu',
        'logo_url': 'https://example.com/logo.png',
        'primary_color': '#4F46E5',
        'secondary_color': '#0EA5E9',
        'status': 'ACTIVE',
        'created_at': '2026-01-01T00:00:00Z',
        'assigned_apps_count': 3,
        'active_subscription_summary': '3/3 Active',
      };

      final school = SchoolModel.fromJson(json);

      expect(school.id, 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11');
      expect(school.schoolCode, 'SCH001');
      expect(school.name, 'Greenwood International');
      expect(school.status, SchoolStatus.active);
      expect(school.primaryColor, '#4F46E5');
      expect(school.assignedAppsCount, 3);
      expect(school.activeSubscriptionSummary, '3/3 Active');
    });

    test('Parses fallback school_code column key', () {
      final json = {
        'id': 'b1eebc99-9c0b-4ef8-bb6d-6bb9bd380a22',
        'school_code': 'SCH002',
        'name': 'St. Jude Academy',
        'status': 'INACTIVE',
        'created_at': '2026-02-01T00:00:00Z',
      };

      final school = SchoolModel.fromJson(json);

      expect(school.schoolCode, 'SCH002');
      expect(school.status, SchoolStatus.inactive);
    });
  });

  group('SchoolAppModel Tests', () {
    test('Parses dedicated school app and preserves tenant school_id as key', () {
      final json = {
        'id': 'app-001',
        'school_id': 'uuid-tenant-123',
        'app_name': 'ABC Public School App',
        'package_name': 'com.company.abcschool',
        'app_identifier': 'ABC_SCHOOL_APP',
        'current_version': '2.1.0',
        'play_store_url': 'https://play.google.com/store/apps/details?id=com.company.abcschool',
        'status': 'ACTIVE',
        'notes': 'Custom release signed with production key',
        'created_at': '2026-03-01T00:00:00Z',
        'updated_at': '2026-03-02T00:00:00Z',
        'schools': {'name': 'ABC Public School'},
      };

      final app = SchoolAppModel.fromJson(json);
      expect(app.id, 'app-001');
      expect(app.schoolId, 'uuid-tenant-123'); // Authoritative tenant identifier
      expect(app.schoolName, 'ABC Public School');
      expect(app.appName, 'ABC Public School App');
      expect(app.appIdentifier, 'ABC_SCHOOL_APP');
      expect(app.packageName, 'com.company.abcschool');
      expect(app.currentVersion, '2.1.0');
      expect(app.isActive, isTrue);
      expect(app.status, SchoolAppStatus.active);
      expect(app.playStoreUrl, 'https://play.google.com/store/apps/details?id=com.company.abcschool');
    });

    test('Correctly handles INACTIVE status', () {
      final json = {
        'id': 'app-002',
        'school_id': 'uuid-tenant-456',
        'app_name': 'XYZ Academy App',
        'status': 'INACTIVE',
        'created_at': '2026-03-01T00:00:00Z',
      };

      final app = SchoolAppModel.fromJson(json);
      expect(app.isActive, isFalse);
      expect(app.status, SchoolAppStatus.inactive);
    });
  });

  group('SubscriptionModel Tests', () {
    test('Correctly evaluates active vs expired subscriptions', () {
      final activeSub = SubscriptionModel(
        id: 's1',
        schoolAppId: 'app-uuid-1',
        schoolId: 'uuid-1',
        schoolName: 'School 1',
        planName: 'Annual School License',
        status: SubscriptionStatus.active,
        startDate: DateTime.now().subtract(const Duration(days: 30)),
        endDate: DateTime.now().add(const Duration(days: 335)),
        createdAt: DateTime.now(),
      );
      expect(activeSub.isExpired, isFalse);
      expect(activeSub.isDateActive, isTrue);
      expect(activeSub.isDateExpired, isFalse);
      expect(activeSub.effectiveStatus, SubscriptionStatus.active);

      final expiredSub = SubscriptionModel(
        id: 's2',
        schoolAppId: 'app-uuid-2',
        schoolId: 'uuid-2',
        schoolName: 'School 2',
        planName: 'Annual School License',
        status: SubscriptionStatus.active,
        startDate: DateTime.now().subtract(const Duration(days: 400)),
        endDate: DateTime.now().subtract(const Duration(days: 35)),
        createdAt: DateTime.now(),
      );
      expect(expiredSub.isExpired, isTrue);
      expect(expiredSub.isDateExpired, isTrue);
      expect(expiredSub.isDateActive, isFalse);
      expect(expiredSub.effectiveStatus, SubscriptionStatus.expired);
    });

    test('Parses from JSON with school_app_subscriptions columns and join', () {
      final json = {
        'id': 'sub-100',
        'school_app_id': 'app-100',
        'plan_name': 'Enterprise 3-Year Plan',
        'status': 'ACTIVE',
        'start_date': '2026-01-01',
        'end_date': '2029-01-01',
        'notes': 'Prepaid contract',
        'created_at': '2026-01-01T00:00:00Z',
        'school_management_apps': {
          'id': 'app-100',
          'app_name': 'Delhi Public App',
          'school_id': 'sch-100',
          'schools': {'id': 'sch-100', 'name': 'Delhi Public School'},
        },
      };

      final sub = SubscriptionModel.fromJson(json);
      expect(sub.id, 'sub-100');
      expect(sub.schoolAppId, 'app-100');
      expect(sub.schoolId, 'sch-100');
      expect(sub.schoolName, 'Delhi Public School');
      expect(sub.appName, 'Delhi Public App');
      expect(sub.planName, 'Enterprise 3-Year Plan');
      expect(sub.status, SubscriptionStatus.active);
      expect(sub.notes, 'Prepaid contract');
    });
  });

  group('Effective Access Control Tests (Phase 4 Central Engine)', () {
    final validSubscription = SubscriptionModel(
      id: 'sub-active',
      schoolAppId: 'app-1',
      status: SubscriptionStatus.active,
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 12, 31),
      createdAt: DateTime(2026, 1, 1),
    );

    final referenceDate = DateTime(2026, 6, 15); // Mid-year within window

    test('Access GRANTED when School, App, and Subscription are all ACTIVE within date window', () {
      final result = evaluateSchoolManagementAppAccess(
        schoolStatus: SchoolStatus.active,
        appStatus: SchoolAppStatus.active,
        subscription: validSubscription,
        referenceDate: referenceDate,
      );

      expect(result.isGranted, isTrue);
      expect(result.code, SchoolAppAccessCode.granted);
      expect(result.userMessage, contains('Access Granted'));

      expect(
        isSchoolManagementAppAccessible(
          schoolStatus: SchoolStatus.active,
          appStatus: SchoolAppStatus.active,
          subscription: validSubscription,
          referenceDate: referenceDate,
        ),
        isTrue,
      );
    });

    test('Access BLOCKED when School is INACTIVE', () {
      final result = evaluateSchoolManagementAppAccess(
        schoolStatus: SchoolStatus.inactive,
        appStatus: SchoolAppStatus.active,
        subscription: validSubscription,
        referenceDate: referenceDate,
      );

      expect(result.isGranted, isFalse);
      expect(result.code, SchoolAppAccessCode.schoolInactive);
      expect(result.userMessage, 'School account is inactive.');
    });

    test('Access BLOCKED when Dedicated App is INACTIVE', () {
      final result = evaluateSchoolManagementAppAccess(
        schoolStatus: SchoolStatus.active,
        appStatus: SchoolAppStatus.inactive,
        subscription: validSubscription,
        referenceDate: referenceDate,
      );

      expect(result.isGranted, isFalse);
      expect(result.code, SchoolAppAccessCode.appInactive);
      expect(result.userMessage, 'Application access is currently disabled.');
    });

    test('Access BLOCKED when Subscription is NULL (Not provisioned)', () {
      final result = evaluateSchoolManagementAppAccess(
        schoolStatus: SchoolStatus.active,
        appStatus: SchoolAppStatus.active,
        subscription: null,
        referenceDate: referenceDate,
      );

      expect(result.isGranted, isFalse);
      expect(result.code, SchoolAppAccessCode.noSubscription);
      expect(result.userMessage, 'No subscription configured for this school app.');
    });

    test('Access BLOCKED when Subscription is SUSPENDED', () {
      final suspendedSub = validSubscription.copyWith(status: SubscriptionStatus.suspended);
      final result = evaluateSchoolManagementAppAccess(
        schoolStatus: SchoolStatus.active,
        appStatus: SchoolAppStatus.active,
        subscription: suspendedSub,
        referenceDate: referenceDate,
      );

      expect(result.isGranted, isFalse);
      expect(result.code, SchoolAppAccessCode.subscriptionSuspended);
      expect(result.userMessage, 'Application subscription has been suspended.');
    });

    test('Access BLOCKED when Subscription is INACTIVE', () {
      final inactiveSub = validSubscription.copyWith(status: SubscriptionStatus.inactive);
      final result = evaluateSchoolManagementAppAccess(
        schoolStatus: SchoolStatus.active,
        appStatus: SchoolAppStatus.active,
        subscription: inactiveSub,
        referenceDate: referenceDate,
      );

      expect(result.isGranted, isFalse);
      expect(result.code, SchoolAppAccessCode.subscriptionInactive);
      expect(result.userMessage, 'Application subscription is inactive.');
    });

    test('Access BLOCKED when date has not started yet', () {
      final beforeStartDate = DateTime(2025, 12, 1);
      final result = evaluateSchoolManagementAppAccess(
        schoolStatus: SchoolStatus.active,
        appStatus: SchoolAppStatus.active,
        subscription: validSubscription,
        referenceDate: beforeStartDate,
      );

      expect(result.isGranted, isFalse);
      expect(result.code, SchoolAppAccessCode.notStartedYet);
      expect(result.userMessage, 'Your subscription has not started yet.');
    });

    test('Access BLOCKED when subscription has expired past end date', () {
      final afterEndDate = DateTime(2027, 1, 15);
      final result = evaluateSchoolManagementAppAccess(
        schoolStatus: SchoolStatus.active,
        appStatus: SchoolAppStatus.active,
        subscription: validSubscription,
        referenceDate: afterEndDate,
      );

      expect(result.isGranted, isFalse);
      expect(result.code, SchoolAppAccessCode.subscriptionExpired);
      expect(result.userMessage, 'Your subscription has expired. Please contact the administrator.');
    });
  });

  group('SchoolProvisionDto Validation Tests', () {
    test('Normalizes school code to uppercase and alphanumeric', () {
      expect(SchoolProvisionDto.normalizeCode('  sch_001-del  '), 'SCH001-DEL');
      expect(SchoolProvisionDto.normalizeCode('st-mary@#2026'), 'ST-MARY2026');
    });

    test('Validates required fields', () {
      final dto = SchoolProvisionDto();
      final errors = dto.validate();

      expect(errors.containsKey('name'), isTrue);
      expect(errors.containsKey('schoolCode'), isTrue);
      expect(errors.containsKey('email'), isTrue);
      expect(errors.containsKey('phone'), isTrue);
      expect(errors.containsKey('address'), isTrue);
      expect(errors.containsKey('initialAdminName'), isTrue);
      expect(errors.containsKey('initialAdminEmail'), isTrue);
      expect(errors.containsKey('initialAdminPhone'), isTrue);
    });

    test('Passes validation when all fields are properly filled', () {
      final dto = SchoolProvisionDto(
        name: 'Apex Academy',
        schoolCode: 'APEX-01',
        email: 'info@apex.edu',
        phone: '+91 9876543210',
        address: 'Sector 62, Noida',
        initialAdminName: 'John Doe',
        initialAdminEmail: 'john@apex.edu',
        initialAdminPhone: '+91 9988776655',
      );

      final errors = dto.validate();
      expect(errors.isEmpty, isTrue);
    });
  });

  group('DashboardStats Tests', () {
    test('Accurately aggregates metrics across schools, products, assignments, and subscriptions', () {
      final schools = [
        SchoolModel(
          id: '1',
          schoolCode: 'S1',
          name: 'School One',
          status: SchoolStatus.active,
          createdAt: DateTime(2026, 1, 1),
        ),
        SchoolModel(
          id: '2',
          schoolCode: 'S2',
          name: 'School Two',
          status: SchoolStatus.active,
          createdAt: DateTime(2026, 1, 2),
        ),
        SchoolModel(
          id: '3',
          schoolCode: 'S3',
          name: 'School Three',
          status: SchoolStatus.inactive,
          createdAt: DateTime(2026, 1, 3),
        ),
        SchoolModel(
          id: '4',
          schoolCode: 'S4',
          name: 'School Four',
          status: SchoolStatus.suspended,
          createdAt: DateTime(2026, 1, 4),
        ),
      ];

      final stats = DashboardStats.fromAggregates(
        schools: schools,
        totalApps: 4,
        activeApps: 4,
        totalSubscriptions: 5,
        activeSubscriptions: 4,
        expiredSubscriptions: 1,
      );

      expect(stats.totalSchools, 4);
      expect(stats.activeSchools, 2);
      expect(stats.inactiveSchools, 1);
      expect(stats.suspendedSchools, 1);
      expect(stats.totalApps, 4);
      expect(stats.activeApps, 4);
      expect(stats.totalSubscriptions, 5);
      expect(stats.activeSubscriptions, 4);
      expect(stats.expiredSubscriptions, 1);
      expect(stats.recentSchools.length, 4);
      expect(stats.recentSchools.first.name, 'School Four');
    });
  });

  group('SuperAdminProfile Tests', () {
    test('Verifies super_admin and owner roles', () {
      final superAdmin = SuperAdminProfile(
        id: '1',
        authUserId: 'auth-1',
        email: 'admin@super.com',
        name: 'Master Admin',
        role: 'super_admin',
        status: 'active',
      );
      expect(superAdmin.isSuperAdmin, isTrue);

      final owner = SuperAdminProfile(
        id: '2',
        authUserId: 'auth-2',
        email: 'owner@schoolos.com',
        name: 'Platform Owner',
        role: 'owner',
        status: 'active',
      );
      expect(owner.isSuperAdmin, isTrue);

      final schoolAdmin = SuperAdminProfile(
        id: '3',
        authUserId: 'auth-3',
        email: 'school@local.edu',
        name: 'Principal',
        role: 'school_admin',
        status: 'active',
      );
      expect(schoolAdmin.isSuperAdmin, isFalse);
    });
  });
}
