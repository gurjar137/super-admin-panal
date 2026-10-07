import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:super_admin_app/core/auth/app_auth_state.dart';
import 'package:super_admin_app/models/super_admin_model.dart';
import 'package:super_admin_app/routing/app_router.dart';
import 'package:super_admin_app/routing/app_routes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Helper factory for SuperAdminProfile instances
  SuperAdminProfile createTestProfile({
    String id = 'test-prof-1',
    String authUserId = 'test-auth-1',
    String email = 'superadmin@schoolos.test',
    String role = 'super_admin',
    String status = 'active',
  }) {
    return SuperAdminProfile.fromJson({
      'id': id,
      'auth_user_id': authUserId,
      'email': email,
      'full_name': 'Test Administrator',
      'role': role,
      'status': status,
      'school_id': null,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  // Create an isolated test GoRouter mirroring production appRouter configuration
  GoRouter createTestRouter({String initialLocation = AppRoutes.dashboard}) {
    return GoRouter(
      initialLocation: initialLocation,
      refreshListenable: AppAuthState.instance,
      redirect: authRouteGuard,
      routes: [
        GoRoute(
          path: AppRoutes.splash,
          builder: (context, state) => const Scaffold(body: Text('SPLASH_SCREEN')),
        ),
        GoRoute(
          path: AppRoutes.login,
          builder: (context, state) => const Scaffold(body: Text('LOGIN_SCREEN')),
        ),
        GoRoute(
          path: AppRoutes.updatePassword,
          builder: (context, state) => const Scaffold(body: Text('UPDATE_PASSWORD_SCREEN')),
        ),
        GoRoute(
          path: AppRoutes.dashboard,
          builder: (context, state) => const Scaffold(body: Text('DASHBOARD_SCREEN')),
        ),
        GoRoute(
          path: AppRoutes.schools,
          builder: (context, state) => const Scaffold(body: Text('SCHOOLS_SCREEN')),
          routes: [
            GoRoute(
              path: ':id',
              builder: (context, state) => Scaffold(
                body: Text('SCHOOL_DETAILS_${state.pathParameters['id']}'),
              ),
            ),
          ],
        ),
        GoRoute(
          path: AppRoutes.billing,
          builder: (context, state) => const Scaffold(body: Text('BILLING_SCREEN')),
        ),
        GoRoute(
          path: AppRoutes.provision,
          builder: (context, state) => const Scaffold(body: Text('PROVISION_SCREEN')),
        ),
        GoRoute(
          path: AppRoutes.settings,
          builder: (context, state) => const Scaffold(body: Text('SETTINGS_SCREEN')),
        ),
        GoRoute(
          path: AppRoutes.profile,
          builder: (context, state) => const Scaffold(body: Text('PROFILE_SCREEN')),
        ),
      ],
    );
  }

  setUp(() {
    AppAuthState.instance.resetForTesting(isInitialized: true, profile: null);
  });

  tearDown(() {
    AppAuthState.instance.resetForTesting(isInitialized: true, profile: null);
  });

  group('SUPER ADMIN P2 #1 — Global Auth Route Guard Requirements', () {
    // -------------------------------------------------------------------------
    // TEST 1: No session + /dashboard -> redirected to login
    // -------------------------------------------------------------------------
    testWidgets('1. No session + /dashboard -> redirected to login with redirect parameter', (tester) async {
      AppAuthState.instance.resetForTesting(isInitialized: true, profile: null);

      final router = createTestRouter(initialLocation: AppRoutes.dashboard);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(find.text('LOGIN_SCREEN'), findsOneWidget);
      expect(find.text('DASHBOARD_SCREEN'), findsNothing);

      final currentUri = router.routerDelegate.currentConfiguration.uri;
      expect(currentUri.path, equals(AppRoutes.login));
      expect(currentUri.queryParameters['redirect'], equals(AppRoutes.dashboard));
    });

    // -------------------------------------------------------------------------
    // TEST 2: No session + direct deep links -> redirected to login
    // -------------------------------------------------------------------------
    testWidgets('2. No session + direct deep links (/schools/123, /billing, /provision, /settings) -> redirected to login', (tester) async {
      AppAuthState.instance.resetForTesting(isInitialized: true, profile: null);

      final deepLinks = [
        '/schools/6254bee9-151d-4332-8a1c-3994af7d2153',
        AppRoutes.billing,
        AppRoutes.provision,
        AppRoutes.settings,
        AppRoutes.profile,
      ];

      for (final link in deepLinks) {
        final router = createTestRouter(initialLocation: link);
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();

        expect(find.text('LOGIN_SCREEN'), findsOneWidget, reason: 'Deep link $link must redirect to login');
        final currentUri = router.routerDelegate.currentConfiguration.uri;
        expect(currentUri.path, equals(AppRoutes.login));
        expect(currentUri.queryParameters['redirect'], equals(link));
      }
    });

    // -------------------------------------------------------------------------
    // TEST 3: Valid authenticated Super Admin + /dashboard -> allowed
    // -------------------------------------------------------------------------
    testWidgets('3. Valid authenticated Super Admin + /dashboard -> allowed and renders dashboard', (tester) async {
      final superAdmin = createTestProfile(role: 'super_admin', status: 'active');
      AppAuthState.instance.resetForTesting(isInitialized: true, profile: superAdmin);

      expect(AppAuthState.instance.isAuthenticated, isTrue);

      final router = createTestRouter(initialLocation: AppRoutes.dashboard);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(find.text('DASHBOARD_SCREEN'), findsOneWidget);
      expect(find.text('LOGIN_SCREEN'), findsNothing);
      expect(router.routerDelegate.currentConfiguration.uri.path, equals(AppRoutes.dashboard));
    });

    // -------------------------------------------------------------------------
    // TEST 4: Valid authenticated Owner + /dashboard -> allowed
    // -------------------------------------------------------------------------
    testWidgets('4. Valid authenticated Owner + /dashboard -> allowed where role rules permit', (tester) async {
      final owner = createTestProfile(role: 'owner', status: 'active');
      AppAuthState.instance.resetForTesting(isInitialized: true, profile: owner);

      expect(AppAuthState.instance.isAuthenticated, isTrue);
      expect(owner.isSuperAdmin, isTrue);

      final router = createTestRouter(initialLocation: AppRoutes.dashboard);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(find.text('DASHBOARD_SCREEN'), findsOneWidget);
      expect(find.text('LOGIN_SCREEN'), findsNothing);
      expect(router.routerDelegate.currentConfiguration.uri.path, equals(AppRoutes.dashboard));
    });

    // -------------------------------------------------------------------------
    // TEST 5: Missing profile -> denied
    // -------------------------------------------------------------------------
    testWidgets('5. Missing profile (null profile in public.profiles) -> denied and redirected to login', (tester) async {
      AppAuthState.instance.resetForTesting(isInitialized: true, profile: null);

      expect(AppAuthState.instance.isAuthenticated, isFalse);

      final router = createTestRouter(initialLocation: AppRoutes.dashboard);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(find.text('LOGIN_SCREEN'), findsOneWidget);
      expect(find.text('DASHBOARD_SCREEN'), findsNothing);
    });

    // -------------------------------------------------------------------------
    // TEST 6: Inactive profile -> denied
    // -------------------------------------------------------------------------
    testWidgets('6. Inactive profile (status != active) -> denied and redirected to login', (tester) async {
      for (final badStatus in ['inactive', 'suspended', 'pending', 'revoked']) {
        final inactiveAdmin = createTestProfile(role: 'super_admin', status: badStatus);
        AppAuthState.instance.resetForTesting(isInitialized: true, profile: inactiveAdmin);

        expect(AppAuthState.instance.isAuthenticated, isFalse, reason: 'Status $badStatus must not be authenticated');

        final router = createTestRouter(initialLocation: AppRoutes.dashboard);
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();

        expect(find.text('LOGIN_SCREEN'), findsOneWidget, reason: 'Inactive admin must be redirected to login');
        expect(find.text('DASHBOARD_SCREEN'), findsNothing);
      }
    });

    // -------------------------------------------------------------------------
    // TEST 7: Wrong role -> denied where Super Admin-only access is required
    // -------------------------------------------------------------------------
    testWidgets('7. Wrong role (teacher, school_admin, parent, staff) -> denied access to protected routes', (tester) async {
      final wrongRoles = ['teacher', 'school_admin', 'parent', 'staff', 'student', 'guest'];

      for (final wrongRole in wrongRoles) {
        final nonAdmin = createTestProfile(role: wrongRole, status: 'active');
        AppAuthState.instance.resetForTesting(isInitialized: true, profile: nonAdmin);

        expect(AppAuthState.instance.isAuthenticated, isFalse, reason: 'Role $wrongRole is not Super Admin');

        final router = createTestRouter(initialLocation: AppRoutes.dashboard);
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();

        expect(find.text('LOGIN_SCREEN'), findsOneWidget, reason: 'Role $wrongRole must be redirected to login');
        expect(find.text('DASHBOARD_SCREEN'), findsNothing);
      }
    });

    // -------------------------------------------------------------------------
    // TEST 8: Logout from protected route -> login
    // -------------------------------------------------------------------------
    testWidgets('8. Logout from protected route -> immediately leaves protected route and returns to login', (tester) async {
      final admin = createTestProfile(role: 'super_admin', status: 'active');
      AppAuthState.instance.resetForTesting(isInitialized: true, profile: admin);

      final router = createTestRouter(initialLocation: AppRoutes.dashboard);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(find.text('DASHBOARD_SCREEN'), findsOneWidget);

      // Trigger logout
      AppAuthState.instance.setUnauthenticated();
      await tester.pumpAndSettle();

      expect(find.text('DASHBOARD_SCREEN'), findsNothing);
      expect(find.text('LOGIN_SCREEN'), findsOneWidget);
      expect(router.routerDelegate.currentConfiguration.uri.path, equals(AppRoutes.login));
    });

    // -------------------------------------------------------------------------
    // TEST 9: Session restoration -> protected route remains accessible
    // -------------------------------------------------------------------------
    testWidgets('9. Session restoration -> protected route remains accessible after session check', (tester) async {
      // Step A: App starts up in uninitialized state targeting a deep link
      AppAuthState.instance.resetForTesting(isInitialized: false, profile: null);

      final router = createTestRouter(initialLocation: '/schools/kps-uuid');
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      // Guard holds on splash with target preserved while initializing
      expect(find.text('SPLASH_SCREEN'), findsOneWidget);
      expect(router.routerDelegate.currentConfiguration.uri.path, equals(AppRoutes.splash));
      expect(router.routerDelegate.currentConfiguration.uri.queryParameters['redirect'], equals('/schools/kps-uuid'));

      // Step B: Authoritative profile restoration completes
      final admin = createTestProfile(role: 'super_admin', status: 'active');
      AppAuthState.instance.setProfile(admin);
      await tester.pumpAndSettle();

      // Target route is restored and allowed to render
      router.go('/schools/kps-uuid');
      await tester.pumpAndSettle();

      expect(find.text('SCHOOL_DETAILS_kps-uuid'), findsOneWidget);
      expect(find.text('LOGIN_SCREEN'), findsNothing);
    });

    // -------------------------------------------------------------------------
    // TEST 10: Expired/invalid session -> redirected to login
    // -------------------------------------------------------------------------
    testWidgets('10. Expired/invalid session -> redirected to login', (tester) async {
      // User has expired session
      AppAuthState.instance.resetForTesting(isInitialized: true, profile: null);

      final router = createTestRouter(initialLocation: AppRoutes.provision);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(find.text('LOGIN_SCREEN'), findsOneWidget);
      expect(find.text('PROVISION_SCREEN'), findsNothing);
      expect(router.routerDelegate.currentConfiguration.uri.path, equals(AppRoutes.login));
      expect(router.routerDelegate.currentConfiguration.uri.queryParameters['redirect'], equals(AppRoutes.provision));
    });

    // -------------------------------------------------------------------------
    // TEST 11: No redirect loop
    // -------------------------------------------------------------------------
    testWidgets('11. No redirect loop across any authentication / route state combinations', (tester) async {
      final admin = createTestProfile(role: 'super_admin', status: 'active');

      // 11A: Unauthenticated user on /login settles cleanly without redirect loop
      AppAuthState.instance.resetForTesting(isInitialized: true, profile: null);
      final routerA = createTestRouter(initialLocation: AppRoutes.login);
      await tester.pumpWidget(MaterialApp.router(routerConfig: routerA));
      await tester.pumpAndSettle();
      expect(routerA.routerDelegate.currentConfiguration.uri.path, equals(AppRoutes.login));

      // 11B: Authenticated user on /dashboard settles cleanly without redirect loop
      AppAuthState.instance.resetForTesting(isInitialized: true, profile: admin);
      final routerB = createTestRouter(initialLocation: AppRoutes.dashboard);
      await tester.pumpWidget(MaterialApp.router(routerConfig: routerB));
      await tester.pumpAndSettle();
      expect(routerB.routerDelegate.currentConfiguration.uri.path, equals(AppRoutes.dashboard));

      // 11C: Uninitialized user on /splash settles cleanly on splash without redirect loop
      AppAuthState.instance.resetForTesting(isInitialized: false, profile: null);
      final routerC = createTestRouter(initialLocation: AppRoutes.splash);
      await tester.pumpWidget(MaterialApp.router(routerConfig: routerC));
      await tester.pumpAndSettle();
      expect(routerC.routerDelegate.currentConfiguration.uri.path, equals(AppRoutes.splash));

      // 11D: Public password recovery settles cleanly without redirect loop
      AppAuthState.instance.resetForTesting(isInitialized: true, profile: null);
      final routerD = createTestRouter(initialLocation: AppRoutes.updatePassword);
      await tester.pumpWidget(MaterialApp.router(routerConfig: routerD));
      await tester.pumpAndSettle();
      expect(routerD.routerDelegate.currentConfiguration.uri.path, equals(AppRoutes.updatePassword));

      // 11E: Authenticated user on /login redirects to /dashboard cleanly without redirect loop
      AppAuthState.instance.resetForTesting(isInitialized: true, profile: admin);
      final routerE = createTestRouter(initialLocation: AppRoutes.login);
      await tester.pumpWidget(MaterialApp.router(routerConfig: routerE));
      await tester.pumpAndSettle();
      expect(routerE.routerDelegate.currentConfiguration.uri.path, equals(AppRoutes.dashboard));

      // 11F: Unauthenticated user on /dashboard redirects to /login cleanly without redirect loop
      AppAuthState.instance.resetForTesting(isInitialized: true, profile: null);
      final routerF = createTestRouter(initialLocation: AppRoutes.dashboard);
      await tester.pumpWidget(MaterialApp.router(routerConfig: routerF));
      await tester.pumpAndSettle();
      expect(routerF.routerDelegate.currentConfiguration.uri.path, equals(AppRoutes.login));
    });

    // -------------------------------------------------------------------------
    // TEST 12: Existing login flow still works
    // -------------------------------------------------------------------------
    testWidgets('12. Existing login flow still works and restores intended destination', (tester) async {
      AppAuthState.instance.resetForTesting(isInitialized: true, profile: null);

      // User hits login with a redirect target
      final router = createTestRouter(initialLocation: '${AppRoutes.login}?redirect=%2Fbilling');
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(find.text('LOGIN_SCREEN'), findsOneWidget);

      // User logs in successfully
      final admin = createTestProfile(role: 'super_admin', status: 'active');
      AppAuthState.instance.setProfile(admin);
      await tester.pumpAndSettle();

      // Guard automatically directs to the intended destination /billing!
      expect(find.text('BILLING_SCREEN'), findsOneWidget);
      expect(find.text('LOGIN_SCREEN'), findsNothing);
      expect(router.routerDelegate.currentConfiguration.uri.path, equals(AppRoutes.billing));
    });
  });

  group('Route Classification Helpers', () {
    test('AppRoutes.isPublicRoute correctly identifies public vs protected routes', () {
      expect(AppRoutes.isPublicRoute(AppRoutes.login), isTrue);
      expect(AppRoutes.isPublicRoute(AppRoutes.splash), isTrue);
      expect(AppRoutes.isPublicRoute(AppRoutes.updatePassword), isTrue);

      expect(AppRoutes.isPublicRoute(AppRoutes.dashboard), isFalse);
      expect(AppRoutes.isPublicRoute(AppRoutes.schools), isFalse);
      expect(AppRoutes.isPublicRoute(AppRoutes.billing), isFalse);
      expect(AppRoutes.isPublicRoute(AppRoutes.provision), isFalse);
      expect(AppRoutes.isPublicRoute(AppRoutes.settings), isFalse);
      expect(AppRoutes.isPublicRoute(AppRoutes.profile), isFalse);
      expect(AppRoutes.isPublicRoute('/schools/123'), isFalse);
    });

    test('AppRoutes.isProtectedRoute correctly protects all other routes by default', () {
      expect(AppRoutes.isProtectedRoute(AppRoutes.dashboard), isTrue);
      expect(AppRoutes.isProtectedRoute(AppRoutes.schools), isTrue);
      expect(AppRoutes.isProtectedRoute(AppRoutes.billing), isTrue);
      expect(AppRoutes.isProtectedRoute(AppRoutes.provision), isTrue);
      expect(AppRoutes.isProtectedRoute(AppRoutes.settings), isTrue);
      expect(AppRoutes.isProtectedRoute(AppRoutes.profile), isTrue);
      expect(AppRoutes.isProtectedRoute('/unknown-deep-link'), isTrue);

      expect(AppRoutes.isProtectedRoute(AppRoutes.login), isFalse);
      expect(AppRoutes.isProtectedRoute(AppRoutes.splash), isFalse);
      expect(AppRoutes.isProtectedRoute(AppRoutes.updatePassword), isFalse);
    });
  });
}
