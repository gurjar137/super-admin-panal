class AppRoutes {
  static const String splash = '/splash';
  static const String login = '/login';
  static const String updatePassword = '/update-password';
  static const String dashboard = '/dashboard';
  static const String schools = '/schools';
  static const String schoolDetails = '/schools/:id';
  static const String billing = '/billing';
  static const String invoiceDetails = '/invoices/:id';
  static const String appDetails = '/apps/:id';
  static const String provision = '/provision';
  static const String profile = '/profile';
  static const String settings = '/settings';
  static const String auditLogs = '/audit-logs';

  static String schoolDetailsPath(String id) => '/schools/$id';
  static String appDetailsPath(String id) => '/apps/$id';
  static String invoiceDetailsPath(String id) => '/invoices/$id';

  /// Authoritative check for public routes. Only /login, /update-password, and /splash are public.
  static bool isPublicRoute(String path) {
    final cleanPath = path.split('?').first.trim();
    return cleanPath == login ||
        cleanPath == splash ||
        cleanPath == updatePassword;
  }

  /// Every route that is not explicitly public is protected by default.
  static bool isProtectedRoute(String path) => !isPublicRoute(path);
}
