import '../core/constants/billing_constants.dart';
import 'school_invoice_model.dart';

class SchoolBillingOverview {
  final String schoolId;
  final int studentCount;
  final double ratePerStudent;
  final double? latestBillAmount;
  final String? latestBillingPeriod;
  final InvoiceStatus? latestStatus;
  final bool hasInvoices;

  const SchoolBillingOverview({
    required this.schoolId,
    required this.studentCount,
    this.ratePerStudent = BillingConstants.defaultRatePerStudent,
    this.latestBillAmount,
    this.latestBillingPeriod,
    this.latestStatus,
    this.hasInvoices = false,
  });

  /// Approximate or calculated current bill based on live count and current rate
  double get estimatedBillAmount =>
      BillingConstants.calculateTotalAmount(studentCount: studentCount, ratePerStudent: ratePerStudent);
}
