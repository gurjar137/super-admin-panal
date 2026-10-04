import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/auth/recovery_session_state.dart';
import '../core/config/supabase_config.dart';
import '../features/applications/applications_screen.dart';
import '../features/assignments/assignments_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/splash_screen.dart';
import '../features/auth/update_password_screen.dart';
import '../features/billing/billing_dashboard_screen.dart';
import '../features/billing/invoice_details_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/details/school_details_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/provisioning/school_provisioning_screen.dart';
import '../features/school_apps/app_details_screen.dart';
import '../features/schools/schools_screen.dart';
import '../features/subscriptions/subscriptions_screen.dart';
import '../services/supabase_service.dart';
import '../widgets/app_shell.dart';
import 'app_routes.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: (RecoverySessionState.codeDetected ||
          RecoverySessionState.exchangeAttempted ||
          RecoverySessionState.recoveryEventReceived)
      ? AppRoutes.updatePassword
      : AppRoutes.splash,
  routes: [
    // Splash Route
    GoRoute(
      path: AppRoutes.splash,
      builder: (context, state) => const SplashScreen(),
    ),

    // Login Route
    GoRoute(
      path: AppRoutes.login,
      builder: (context, state) => const LoginScreen(),
    ),

    // Provisioning Route
    GoRoute(
      path: AppRoutes.provision,
      builder: (context, state) => const SchoolProvisioningScreen(),
    ),

    // Dedicated App Details Route (NO build buttons, pure metadata)
    GoRoute(
      path: AppRoutes.appDetails,
      builder: (context, state) {
        final appId = state.pathParameters['id'] ?? '';
        return AppDetailsScreen(appId: appId);
      },
    ),

    // Stateful Nested Shell Route for Central Control Navigation
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return AppShell(navigationShell: navigationShell);
      },
      branches: [
        // Branch 0: Dashboard
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.dashboard,
              pageBuilder: (context, state) => const NoTransitionPage(
                child: DashboardScreen(),
              ),
            ),
          ],
        ),

        // Branch 1: Schools Directory & School Details
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.schools,
              pageBuilder: (context, state) => const NoTransitionPage(
                child: SchoolsScreen(),
              ),
              routes: [
                GoRoute(
                  path: ':id',
                  pageBuilder: (context, state) {
                    final schoolId = state.pathParameters['id'] ?? '';
                    return MaterialPage(
                      child: SchoolDetailsScreen(schoolId: schoolId),
                    );
                  },
                ),
              ],
            ),
          ],
        ),

        // Branch 2: Billing & Invoices
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.billing,
              pageBuilder: (context, state) => const NoTransitionPage(
                child: BillingDashboardScreen(),
              ),
            ),
          ],
        ),

        // Branch 3: Profile / Settings
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.profile,
              pageBuilder: (context, state) => const NoTransitionPage(
                child: ProfileScreen(),
              ),
            ),
          ],
        ),
      ],
    ),

    // Invoice Details Route
    GoRoute(
      path: AppRoutes.invoiceDetails,
      builder: (context, state) {
        final invoiceId = state.pathParameters['id'] ?? '';
        return InvoiceDetailsScreen(invoiceId: invoiceId);
      },
    ),

    // Password Recovery / Update Password Route
    GoRoute(
      path: AppRoutes.updatePassword,
      builder: (context, state) => const UpdatePasswordScreen(),
    ),

    // Standalone secondary routes (available if deep-linked, unlinked from main nav)
    GoRoute(
      path: AppRoutes.applications,
      builder: (context, state) => const ApplicationsScreen(),
    ),
    GoRoute(
      path: AppRoutes.assignments,
      builder: (context, state) => const AssignmentsScreen(),
    ),
    GoRoute(
      path: AppRoutes.subscriptions,
      builder: (context, state) => const SubscriptionsScreen(),
    ),
  ],
);

/// Initialize auth state listener for password recovery redirects
void initAuthRecoveryListener() {
  if (!SupabaseConfig.isConfigured) return;
  try {
    final client = SupabaseService.instance.client;
    client?.auth.onAuthStateChange.listen((data) {
      final AuthChangeEvent event = data.event;
      debugPrint('[AppRouter] Supabase AuthChangeEvent: $event');
      if (event == AuthChangeEvent.passwordRecovery) {
        debugPrint('[AppRouter] PASSWORD_RECOVERY detected -> navigating to ${AppRoutes.updatePassword}');
        appRouter.go(AppRoutes.updatePassword);
      }
    });
  } catch (e) {
    debugPrint('[AppRouter] Error initializing auth recovery listener: $e');
  }
}

