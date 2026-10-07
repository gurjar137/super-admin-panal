import 'package:flutter/foundation.dart';
import 'school_admin_model.dart';
import 'school_app_model.dart';
import 'school_model.dart';
import 'subscription_model.dart';

/// Complete, validated input request for atomic school provisioning
@immutable
class SchoolProvisioningRequest {
  // 1. School Information
  final String schoolName;
  final String schoolCode;
  final String? address;
  final String? phone;
  final String? email;
  final String? logoUrl;
  final SchoolStatus schoolStatus;

  // 2. Dedicated App Information
  final String appName;
  final String packageBundleId;
  final String appIdentifier;
  final String currentVersion;
  final String? playStoreUrl;
  final SchoolAppStatus appStatus;

  // 3. Administrator Information
  final String adminFullName;
  final String adminEmail;
  final String? adminPhone;
  final String adminPassword;

  // 4. Subscription & Billing Information
  final String planName;
  final DateTime startDate;
  final DateTime endDate;
  final SubscriptionStatus subscriptionStatus;
  final String? subscriptionNotes;
  final double ratePerStudent;
  final String currency;
  final String billingCycle;

  // 5. Idempotency Key (prevents duplicate submission)
  final String idempotencyKey;

  const SchoolProvisioningRequest({
    required this.schoolName,
    required this.schoolCode,
    this.address,
    this.phone,
    this.email,
    this.logoUrl,
    this.schoolStatus = SchoolStatus.active,
    required this.appName,
    required this.packageBundleId,
    required this.appIdentifier,
    this.currentVersion = '1.0.0',
    this.playStoreUrl,
    this.appStatus = SchoolAppStatus.active,
    required this.adminFullName,
    required this.adminEmail,
    this.adminPhone,
    required this.adminPassword,
    this.planName = 'Annual School License',
    required this.startDate,
    required this.endDate,
    this.subscriptionStatus = SubscriptionStatus.active,
    this.subscriptionNotes,
    this.ratePerStudent = 20.00,
    this.currency = 'INR',
    this.billingCycle = 'MONTHLY',
    required this.idempotencyKey,
  });

  /// Validates all fields across all components before submission
  Map<String, String> validate() {
    final errors = <String, String>{};

    // School validation
    if (schoolName.trim().isEmpty) {
      errors['schoolName'] = 'School Name is required';
    } else if (schoolName.trim().length < 3) {
      errors['schoolName'] = 'School Name must be at least 3 characters';
    }

    final cleanCode = schoolCode.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9\-]'), '');
    if (cleanCode.isEmpty) {
      errors['schoolCode'] = 'School Code is required';
    } else if (cleanCode.length < 3 || cleanCode.length > 16) {
      errors['schoolCode'] = 'School Code must be between 3 and 16 alphanumeric characters';
    }

    // App validation
    if (appName.trim().isEmpty) {
      errors['appName'] = 'App Name is required';
    }
    if (appIdentifier.trim().isEmpty) {
      errors['appIdentifier'] = 'App Identifier is required';
    }
    final pkg = packageBundleId.trim().toLowerCase();
    if (pkg.isEmpty) {
      errors['packageBundleId'] = 'Android Package Name is required';
    } else if (!RegExp(r'^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$').hasMatch(pkg)) {
      errors['packageBundleId'] = 'Invalid package name. Must follow reverse-domain format (e.g. com.school.app)';
    }

    // Admin validation
    if (adminFullName.trim().isEmpty) {
      errors['adminFullName'] = 'Administrator Name is required';
    }
    final adminMail = adminEmail.trim().toLowerCase();
    if (adminMail.isEmpty || !RegExp(r'^[\w\.-]+@[\w\.-]+\.\w+$').hasMatch(adminMail)) {
      errors['adminEmail'] = 'Enter a valid administrator email address';
    }
    if (adminPassword.length < 8) {
      errors['adminPassword'] = 'Administrator password must be at least 8 characters';
    }

    // Subscription validation
    if (planName.trim().isEmpty) {
      errors['planName'] = 'Plan Name is required';
    }
    if (endDate.isBefore(startDate)) {
      errors['endDate'] = 'Subscription end date cannot be earlier than start date';
    }

    return errors;
  }
}

/// The result returned upon successful atomic school provisioning
@immutable
class SchoolProvisioningResult {
  final SchoolModel school;
  final SchoolAppModel app;
  final SchoolAdminModel admin;
  final SubscriptionModel subscription;
  final String? billingSettingsId;
  final bool isIdempotentReplay;

  const SchoolProvisioningResult({
    required this.school,
    required this.app,
    required this.admin,
    required this.subscription,
    this.billingSettingsId,
    this.isIdempotentReplay = false,
  });
}
