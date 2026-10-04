class SchoolAdminModel {
  final String id;
  final String authUserId;
  final String schoolId;
  final String fullName;
  final String email;
  final String? phone;
  final String role;
  final String status;
  final String? designation;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const SchoolAdminModel({
    required this.id,
    required this.authUserId,
    required this.schoolId,
    required this.fullName,
    required this.email,
    this.phone,
    this.role = 'school_admin',
    this.status = 'active',
    this.designation = 'School Administrator',
    this.createdAt,
    this.updatedAt,
  });

  bool get isActive => status.toLowerCase() == 'active';
  bool get isSchoolAdmin => role.toLowerCase() == 'school_admin';

  factory SchoolAdminModel.fromJson(Map<String, dynamic> json) {
    return SchoolAdminModel(
      id: json['id']?.toString() ?? '',
      authUserId: json['auth_user_id']?.toString() ?? '',
      schoolId: json['school_id']?.toString() ?? '',
      fullName: json['full_name']?.toString() ?? json['name']?.toString() ?? 'School Admin',
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString(),
      role: json['role']?.toString() ?? 'school_admin',
      status: json['status']?.toString() ?? 'active',
      designation: json['designation']?.toString() ?? 'School Administrator',
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'auth_user_id': authUserId,
      'school_id': schoolId,
      'full_name': fullName,
      'email': email,
      'phone': phone,
      'role': role,
      'status': status,
      'designation': designation,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }

  SchoolAdminModel copyWith({
    String? id,
    String? authUserId,
    String? schoolId,
    String? fullName,
    String? email,
    String? phone,
    String? role,
    String? status,
    String? designation,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SchoolAdminModel(
      id: id ?? this.id,
      authUserId: authUserId ?? this.authUserId,
      schoolId: schoolId ?? this.schoolId,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      status: status ?? this.status,
      designation: designation ?? this.designation,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
