enum SchoolAppStatus {
  active,
  inactive;

  static SchoolAppStatus fromString(String? val) {
    if (val?.toUpperCase().trim() == 'INACTIVE') {
      return SchoolAppStatus.inactive;
    }
    return SchoolAppStatus.active;
  }

  String get dbValue => name.toUpperCase();
  String get displayName => name[0].toUpperCase() + name.substring(1);
}

class SchoolAppModel {
  final String id;
  final String schoolId; // Authoritative tenant identifier (UUID referencing public.schools)
  final String? schoolName;
  final String appName;
  final String? packageName;
  final String? appIdentifier;
  final String currentVersion;
  final String? playStoreUrl;
  final SchoolAppStatus status;
  final String? notes;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const SchoolAppModel({
    required this.id,
    required this.schoolId,
    this.schoolName,
    required this.appName,
    this.packageName,
    this.appIdentifier,
    this.currentVersion = '1.0.0',
    this.playStoreUrl,
    this.status = SchoolAppStatus.active,
    this.notes,
    required this.createdAt,
    this.updatedAt,
  });

  bool get isActive => status == SchoolAppStatus.active;
  String get productDisplayName => 'School Management App';

  factory SchoolAppModel.fromJson(Map<String, dynamic> json) {
    // School join fallback
    final schoolMap = json['schools'];
    final schoolName = schoolMap is Map
        ? schoolMap['name']?.toString()
        : json['school_name']?.toString();

    final rawStatus = json['status']?.toString();

    return SchoolAppModel(
      id: json['id']?.toString() ?? '',
      schoolId: json['school_id']?.toString() ?? '',
      schoolName: schoolName,
      appName: json['app_name']?.toString() ?? 'School Management App',
      packageName: json['package_name']?.toString(),
      appIdentifier: json['app_identifier']?.toString(),
      currentVersion: json['current_version']?.toString() ?? '1.0.0',
      playStoreUrl: json['play_store_url']?.toString(),
      status: SchoolAppStatus.fromString(rawStatus),
      notes: json['notes']?.toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'school_id': schoolId,
      'app_name': appName,
      if (packageName != null) 'package_name': packageName,
      if (appIdentifier != null) 'app_identifier': appIdentifier,
      'current_version': currentVersion,
      if (playStoreUrl != null) 'play_store_url': playStoreUrl,
      'status': status.dbValue,
      if (notes != null) 'notes': notes,
      'created_at': createdAt.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }

  SchoolAppModel copyWith({
    String? appName,
    String? packageName,
    String? appIdentifier,
    String? currentVersion,
    String? playStoreUrl,
    SchoolAppStatus? status,
    String? notes,
  }) {
    return SchoolAppModel(
      id: id,
      schoolId: schoolId,
      schoolName: schoolName,
      appName: appName ?? this.appName,
      packageName: packageName ?? this.packageName,
      appIdentifier: appIdentifier ?? this.appIdentifier,
      currentVersion: currentVersion ?? this.currentVersion,
      playStoreUrl: playStoreUrl ?? this.playStoreUrl,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
