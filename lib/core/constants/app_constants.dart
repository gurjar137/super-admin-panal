class AppConstants {
  static const String appName = 'Super Admin';
  static const String appTagline = 'Multi-Tenant School Management OS';
  static const String appVersion = 'v1.0.0';

  // Session & Storage keys
  static const String sessionKey = 'super_admin_session';

  /// TEMPORARY DEVELOPMENT ONLY:
  /// When true, bypasses the initial Super Admin login screen check.
  /// DISABLED for production Supabase authentication.
  static const bool isDevAuthBypassEnabled = false;

  // Standard paddings
  static const double paddingXS = 4.0;
  static const double paddingS = 8.0;
  static const double paddingM = 16.0;
  static const double paddingL = 24.0;
  static const double paddingXL = 32.0;

  // Responsive Breakpoints
  static const double breakpointMobile = 600.0;
  static const double breakpointTablet = 900.0;
  static const double breakpointDesktop = 1200.0;
  static const double maxContentWidth = 1200.0;
}
