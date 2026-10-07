import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/auth/app_auth_state.dart';
import '../core/auth/recovery_session_state.dart';
import '../core/config/supabase_config.dart';
import '../features/audit_logs/audit_logs_screen.dart';
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
import '../services/supabase_service.dart';
import '../widgets/app_shell.dart';
import 'app_routes.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

/// Global Authentication Route Guard.
/// Intercepts every route transition before the destination screen can render.
///
/// Rules:
/// 1. Password recovery (/update-password) is always accessible for recovery sessions.
/// 2. If session initialization has not completed, hold on /splash (preserving deep links).
/// 3. If unauthenticated, redirect all protected routes immediately to /login with target preserved.
/// 4. If authenticated, prevent rendering /login or /splash and redirect to intended path or /dashboard.
/// 5. Protected routes NEVER render without a valid, active Super Admin profile.
String? authRouteGuard(BuildContext context, GoRouterState state) {
  final path = state.uri.path;
  final authState = AppAuthState.instance;

  // 1. Password recovery exception (always public)
  if (path == AppRoutes.updatePassword) {
    return null;
  }

  // 2. Initial session restoration / Startup phase
  if (!authState.isInitialized) {
    if (path == AppRoutes.splash) {
      return null;
    }
    // Deep-linked while session is still restoring:
    // Route to splash to allow session check, preserving target
    final fullTarget = state.uri.toString();
    return '${AppRoutes.splash}?redirect=${Uri.encodeComponent(fullTarget)}';
  }

  // 3. Initialized state evaluation
  final bool isAuthenticated = authState.isAuthenticated;
  final bool isLoginRoute = path == AppRoutes.login;
  final bool isSplashRoute = path == AppRoutes.splash;

  // Case A: Unauthenticated user
  if (!isAuthenticated) {
    if (isLoginRoute) {
      // Already on login page, permit render
      return null;
    }
    // Deep link or protected route access attempt:
    // Determine the intended destination to restore after login
    String targetPath;
    if (isSplashRoute) {
      // If coming from splash, check if a deep-link target was stored in splash params
      final splashRedirect = state.uri.queryParameters['redirect'];
      targetPath = (splashRedirect != null &&
              splashRedirect.isNotEmpty &&
              splashRedirect != AppRoutes.login &&
              splashRedirect != AppRoutes.splash)
          ? splashRedirect
          : AppRoutes.dashboard;
    } else {
      // Direct deep link or navigation to a protected route
      targetPath = state.uri.toString();
    }

    if (targetPath == AppRoutes.login || targetPath == AppRoutes.splash) {
      targetPath = AppRoutes.dashboard;
    }

    return '${AppRoutes.login}?redirect=${Uri.encodeComponent(targetPath)}';
  }

  // Case B: Authenticated Super Admin / Owner
  if (isAuthenticated) {
    // If user is on /login or /splash:
    if (isLoginRoute || isSplashRoute) {
      final redirectParam = state.uri.queryParameters['redirect'];
      if (redirectParam != null &&
          redirectParam.isNotEmpty &&
          redirectParam != AppRoutes.login &&
          redirectParam != AppRoutes.splash) {
        return redirectParam;
      }
      return AppRoutes.dashboard;
    }

    // Protected route: allow access!
    return null;
  }

  return null;
}

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  refreshListenable: AppAuthState.instance,
  redirect: authRouteGuard,
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

    // Settings Route (Deep link support, renders ProfileScreen)
    GoRoute(
      path: AppRoutes.settings,
      pageBuilder: (context, state) => const NoTransitionPage(
        child: ProfileScreen(),
      ),
    ),

    // Audit Logs Route (Immutable Administrative Event Trail)
    GoRoute(
      path: AppRoutes.auditLogs,
      builder: (context, state) => const AuditLogsScreen(),
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

