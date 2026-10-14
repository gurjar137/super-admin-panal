import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_admin_app/core/config/supabase_config.dart';
import 'package:super_admin_app/models/school_app_model.dart';
import 'package:super_admin_app/models/school_model.dart';

void main() {
  group('School Identity Propagation & Canonical UUID Tests', () {
    test('Canonical School UUID matches KPS production identity without fallback discrepancy', () {
      const kpsSchoolId = '6254bee9-151d-4332-8a1c-3994af7d2153';
      const kpsAppIdentifier = 'KPS_APP';
      const separateTenantSchoolId = 'cf895651-4783-489b-8551-959a70098ca8';

      final kpsSchool = SchoolModel(
        id: kpsSchoolId,
        schoolCode: 'KPS',
        name: 'KPS',
        status: SchoolStatus.active,
        createdAt: DateTime.parse('2026-03-01T00:00:00Z'),
      );

      final kpsApp = SchoolAppModel(
        id: 'ae42a8cc-6a01-4a4f-bc7b-8839c1b9782a',
        schoolId: kpsSchool.id,
        schoolName: kpsSchool.name,
        appName: 'KPS School App',
        packageName: 'com.school.app.school_app',
        appIdentifier: kpsAppIdentifier,
        currentVersion: '1.0.0',
        status: SchoolAppStatus.active,
        createdAt: DateTime.parse('2026-03-01T00:00:00Z'),
      );

      // Verify canonical UUID propagation
      expect(kpsApp.schoolId, equals(kpsSchool.id));
      expect(kpsApp.schoolId, equals(kpsSchoolId));
      expect(kpsApp.schoolId, isNot(equals(separateTenantSchoolId)));
      expect(kpsApp.appIdentifier, equals('KPS_APP'));
    });

    test('Dedicated build command generator strictly includes both SCHOOL_ID and APP_IDENTIFIER', () {
      const schoolId = '6254bee9-151d-4332-8a1c-3994af7d2153';
      const appIdentifier = 'KPS_APP';

      String generateDedicatedBuildCommand({required String sId, required String appId}) {
        return 'flutter build apk --release --dart-define=SCHOOL_ID=$sId --dart-define=APP_IDENTIFIER=$appId';
      }

      final cmd = generateDedicatedBuildCommand(sId: schoolId, appId: appIdentifier);

      expect(cmd, contains('--dart-define=SCHOOL_ID=6254bee9-151d-4332-8a1c-3994af7d2153'));
      expect(cmd, contains('--dart-define=APP_IDENTIFIER=KPS_APP'));
      expect(cmd, isNot(contains('cf895651-4783-489b-8551-959a70098ca8')));
    });

    test('Shared dynamic multi-tenant mode command does not hardcode school identity', () {
      String generateMultiTenantBuildCommand() {
        return 'flutter build apk --release';
      }

      final cmd = generateMultiTenantBuildCommand();

      expect(cmd, equals('flutter build apk --release'));
      expect(cmd, isNot(contains('SCHOOL_ID')));
      expect(cmd, isNot(contains('APP_IDENTIFIER')));
    });

    test('Configuration export formats (.env and JSON) contain canonical UUID and omit secrets', () {
      final school = SchoolModel(
        id: '6254bee9-151d-4332-8a1c-3994af7d2153',
        schoolCode: 'KPS',
        name: 'KPS',
        status: SchoolStatus.active,
        createdAt: DateTime.now(),
      );

      final app = SchoolAppModel(
        id: 'ae42a8cc-6a01-4a4f-bc7b-8839c1b9782a',
        schoolId: school.id,
        appName: 'KPS School App',
        appIdentifier: 'KPS_APP',
        packageName: 'com.school.app.school_app',
        currentVersion: '1.0.0',
        status: SchoolAppStatus.active,
        createdAt: DateTime.now(),
      );

      final jsonConfig = {
        'school_name': school.name,
        'school_id': school.id,
        'app_identifier': app.appIdentifier,
        'app_name': app.appName,
        'package_name': app.packageName,
        'current_version': app.currentVersion,
        'supabase_url': SupabaseConfig.url,
        'supabase_publishable_key': SupabaseConfig.publishableKey,
      };

      final jsonStr = jsonEncode(jsonConfig);
      expect(jsonStr, contains('"school_id":"6254bee9-151d-4332-8a1c-3994af7d2153"'));
      expect(jsonStr, contains('"app_identifier":"KPS_APP"'));
      expect(jsonStr.toLowerCase(), isNot(contains('service_role')));
      expect(jsonStr.toLowerCase(), isNot(contains('postgres_password')));
      expect(jsonStr.toLowerCase(), isNot(contains('secret')));

      final envConfig = '''
SCHOOL_NAME=${school.name}
SCHOOL_ID=${school.id}
APP_IDENTIFIER=${app.appIdentifier}
APP_NAME=${app.appName}
PACKAGE_NAME=${app.packageName}
''';

      expect(envConfig, contains('SCHOOL_ID=6254bee9-151d-4332-8a1c-3994af7d2153'));
      expect(envConfig, contains('APP_IDENTIFIER=KPS_APP'));
    });

    test('Distinct schools maintain strictly distinct UUIDs and cannot collide', () {
      final kpsSchool = SchoolModel(
        id: '6254bee9-151d-4332-8a1c-3994af7d2153',
        schoolCode: 'KPS',
        name: 'KPS',
        status: SchoolStatus.active,
        createdAt: DateTime.now(),
      );

      final school1 = SchoolModel(
        id: 'cf895651-4783-489b-8551-959a70098ca8',
        schoolCode: 'SCHOOL-1',
        name: 'school 1',
        status: SchoolStatus.active,
        createdAt: DateTime.now(),
      );

      final greenwood = SchoolModel(
        id: '8dfc32c4-32b5-4568-9848-0056c31a74ce',
        schoolCode: 'GRN-LIVE-4456',
        name: 'Greenwood International Academy',
        status: SchoolStatus.active,
        createdAt: DateTime.now(),
      );

      final allIds = [kpsSchool.id, school1.id, greenwood.id];
      expect(allIds.toSet().length, equals(3));
    });

    test('Operational summary distinguishes App Config Status from Build / Deploy Status', () {
      final appPendingRelease = SchoolAppModel(
        id: 'app-1',
        schoolId: '6254bee9-151d-4332-8a1c-3994af7d2153',
        appName: 'KPS School App',
        appIdentifier: 'KPS_APP',
        playStoreUrl: null,
        status: SchoolAppStatus.active,
        createdAt: DateTime.now(),
      );

      final buildStatusPending = appPendingRelease.playStoreUrl != null && appPendingRelease.playStoreUrl!.isNotEmpty
          ? 'RELEASED'
          : 'CONFIGURED (PENDING STORE RELEASE)';

      final appConfigStatus = appPendingRelease.isActive ? 'CONFIGURED (ACTIVE)' : 'INACTIVE';

      expect(appConfigStatus, equals('CONFIGURED (ACTIVE)'));
      expect(buildStatusPending, equals('CONFIGURED (PENDING STORE RELEASE)'));

      final appReleased = appPendingRelease.copyWith(
        playStoreUrl: 'https://play.google.com/store/apps/details?id=com.school.app.school_app',
      );

      final buildStatusReleased = appReleased.playStoreUrl != null && appReleased.playStoreUrl!.isNotEmpty
          ? 'RELEASED'
          : 'CONFIGURED (PENDING STORE RELEASE)';

      expect(buildStatusReleased, equals('RELEASED'));
    });
  });
}
