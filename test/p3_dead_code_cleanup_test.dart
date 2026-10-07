import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_admin_app/routing/app_routes.dart';

void main() {
  group('SUPER ADMIN P3 — Final Legacy / Dead Code Cleanup Verification Tests', () {
    test('1. Obsolete route constants are removed from AppRoutes', () {
      final routesFile = File('lib/routing/app_routes.dart');
      expect(routesFile.existsSync(), isTrue);
      final content = routesFile.readAsStringSync();

      expect(content.contains("applications = '/applications'"), isFalse);
      expect(content.contains("assignments = '/assignments'"), isFalse);
      expect(content.contains("subscriptions = '/subscriptions'"), isFalse);
    });

    test('2. GoRouter does not contain dead prototype routes', () {
      final routerFile = File('lib/routing/app_router.dart');
      expect(routerFile.existsSync(), isTrue);
      final content = routerFile.readAsStringSync();

      expect(content.contains('/applications'), isFalse);
      expect(content.contains('/assignments'), isFalse);
      expect(content.contains('/subscriptions'), isFalse);
      expect(content.contains('ApplicationsScreen'), isFalse);
      expect(content.contains('AssignmentsScreen'), isFalse);
      expect(content.contains('SubscriptionsScreen'), isFalse);
    });

    test('3. Obsolete prototype screen files are permanently deleted', () {
      expect(File('lib/features/applications/applications_screen.dart').existsSync(), isFalse);
      expect(File('lib/features/assignments/assignments_screen.dart').existsSync(), isFalse);
      expect(File('lib/features/subscriptions/subscriptions_screen.dart').existsSync(), isFalse);
      expect(Directory('lib/features/applications').existsSync(), isFalse);
      expect(Directory('lib/features/assignments').existsSync(), isFalse);
      expect(Directory('lib/features/subscriptions').existsSync(), isFalse);
    });

    test('4. Obsolete ProductService and ProductRepository are permanently deleted', () {
      expect(File('lib/services/product_service.dart').existsSync(), isFalse);
      expect(File('lib/repositories/product_repository.dart').existsSync(), isFalse);
    });

    test('5. Zero runtime queries against obsolete public.products table', () {
      final libDir = Directory('lib');
      final dartFiles = libDir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

      for (final file in dartFiles) {
        final content = file.readAsStringSync();
        expect(
          content.contains("from('products')") || content.contains('from("products")'),
          isFalse,
          reason: 'File ${file.path} must not query obsolete products table',
        );
      }
    });

    test('6. Zero runtime queries against obsolete public.school_apps table', () {
      final libDir = Directory('lib');
      final dartFiles = libDir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

      for (final file in dartFiles) {
        final content = file.readAsStringSync();
        expect(
          content.contains("from('school_apps')") || content.contains('from("school_apps")'),
          isFalse,
          reason: 'File ${file.path} must not query obsolete school_apps table',
        );
      }
    });

    test('7. Zero runtime queries against obsolete public.subscriptions table', () {
      final libDir = Directory('lib');
      final dartFiles = libDir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

      for (final file in dartFiles) {
        final content = file.readAsStringSync();
        expect(
          content.contains("from('subscriptions')") || content.contains('from("subscriptions")'),
          isFalse,
          reason: 'File ${file.path} must not query obsolete subscriptions table',
        );
      }
    });

    test('8. DashboardScreen quick action chips contain zero links to obsolete routes', () {
      final dashboardFile = File('lib/features/dashboard/dashboard_screen.dart');
      expect(dashboardFile.existsSync(), isTrue);
      final content = dashboardFile.readAsStringSync();

      expect(content.contains('AppRoutes.applications'), isFalse);
      expect(content.contains('AppRoutes.assignments'), isFalse);
      expect(content.contains('AppRoutes.subscriptions'), isFalse);
      expect(content.contains('SaaS Products'), isFalse);
      expect(content.contains('App Assignments'), isFalse);
    });

    test('9. AppConstants contains zero isDevAuthBypassEnabled flag', () {
      final constFile = File('lib/core/constants/app_constants.dart');
      expect(constFile.existsSync(), isTrue);
      final content = constFile.readAsStringSync();

      expect(content.contains('isDevAuthBypassEnabled'), isFalse);
    });

    test('10. Active production canonical routes remain defined and intact', () {
      expect(AppRoutes.login, equals('/login'));
      expect(AppRoutes.splash, equals('/splash'));
      expect(AppRoutes.updatePassword, equals('/update-password'));
      expect(AppRoutes.dashboard, equals('/dashboard'));
      expect(AppRoutes.schools, equals('/schools'));
      expect(AppRoutes.schoolDetails, equals('/schools/:id'));
      expect(AppRoutes.billing, equals('/billing'));
      expect(AppRoutes.invoiceDetails, equals('/invoices/:id'));
      expect(AppRoutes.appDetails, equals('/apps/:id'));
      expect(AppRoutes.provision, equals('/provision'));
      expect(AppRoutes.profile, equals('/profile'));
      expect(AppRoutes.settings, equals('/settings'));
    });
  });
}
