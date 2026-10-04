class AppRoutes {
  static const String splash = '/splash';
  static const String login = '/login';
  static const String updatePassword = '/update-password';
  static const String dashboard = '/dashboard';
  static const String schools = '/schools';
  static const String schoolDetails = '/schools/:id';
  static const String billing = '/billing';
  static const String invoiceDetails = '/invoices/:id';
  static const String applications = '/applications';
  static const String assignments = '/assignments';
  static const String subscriptions = '/subscriptions';
  static const String appDetails = '/apps/:id';
  static const String provision = '/provision';
  static const String profile = '/profile';

  static String schoolDetailsPath(String id) => '/schools/$id';
  static String appDetailsPath(String id) => '/apps/$id';
  static String invoiceDetailsPath(String id) => '/invoices/$id';
}
