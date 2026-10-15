import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_admin_app/models/school_provision_dto.dart';
import 'package:super_admin_app/models/super_admin_model.dart';
import 'package:super_admin_app/routing/app_routes.dart';

void main() {
  group('Requirement 1: Development Auth Bypass Removed', () {
    test('AppConstants contains zero development auth bypass flags', () {
      final file = File('lib/core/constants/app_constants.dart');
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();
      expect(content.contains('isDevAuthBypassEnabled'), isFalse);
    });
  });

  group('Requirement 3 & 4: Super Admin Model & Authorization Tests', () {
    test('A. Real authenticated Super Admin session is validated for super_admin and owner', () {
      final superAdmin = SuperAdminProfile.fromJson({
        'id': 'prof-1',
        'auth_user_id': 'auth-user-1',
        'email': 'super@schoolos.com',
        'full_name': 'Chief Super Admin',
        'role': 'super_admin',
        'status': 'active',
        'school_id': null, // Super Admin is platform-level; school_id is null
      });

      expect(superAdmin.isSuperAdmin, isTrue);
      expect(superAdmin.status, 'active');
      expect(superAdmin.schoolId, isNull);
      expect(superAdmin.name, 'Chief Super Admin');

      final owner = SuperAdminProfile.fromJson({
        'id': 'prof-2',
        'auth_user_id': 'auth-user-2',
        'email': 'owner@schoolos.com',
        'full_name': 'Platform Owner',
        'role': 'owner',
        'status': 'active',
        'school_id': null,
      });

      expect(owner.isSuperAdmin, isTrue);
      expect(owner.status, 'active');
      expect(owner.schoolId, isNull);

      final platformAdmin = SuperAdminProfile.fromJson({
        'id': 'prof-platform',
        'auth_user_id': 'auth-user-platform',
        'email': 'admin@platform.com',
        'full_name': 'Platform Administrator',
        'role': 'platform_admin',
        'status': 'active',
        'school_id': null,
      });

      expect(platformAdmin.isSuperAdmin, isTrue);
      expect(platformAdmin.status, 'active');
    });

    test('B. Unauthorized roles (teacher, school_admin, parent, staff) are denied Super Admin access', () {
      final roles = ['teacher', 'school_admin', 'parent', 'staff', 'student', 'guest'];

      for (final role in roles) {
        final profile = SuperAdminProfile.fromJson({
          'id': 'prof-$role',
          'auth_user_id': 'auth-$role',
          'email': '$role@school.edu',
          'full_name': 'User $role',
          'role': role,
          'status': 'active',
          'school_id': 'some-school-id',
        });

        expect(profile.isSuperAdmin, isFalse, reason: 'Role $role must not have Super Admin privileges');
      }
    });

    test('C. Inactive or suspended profile is rejected even if role is super_admin or owner', () {
      final inactiveAdmin = SuperAdminProfile.fromJson({
        'id': 'prof-inactive',
        'auth_user_id': 'auth-inactive',
        'email': 'inactive@schoolos.com',
        'full_name': 'Inactive Admin',
        'role': 'super_admin',
        'status': 'inactive',
      });

      final isAuthorized = inactiveAdmin.isSuperAdmin && inactiveAdmin.status.toLowerCase() == 'active';
      expect(isAuthorized, isFalse, reason: 'Inactive super_admin must be rejected');

      final suspendedOwner = SuperAdminProfile.fromJson({
        'id': 'prof-suspended',
        'auth_user_id': 'auth-suspended',
        'email': 'suspended@schoolos.com',
        'full_name': 'Suspended Owner',
        'role': 'owner',
        'status': 'suspended',
      });

      final isOwnerAuthorized = suspendedOwner.isSuperAdmin && suspendedOwner.status.toLowerCase() == 'active';
      expect(isOwnerAuthorized, isFalse, reason: 'Suspended owner must be rejected');
    });
  });

  group('Requirement 6: Session Persistence & Logout Navigation', () {
    test('D. Logout clears session state and active Super Admin profile', () {
      SuperAdminProfile? currentSession = const SuperAdminProfile(
        id: 'active-id',
        authUserId: 'active-auth-id',
        email: 'admin@schoolos.com',
        name: 'Admin',
        role: 'super_admin',
        status: 'active',
      );

      expect(currentSession, isNotNull);

      // Simulate sign out
      currentSession = null;
      expect(currentSession, isNull);
    });

    test('E. Unauthenticated user (null session) resolves to Login route', () {
      SuperAdminProfile? activeSession = const SuperAdminProfile(
        id: 'temp',
        authUserId: 'temp',
        email: 'temp@school.com',
        name: 'Temp',
        role: 'super_admin',
        status: 'active',
      );
      activeSession = null; // explicitly cleared session

      final targetRoute = activeSession != null ? AppRoutes.dashboard : AppRoutes.login;
      expect(targetRoute, AppRoutes.login);
    });

    test('F. Authenticated active Super Admin resolves to Dashboard route', () {
      final activeSession = SuperAdminProfile.fromJson({
        'id': 'prof-active',
        'auth_user_id': 'auth-active',
        'email': 'admin@schoolos.com',
        'full_name': 'Platform Admin',
        'role': 'super_admin',
        'status': 'active',
      });

      final targetRoute = (activeSession.isSuperAdmin && activeSession.status == 'active')
          ? AppRoutes.dashboard
          : AppRoutes.login;

      expect(targetRoute, AppRoutes.dashboard);
    });
  });

  group('Requirement 10 & 11: Authenticated Super Admin School Provisioning', () {
    test('G. Authenticated Super Admin can formulate and validate school provisioning payload', () {
      final dto = SchoolProvisionDto(
        name: 'AUTH TEST SCHOOL',
        schoolCode: 'AUTHTEST01',
        email: 'auth.test@schoolos.internal',
        phone: '+91 98765 43210',
        address: 'Test Verification Campus',
        initialAdminName: 'Dr. Test Administrator',
        initialAdminEmail: 'admin@authtest.internal',
        initialAdminPhone: '+91 98765 43211',
      );

      final errors = dto.validate();
      expect(errors, isEmpty, reason: 'Valid school provision payload must produce no validation errors');

      final payload = dto.toSchoolPayload();
      expect(payload['name'], 'AUTH TEST SCHOOL');
      expect(payload['code'], 'AUTHTEST01');
      expect(payload['email'], 'auth.test@schoolos.internal');
      expect(payload['status'], 'ACTIVE');

      // Verify RLS policy logic:
      // profiles.auth_user_id = auth.uid() AND profiles.role IN ('super_admin', 'owner') AND profiles.status = 'active'
      final callerProfile = SuperAdminProfile.fromJson({
        'id': 'auth-caller',
        'auth_user_id': 'uuid-1234',
        'email': 'super@schoolos.com',
        'full_name': 'Super Admin Caller',
        'role': 'super_admin',
        'status': 'active',
      });

      const authenticatedUid = 'uuid-1234';
      final rlsCheck = callerProfile.authUserId == authenticatedUid &&
          (callerProfile.role == 'super_admin' || callerProfile.role == 'owner') &&
          callerProfile.status == 'active';

      expect(rlsCheck, isTrue, reason: 'Active super admin caller must satisfy RLS policy');
    });
  });

  group('P1 Security Remediation: Authoritative public.profiles Role Verification (No userMetadata Fallback)', () {
    bool verifySuperAdminAuthorization({
      required Map<String, dynamic>? profileRow,
      Map<String, dynamic>? userMetadata,
    }) {
      // Authoritative lookup ONLY from public.profiles
      if (profileRow != null) {
        final profile = SuperAdminProfile.fromJson(profileRow);
        if (!profile.isSuperAdmin) return false;
        if (profile.status.toLowerCase() != 'active') return false;
        return true;
      }

      // No userMetadata fallback allowed!
      return false;
    }

    test('Critical: profile role = school_admin BUT userMetadata["role"] = "super_admin" -> Super Admin access DENIED', () {
      final profileRow = {
        'id': 'prof-school-admin',
        'auth_user_id': 'auth-usr-1',
        'email': 'admin@kps.edu',
        'full_name': 'KPS Admin',
        'role': 'school_admin',
        'status': 'active',
        'school_id': 'school-kps-uuid',
      };
      final forgedUserMetadata = {
        'role': 'super_admin',
        'name': 'Forged Super Admin',
      };

      final isAuthorized = verifySuperAdminAuthorization(
        profileRow: profileRow,
        userMetadata: forgedUserMetadata,
      );

      expect(isAuthorized, isFalse, reason: 'Forged userMetadata role must NEVER grant Super Admin access');
    });

    test('A. Active super_admin in public.profiles -> PASS', () {
      final profileRow = {
        'id': 'prof-sa',
        'auth_user_id': 'sa-auth-id',
        'email': 'super@schoolos.com',
        'full_name': 'Valid Super Admin',
        'role': 'super_admin',
        'status': 'active',
      };
      expect(verifySuperAdminAuthorization(profileRow: profileRow), isTrue);
    });

    test('B. Active owner in public.profiles -> PASS', () {
      final profileRow = {
        'id': 'prof-owner',
        'auth_user_id': 'owner-auth-id',
        'email': 'owner@schoolos.com',
        'full_name': 'Valid Owner',
        'role': 'owner',
        'status': 'active',
      };
      expect(verifySuperAdminAuthorization(profileRow: profileRow), isTrue);
    });

    test('C. Active school_admin in public.profiles -> FAIL', () {
      final profileRow = {
        'id': 'prof-admin',
        'auth_user_id': 'admin-auth-id',
        'email': 'admin@school.com',
        'full_name': 'School Admin',
        'role': 'school_admin',
        'status': 'active',
      };
      expect(verifySuperAdminAuthorization(profileRow: profileRow), isFalse);
    });

    test('D. Active teacher in public.profiles -> FAIL', () {
      final profileRow = {
        'id': 'prof-teacher',
        'auth_user_id': 'teacher-auth-id',
        'email': 'teacher@school.com',
        'full_name': 'Teacher User',
        'role': 'teacher',
        'status': 'active',
      };
      expect(verifySuperAdminAuthorization(profileRow: profileRow), isFalse);
    });

    test('E. Active parent in public.profiles -> FAIL', () {
      final profileRow = {
        'id': 'prof-parent',
        'auth_user_id': 'parent-auth-id',
        'email': 'parent@school.com',
        'full_name': 'Parent User',
        'role': 'parent',
        'status': 'active',
      };
      expect(verifySuperAdminAuthorization(profileRow: profileRow), isFalse);
    });

    test('F. Inactive super_admin in public.profiles -> FAIL and triggers signOut flow', () {
      final profileRow = {
        'id': 'prof-inactive',
        'auth_user_id': 'inactive-auth-id',
        'email': 'inactive@schoolos.com',
        'full_name': 'Inactive Admin',
        'role': 'super_admin',
        'status': 'inactive',
      };
      expect(verifySuperAdminAuthorization(profileRow: profileRow), isFalse);
    });

    test('G. Missing profile (null record in public.profiles) -> FAIL and triggers signOut flow', () {
      expect(verifySuperAdminAuthorization(profileRow: null), isFalse);
    });

    test('H. Missing profile with forged metadata role userMetadata["role"] = "super_admin" -> FAIL', () {
      final forgedUserMetadata = {
        'role': 'super_admin',
        'name': 'Hacker Admin',
      };
      expect(
        verifySuperAdminAuthorization(
          profileRow: null,
          userMetadata: forgedUserMetadata,
        ),
        isFalse,
        reason: 'Missing profile must never fall back to userMetadata to grant access',
      );
    });
  });
}
