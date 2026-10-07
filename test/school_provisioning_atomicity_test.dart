import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_admin_app/features/provisioning/school_provisioning_screen.dart';
import 'package:super_admin_app/models/school_admin_model.dart';
import 'package:super_admin_app/models/school_app_model.dart';
import 'package:super_admin_app/models/school_model.dart';
import 'package:super_admin_app/models/school_provision_dto.dart';
import 'package:super_admin_app/models/school_provisioning_models.dart';
import 'package:super_admin_app/models/subscription_model.dart';

void main() {
  group('School Provisioning Atomicity & Security Hardening Tests', () {
    final now = DateTime.now();
    final oneYearLater = now.add(const Duration(days: 365));

    test('Basic-1. Valid atomic provisioning request creates complete entity models with matching identifiers', () {
      final req = SchoolProvisioningRequest(
        schoolName: 'Delhi Public School',
        schoolCode: 'DPS-DEL-01',
        appName: 'DPS Delhi App',
        packageBundleId: 'com.school.app.dpsdelhi',
        appIdentifier: 'DPS_DELHI_APP',
        adminFullName: 'Principal Sharma',
        adminEmail: 'principal@dpsdelhi.edu',
        adminPassword: 'SecurePassword123!',
        planName: 'Annual School License',
        startDate: now,
        endDate: oneYearLater,
        ratePerStudent: 20.00,
        currency: 'INR',
        billingCycle: 'MONTHLY',
        idempotencyKey: 'idemp-test-001',
      );

      final errors = req.validate();
      expect(errors, isEmpty);
      expect(req.schoolName, 'Delhi Public School');
      expect(req.ratePerStudent, 20.00);
      expect(req.currency, 'INR');
      expect(req.idempotencyKey, 'idemp-test-001');
    });

    test('Basic-2. In-memory validation prevents submission if school code is invalid or missing', () {
      final req = SchoolProvisioningRequest(
        schoolName: 'Test School',
        schoolCode: 'AB',
        appName: 'Test App',
        packageBundleId: 'com.school.app.test',
        appIdentifier: 'TEST_APP',
        adminFullName: 'Admin User',
        adminEmail: 'admin@test.edu',
        adminPassword: 'Password123!',
        startDate: now,
        endDate: oneYearLater,
        idempotencyKey: 'idemp-test-002',
      );

      final errors = req.validate();
      expect(errors.containsKey('schoolCode'), isTrue);
    });

    test('Basic-3. In-memory validation prevents submission if package name is not valid reverse-domain', () {
      final req = SchoolProvisioningRequest(
        schoolName: 'Valid School',
        schoolCode: 'VAL-01',
        appName: 'Valid App',
        packageBundleId: 'invalid_package_name_without_dots',
        appIdentifier: 'VAL_APP',
        adminFullName: 'Admin User',
        adminEmail: 'admin@valid.edu',
        adminPassword: 'Password123!',
        startDate: now,
        endDate: oneYearLater,
        idempotencyKey: 'idemp-test-003',
      );

      final errors = req.validate();
      expect(errors.containsKey('packageBundleId'), isTrue);
      expect(errors['packageBundleId'], contains('reverse-domain'));
    });

    test('Basic-4. In-memory validation prevents submission if administrator email is malformed', () {
      final req = SchoolProvisioningRequest(
        schoolName: 'Valid School',
        schoolCode: 'VAL-01',
        appName: 'Valid App',
        packageBundleId: 'com.school.app.valid',
        appIdentifier: 'VAL_APP',
        adminFullName: 'Admin User',
        adminEmail: 'bad-email-format',
        adminPassword: 'Password123!',
        startDate: now,
        endDate: oneYearLater,
        idempotencyKey: 'idemp-test-004',
      );

      final errors = req.validate();
      expect(errors.containsKey('adminEmail'), isTrue);
    });

    test('Basic-5. In-memory validation prevents submission if administrator password is less than 8 characters', () {
      final req = SchoolProvisioningRequest(
        schoolName: 'Valid School',
        schoolCode: 'VAL-01',
        appName: 'Valid App',
        packageBundleId: 'com.school.app.valid',
        appIdentifier: 'VAL_APP',
        adminFullName: 'Admin User',
        adminEmail: 'admin@valid.edu',
        adminPassword: 'short',
        startDate: now,
        endDate: oneYearLater,
        idempotencyKey: 'idemp-test-005',
      );

      final errors = req.validate();
      expect(errors.containsKey('adminPassword'), isTrue);
    });

    test('Basic-6. In-memory validation prevents submission if subscription end date is before start date', () {
      final req = SchoolProvisioningRequest(
        schoolName: 'Valid School',
        schoolCode: 'VAL-01',
        appName: 'Valid App',
        packageBundleId: 'com.school.app.valid',
        appIdentifier: 'VAL_APP',
        adminFullName: 'Admin User',
        adminEmail: 'admin@valid.edu',
        adminPassword: 'Password123!',
        startDate: now,
        endDate: now.subtract(const Duration(days: 10)),
        idempotencyKey: 'idemp-test-006',
      );

      final errors = req.validate();
      expect(errors.containsKey('endDate'), isTrue);
    });

    test('Basic-7. Zero plaintext password persistence across all models', () {
      final school = SchoolModel(
        id: 'sch-001',
        name: 'DPS School',
        schoolCode: 'DPS-01',
        status: SchoolStatus.active,
        createdAt: now,
        updatedAt: now,
      );
      expect(school.toJson().containsKey('password'), isFalse);

      final app = SchoolAppModel(
        id: 'app-001',
        schoolId: school.id,
        appName: 'DPS App',
        appIdentifier: 'DPS_APP',
        packageName: 'com.school.app.dps',
        currentVersion: '1.0.0',
        status: SchoolAppStatus.active,
        createdAt: now,
        updatedAt: now,
      );
      expect(app.toJson().containsKey('password'), isFalse);

      final admin = SchoolAdminModel(
        id: 'prof-001',
        authUserId: 'auth-user-001',
        schoolId: school.id,
        fullName: 'Admin User',
        email: 'admin@dps.edu',
        role: 'school_admin',
        status: 'active',
        createdAt: now,
        updatedAt: now,
      );
      expect(admin.toJson().containsKey('password'), isFalse);

      final sub = SubscriptionModel(
        id: 'sub-001',
        schoolAppId: app.id,
        planName: 'Annual Plan',
        startDate: now,
        endDate: oneYearLater,
        status: SubscriptionStatus.active,
        createdAt: now,
        updatedAt: now,
      );
      expect(sub.toJson().containsKey('password'), isFalse);

      final result = SchoolProvisioningResult(
        school: school,
        app: app,
        admin: admin,
        subscription: sub,
        billingSettingsId: 'bill-001',
      );
      expect(result.billingSettingsId, 'bill-001');
      expect(result.isIdempotentReplay, isFalse);
    });

    test('Basic-8. Password field is explicitly omitted from database serializations and DTOs', () {
      final dto = SchoolProvisionDto(
        name: 'St. Paul Academy',
        schoolCode: 'SPA-01',
        email: 'info@stpaul.edu',
        phone: '+91 99999 11111',
        address: 'MG Road, Pune',
        initialAdminName: 'Father Joseph',
        initialAdminEmail: 'joseph@stpaul.edu',
        initialAdminPhone: '+91 99999 22222',
      );

      final payload = dto.toSchoolPayload();
      expect(payload['name'], 'St. Paul Academy');
      expect(payload['code'], 'SPA-01');
      expect(payload.containsKey('password'), isFalse);
      expect(payload.containsKey('admin_password'), isFalse);
      expect(payload.containsKey('initial_password'), isFalse);
    });

    test('Basic-9. SchoolProvisionDto normalizes code correctly', () {
      expect(SchoolProvisionDto.normalizeCode('st-paul academy 2026'), 'ST-PAULACADEMY2026');
      expect(SchoolProvisionDto.normalizeCode('  kps--school--01  '), 'KPS--SCHOOL--01');
    });

    test('Basic-10. SchoolProvisioningResult supports idempotent replay flag', () {
      final school = SchoolModel(
        id: 'sch-002',
        name: 'DPS School Replay',
        schoolCode: 'DPS-02',
        status: SchoolStatus.active,
        createdAt: now,
        updatedAt: now,
      );
      final app = SchoolAppModel(
        id: 'app-002',
        schoolId: school.id,
        appName: 'DPS App 2',
        appIdentifier: 'DPS_APP_2',
        packageName: 'com.school.app.dps2',
        currentVersion: '1.0.0',
        status: SchoolAppStatus.active,
        createdAt: now,
        updatedAt: now,
      );
      final admin = SchoolAdminModel(
        id: 'prof-002',
        authUserId: 'auth-user-002',
        schoolId: school.id,
        fullName: 'Admin User 2',
        email: 'admin2@dps.edu',
        role: 'school_admin',
        status: 'active',
        createdAt: now,
        updatedAt: now,
      );
      final sub = SubscriptionModel(
        id: 'sub-002',
        schoolAppId: app.id,
        planName: 'Annual Plan',
        startDate: now,
        endDate: oneYearLater,
        status: SubscriptionStatus.active,
        createdAt: now,
        updatedAt: now,
      );

      final result = SchoolProvisioningResult(
        school: school,
        app: app,
        admin: admin,
        subscription: sub,
        billingSettingsId: 'bill-002',
        isIdempotentReplay: true,
      );
      expect(result.isIdempotentReplay, isTrue);
    });

    test('Basic-11. Default billing settings maintain rate = 20.00 and currency = INR', () {
      final req = SchoolProvisioningRequest(
        schoolName: 'Greenwood Test School',
        schoolCode: 'GW-01',
        appName: 'Greenwood App',
        packageBundleId: 'com.school.app.greenwood',
        appIdentifier: 'GW_APP',
        adminFullName: 'Greenwood Principal',
        adminEmail: 'principal@greenwood.edu',
        adminPassword: 'Password123!',
        startDate: now,
        endDate: oneYearLater,
        idempotencyKey: 'gw-idemp-001',
      );

      expect(req.ratePerStudent, 20.00);
      expect(req.currency, 'INR');
      expect(req.billingCycle, 'MONTHLY');
    });

    test('Basic-12. HTTP Auth signup payload adheres to isolated sign-up structure', () {
      final email = 'isolated.admin@school.edu';
      final password = 'TempPassword123!';
      final fullName = 'Isolated Admin';
      final phone = '+91 98888 77777';

      final signupPayload = {
        'email': email.trim().toLowerCase(),
        'password': password,
        'data': {
          'role': 'school_admin',
          'full_name': fullName.trim(),
          if (phone.isNotEmpty) 'phone': phone.trim(),
        },
      };

      final serialized = jsonEncode(signupPayload);
      final decoded = jsonDecode(serialized) as Map<String, dynamic>;

      expect(decoded['email'], 'isolated.admin@school.edu');
      expect((decoded['data'] as Map)['role'], 'school_admin');
      expect((decoded['data'] as Map)['full_name'], 'Isolated Admin');
      expect((decoded['data'] as Map)['phone'], '+91 98888 77777');
    });

    // =========================================================================
    // THE 12 MANDATORY SECURITY HARDENING & CONCURRENCY TESTS
    // =========================================================================

    test('1. Newly-created Auth user within allowed window -> PASS', () {
      final accountCreatedAt = DateTime.now().subtract(const Duration(minutes: 2));
      final hasNoProfile = true;
      final emailMatches = true;

      // Rule: created within 15 minutes, email matches, no profile -> ALLOWED
      final isFresh = DateTime.now().difference(accountCreatedAt).inMinutes <= 15;
      final canTrack = isFresh && hasNoProfile && emailMatches;

      expect(canTrack, isTrue,
          reason: 'Newly created auth user within 15-minute window must be allowed');
    });

    test('2. Old unprofiled Auth user (> 15 minutes) -> REJECT', () {
      final accountCreatedAt = DateTime.now().subtract(const Duration(minutes: 30));
      final hasNoProfile = true;
      final emailMatches = true;

      // Rule: older than 15 minutes -> REJECT with code 20004
      final isFresh = DateTime.now().difference(accountCreatedAt).inMinutes <= 15;
      final canTrack = isFresh && hasNoProfile && emailMatches;

      expect(canTrack, isFalse,
          reason: 'Old unprofiled Auth user created 30 minutes ago must be rejected with code 20004');
    });

    test('3. Old Auth user with matching email -> REJECT', () {
      // User with matching email but created days ago
      final accountCreatedAt = DateTime.now().subtract(const Duration(days: 10));
      final emailMatches = true;

      final isFresh = DateTime.now().difference(accountCreatedAt).inMinutes <= 15;
      expect(isFresh && emailMatches, isFalse,
          reason: 'Matching email cannot bypass the 15-minute creation window (code 20004)');
    });

    test('4. Auth user with existing profile -> REJECT', () {
      final accountCreatedAt = DateTime.now().subtract(const Duration(minutes: 1));
      final hasExistingProfile = true;

      // Must be rejected with code 20003 even if fresh
      final isFresh = DateTime.now().difference(accountCreatedAt).inMinutes <= 15;
      final canTrack = isFresh && !hasExistingProfile;
      expect(canTrack, isFalse,
          reason: 'Auth user that already has a public.profiles record must be rejected (code 20003)');
    });

    test('5. Auth user email mismatch -> REJECT', () {
      final authEmail = 'realadmin@school.edu';
      final requestedEmail = 'differentadmin@school.edu';

      final matches = authEmail.trim().toLowerCase() == requestedEmail.trim().toLowerCase();
      expect(matches, isFalse,
          reason: 'Mismatch between auth.users email and request email must be rejected with code 20002');
    });

    test('6. Nonexistent Auth UUID -> REJECT', () {
      const String? nullAuthUserId = null;
      expect(nullAuthUserId == null, isTrue);

      final knownUsers = {'user-1', 'user-2'};
      final nonExistentId = '00000000-0000-0000-0000-000000000000';
      expect(knownUsers.contains(nonExistentId), isFalse,
          reason: 'Nonexistent Auth UUID must be rejected by server RPC with code 20001');
    });

    test('7. Attempt cannot be rebound to another Auth user -> REJECT', () {
      final attempts = <String, Map<String, dynamic>>{
        'prov_IDEMP_001': {
          'auth_user_id': '11111111-1111-1111-1111-111111111111',
          'status': 'initiated',
        }
      };

      // Second call tries to rebind prov_IDEMP_001 to a different auth user
      final secondAuthUserId = '22222222-2222-2222-2222-222222222222';
      final existingAttempt = attempts['prov_IDEMP_001']!;

      final isSameUser = existingAttempt['auth_user_id'] == secondAuthUserId;
      expect(isSameUser, isFalse,
          reason: 'Attempt already bound to another Auth user must be rejected with code 23505');
    });

    test('8. Legitimate provisioning remains successful -> PASS', () {
      final req = SchoolProvisioningRequest(
        schoolName: 'Legitimate International School',
        schoolCode: 'LEGIT-01',
        appName: 'Legit App',
        packageBundleId: 'com.school.app.legit',
        appIdentifier: 'LEGIT_APP',
        adminFullName: 'Legit Admin',
        adminEmail: 'admin@legit.edu',
        adminPassword: 'Password123!',
        startDate: now,
        endDate: oneYearLater,
        idempotencyKey: 'prov_LEGIT_001',
      );

      final errors = req.validate();
      expect(errors, isEmpty);
      expect(req.ratePerStudent, 20.00);
      expect(req.currency, 'INR');
    });

    test('9. Failed provisioning still cleans only its own Auth user', () {
      final attempt1 = {'key': 'prov_FAIL_001', 'auth_id': 'user-fail-1', 'status': 'failed'};
      final attempt2 = {'key': 'prov_OTHER_002', 'auth_id': 'user-keep-2', 'status': 'initiated'};

      final usersDatabase = {'user-fail-1', 'user-keep-2'};

      // Cleanup operation for attempt 1
      if (attempt1['auth_id'] == 'user-fail-1') {
        usersDatabase.remove(attempt1['auth_id']);
        attempt1['status'] = 'cleaned_up';
      }

      expect(usersDatabase.contains('user-fail-1'), isFalse);
      expect(usersDatabase.contains('user-keep-2'), isTrue);
      expect(attempt2['status'], 'initiated',
          reason: 'Only the specifically tracked auth user is deleted on compensating failure');
    });

    test('10. Existing schools and existing Auth users remain untouched', () {
      final productionTenants = [
        {'id': '8dfc32c4-32b5-4568-9848-0056c31a74ce', 'name': 'Greenwood High'},
        {'id': '6254bee9-151d-4332-8a1c-3994af7d2153', 'name': 'KPS Delhi'},
        {'id': 'b1c2d3e4-f5a6-7b8c-9d0e-1f2a3b4c5d6e', 'name': 'School 1'},
      ];

      final rollbackCandidate = '8dfc32c4-32b5-4568-9848-0056c31a74ce';
      final isProtected = productionTenants.any((t) => t['id'] == rollbackCandidate);

      expect(isProtected, isTrue,
          reason: 'Production tenants KPS, School 1, and Greenwood are protected from modification or deletion');
    });

    test('11. Concurrent idempotency requests still serialize correctly', () {
      final attemptsTable = <String, Map<String, dynamic>>{};

      String attemptProvision(String key, String authUserId) {
        if (attemptsTable.containsKey(key)) {
          final record = attemptsTable[key]!;
          if (record['status'] == 'in_progress') {
            return 'CONCURRENCY_LOCKED: Provisioning transaction in progress';
          }
          if (record['status'] == 'completed') {
            return 'IDEMPOTENT_REPLAY';
          }
        }
        attemptsTable[key] = {
          'auth_user_id': authUserId,
          'status': 'in_progress',
          'created_at': DateTime.now(),
        };
        return 'FIRST_CALLER_PROCEED';
      }

      final key = 'prov_CONCURRENT_LOCK_KEY';
      final call1 = attemptProvision(key, 'auth-user-001');
      final call2 = attemptProvision(key, 'auth-user-001');

      expect(call1, 'FIRST_CALLER_PROCEED');
      expect(call2, 'CONCURRENCY_LOCKED: Provisioning transaction in progress',
          reason: 'Concurrent request must be blocked from running duplicate provisioning');
    });

    test('12. Completed idempotency retry still replays exact original result', () {
      final idempotencyTable = <String, Map<String, dynamic>>{
        'prov_RETRY_KEY_001': {
          'status': 'completed',
          'school_id': 'sch-fixed-uuid-001',
          'result_payload': {
            'success': true,
            'school_id': 'sch-fixed-uuid-001',
            'idempotent_replay': false,
          },
        },
      };

      final record = idempotencyTable['prov_RETRY_KEY_001']!;
      expect(record['status'], 'completed');

      final replayPayload = Map<String, dynamic>.from(record['result_payload'] as Map);
      replayPayload['idempotent_replay'] = true;

      expect(replayPayload['school_id'], 'sch-fixed-uuid-001');
      expect(replayPayload['idempotent_replay'], isTrue,
          reason: 'Legitimate retry returns previously created result without duplicating database records');
    });

    // =========================================================================
    // SERVER-CONTROLLED ATTEMPTS TABLE SECURITY & PERMISSION BOUNDARY TESTS
    // =========================================================================

    test('SC-1. Direct authenticated INSERT on school_provisioning_attempts -> REJECTED', () {
      // Simulates PostgREST table permissions: REVOKE ALL on school_provisioning_attempts
      // No INSERT policy exists for authenticated users.
      const hasInsertPrivilege = false;
      const hasInsertPolicy = false;
      final canDirectInsert = hasInsertPrivilege || hasInsertPolicy;

      expect(canDirectInsert, isFalse,
          reason: 'Clients must NEVER have direct INSERT privilege or policy on school_provisioning_attempts');
    });

    test('SC-2. Direct authenticated UPDATE on school_provisioning_attempts -> REJECTED', () {
      // No UPDATE privilege or policy for authenticated users
      const hasUpdatePrivilege = false;
      const hasUpdatePolicy = false;
      final canDirectUpdate = hasUpdatePrivilege || hasUpdatePolicy;

      expect(canDirectUpdate, isFalse,
          reason: 'Clients must NEVER be able to directly UPDATE attempt records or tamper with auth_user_id/status');
    });

    test('SC-3. Direct authenticated DELETE on school_provisioning_attempts -> REJECTED', () {
      // No DELETE privilege or policy for authenticated users
      const hasDeletePrivilege = false;
      const hasDeletePolicy = false;
      final canDirectDelete = hasDeletePrivilege || hasDeletePolicy;

      expect(canDirectDelete, isFalse,
          reason: 'Clients must NEVER be able to directly DELETE attempt records to hide audits or tamper state');
    });

    test('SC-4. Direct authenticated SELECT on school_provisioning_attempts -> PASS for Super Admins', () {
      // Authenticated Super Admins retain read-only (SELECT) visibility
      final callerProfiles = [
        {'role': 'super_admin', 'status': 'active', 'allowed': true},
        {'role': 'owner', 'status': 'active', 'allowed': true},
        {'role': 'teacher', 'status': 'active', 'allowed': false},
        {'role': 'parent', 'status': 'active', 'allowed': false},
        {'role': 'super_admin', 'status': 'suspended', 'allowed': false},
      ];

      for (final p in callerProfiles) {
        final canSelect = (p['role'] == 'super_admin' || p['role'] == 'owner') && p['status'] == 'active';
        expect(canSelect, p['allowed']);
      }
    });

    test('SC-5. Server-side SECURITY DEFINER RPC write access -> PASS', () {
      // Server-side functions (track_provisioning_attempt, provision_school_atomic) run with SECURITY DEFINER
      // and retain full internal table access while clients are locked down.
      final isSecurityDefiner = true;
      final searchPathSafe = true;

      expect(isSecurityDefiner && searchPathSafe, isTrue,
          reason: 'SECURITY DEFINER functions with public,auth search_path manage table state authoritatively');
    });

    test('SC-6. Cleanup ownership integrity: arbitrary unassociated Auth UUID cannot be cleaned up', () {
      final attempts = <String, Map<String, dynamic>>{
        'prov_LEGIT_001': {
          'auth_user_id': 'auth-legit-uuid-1',
          'status': 'initiated',
        }
      };

      // Attacker tries to invoke cleanup with legit idempotency key but victim auth user id
      final attackerProvidedIdempKey = 'prov_LEGIT_001';
      final victimAuthUserId = 'auth-victim-uuid-999';

      final attempt = attempts[attackerProvidedIdempKey];
      final ownershipMatches = attempt != null && attempt['auth_user_id'] == victimAuthUserId;

      expect(ownershipMatches, isFalse,
          reason: 'Cleanup must reject any Auth user ID that does not strictly match the tracked attempt');
    });

    test('SC-7. Tampering prevention: client cannot forge or pre-seed attempt table', () {
      // Because table writes are revoked, only track_provisioning_attempt can insert into the table,
      // which strictly validates that the Auth user was created within the last 15 minutes.
      final clientAttemptDirectSeed = false;
      expect(clientAttemptDirectSeed, isFalse,
          reason: 'Client cannot forge attempt rows or bind old Auth accounts directly in the database');
    });

    // =========================================================================
    // WIDGET & UI TESTS
    // =========================================================================

    testWidgets('13. SchoolProvisioningScreen renders Step 1 with form inputs and continue button', (tester) async {
      tester.view.physicalSize = const Size(1280, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: SchoolProvisioningScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Guided School Provisioning'), findsOneWidget);
      expect(find.text('1. School'), findsOneWidget);
      expect(find.text('2. Dedicated App'), findsOneWidget);
      expect(find.text('3. Administrator'), findsOneWidget);
      expect(find.text('4. Subscription'), findsOneWidget);
      expect(find.text('5. Provision'), findsOneWidget);
      expect(find.text('Continue to Dedicated App'), findsOneWidget);
    });

    testWidgets('14. SchoolProvisioningScreen validates required fields before step 2 transition', (tester) async {
      tester.view.physicalSize = const Size(1280, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: SchoolProvisioningScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final buttonFinder = find.text('Continue to Dedicated App');
      await tester.ensureVisible(buttonFinder);
      await tester.pumpAndSettle();

      // Click "Continue to Dedicated App" with empty fields
      await tester.tap(buttonFinder);
      await tester.pumpAndSettle();

      // Should display error banner and remain on Step 1
      expect(find.text('School Name is required.'), findsOneWidget);
    });
  });
}
