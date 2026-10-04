enum SchoolStatus {
  active,
  inactive,
  suspended;

  static SchoolStatus fromString(String? raw) {
    switch (raw?.toUpperCase().trim()) {
      case 'ACTIVE':
        return SchoolStatus.active;
      case 'INACTIVE':
        return SchoolStatus.inactive;
      case 'SUSPENDED':
      case 'EXPIRED':
        return SchoolStatus.suspended;
      default:
        return SchoolStatus.active;
    }
  }

  String get dbValue {
    switch (this) {
      case SchoolStatus.active:
        return 'ACTIVE';
      case SchoolStatus.inactive:
        return 'INACTIVE';
      case SchoolStatus.suspended:
        return 'SUSPENDED';
    }
  }

  String get displayName {
    switch (this) {
      case SchoolStatus.active:
        return 'Active';
      case SchoolStatus.inactive:
        return 'Inactive';
      case SchoolStatus.suspended:
        return 'Suspended';
    }
  }
}

class SchoolModel {
  final String id;
  final String schoolCode;
  final String name;
  final String? address;
  final String? phone;
  final String? email;
  final String? logoUrl;
  final String? appName;
  final String? primaryColor;
  final String? secondaryColor;
  final SchoolStatus status;
  final DateTime createdAt;
  final DateTime? updatedAt;

  // Joined Admin Profile / Metadata (Optional)
  final String? adminName;
  final String? adminEmail;
  final String? adminPhone;

  // Subscription Details (Optional/Virtual)
  final DateTime? subscriptionStart;
  final DateTime? subscriptionEnd;
  final int assignedAppsCount;
  final String? activeSubscriptionSummary;

  String get code => schoolCode;

  const SchoolModel({
    required this.id,
    required this.schoolCode,
    required this.name,
    this.address,
    this.phone,
    this.email,
    this.logoUrl,
    this.appName,
    this.primaryColor,
    this.secondaryColor,
    this.status = SchoolStatus.active,
    required this.createdAt,
    this.updatedAt,
    this.adminName,
    this.adminEmail,
    this.adminPhone,
    this.subscriptionStart,
    this.subscriptionEnd,
    this.assignedAppsCount = 0,
    this.activeSubscriptionSummary,
  });

  factory SchoolModel.fromJson(Map<String, dynamic> json) {
    // Aligned strictly with verified columns in public.schools
    final codeVal = json['code'] ?? json['school_code'] ?? '';
    return SchoolModel(
      id: json['id']?.toString() ?? '',
      schoolCode: codeVal.toString(),
      name: json['name']?.toString() ?? 'Unnamed School',
      address: json['address']?.toString(),
      phone: json['phone']?.toString(),
      email: json['email']?.toString(),
      logoUrl: json['logo_url']?.toString(),
      appName: json['app_name']?.toString(),
      primaryColor: json['primary_color']?.toString() ?? '#4F46E5',
      secondaryColor: json['secondary_color']?.toString() ?? '#0EA5E9',
      status: SchoolStatus.fromString(json['status']?.toString()),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'].toString()) : null,
      adminName: json['admin_name']?.toString() ?? json['full_name']?.toString(),
      adminEmail: json['admin_email']?.toString(),
      adminPhone: json['admin_phone']?.toString(),
      subscriptionStart: json['subscription_start'] != null
          ? DateTime.tryParse(json['subscription_start'].toString())
          : null,
      subscriptionEnd: json['subscription_end'] != null
          ? DateTime.tryParse(json['subscription_end'].toString())
          : null,
      assignedAppsCount: (json['assigned_apps_count'] as num?)?.toInt() ?? 0,
      activeSubscriptionSummary: json['active_subscription_summary']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'code': schoolCode,
      'name': name,
      if (address != null) 'address': address,
      if (phone != null) 'phone': phone,
      if (email != null) 'email': email,
      if (logoUrl != null) 'logo_url': logoUrl,
      'status': status.dbValue,
      'created_at': createdAt.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }

  SchoolModel copyWith({
    String? name,
    String? address,
    String? phone,
    String? email,
    String? logoUrl,
    String? appName,
    String? primaryColor,
    String? secondaryColor,
    SchoolStatus? status,
    String? adminName,
    String? adminEmail,
    String? adminPhone,
    DateTime? subscriptionStart,
    DateTime? subscriptionEnd,
    int? assignedAppsCount,
    String? activeSubscriptionSummary,
  }) {
    return SchoolModel(
      id: id,
      schoolCode: schoolCode,
      name: name ?? this.name,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      logoUrl: logoUrl ?? this.logoUrl,
      appName: appName ?? this.appName,
      primaryColor: primaryColor ?? this.primaryColor,
      secondaryColor: secondaryColor ?? this.secondaryColor,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      adminName: adminName ?? this.adminName,
      adminEmail: adminEmail ?? this.adminEmail,
      adminPhone: adminPhone ?? this.adminPhone,
      subscriptionStart: subscriptionStart ?? this.subscriptionStart,
      subscriptionEnd: subscriptionEnd ?? this.subscriptionEnd,
      assignedAppsCount: assignedAppsCount ?? this.assignedAppsCount,
      activeSubscriptionSummary: activeSubscriptionSummary ?? this.activeSubscriptionSummary,
    );
  }
}
