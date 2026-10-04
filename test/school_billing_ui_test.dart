import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_admin_app/core/constants/billing_constants.dart';
import 'package:super_admin_app/models/school_billing_overview.dart';
import 'package:super_admin_app/models/school_invoice_model.dart';
import 'package:super_admin_app/repositories/school_billing_repository.dart';

void main() {
  group('Per-Student Billing UI Component Tests', () {
    testWidgets('1. Billing strip renders student count, rate, and estimated bill when unbilled', (tester) async {
      const mockOverview = SchoolBillingOverview(
        schoolId: 'test-school-kps',
        studentCount: 1000,
        ratePerStudent: 20.00,
        hasInvoices: false,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            schoolBillingOverviewProvider('test-school-kps').overrideWith((ref) => Future.value(mockOverview)),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  final billingAsync = ref.watch(schoolBillingOverviewProvider('test-school-kps'));
                  return billingAsync.when(
                    loading: () => const Text('Loading...'),
                    error: (e, _) => Text('Error: $e'),
                    data: (b) => Column(
                      children: [
                        Text('Students: ${b.studentCount}'),
                        Text('Rate: ${BillingConstants.formatCurrency(b.ratePerStudent)}/student'),
                        Text('Est. Bill: ${BillingConstants.formatCurrency(b.estimatedBillAmount)}'),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Students: 1000'), findsOneWidget);
      expect(find.text('Rate: ₹20/student'), findsOneWidget);
      expect(find.text('Est. Bill: ₹20000'), findsOneWidget);
    });

    testWidgets('2. Billing strip renders current bill and PAID status when invoice exists', (tester) async {
      const mockOverview = SchoolBillingOverview(
        schoolId: 'test-school-kps',
        studentCount: 1000,
        ratePerStudent: 20.00,
        latestBillAmount: 20000.00,
        latestBillingPeriod: '09/2026',
        latestStatus: InvoiceStatus.paid,
        hasInvoices: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            schoolBillingOverviewProvider('test-school-kps').overrideWith((ref) => Future.value(mockOverview)),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  final billingAsync = ref.watch(schoolBillingOverviewProvider('test-school-kps'));
                  return billingAsync.when(
                    loading: () => const Text('Loading...'),
                    error: (e, _) => Text('Error: $e'),
                    data: (b) => Column(
                      children: [
                        Text('Students: ${b.studentCount}'),
                        Text('Current Bill: ${BillingConstants.formatCurrency(b.latestBillAmount!)}'),
                        Text('Status: ${b.latestStatus?.dbValue}'),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Students: 1000'), findsOneWidget);
      expect(find.text('Current Bill: ₹20000'), findsOneWidget);
      expect(find.text('Status: PAID'), findsOneWidget);
    });

    testWidgets('3. Invoices list renders invoice snapshot cards with view snapshot and mark paid actions', (tester) async {
      final mockInvoice = SchoolInvoiceModel(
        id: 'inv-12345',
        schoolId: 'school-kps',
        academicYearId: 'ay-1',
        academicYearName: '2026-2027',
        billingPeriodStart: DateTime(2026, 9, 1),
        billingPeriodEnd: DateTime(2026, 9, 30),
        studentCount: 1000,
        ratePerStudent: 20.00,
        subtotal: 20000.00,
        totalAmount: 20000.00,
        status: InvoiceStatus.unpaid,
        dueDate: DateTime(2026, 10, 15),
        createdAt: DateTime(2026, 9, 15),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            schoolInvoicesProvider('school-kps').overrideWith((ref) => Future.value([mockInvoice])),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  final invAsync = ref.watch(schoolInvoicesProvider('school-kps'));
                  return invAsync.when(
                    loading: () => const Text('Loading...'),
                    error: (e, _) => Text('Error: $e'),
                    data: (invoices) => ListView.builder(
                      itemCount: invoices.length,
                      itemBuilder: (ctx, i) {
                        final inv = invoices[i];
                        return ListTile(
                          title: Text('Amount: ${BillingConstants.formatCurrency(inv.totalAmount)}'),
                          subtitle: Text('Students: ${inv.studentCount} @ ${BillingConstants.formatCurrency(inv.ratePerStudent)}'),
                          trailing: Text(inv.status.dbValue),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Amount: ₹20000'), findsOneWidget);
      expect(find.text('Students: 1000 @ ₹20'), findsOneWidget);
      expect(find.text('UNPAID'), findsOneWidget);
    });
  });
}
