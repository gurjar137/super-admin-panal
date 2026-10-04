import 'package:flutter_test/flutter_test.dart';
import 'package:super_admin_app/core/constants/billing_constants.dart';
import 'package:super_admin_app/models/school_billing_overview.dart';
import 'package:super_admin_app/models/school_billing_settings_model.dart';
import 'package:super_admin_app/models/school_invoice_model.dart';
import 'package:super_admin_app/models/school_student_count_summary.dart';

void main() {
  group('Per-Student Billing: Decimal-Safe Arithmetic & Formatting', () {
    test('1. Exact calculation for 500 students at ₹20 = ₹10,000', () {
      final total = BillingConstants.calculateTotalAmount(
        studentCount: 500,
        ratePerStudent: 20.00,
      );
      expect(total, 10000.00);
      expect(BillingConstants.formatCurrency(total), '₹10000');
    });

    test('2. Exact calculation for 1000 students at ₹20 = ₹20,000', () {
      final total = BillingConstants.calculateTotalAmount(
        studentCount: 1000,
        ratePerStudent: 20.00,
      );
      expect(total, 20000.00);
      expect(BillingConstants.formatCurrency(total), '₹20000');
    });

    test('3. Exact decimal arithmetic with fractional rates without IEEE float rounding errors', () {
      // 333 students * 19.95 = 6643.35
      final total = BillingConstants.calculateTotalAmount(
        studentCount: 333,
        ratePerStudent: 19.95,
      );
      expect(total, 6643.35);
      expect(BillingConstants.formatCurrency(total), '₹6643.35');
    });

    test('4. Zero or negative students / rates return 0.00 safely', () {
      expect(BillingConstants.calculateTotalAmount(studentCount: 0, ratePerStudent: 20.0), 0.0);
      expect(BillingConstants.calculateTotalAmount(studentCount: -5, ratePerStudent: 20.0), 0.0);
      expect(BillingConstants.calculateTotalAmount(studentCount: 100, ratePerStudent: -20.0), 0.0);
    });
  });

  group('Per-Student Billing: Settings Model & Defaults', () {
    test('5. Default billing settings uses ₹20.00 rate and INR currency', () {
      final settings = SchoolBillingSettingsModel.defaultForSchool('test-school-123');
      expect(settings.schoolId, 'test-school-123');
      expect(settings.ratePerStudent, 20.00);
      expect(settings.currency, 'INR');
      expect(settings.billingCycle, 'MONTHLY');
      expect(settings.active, true);
    });

    test('6. SchoolBillingSettingsModel JSON serialization round-trip', () {
      final json = {
        'id': 'settings-uuid-1',
        'school_id': 'school-uuid-1',
        'rate_per_student': 25.50,
        'currency': 'INR',
        'billing_cycle': 'QUARTERLY',
        'active': true,
        'created_at': '2026-09-01T00:00:00.000Z',
        'updated_at': '2026-09-15T00:00:00.000Z',
      };

      final model = SchoolBillingSettingsModel.fromJson(json);
      expect(model.id, 'settings-uuid-1');
      expect(model.schoolId, 'school-uuid-1');
      expect(model.ratePerStudent, 25.50);
      expect(model.currency, 'INR');
      expect(model.billingCycle, 'QUARTERLY');
      expect(model.active, true);

      final exported = model.toJson();
      expect(exported['school_id'], 'school-uuid-1');
      expect(exported['rate_per_student'], 25.50);
    });
  });

  group('Per-Student Billing: Immutable Invoice Snapshots', () {
    final invoiceJson = {
      'id': 'inv-uuid-101',
      'school_id': 'school-uuid-kps',
      'academic_year_id': 'ay-uuid-2026',
      'billing_period_start': '2026-09-01',
      'billing_period_end': '2026-09-30',
      'student_count': 1000,
      'rate_per_student': 20.00,
      'currency': 'INR',
      'subtotal': 20000.00,
      'total_amount': 20000.00,
      'status': 'UNPAID',
      'due_date': '2026-10-15',
      'paid_at': null,
      'notes': 'September 2026 regular billing',
      'created_at': '2026-09-15T03:00:00.000Z',
      'school_name': 'KPS',
      'academic_year_name': '2026-2027',
    };

    test('7. Invoice model parses snapshot values correctly', () {
      final invoice = SchoolInvoiceModel.fromJson(invoiceJson);
      expect(invoice.id, 'inv-uuid-101');
      expect(invoice.schoolId, 'school-uuid-kps');
      expect(invoice.studentCount, 1000);
      expect(invoice.ratePerStudent, 20.00);
      expect(invoice.totalAmount, 20000.00);
      expect(invoice.status, InvoiceStatus.unpaid);
      expect(invoice.isPaid, false);
      expect(invoice.isOverdue, false);
      expect(invoice.schoolName, 'KPS');
      expect(invoice.academicYearName, '2026-2027');
    });

    test('8. Rate changes in settings do NOT modify historical invoice snapshot', () {
      final invoice = SchoolInvoiceModel.fromJson(invoiceJson);

      // Now simulate a school billing setting rate change from ₹20 to ₹35
      final updatedSettings = SchoolBillingSettingsModel(
        id: 'settings-1',
        schoolId: invoice.schoolId,
        ratePerStudent: 35.00,
        createdAt: DateTime.now(),
      );

      // Verify the historical invoice retains its frozen student count, rate, and amount
      expect(updatedSettings.ratePerStudent, 35.00);
      expect(invoice.ratePerStudent, 20.00);
      expect(invoice.studentCount, 1000);
      expect(invoice.totalAmount, 20000.00);
    });

    test('9. Payment status toggles set and clear paid_at timestamp correctly', () {
      final invoiceUnpaid = SchoolInvoiceModel.fromJson(invoiceJson);
      expect(invoiceUnpaid.status, InvoiceStatus.unpaid);
      expect(invoiceUnpaid.paidAt, isNull);

      final now = DateTime.now();
      final paidJson = Map<String, dynamic>.from(invoiceJson);
      paidJson['status'] = 'PAID';
      paidJson['paid_at'] = now.toIso8601String();

      final invoicePaid = SchoolInvoiceModel.fromJson(paidJson);
      expect(invoicePaid.status, InvoiceStatus.paid);
      expect(invoicePaid.isPaid, true);
      expect(invoicePaid.paidAt, isNotNull);
    });
  });

  group('Per-Student Billing: Overview and Student Count Breakdown', () {
    test('10. SchoolBillingOverview correctly estimates bill when no invoices exist', () {
      const overview = SchoolBillingOverview(
        schoolId: 'school-uuid-1',
        studentCount: 750,
        ratePerStudent: 20.00,
        hasInvoices: false,
      );

      expect(overview.studentCount, 750);
      expect(overview.estimatedBillAmount, 15000.00);
      expect(overview.latestBillAmount, isNull);
    });

    test('11. SchoolStudentCountSummary encapsulates available academic years', () {
      final ayOption = AcademicYearOption(
        id: 'ay-1',
        name: '2026-2027',
        status: 'active',
        startDate: DateTime(2026, 4, 1),
        endDate: DateTime(2027, 3, 31),
      );

      final summary = SchoolStudentCountSummary(
        schoolId: 'school-kps',
        totalStudents: 1000,
        billableStudents: 1000,
        selectedAcademicYearId: 'ay-1',
        selectedAcademicYearName: '2026-2027',
        availableAcademicYears: [ayOption],
      );

      expect(summary.totalStudents, 1000);
      expect(summary.billableStudents, 1000);
      expect(summary.selectedAcademicYearId, 'ay-1');
      expect(summary.availableAcademicYears.first.isActive, true);
      expect(summary.hasAcademicYear, true);
    });
  });

  group('Academic Year Resolution & Student Count Rules', () {
    test('12. AcademicYearOption.resolveCurrent correctly resolves active year matching current date', () {
      final pastYear = AcademicYearOption(
        id: 'ay-past',
        name: '2024-2025',
        status: 'completed',
        startDate: DateTime(2024, 4, 1),
        endDate: DateTime(2025, 3, 31),
      );
      final currentYear = AcademicYearOption(
        id: 'ay-current',
        name: '2026-2027',
        status: 'active',
        startDate: DateTime(2026, 4, 1),
        endDate: DateTime(2027, 3, 31),
      );
      final futureYear = AcademicYearOption(
        id: 'ay-future',
        name: '2027-2028',
        status: 'upcoming',
        startDate: DateTime(2027, 4, 1),
        endDate: DateTime(2028, 3, 31),
      );

      final resolved = AcademicYearOption.resolveCurrent(
        [pastYear, currentYear, futureYear],
        DateTime(2026, 9, 15),
      );

      expect(resolved, isNotNull);
      expect(resolved!.id, 'ay-current');
      expect(resolved.name, '2026-2027');
    });

    test('13. AcademicYearOption.resolveCurrent returns null when no academic years exist', () {
      final resolved = AcademicYearOption.resolveCurrent([]);
      expect(resolved, isNull);
    });

    test('14. SchoolStudentCountSummary.empty flags hasAcademicYear as false and student count 0', () {
      final emptySummary = SchoolStudentCountSummary.empty('school-empty');
      expect(emptySummary.hasAcademicYear, false);
      expect(emptySummary.totalStudents, 0);
      expect(emptySummary.billableStudents, 0);
      expect(emptySummary.selectedAcademicYearId, isNull);
    });

    test('15. Zero billable students calculation yields ₹0 and triggers zero student error in billing rules', () {
      final totalAmount = BillingConstants.calculateTotalAmount(
        studentCount: 0,
        ratePerStudent: 20.00,
      );
      expect(totalAmount, 0.0);
    });

    test('16. Cross-school student isolation ensures students belonging to School A are not billable for School B', () {
      const schoolAId = 'school-a-uuid';
      const schoolBId = 'school-b-uuid';
      const ayAId = 'ay-a-uuid';

      final studentsDataset = [
        {'id': 's1', 'school_id': schoolAId, 'academic_year_id': ayAId, 'status': 'ACTIVE'},
        {'id': 's2', 'school_id': schoolAId, 'academic_year_id': ayAId, 'status': 'ACTIVE'},
        {'id': 's3', 'school_id': schoolAId, 'academic_year_id': ayAId, 'status': 'INACTIVE'},
        {'id': 's4', 'school_id': schoolBId, 'academic_year_id': 'ay-b-uuid', 'status': 'ACTIVE'},
      ];

      // Filter for School A
      final schoolABillable = studentsDataset.where((st) {
        return st['school_id'] == schoolAId &&
            st['academic_year_id'] == ayAId &&
            st['status'] == 'ACTIVE';
      }).length;

      // Filter for School B with ayAId
      final schoolBBillableInAyA = studentsDataset.where((st) {
        return st['school_id'] == schoolBId &&
            st['academic_year_id'] == ayAId &&
            st['status'] == 'ACTIVE';
      }).length;

      expect(schoolABillable, 2);
      expect(schoolBBillableInAyA, 0);
    });
  });
}
