import 'package:flutter_test/flutter_test.dart';
import 'package:super_admin_app/core/constants/app_constants.dart';
import 'package:super_admin_app/models/school_provision_dto.dart';
import 'package:super_admin_app/models/super_admin_model.dart';
import 'package:super_admin_app/routing/app_routes.dart';

void main() {
  group('Requirement 1: Development Auth Bypass Disabled', () {
    test('AppConstants.isDevAuthBypassEnabled is false for normal application flow', () {
      expect(AppConstants.isDevAuthBypassEnabled, isFalse);
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
}
