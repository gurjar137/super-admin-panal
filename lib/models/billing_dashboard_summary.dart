class BillingDashboardSummary {
  final int totalSchools;
  final int totalStudentsBilled;
  final double totalBilled;
  final double totalPaid;
  final double totalOutstanding;
  final double totalOverdue;
  final String selectedPeriod;

  const BillingDashboardSummary({
    required this.totalSchools,
    required this.totalStudentsBilled,
    required this.totalBilled,
    required this.totalPaid,
    required this.totalOutstanding,
    required this.totalOverdue,
    this.selectedPeriod = 'All Time',
  });

  factory BillingDashboardSummary.empty({String selectedPeriod = 'All Time'}) {
    return BillingDashboardSummary(
      totalSchools: 0,
      totalStudentsBilled: 0,
      totalBilled: 0.0,
      totalPaid: 0.0,
      totalOutstanding: 0.0,
      totalOverdue: 0.0,
      selectedPeriod: selectedPeriod,
    );
  }
}
