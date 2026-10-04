class AcademicYearOption {
  final String id;
  final String name;
  final String status;
  final DateTime? startDate;
  final DateTime? endDate;

  const AcademicYearOption({
    required this.id,
    required this.name,
    required this.status,
    this.startDate,
    this.endDate,
  });

  bool get isActive => status.toLowerCase() == 'active';

  /// Resolves the current/active academic year from existing academic-year records
  /// using status and date boundaries without inventing unmapped schema columns.
  static AcademicYearOption? resolveCurrent(List<AcademicYearOption> years, [DateTime? referenceDate]) {
    if (years.isEmpty) return null;
    final now = referenceDate ?? DateTime.now();

    // 1. Active status where today falls within [start_date, end_date]
    final activeCurrent = years.where((ay) {
      if (!ay.isActive) return false;
      if (ay.startDate != null && ay.endDate != null) {
        return !now.isBefore(ay.startDate!) && !now.isAfter(ay.endDate!);
      }
      return false;
    }).toList();
    if (activeCurrent.isNotEmpty) return activeCurrent.first;

    // 2. Active status, sorted by start_date descending (most recent)
    final activeYears = years.where((ay) => ay.isActive).toList();
    if (activeYears.isNotEmpty) {
      activeYears.sort((a, b) {
        if (a.startDate == null && b.startDate == null) return 0;
        if (a.startDate == null) return 1;
        if (b.startDate == null) return -1;
        return b.startDate!.compareTo(a.startDate!);
      });
      return activeYears.first;
    }

    // 3. Any academic year where today falls within [start_date, end_date]
    final dateMatching = years.where((ay) {
      if (ay.startDate != null && ay.endDate != null) {
        return !now.isBefore(ay.startDate!) && !now.isAfter(ay.endDate!);
      }
      return false;
    }).toList();
    if (dateMatching.isNotEmpty) return dateMatching.first;

    // 4. Most recent academic year by start_date
    final sorted = List<AcademicYearOption>.from(years);
    sorted.sort((a, b) {
      if (a.startDate == null && b.startDate == null) return 0;
      if (a.startDate == null) return 1;
      if (b.startDate == null) return -1;
      return b.startDate!.compareTo(a.startDate!);
    });
    return sorted.first;
  }

  factory AcademicYearOption.fromJson(Map<String, dynamic> json) {
    return AcademicYearOption(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      status: json['status']?.toString() ?? 'active',
      startDate: json['start_date'] != null ? DateTime.tryParse(json['start_date'].toString()) : null,
      endDate: json['end_date'] != null ? DateTime.tryParse(json['end_date'].toString()) : null,
    );
  }
}

class SchoolStudentCountSummary {
  final String schoolId;
  final int totalStudents;
  final int billableStudents;
  final String? selectedAcademicYearId;
  final String? selectedAcademicYearName;
  final List<AcademicYearOption> availableAcademicYears;

  const SchoolStudentCountSummary({
    required this.schoolId,
    required this.totalStudents,
    required this.billableStudents,
    this.selectedAcademicYearId,
    this.selectedAcademicYearName,
    this.availableAcademicYears = const [],
  });

  bool get hasAcademicYear =>
      selectedAcademicYearId != null && selectedAcademicYearId!.isNotEmpty;

  factory SchoolStudentCountSummary.empty(String schoolId) {
    return SchoolStudentCountSummary(
      schoolId: schoolId,
      totalStudents: 0,
      billableStudents: 0,
    );
  }
}
