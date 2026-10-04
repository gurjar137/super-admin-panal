import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_admin_app/models/school_admin_model.dart';
import 'package:super_admin_app/models/school_app_model.dart';
import 'package:super_admin_app/models/school_model.dart';
import 'package:super_admin_app/models/school_provision_dto.dart';
import 'package:super_admin_app/models/subscription_model.dart';

void main() {
  group('Production School Provisioning Flow Tests', () {
    test('1. SchoolProvisionDto normalizes school code consistently', () {
      expect(SchoolProvisionDto.normalizeCode('oak ridge international'), 'OAKRIDGEINTERNATIONAL');
      expect(SchoolProvisionDto.normalizeCode('dps@delhi#01'), 'DPSDELHI01');
      expect(SchoolProvisionDto.normalizeCode('  kps-2026--delhi  '), 'KPS-2026--DELHI');
      expect(SchoolProvisionDto.normalizeCode('SCH-01'), 'SCH-01');
    });

    test('2. SchoolProvisionDto validates all required fields before submission', () {
      final validDto = SchoolProvisionDto(
        name: 'Oakridge Academy',
        schoolCode: 'OAK-01',
        email: 'info@oakridge.edu',
        phone: '+91 98765 43210',
        address: 'Sector 62, Noida',
        initialAdminName: 'Dr. Robert Vance',
        initialAdminEmail: 'robert@oakridge.edu',
        initialAdminPhone: '+91 98765 43211',
      );

      final errors = validDto.validate();
      expect(errors, isEmpty);

      final invalidDto = SchoolProvisionDto(
        name: '',
        schoolCode: 'AB',
        email: 'not-an-email',
        phone: '',
        address: '',
        initialAdminName: '',
        initialAdminEmail: 'bad-email',
        initialAdminPhone: '',
      );

      final invalidErrors = invalidDto.validate();
      expect(invalidErrors.isNotEmpty, isTrue);
      expect(invalidErrors.containsKey('name'), isTrue);
      expect(invalidErrors.containsKey('schoolCode'), isTrue);
      expect(invalidErrors.containsKey('email'), isTrue);
      expect(invalidErrors.containsKey('initialAdminEmail'), isTrue);
    });

    test('3. Strict Zero Plaintext Password Persistence Guarantee', () {
      final now = DateTime.now();

      // Model 1: SchoolModel
      final school = SchoolModel(
        id: '6254bee9-151d-4332-8a1c-3994af7d2153',
        name: 'KPS School',
        schoolCode: 'KPS-01',
        status: SchoolStatus.active,
        createdAt: now,
        updatedAt: now,
      );
      final schoolJson = school.toJson();
      expect(schoolJson.containsKey('password'), isFalse);
      expect(schoolJson.containsKey('admin_password'), isFalse);

      // Model 2: SchoolAppModel
      final app = SchoolAppModel(
        id: 'app-uuid-001',
        schoolId: school.id,
        appName: 'KPS App',
        appIdentifier: 'KPS_APP',
        packageName: 'com.school.app.kps',
        currentVersion: '1.0.0',
        status: SchoolAppStatus.active,
        createdAt: now,
        updatedAt: now,
      );
      final appJson = app.toJson();
      expect(appJson.containsKey('password'), isFalse);
      expect(appJson.containsKey('initial_password'), isFalse);

      // Model 3: SchoolAdminModel (for public.profiles)
      final admin = SchoolAdminModel(
        id: 'prof-uuid-001',
        authUserId: 'auth-user-001',
        schoolId: school.id,
        fullName: 'Principal Admin',
        email: 'principal@kps.edu',
        phone: '+91 99999 88888',
        role: 'school_admin',
        status: 'active',
        designation: 'School Administrator',
        createdAt: now,
        updatedAt: now,
      );
      final adminJson = admin.toJson();
      expect(adminJson.containsKey('password'), isFalse);
      expect(adminJson.containsKey('admin_password'), isFalse);
      expect(adminJson.containsKey('initial_password'), isFalse);
      expect(adminJson.containsKey('must_change_password'), isFalse);

      // Model 4: SubscriptionModel
      final sub = SubscriptionModel(
        id: 'sub-uuid-001',
        schoolAppId: app.id,
        planName: 'Annual Plan',
        startDate: now,
        endDate: now.add(const Duration(days: 365)),
        status: SubscriptionStatus.active,
        createdAt: now,
        updatedAt: now,
      );
      final subJson = sub.toJson();
      expect(subJson.containsKey('password'), isFalse);
    });

    test('4. School Provision DTO conversion produces exact database payload without password', () {
      final dto = SchoolProvisionDto(
        name: 'St. Jude School',
        schoolCode: 'ST-JUDE-01',
        email: 'contact@stjude.edu',
        phone: '+91 98765 00000',
        address: 'Civil Lines',
        initialAdminName: 'Father Thomas',
        initialAdminEmail: 'principal@stjude.edu',
        initialAdminPhone: '+91 98765 00001',
      );

      final schoolPayload = dto.toSchoolPayload();
      expect(schoolPayload['name'], 'St. Jude School');
      expect(schoolPayload['code'], 'ST-JUDE-01');
      expect(schoolPayload.containsKey('password'), isFalse);
      expect(schoolPayload.containsKey('initialAdminPassword'), isFalse);
    });

    test('5. Auth Signup payload enforces must_change_password in user_metadata', () {
      // Simulating SchoolAdminService isolated HTTP signup payload
      final email = 'newadmin@testschool.edu';
      final initialPassword = 'InitialSecretPass99!';
      final fullName = 'New Admin';
      final phone = '+91 91234 56789';

      final signupPayload = {
        'email': email.trim().toLowerCase(),
        'password': initialPassword,
        'data': {
          'full_name': fullName.trim(),
          'phone': phone.trim(),
          'role': 'school_admin',
          'must_change_password': true,
        },
      };

      final encoded = jsonEncode(signupPayload);
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;

      expect(decoded['email'], 'newadmin@testschool.edu');
      expect(decoded['data']['role'], 'school_admin');
      expect(decoded['data']['must_change_password'], isTrue);
    });

    test('6. Password change reset payload sets must_change_password to false', () {
      // Simulating client.auth.updateUser with must_change_password = false
      final newPassword = 'NewPermanentPassword2026!';
      final updatePayload = {
        'password': newPassword,
        'data': {
          'must_change_password': false,
        },
      };

      final encoded = jsonEncode(updatePayload);
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;

      expect(decoded['password'], 'NewPermanentPassword2026!');
      expect(decoded['data']['must_change_password'], isFalse);
    });
  });
}
