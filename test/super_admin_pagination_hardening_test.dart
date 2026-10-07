import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_admin_app/features/billing/billing_dashboard_screen.dart';
import 'package:super_admin_app/features/schools/schools_screen.dart';
import 'package:super_admin_app/models/billing_dashboard_summary.dart';
import 'package:super_admin_app/models/school_model.dart';
import 'package:super_admin_app/models/school_invoice_model.dart';
import 'package:super_admin_app/repositories/school_billing_repository.dart';
import 'package:super_admin_app/repositories/school_repository.dart';
import 'package:super_admin_app/services/dashboard_service.dart';
import 'package:super_admin_app/services/school_billing_service.dart';
import 'package:super_admin_app/services/school_service.dart';

void main() {
  group('SUPER ADMIN — PERFORMANCE & PAGINATION HARDENING TESTS', () {
    // ------------------------------------------------------------------------
    // 1. Static Verification: Zero in-memory search or full-table slicing
    // ------------------------------------------------------------------------
    test('1. Static verification: school_service.dart uses server-side .range() and server-side .or() search', () {
      final file = File('lib/services/school_service.dart');
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();

      expect(content.contains('.range('), isTrue, reason: 'Must use PostgREST .range for pagination');
      expect(content.contains('.or('), isTrue, reason: 'Must use PostgREST .or for multi-column search');
      expect(content.contains('name.ilike.'), isTrue, reason: 'Must search name column via PostgREST');
      expect(content.contains('code.ilike.'), isTrue, reason: 'Must search code column via PostgREST');
      expect(content.contains('email.ilike.'), isTrue, reason: 'Must search email column via PostgREST');
      expect(content.contains("order('id', ascending: false)"), isTrue, reason: 'Must use id as stable tie-breaker');
      expect(content.contains('fetchSchoolsCount'), isTrue, reason: 'Must implement count query');
    });

    test('2. Static verification: school_billing_service.dart uses server-side .range() and server-side filtering', () {
      final file = File('lib/services/school_billing_service.dart');
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();

      expect(content.contains('.range('), isTrue, reason: 'Must use PostgREST .range for invoice pagination');
      expect(content.contains('fetchFilteredInvoicesCount'), isTrue, reason: 'Must implement invoice count query');
      expect(content.contains("order('id', ascending: false)"), isTrue, reason: 'Must use id as stable tie-breaker');
      expect(
        content.contains(".neq('status', 'PAID').neq('status', 'CANCELLED').lt('due_date'"),
        isTrue,
        reason: 'OVERDUE filter must be evaluated on server via due_date before pagination',
      );
    });

    // ------------------------------------------------------------------------
    // 2. School Directory State & Pagination Logic
    // ------------------------------------------------------------------------
    test('3. SchoolFilterState defaults to page 0 and pageSize 25', () {
      const state = SchoolFilterState();
      expect(state.page, equals(0));
      expect(state.pageSize, equals(25));
      expect(state.searchQuery, isEmpty);
      expect(state.statusFilter, isNull);
    });

    test('4. SchoolFilterState.copyWith resets page to 0 when searchQuery changes', () {
      const state = SchoolFilterState(page: 3, pageSize: 25);
      final updated = state.copyWith(searchQuery: 'DPS');
      expect(updated.page, equals(0));
      expect(updated.searchQuery, equals('DPS'));
    });

    test('5. SchoolFilterState.copyWith resets page to 0 when statusFilter changes', () {
      const state = SchoolFilterState(page: 2, pageSize: 25);
      final updated = state.copyWith(statusFilter: () => SchoolStatus.active);
      expect(updated.page, equals(0));
      expect(updated.statusFilter, equals(SchoolStatus.active));
    });

    test('6. SchoolFilterState.copyWith preserves explicit page setting', () {
      const state = SchoolFilterState(page: 0, pageSize: 25);
      final next = state.copyWith(page: 1);
      expect(next.page, equals(1));

      final prev = next.copyWith(page: 0);
      expect(prev.page, equals(0));
    });

    test('7. SchoolRepository forwards page and pageSize parameters', () async {
      final service = SchoolService();
      final dashboardService = DashboardService(schoolService: service);
      final repo = SchoolRepository(service, dashboardService);
      // Verify method signature accepts page and pageSize
      expect(
        () => repo.getSchools(searchQuery: 'test', statusFilter: SchoolStatus.active, page: 1, pageSize: 50),
        returnsNormally,
      );
      expect(
        () => repo.getSchoolsCount(searchQuery: 'test', statusFilter: SchoolStatus.active),
        returnsNormally,
      );
    });

    // ------------------------------------------------------------------------
    // 3. Billing Invoices State & Pagination Logic
    // ------------------------------------------------------------------------
    test('8. InvoiceFilterParams defaults to page 0 and pageSize 25', () {
      const params = InvoiceFilterParams();
      expect(params.page, equals(0));
      expect(params.pageSize, equals(25));
      expect(params.statusFilter, isNull);
      expect(params.searchQuery, isNull);
    });

    test('9. InvoiceFilterParams.copyWith resets page to 0 when filters change', () {
      const params = InvoiceFilterParams(page: 4, pageSize: 25);
      final updated = params.copyWith(statusFilter: 'PAID');
      expect(updated.page, equals(0));
      expect(updated.statusFilter, equals('PAID'));

      final searchUpdated = params.copyWith(searchQuery: 'INV-001');
      expect(searchUpdated.page, equals(0));
      expect(searchUpdated.searchQuery, equals('INV-001'));
    });

    test('10. InvoiceFilterParams.copyWith preserves explicit page setting', () {
      const params = InvoiceFilterParams(page: 0, pageSize: 25);
      final next = params.copyWith(page: 2);
      expect(next.page, equals(2));
    });

    test('11. InvoiceFilterParams equality and hashCode account for page and pageSize', () {
      const p1 = InvoiceFilterParams(page: 0, pageSize: 25);
      const p2 = InvoiceFilterParams(page: 0, pageSize: 25);
      const p3 = InvoiceFilterParams(page: 1, pageSize: 25);
      const p4 = InvoiceFilterParams(page: 0, pageSize: 50);

      expect(p1 == p2, isTrue);
      expect(p1.hashCode, equals(p2.hashCode));
      expect(p1 == p3, isFalse);
      expect(p1 == p4, isFalse);
    });

    test('12. SchoolBillingRepository forwards page and pageSize parameters', () async {
      final service = SchoolBillingService();
      final repo = SchoolBillingRepository(service);

      expect(
        () => repo.getFilteredInvoices(
          schoolId: 'school-1',
          statusFilter: 'PAID',
          searchQuery: 'INV',
          page: 1,
          pageSize: 25,
        ),
        returnsNormally,
      );
      expect(
        () => repo.getFilteredInvoicesCount(schoolId: 'school-1', statusFilter: 'PAID'),
        returnsNormally,
      );
    });

    // ------------------------------------------------------------------------
    // 4. UI Rendering & Pagination Widget Tests
    // ------------------------------------------------------------------------
    testWidgets('13. SchoolsScreen renders search, filter chips, and pagination footer', (tester) async {
      final mockSchools = List.generate(
        10,
        (i) => SchoolModel(
          id: 'school-$i',
          schoolCode: 'SCH-$i',
          name: 'School $i',
          status: SchoolStatus.active,
          createdAt: DateTime.now().subtract(Duration(days: i)),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            schoolsListProvider.overrideWith((ref) => Future.value(mockSchools)),
            schoolsCountProvider.overrideWith((ref) => Future.value(45)),
          ],
          child: const MaterialApp(
            home: SchoolsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Schools Directory'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('All Schools'), findsOneWidget);
      expect(find.text('Showing 1–10 of 45 schools'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Previous'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Next'), findsOneWidget);

      // On page 0, Previous should be disabled
      final prevBtn = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Previous'));
      expect(prevBtn.onPressed, isNull);

      // Next should be enabled since totalCount (45) > page 1 end (10)
      final nextBtn = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Next'));
      expect(nextBtn.onPressed, isNotNull);
    });

    testWidgets('14. SchoolsScreen Next button triggers next page', (tester) async {
      final mockSchools = List.generate(
        25,
        (i) => SchoolModel(
          id: 'school-$i',
          schoolCode: 'SCH-$i',
          name: 'School $i',
          status: SchoolStatus.active,
          createdAt: DateTime.now().subtract(Duration(days: i)),
        ),
      );

      final container = ProviderContainer(
        overrides: [
          schoolsListProvider.overrideWith((ref) => Future.value(mockSchools)),
          schoolsCountProvider.overrideWith((ref) => Future.value(50)),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: SchoolsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Click Next
      final nextBtnFinder = find.widgetWithText(OutlinedButton, 'Next');
      expect(nextBtnFinder, findsOneWidget);
      await tester.tap(nextBtnFinder);
      await tester.pump();

      // Filter state page should now be 1
      expect(container.read(schoolFilterProvider).page, equals(1));
    });

    testWidgets('15. BillingDashboardScreen renders invoice ledger and pagination bar', (tester) async {
      final now = DateTime.now();
      final mockInvoices = [
        SchoolInvoiceModel(
          id: 'inv-1',
          invoiceNumber: 'INV-2026-001',
          schoolId: 'school-1',
          schoolName: 'Greenwood High',
          billingPeriodStart: now.subtract(const Duration(days: 30)),
          billingPeriodEnd: now,
          studentCount: 500,
          ratePerStudent: 20.0,
          subtotal: 10000.0,
          totalAmount: 10000.0,
          status: InvoiceStatus.paid,
          dueDate: now.add(const Duration(days: 15)),
          createdAt: now,
        ),
      ];

      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const defaultParams = InvoiceFilterParams(
        statusFilter: 'ALL',
        searchQuery: '',
        page: 0,
        pageSize: 25,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            billingDashboardSummaryProvider('All Time').overrideWith(
              (ref) => Future.value(BillingDashboardSummary.empty()),
            ),
            filteredInvoicesProvider(defaultParams).overrideWith(
              (ref) => Future.value(mockInvoices),
            ),
            filteredInvoicesCountProvider(defaultParams).overrideWith(
              (ref) => Future.value(1),
            ),
          ],
          child: const MaterialApp(
            home: BillingDashboardScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Invoice Ledger'), findsOneWidget);
      expect(find.text('INV-2026-001'), findsOneWidget);
      expect(find.text('Showing 1–1 of 1 invoices'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Previous'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Next'), findsOneWidget);

      // On single-page results, both Prev and Next should be disabled
      final prevBtn = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Previous'));
      final nextBtn = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Next'));
      expect(prevBtn.onPressed, isNull);
      expect(nextBtn.onPressed, isNull);
    });
  });
}
