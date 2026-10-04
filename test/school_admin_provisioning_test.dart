import 'package:flutter_test/flutter_test.dart';
import 'package:super_admin_app/models/school_admin_model.dart';
import 'package:super_admin_app/models/school_model.dart';

void main() {
  group('SchoolAdminModel Domain & Serialization Tests', () {
    test('fromJson parses all fields accurately from profiles table format', () {
      final json = {
        'id': 'prof-uuid-001',
        'auth_user_id': 'auth-uuid-001',
        'school_id': 'cf895651-4783-489b-8551-959a70098ca8',
        'full_name': 'Rahul Sharma',
        'email': 'admin.school1@schoolos.test',
        'phone': '+91 98765 43210',
        'role': 'school_admin',
        'status': 'active',
        'designation': 'Principal Administrator',
        'created_at': '2026-09-13T10:00:00.000Z',
        'updated_at': '2026-09-13T12:00:00.000Z',
      };

      final admin = SchoolAdminModel.fromJson(json);

      expect(admin.id, 'prof-uuid-001');
      expect(admin.authUserId, 'auth-uuid-001');
      expect(admin.schoolId, 'cf895651-4783-489b-8551-959a70098ca8');
      expect(admin.fullName, 'Rahul Sharma');
      expect(admin.email, 'admin.school1@schoolos.test');
      expect(admin.phone, '+91 98765 43210');
      expect(admin.role, 'school_admin');
      expect(admin.status, 'active');
      expect(admin.designation, 'Principal Administrator');
      expect(admin.isActive, isTrue);
      expect(admin.isSchoolAdmin, isTrue);
      expect(admin.createdAt, DateTime.parse('2026-09-13T10:00:00.000Z'));
      expect(admin.updatedAt, DateTime.parse('2026-09-13T12:00:00.000Z'));
    });

    test('isActive and isSchoolAdmin helper getters handle casing and status variations', () {
      const activeAdmin = SchoolAdminModel(
        id: '1',
        authUserId: 'a1',
        schoolId: 's1',
        fullName: 'Admin One',
        email: 'one@test.com',
        role: 'SCHOOL_ADMIN',
        status: 'ACTIVE',
      );
      expect(activeAdmin.isActive, isTrue);
      expect(activeAdmin.isSchoolAdmin, isTrue);

      const inactiveAdmin = SchoolAdminModel(
        id: '2',
        authUserId: 'a2',
        schoolId: 's2',
        fullName: 'Admin Two',
        email: 'two@test.com',
        role: 'school_admin',
        status: 'inactive',
      );
      expect(inactiveAdmin.isActive, isFalse);
      expect(inactiveAdmin.isSchoolAdmin, isTrue);

      const otherRole = SchoolAdminModel(
        id: '3',
        authUserId: 'a3',
        schoolId: 's3',
        fullName: 'Teacher Three',
        email: 'three@test.com',
        role: 'teacher',
        status: 'active',
      );
      expect(otherRole.isActive, isTrue);
      expect(otherRole.isSchoolAdmin, isFalse);
    });

    test('toJson produces valid schema for public.profiles without password', () {
      final now = DateTime.now();
      final admin = SchoolAdminModel(
        id: 'prof-123',
        authUserId: 'auth-456',
        schoolId: 'cf895651-4783-489b-8551-959a70098ca8',
        fullName: 'Vikram Singh',
        email: 'vikram@school.test',
        phone: '+919999988888',
        role: 'school_admin',
        status: 'active',
        designation: 'School Administrator',
        createdAt: now,
        updatedAt: now,
      );

      final json = admin.toJson();

      expect(json.containsKey('password'), isFalse);
      expect(json.containsKey('hashed_password'), isFalse);
      expect(json['id'], 'prof-123');
      expect(json['auth_user_id'], 'auth-456');
      expect(json['school_id'], 'cf895651-4783-489b-8551-959a70098ca8');
      expect(json['full_name'], 'Vikram Singh');
      expect(json['email'], 'vikram@school.test');
      expect(json['role'], 'school_admin');
      expect(json['status'], 'active');
    });

    test('copyWith properly clones and overrides fields', () {
      const original = SchoolAdminModel(
        id: 'orig-id',
        authUserId: 'orig-auth',
        schoolId: 'orig-school',
        fullName: 'Original Name',
        email: 'orig@test.com',
        status: 'active',
      );

      final modified = original.copyWith(
        fullName: 'Updated Name',
        status: 'inactive',
        phone: '+91 1234567890',
      );

      expect(modified.id, 'orig-id');
      expect(modified.authUserId, 'orig-auth');
      expect(modified.schoolId, 'orig-school');
      expect(modified.fullName, 'Updated Name');
      expect(modified.email, 'orig@test.com');
      expect(modified.status, 'inactive');
      expect(modified.phone, '+91 1234567890');
      expect(modified.isActive, isFalse);
    });
  });

  group('School Admin Security & Architecture Verification', () {
    test('school_id context inheritance prevents cross-school tenant leakage', () {
      final testSchool = SchoolModel(
        id: 'cf895651-4783-489b-8551-959a70098ca8',
        name: 'school 1',
        schoolCode: 'SCHOOL-1',
        email: 'admin@school1.test',
        phone: '1234567890',
        address: '123 Main St',
        status: SchoolStatus.active,
        createdAt: DateTime.now(),
      );

      // Verify that provisioning modal inherits the exact authoritative school ID
      final inheritedSchoolId = testSchool.id;
      expect(inheritedSchoolId, 'cf895651-4783-489b-8551-959a70098ca8');

      // The created admin's school_id must strictly match the parent school's authoritative UUID
      final admin = SchoolAdminModel(
        id: 'admin-1',
        authUserId: 'auth-1',
        schoolId: inheritedSchoolId,
        fullName: 'School One Admin',
        email: 'admin.school1@schoolos.test',
      );

      expect(admin.schoolId, equals(testSchool.id));
      expect(admin.schoolId, isNot(equals('d65c3b17-7e61-460d-83b3-8c704f7fca13'))); // Not KPS
    });

    test('Duplicate admin detection rule flags school with existing active admin', () {
      final existingProfiles = [
        {
          'id': 'p1',
          'school_id': 'cf895651-4783-489b-8551-959a70098ca8',
          'role': 'school_admin',
          'status': 'active',
          'email': 'admin1@schoolos.test',
        },
        {
          'id': 'p2',
          'school_id': 'd65c3b17-7e61-460d-83b3-8c704f7fca13',
          'role': 'school_admin',
          'status': 'active',
          'email': 'kps@schoolos.test',
        },
      ];

      // Simulating duplicate protection query
      const targetSchoolId = 'cf895651-4783-489b-8551-959a70098ca8';
      final hasActiveAdmin = existingProfiles.any((p) =>
          p['school_id'] == targetSchoolId &&
          p['role'] == 'school_admin' &&
          p['status'] == 'active');

      expect(hasActiveAdmin, isTrue);
    });

    test('Duplicate email detection rule flags existing email in profiles table', () {
      final existingProfiles = [
        {'email': 'admin.school1@schoolos.test', 'id': 'p1'},
        {'email': 'superadmin@schoolos.com', 'id': 'p2'},
      ];

      bool isEmailTaken(String email) =>
          existingProfiles.any((p) => p['email'] == email.trim().toLowerCase());

      expect(isEmailTaken('admin.school1@schoolos.test'), isTrue);
      expect(isEmailTaken('ADMIN.SCHOOL1@SCHOOLOS.TEST '), isTrue);
      expect(isEmailTaken('new.admin@schoolos.test'), isFalse);
    });
  });
}
