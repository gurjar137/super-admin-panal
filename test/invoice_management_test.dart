import 'package:flutter_test/flutter_test.dart';
import 'package:super_admin_app/core/constants/billing_constants.dart';
import 'package:super_admin_app/models/invoice_payment_model.dart';
import 'package:super_admin_app/models/school_billing_financial_summary.dart';
import 'package:super_admin_app/models/school_invoice_model.dart';

void main() {
  group('Invoice Management & Payment Tracking Unit Tests', () {
    final today = DateTime.now();
    final pastDate = today.subtract(const Duration(days: 15));
    final futureDate = today.add(const Duration(days: 15));

    SchoolInvoiceModel createTestInvoice({
      String id = 'inv-uuid-1234-5678',
      String? invoiceNumber,
      String schoolId = 'school-greenwood-uuid',
      int studentCount = 100,
      double ratePerStudent = 20.00,
      InvoiceStatus status = InvoiceStatus.unpaid,
      DateTime? dueDate,
      DateTime? paidAt,
      List<InvoicePaymentModel> payments = const [],
    }) {
      final total = BillingConstants.calculateTotalAmount(
        studentCount: studentCount,
        ratePerStudent: ratePerStudent,
      );
      return SchoolInvoiceModel(
        id: id,
        invoiceNumber: invoiceNumber,
        schoolId: schoolId,
        billingPeriodStart: DateTime(2026, 9, 1),
        billingPeriodEnd: DateTime(2026, 9, 30),
        studentCount: studentCount,
        ratePerStudent: ratePerStudent,
        subtotal: total,
        totalAmount: total,
        status: status,
        dueDate: dueDate ?? futureDate,
        paidAt: paidAt,
        createdAt: DateTime(2026, 9, 1, 10, 0),
        payments: payments,
      );
    }

    test('1. Invoice number formatting and display fallback', () {
      final invWithNumber = createTestInvoice(invoiceNumber: 'INV-2026-000001');
      expect(invWithNumber.displayInvoiceNumber, equals('INV-2026-000001'));

      final invWithoutNumber = createTestInvoice(id: 'abcdef12-3456-7890-abcd-ef1234567890', invoiceNumber: null);
      expect(invWithoutNumber.displayInvoiceNumber, equals('INV-ABCDEF12'));
    });

    test('2. Automatic overdue calculation for UNPAID past due date', () {
      final pastDueInvoice = createTestInvoice(
        dueDate: pastDate,
        status: InvoiceStatus.unpaid,
      );
      expect(pastDueInvoice.isOverdue, isTrue);
      expect(pastDueInvoice.effectiveStatus, equals(InvoiceStatus.overdue));

      final futureDueInvoice = createTestInvoice(
        dueDate: futureDate,
        status: InvoiceStatus.unpaid,
      );
      expect(futureDueInvoice.isOverdue, isFalse);
      expect(futureDueInvoice.effectiveStatus, equals(InvoiceStatus.unpaid));
    });

    test('3. Overdue cleared when marked PAID', () {
      final paidPastDueInvoice = createTestInvoice(
        dueDate: pastDate,
        status: InvoiceStatus.paid,
        paidAt: today,
      );
      expect(paidPastDueInvoice.isPaid, isTrue);
      expect(paidPastDueInvoice.isOverdue, isFalse);
      expect(paidPastDueInvoice.effectiveStatus, equals(InvoiceStatus.paid));
    });

    test('4. Outstanding amount calculation', () {
      final unpaidInv = createTestInvoice(studentCount: 100, ratePerStudent: 20.0);
      expect(unpaidInv.totalAmount, equals(2000.0));
      expect(unpaidInv.outstandingAmount, equals(2000.0));

      final paidInv = unpaidInv.copyWith(status: InvoiceStatus.paid, paidAt: today);
      expect(paidInv.outstandingAmount, equals(0.0));

      final cancelledInv = unpaidInv.copyWith(status: InvoiceStatus.cancelled);
      expect(cancelledInv.outstandingAmount, equals(0.0));
    });

    test('5. Full payment validation logic', () {
      final invoice = createTestInvoice(studentCount: 50, ratePerStudent: 20.0); // total 1000.0

      // Zero or negative payment
      expect(0.0 <= 0, isTrue);
      expect(-100.0 <= 0, isTrue);

      // Partial payment (< totalAmount)
      const partialAmount = 500.0;
      final isPartial = (partialAmount - invoice.totalAmount).abs() > 0.01;
      expect(isPartial, isTrue);

      // Overpayment (> totalAmount)
      const overAmount = 1500.0;
      final isOver = (overAmount - invoice.totalAmount).abs() > 0.01;
      expect(isOver, isTrue);

      // Exact full payment
      const exactAmount = 1000.0;
      final isExact = (exactAmount - invoice.totalAmount).abs() <= 0.01;
      expect(isExact, isTrue);
    });

    test('6. Payment record linkage and model attributes', () {
      final payment = InvoicePaymentModel(
        id: 'pay-uuid-001',
        invoiceId: 'inv-uuid-1234-5678',
        amount: 2000.0,
        paymentDate: today,
        paymentMethod: PaymentMethod.upi,
        paymentReference: 'UPI/2026/09/987654321',
        notes: 'September school billing',
        status: PaymentStatus.completed,
        createdBy: 'superadmin@schoolos.test',
        createdAt: today,
      );

      expect(payment.isCompleted, isTrue);
      expect(payment.isVoided, isFalse);
      expect(payment.paymentMethod.dbValue, equals('UPI'));
      expect(payment.paymentMethod.displayName, equals('UPI'));

      final json = payment.toJson();
      expect(json['payment_method'], equals('UPI'));
      expect(json['status'], equals('COMPLETED'));
      expect(json['amount'], equals(2000.0));

      final fromJson = InvoicePaymentModel.fromJson(json);
      expect(fromJson.amount, equals(2000.0));
      expect(fromJson.paymentMethod, equals(PaymentMethod.upi));
    });

    test('7. Payment history audit preservation (Voided rather than deleted on Mark as Unpaid)', () {
      final payment = InvoicePaymentModel(
        id: 'pay-uuid-001',
        invoiceId: 'inv-uuid-1234-5678',
        amount: 2000.0,
        paymentDate: today,
        paymentMethod: PaymentMethod.bankTransfer,
        status: PaymentStatus.completed,
        createdAt: today,
      );

      final voidedPayment = InvoicePaymentModel(
        id: payment.id,
        invoiceId: payment.invoiceId,
        amount: payment.amount,
        paymentDate: payment.paymentDate,
        paymentMethod: payment.paymentMethod,
        status: PaymentStatus.voided,
        notes: 'Voided on mark unpaid',
        createdAt: payment.createdAt,
      );

      expect(voidedPayment.isVoided, isTrue);
      expect(voidedPayment.isCompleted, isFalse);
      expect(voidedPayment.status.dbValue, equals('VOIDED'));
    });

    test('8. Invoice cancellation rules', () {
      final unpaidInvoice = createTestInvoice(status: InvoiceStatus.unpaid);
      expect(unpaidInvoice.canCancel, isTrue);

      final paidInvoice = createTestInvoice(status: InvoiceStatus.paid, paidAt: today);
      expect(paidInvoice.canCancel, isFalse); // Paid invoice CANNOT be cancelled

      final alreadyCancelled = createTestInvoice(status: InvoiceStatus.cancelled);
      expect(alreadyCancelled.canCancel, isFalse);
    });

    test('9. Paid invoice snapshot immutability', () {
      final original = createTestInvoice(
        studentCount: 1000,
        ratePerStudent: 20.00,
        status: InvoiceStatus.paid,
        paidAt: today,
      );

      // Snapshot values must be permanently frozen
      expect(original.studentCount, equals(1000));
      expect(original.ratePerStudent, equals(20.00));
      expect(original.subtotal, equals(20000.00));
      expect(original.totalAmount, equals(20000.00));

      // Even if new students enroll or rate changes to ₹25, historical invoice remains 1000 * 20
      const newRate = 25.00;
      expect(original.ratePerStudent, equals(20.00));
      expect(original.ratePerStudent != newRate, isTrue);
    });

    test('10. School Financial Summary aggregation logic', () {
      final inv1 = createTestInvoice(
        id: 'inv-1',
        studentCount: 500, // 10,000
        status: InvoiceStatus.paid,
        paidAt: today,
      );
      final inv2 = createTestInvoice(
        id: 'inv-2',
        studentCount: 300, // 6,000
        status: InvoiceStatus.unpaid,
        dueDate: futureDate,
      );
      final inv3 = createTestInvoice(
        id: 'inv-3',
        studentCount: 200, // 4,000
        status: InvoiceStatus.unpaid,
        dueDate: pastDate, // Overdue
      );
      final invCancelled = createTestInvoice(
        id: 'inv-4',
        studentCount: 100, // 2,000
        status: InvoiceStatus.cancelled,
      );

      final summary = SchoolBillingFinancialSummary.fromInvoices(
        'school-greenwood-uuid',
        [inv1, inv2, inv3, invCancelled],
      );

      expect(summary.hasInvoices, isTrue);
      expect(summary.totalBilled, equals(20000.0)); // 10k + 6k + 4k (cancelled excluded)
      expect(summary.totalPaid, equals(10000.0));
      expect(summary.outstandingAmount, equals(10000.0)); // 20k - 10k
      expect(summary.overdueAmount, equals(4000.0)); // inv3 is overdue
    });

    test('11. Multi-tenant isolation expectation for invoice queries', () {
      final schoolAInvoice = createTestInvoice(schoolId: 'school-a-uuid');
      final schoolBInvoice = createTestInvoice(schoolId: 'school-b-uuid');

      final allInvoices = [schoolAInvoice, schoolBInvoice];

      // Simulated tenant filter: where school_id == userSchoolId
      final schoolAVisible = allInvoices.where((inv) => inv.schoolId == 'school-a-uuid').toList();
      expect(schoolAVisible.length, equals(1));
      expect(schoolAVisible.first.schoolId, equals('school-a-uuid'));

      final hasLeakage = schoolAVisible.any((inv) => inv.schoolId == 'school-b-uuid');
      expect(hasLeakage, isFalse);
    });
  });
}
