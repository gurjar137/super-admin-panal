enum SubscriptionStatus {
  active,
  inactive,
  expired,
  suspended;

  static SubscriptionStatus fromString(String? raw) {
    switch (raw?.toUpperCase().trim()) {
      case 'INACTIVE':
        return SubscriptionStatus.inactive;
      case 'EXPIRED':
        return SubscriptionStatus.expired;
      case 'SUSPENDED':
        return SubscriptionStatus.suspended;
      case 'ACTIVE':
      default:
        return SubscriptionStatus.active;
    }
  }

  String get dbValue => name.toUpperCase();
  String get displayName => name[0].toUpperCase() + name.substring(1);
}

class SubscriptionModel {
  final String id;
  final String schoolAppId; // Foreign key referencing public.school_management_apps(id)
  final String? schoolId; // Authoritative tenant identifier
  final String schoolName;
  final String appName;
  final String planName;
  final SubscriptionStatus status;
  final DateTime startDate;
  final DateTime endDate;
  final String? notes;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const SubscriptionModel({
    required this.id,
    required this.schoolAppId,
    this.schoolId,
    this.schoolName = 'School',
    this.appName = 'School Management App',
    this.planName = 'Annual School License',
    this.status = SubscriptionStatus.active,
    required this.startDate,
    required this.endDate,
    this.notes,
    required this.createdAt,
    this.updatedAt,
  });

  // Compatibility getters for legacy dashboard or views
  String get productDisplayName => 'School Management App';
  String get productId => 'school_management';
  String get planType => planName;

  /// Check if the subscription date window is active today
  bool get isDateActive {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    return !today.isBefore(start) && !today.isAfter(end);
  }

  /// Check if subscription date window has passed
  bool get isDateExpired {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    return today.isAfter(end);
  }

  /// Check if subscription start date is in the future
  bool get isDateNotStarted {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    return today.isBefore(start);
  }

  /// Subscription is considered expired if status == expired OR date is in the past
  bool get isExpired => status == SubscriptionStatus.expired || isDateExpired;

  /// Effective status derived from both stored status and validity dates
  SubscriptionStatus get effectiveStatus {
    if (status == SubscriptionStatus.suspended) return SubscriptionStatus.suspended;
    if (status == SubscriptionStatus.inactive) return SubscriptionStatus.inactive;
    if (status == SubscriptionStatus.expired || isDateExpired) return SubscriptionStatus.expired;
    if (isDateNotStarted) return SubscriptionStatus.inactive;
    return SubscriptionStatus.active;
  }

  factory SubscriptionModel.fromJson(Map<String, dynamic> json) {
    // Check joined school_management_apps -> schools if available
    String appName = 'School Management App';
    String schoolName = 'School';
    String? schoolId = json['school_id']?.toString();

    final appMap = json['school_management_apps'];
    if (appMap is Map) {
      appName = appMap['app_name']?.toString() ?? appName;
      schoolId = schoolId ?? appMap['school_id']?.toString();
      final schoolMap = appMap['schools'];
      if (schoolMap is Map) {
        schoolName = schoolMap['name']?.toString() ?? schoolName;
      }
    }

    final rawSchoolName = json['school_name']?.toString();
    if (rawSchoolName != null && rawSchoolName.isNotEmpty) {
      schoolName = rawSchoolName;
    }

    final rawAppName = json['app_name']?.toString();
    if (rawAppName != null && rawAppName.isNotEmpty) {
      appName = rawAppName;
    }

    return SubscriptionModel(
      id: json['id']?.toString() ?? '',
      schoolAppId: json['school_app_id']?.toString() ?? '',
      schoolId: schoolId,
      schoolName: schoolName,
      appName: appName,
      planName: json['plan_name']?.toString() ?? json['plan_type']?.toString() ?? 'Annual School License',
      status: SubscriptionStatus.fromString(json['status']?.toString()),
      startDate: DateTime.tryParse(json['start_date']?.toString() ?? '') ?? DateTime.now(),
      endDate: DateTime.tryParse(json['end_date']?.toString() ?? '') ?? DateTime.now().add(const Duration(days: 365)),
      notes: json['notes']?.toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'school_app_id': schoolAppId,
      'plan_name': planName,
      'status': status.dbValue,
      'start_date': startDate.toIso8601String().split('T').first,
      'end_date': endDate.toIso8601String().split('T').first,
      if (notes != null) 'notes': notes,
      'created_at': createdAt.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }

  SubscriptionModel copyWith({
    String? planName,
    SubscriptionStatus? status,
    DateTime? startDate,
    DateTime? endDate,
    String? notes,
  }) {
    return SubscriptionModel(
      id: id,
      schoolAppId: schoolAppId,
      schoolId: schoolId,
      schoolName: schoolName,
      appName: appName,
      planName: planName ?? this.planName,
      status: status ?? this.status,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      notes: notes ?? this.notes,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
