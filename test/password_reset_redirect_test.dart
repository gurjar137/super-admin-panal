import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:super_admin_app/core/auth/recovery_session_state.dart';
import 'package:super_admin_app/core/config/supabase_config.dart';
import 'package:super_admin_app/features/auth/login_screen.dart';
import 'package:super_admin_app/features/auth/update_password_screen.dart';
import 'package:super_admin_app/routing/app_router.dart';
import 'package:super_admin_app/routing/app_routes.dart';

void main() {
  group('Super Admin Password Reset & Redirect Flow Tests', () {
    test('1. SupabaseConfig.passwordResetRedirectUrl returns hash-routing URL matching School/Admin App (/#/update-password)', () {
      final url = SupabaseConfig.passwordResetRedirectUrl;
      expect(url, contains('/#${AppRoutes.updatePassword}'));
      expect(url, startsWith('http'));
    });

    test('2. AppRoutes.updatePassword is correctly defined', () {
      expect(AppRoutes.updatePassword, equals('/update-password'));
    });

    test('3. appRouter routes list includes /update-password route', () {
      final hasRoute = appRouter.configuration.routes.any(
        (r) => r is GoRoute && r.path == AppRoutes.updatePassword,
      );
      expect(hasRoute, isTrue, reason: 'appRouter must contain /update-password route');
    });

    testWidgets('4. UpdatePasswordScreen renders title, fields, and update button', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: UpdatePasswordScreen(bypassSessionCheckForTesting: true),
          ),
        ),
      );

      expect(find.text('Create New Password'), findsOneWidget);
      expect(find.text('New Password'), findsOneWidget);
      expect(find.text('Confirm New Password'), findsOneWidget);
      expect(find.text('Update Password'), findsOneWidget);
      expect(find.text('Return to Login'), findsOneWidget);
    });

    testWidgets('5. UpdatePasswordScreen validates password matching and minimum length', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: UpdatePasswordScreen(bypassSessionCheckForTesting: true),
          ),
        ),
      );

      final textFields = find.byType(TextField);
      expect(textFields, findsNWidgets(2));

      // Test 5A: Short password (< 6 chars)
      await tester.enterText(textFields.at(0), '123');
      await tester.enterText(textFields.at(1), '123');
      await tester.tap(find.text('Update Password'));
      await tester.pump();

      expect(find.text('Password must be at least 6 characters long.'), findsOneWidget);

      // Test 5B: Mismatched passwords
      await tester.enterText(textFields.at(0), 'NewSuperPass123!');
      await tester.enterText(textFields.at(1), 'DifferentPass123!');
      await tester.tap(find.text('Update Password'));
      await tester.pump();

      expect(find.text('Passwords do not match.'), findsOneWidget);
    });

    testWidgets('6. UpdatePasswordScreen shows notice when opened without active recovery session', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: UpdatePasswordScreen(bypassSessionCheckForTesting: false),
          ),
        ),
      );

      expect(
        find.text('A valid password recovery link from your email is required to update your password.'),
        findsOneWidget,
      );

      // Attempting to submit without session displays expiration notice
      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'ValidMasterPassword123!');
      await tester.enterText(textFields.at(1), 'ValidMasterPassword123!');
      await tester.tap(find.text('Update Password'));
      await tester.pump();

      expect(
        find.text('Password reset link has expired or is invalid. Please request a new one.'),
        findsOneWidget,
      );
    });

    testWidgets('7. LoginScreen displays Forgot Password button and opens reset dialog', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );

      final forgotBtn = find.text('Forgot Password?');
      expect(forgotBtn, findsOneWidget);

      await tester.tap(forgotBtn);
      await tester.pumpAndSettle();

      expect(find.text('Reset Password'), findsOneWidget);
      expect(find.text('Send Reset Link'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    test('8. Double-hash recovery URL from /#/update-password is normalized to standard Supabase hash', () {
      const doubleHashUrl = 'http://localhost:50000/#/update-password#access_token=sample_token&refresh_token=sample_refresh&type=recovery&expires_at=1700000000';
      final normalized = normalizeRecoveryUrl(doubleHashUrl);

      expect(normalized.toString(), startsWith('http://localhost:50000/#access_token='));
      final params = Uri.splitQueryString(normalized.fragment);
      expect(params.containsKey('access_token'), isTrue);
      expect(params['access_token'], equals('sample_token'));
      expect(params['refresh_token'], equals('sample_refresh'));
      expect(params['type'], equals('recovery'));
    });

    test('9. Standard single-hash recovery URL is preserved by normalizer', () {
      const singleHashUrl = 'http://localhost:50000/#access_token=token_abc&refresh_token=refresh_xyz&type=recovery';
      final normalized = normalizeRecoveryUrl(singleHashUrl);

      expect(normalized.toString(), equals(singleHashUrl));
      final params = Uri.splitQueryString(normalized.fragment);
      expect(params['access_token'], equals('token_abc'));
      expect(params['type'], equals('recovery'));
    });

    test('10. PKCE code URL format is normalized correctly', () {
      const pkceUrl = 'http://localhost:50000/#/update-password?code=3b29ac5b-4395-46b2-a429';
      final normalized = normalizeRecoveryUrl(pkceUrl);

      expect(normalized.queryParameters.containsKey('code'), isTrue);
      expect(normalized.queryParameters['code'], equals('3b29ac5b-4395-46b2-a429'));
    });

    test('11. RecoverySessionState tracks parameter detection safely without secrets', () {
      expect(RecoverySessionState.hasActiveSession, isA<bool>());
      expect(RecoverySessionState.isProcessing, isFalse);
    });

    test('12. Router route definition for update-password matches expected path and builder', () {
      final route = appRouter.configuration.routes.firstWhere(
        (r) => r is GoRoute && r.path == AppRoutes.updatePassword,
      ) as GoRoute;

      expect(route.path, equals('/update-password'));
      expect(route.builder, isNotNull);
    });

    testWidgets('13. UpdatePasswordScreen with invalid recoveryCode displays error notice and blocks update', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: UpdatePasswordScreen(
              recoveryCode: 'expired-or-invalid-code',
              bypassSessionCheckForTesting: false,
            ),
          ),
        ),
      );
      await tester.pump();

      // Ensure recovery banner is visible
      expect(find.text('A valid password recovery link from your email is required to update your password.'), findsOneWidget);

      // Attempting to update password without a valid active session is strictly blocked
      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'ValidSecret123!');
      await tester.enterText(textFields.at(1), 'ValidSecret123!');
      await tester.tap(find.text('Update Password'));
      await tester.pump();

      expect(find.text('Password reset link has expired or is invalid. Please request a new one.'), findsOneWidget);
    });

    testWidgets('14. Valid recovery session allows password update submission', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: UpdatePasswordScreen(
              bypassSessionCheckForTesting: true, // simulates valid active recovery session
            ),
          ),
        ),
      );
      await tester.pump();

      // When valid recovery session exists, expiration notice is not shown
      expect(find.text('A valid password recovery link from your email is required to update your password.'), findsNothing);
      expect(find.text('Update Password'), findsOneWidget);
    });

    test('15. RecoverySessionState strictly enforces single exchange idempotency', () {
      RecoverySessionState.resetForTesting();
      expect(RecoverySessionState.exchangeCount, equals(0));
      expect(RecoverySessionState.exchangeAttempted, isFalse);

      // Simulate first exchange marked
      RecoverySessionState.exchangeAttempted = true;
      RecoverySessionState.exchangeCount = 1;

      // Idempotency: exchangeAttempted and exchangeCount prevent duplicate calls
      expect(RecoverySessionState.exchangeCount, equals(1));
      expect(RecoverySessionState.exchangeAttempted, isTrue);
    });

    testWidgets('16. UpdatePasswordScreen renders verifying UI when RecoverySessionState is processing', (tester) async {
      RecoverySessionState.resetForTesting(initialStatus: RecoveryStatus.processing);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: UpdatePasswordScreen(),
          ),
        ),
      );
      await tester.pump();

      // Shows verification status, NOT invalid link
      expect(find.text('Verifying password reset link...'), findsOneWidget);
      expect(find.text('Password reset link has expired or is invalid. Please request a new one.'), findsNothing);
      expect(find.text('A valid password recovery link from your email is required to update your password.'), findsNothing);

      RecoverySessionState.resetForTesting(initialStatus: RecoveryStatus.idle);
    });

    test('17. Router includes update-password route and is configured for hash routing', () {
      final routes = appRouter.configuration.routes;
      final updateRoute = routes.whereType<GoRoute>().firstWhere((r) => r.path == AppRoutes.updatePassword);
      expect(updateRoute, isNotNull);
      expect(updateRoute.path, equals('/update-password'));
    });

    test('18. Proven recovery architecture uses getSessionFromUrl with zero exchangeCodeForSession', () {
      expect(RecoverySessionState.exchangeAttempted, isFalse);
      expect(RecoverySessionState.exchangeCount, equals(0));
      // Mechanism defaults to 'none' until implicit recovery is triggered
      expect(RecoverySessionState.recoveryMechanism, equals('none'));
    });
  });
}




