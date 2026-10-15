class SuperAdminProfile {
  final String id;
  final String authUserId;
  final String email;
  final String name;
  final String role;
  final String status;
  final String? schoolId;
  final DateTime? createdAt;

  const SuperAdminProfile({
    required this.id,
    required this.authUserId,
    required this.email,
    required this.name,
    required this.role,
    required this.status,
    this.schoolId,
    this.createdAt,
  });

  bool get isSuperAdmin =>
      role.toLowerCase() == 'super_admin' ||
      role.toLowerCase() == 'platform_admin' ||
      role.toLowerCase() == 'owner';

  factory SuperAdminProfile.fromJson(Map<String, dynamic> json) {
    return SuperAdminProfile(
      id: json['id']?.toString() ?? '',
      authUserId: json['auth_user_id']?.toString() ?? json['id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      name: json['full_name']?.toString() ?? json['name']?.toString() ?? 'Super Admin',
      role: json['role']?.toString() ?? 'super_admin',
      status: json['status']?.toString() ?? 'active',
      schoolId: json['school_id']?.toString(),
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'auth_user_id': authUserId,
      'email': email,
      'name': name,
      'role': role,
      'status': status,
      'school_id': schoolId,
    };
  }
}
