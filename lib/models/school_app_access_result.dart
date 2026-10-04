import 'school_app_model.dart';
import 'school_model.dart';
import 'subscription_model.dart';

/// Machine-readable code for the evaluated access state
enum SchoolAppAccessCode {
  granted,
  schoolInactive,
  appInactive,
  noSubscription,
  subscriptionSuspended,
  subscriptionInactive,
  subscriptionExpired,
  notStartedYet,
}

/// Structured outcome of evaluating dedicated School Management App access.
class SchoolAppAccessResult {
  final bool isGranted;
  final SchoolAppAccessCode code;
  final String userMessage;
  final String detailedReason;

  const SchoolAppAccessResult({
    required this.isGranted,
    required this.code,
    required this.userMessage,
    required this.detailedReason,
  });

  bool get isDenied => !isGranted;

  static const SchoolAppAccessResult accessGranted = SchoolAppAccessResult(
    isGranted: true,
    code: SchoolAppAccessCode.granted,
    userMessage: 'Access Granted • School Management App is fully active',
    detailedReason: 'Institution, dedicated mobile app, and subscription are all in active standing within the validity window.',
  );
}

/// Centralized, date-aware access evaluation function for the School Management App.
/// Evaluates:
/// 1. School status
/// 2. Dedicated App status
/// 3. Subscription status
/// 4. Start date
/// 5. End date
SchoolAppAccessResult evaluateSchoolManagementAppAccess({
  required SchoolStatus schoolStatus,
  required SchoolAppStatus appStatus,
  required SubscriptionModel? subscription,
  DateTime? referenceDate,
}) {
  // 1. School Status Check
  if (schoolStatus != SchoolStatus.active) {
    return const SchoolAppAccessResult(
      isGranted: false,
      code: SchoolAppAccessCode.schoolInactive,
      userMessage: 'School account is inactive.',
      detailedReason: 'The tenant school account has been deactivated or suspended in Super Admin.',
    );
  }

  // 2. Dedicated App Status Check
  if (appStatus != SchoolAppStatus.active) {
    return const SchoolAppAccessResult(
      isGranted: false,
      code: SchoolAppAccessCode.appInactive,
      userMessage: 'Application access is currently disabled.',
      detailedReason: 'Access for this specific School Management App has been toggled off by Super Admin.',
    );
  }

  // 3. Subscription Existence Check
  if (subscription == null) {
    return const SchoolAppAccessResult(
      isGranted: false,
      code: SchoolAppAccessCode.noSubscription,
      userMessage: 'No subscription configured for this school app.',
      detailedReason: 'A valid subscription record must be created by Super Admin to activate app access.',
    );
  }

  // 4. Stored Subscription Status Check
  switch (subscription.status) {
    case SubscriptionStatus.suspended:
      return const SchoolAppAccessResult(
        isGranted: false,
        code: SchoolAppAccessCode.subscriptionSuspended,
        userMessage: 'Application subscription has been suspended.',
        detailedReason: 'The subscription was manually suspended by Super Admin.',
      );
    case SubscriptionStatus.inactive:
      return const SchoolAppAccessResult(
        isGranted: false,
        code: SchoolAppAccessCode.subscriptionInactive,
        userMessage: 'Application subscription is inactive.',
        detailedReason: 'The subscription is currently marked inactive.',
      );
    case SubscriptionStatus.expired:
      return const SchoolAppAccessResult(
        isGranted: false,
        code: SchoolAppAccessCode.subscriptionExpired,
        userMessage: 'Your subscription has expired. Please contact the administrator.',
        detailedReason: 'The subscription is explicitly marked as expired in the database.',
      );
    case SubscriptionStatus.active:
      break;
  }

  // 5. Date-Aware Validity Check
  final today = referenceDate ?? DateTime.now();
  final todayDate = DateTime(today.year, today.month, today.day);
  final startDate = DateTime(
    subscription.startDate.year,
    subscription.startDate.month,
    subscription.startDate.day,
  );
  final endDate = DateTime(
    subscription.endDate.year,
    subscription.endDate.month,
    subscription.endDate.day,
  );

  if (todayDate.isBefore(startDate)) {
    return const SchoolAppAccessResult(
      isGranted: false,
      code: SchoolAppAccessCode.notStartedYet,
      userMessage: 'Your subscription has not started yet.',
      detailedReason: 'The subscription start date is scheduled in the future.',
    );
  }

  if (todayDate.isAfter(endDate)) {
    return const SchoolAppAccessResult(
      isGranted: false,
      code: SchoolAppAccessCode.subscriptionExpired,
      userMessage: 'Your subscription has expired. Please contact the administrator.',
      detailedReason: 'The subscription end date has passed.',
    );
  }

  // All 5 conditions passed!
  return SchoolAppAccessResult.accessGranted;
}

/// Convenience helper returning a simple boolean access decision.
bool isSchoolManagementAppAccessible({
  required SchoolStatus schoolStatus,
  required SchoolAppStatus appStatus,
  required SubscriptionModel? subscription,
  DateTime? referenceDate,
}) {
  return evaluateSchoolManagementAppAccess(
    schoolStatus: schoolStatus,
    appStatus: appStatus,
    subscription: subscription,
    referenceDate: referenceDate,
  ).isGranted;
}
