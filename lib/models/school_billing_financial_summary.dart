import 'school_invoice_model.dart';

class SchoolBillingFinancialSummary {
  final String schoolId;
  final double currentBillAmount;
  final double totalBilled;
  final double totalPaid;
  final double outstandingAmount;
  final double overdueAmount;
  final SchoolInvoiceModel? currentInvoice;
  final List<SchoolInvoiceModel> invoices;

  const SchoolBillingFinancialSummary({
    required this.schoolId,
    required this.currentBillAmount,
    required this.totalBilled,
    required this.totalPaid,
    required this.outstandingAmount,
    required this.overdueAmount,
    this.currentInvoice,
    this.invoices = const [],
  });

  bool get hasInvoices => invoices.isNotEmpty;

  factory SchoolBillingFinancialSummary.fromInvoices(
    String schoolId,
    List<SchoolInvoiceModel> invoices,
  ) {
    if (invoices.isEmpty) {
      return SchoolBillingFinancialSummary(
        schoolId: schoolId,
        currentBillAmount: 0.0,
        totalBilled: 0.0,
        totalPaid: 0.0,
        outstandingAmount: 0.0,
        overdueAmount: 0.0,
        currentInvoice: null,
        invoices: const [],
      );
    }

    final sorted = List<SchoolInvoiceModel>.from(invoices)
      ..sort((a, b) => b.billingPeriodStart.compareTo(a.billingPeriodStart));

    final current = sorted.firstWhere(
      (inv) => inv.status != InvoiceStatus.cancelled,
      orElse: () => sorted.first,
    );

    double billed = 0.0;
    double paid = 0.0;
    double overdue = 0.0;

    for (final inv in sorted) {
      if (inv.status == InvoiceStatus.cancelled) continue;

      billed += inv.totalAmount;
      if (inv.isPaid) {
        paid += inv.totalAmount;
      } else if (inv.isOverdue) {
        overdue += inv.totalAmount;
      }
    }

    final outstanding = (billed - paid).clamp(0.0, double.infinity);

    return SchoolBillingFinancialSummary(
      schoolId: schoolId,
      currentBillAmount: current.totalAmount,
      totalBilled: billed,
      totalPaid: paid,
      outstandingAmount: outstanding,
      overdueAmount: overdue,
      currentInvoice: current,
      invoices: sorted,
    );
  }
}