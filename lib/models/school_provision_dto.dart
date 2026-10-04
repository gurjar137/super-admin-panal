import 'school_model.dart';

class SchoolProvisionDto {
  String name;
  String schoolCode;
  String? logoUrl;
  String phone;
  String email;
  String address;

  // Initial Admin
  String initialAdminName;
  String initialAdminEmail;
  String initialAdminPhone;

  // Status (only verified DB column)
  SchoolStatus status;

  SchoolProvisionDto({
    this.name = '',
    this.schoolCode = '',
    this.logoUrl,
    this.phone = '',
    this.email = '',
    this.address = '',
    this.initialAdminName = '',
    this.initialAdminEmail = '',
    this.initialAdminPhone = '',
    this.status = SchoolStatus.active,
  });

  /// Normalize school code: UPPERCASE, alphanumeric with optional dashes, trimmed
  static String normalizeCode(String code) {
    return code.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9\-]'), '');
  }

  /// Validation helper returning an error map (or empty if valid)
  Map<String, String> validate() {
    final errors = <String, String>{};

    if (name.trim().isEmpty) {
      errors['name'] = 'School name is required';
    } else if (name.trim().length < 3) {
      errors['name'] = 'School name must be at least 3 characters';
    }

    final cleanCode = normalizeCode(schoolCode);
    if (cleanCode.isEmpty) {
      errors['schoolCode'] = 'School code is required';
    } else if (cleanCode.length < 3 || cleanCode.length > 12) {
      errors['schoolCode'] = 'Code must be between 3 and 12 alphanumeric characters';
    }

    if (email.trim().isEmpty) {
      errors['email'] = 'School email is required';
    } else if (!RegExp(r'^[\w\.-]+@[\w\.-]+\.\w+$').hasMatch(email.trim())) {
      errors['email'] = 'Enter a valid school email address';
    }

    if (phone.trim().isEmpty) {
      errors['phone'] = 'School phone number is required';
    }

    if (address.trim().isEmpty) {
      errors['address'] = 'School address is required';
    }

    if (initialAdminName.trim().isEmpty) {
      errors['initialAdminName'] = 'Initial admin name is required';
    }

    if (initialAdminEmail.trim().isEmpty) {
      errors['initialAdminEmail'] = 'Initial admin email is required';
    } else if (!RegExp(r'^[\w\.-]+@[\w\.-]+\.\w+$').hasMatch(initialAdminEmail.trim())) {
      errors['initialAdminEmail'] = 'Enter a valid administrator email';
    }

    if (initialAdminPhone.trim().isEmpty) {
      errors['initialAdminPhone'] = 'Initial admin phone is required';
    }

    return errors;
  }

  /// Exports map formatted for Supabase insertion strictly aligned with public.schools columns
  Map<String, dynamic> toSchoolPayload() {
    return {
      'name': name.trim(),
      'code': normalizeCode(schoolCode),
      if (phone.trim().isNotEmpty) 'phone': phone.trim(),
      if (email.trim().isNotEmpty) 'email': email.trim().toLowerCase(),
      if (address.trim().isNotEmpty) 'address': address.trim(),
      if (logoUrl != null && logoUrl!.trim().isNotEmpty) 'logo_url': logoUrl!.trim(),
      'status': status.dbValue,
    };
  }
}
