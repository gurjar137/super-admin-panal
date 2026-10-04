import '../core/constants/billing_constants.dart';

class SchoolBillingSettingsModel {
  final String id;
  final String schoolId;
  final double ratePerStudent;
  final String currency;
  final String billingCycle;
  final bool active;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const SchoolBillingSettingsModel({
    required this.id,
    required this.schoolId,
    this.ratePerStudent = BillingConstants.defaultRatePerStudent,
    this.currency = BillingConstants.defaultCurrency,
    this.billingCycle = BillingConstants.defaultBillingCycle,
    this.active = true,
    required this.createdAt,
    this.updatedAt,
  });

  factory SchoolBillingSettingsModel.defaultForSchool(String schoolId) {
    return SchoolBillingSettingsModel(
      id: '',
      schoolId: schoolId,
      ratePerStudent: BillingConstants.defaultRatePerStudent,
      currency: BillingConstants.defaultCurrency,
      billingCycle: BillingConstants.defaultBillingCycle,
      active: true,
      createdAt: DateTime.now(),
    );
  }

  factory SchoolBillingSettingsModel.fromJson(Map<String, dynamic> json) {
    final rawRate = json['rate_per_student'];
    double parsedRate = BillingConstants.defaultRatePerStudent;
    if (rawRate is num) {
      parsedRate = rawRate.toDouble();
    } else if (rawRate != null) {
      parsedRate = double.tryParse(rawRate.toString()) ?? BillingConstants.defaultRatePerStudent;
    }

    return SchoolBillingSettingsModel(
      id: json['id']?.toString() ?? '',
      schoolId: json['school_id']?.toString() ?? '',
      ratePerStudent: parsedRate,
      currency: json['currency']?.toString() ?? BillingConstants.defaultCurrency,
      billingCycle: json['billing_cycle']?.toString() ?? BillingConstants.defaultBillingCycle,
      active: json['active'] == true,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id.isNotEmpty) 'id': id,
      'school_id': schoolId,
      'rate_per_student': ratePerStudent,
      'currency': currency,
      'billing_cycle': billingCycle,
      'active': active,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  SchoolBillingSettingsModel copyWith({
    String? id,
    String? schoolId,
    double? ratePerStudent,
    String? currency,
    String? billingCycle,
    bool? active,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SchoolBillingSettingsModel(
      id: id ?? this.id,
      schoolId: schoolId ?? this.schoolId,
      ratePerStudent: ratePerStudent ?? this.ratePerStudent,
      currency: currency ?? this.currency,
      billingCycle: billingCycle ?? this.billingCycle,
      active: active ?? this.active,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
