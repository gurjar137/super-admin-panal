import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_result.dart';
import '../models/billing_dashboard_summary.dart';
import '../models/invoice_payment_model.dart';
import '../models/school_billing_financial_summary.dart';
import '../models/school_billing_overview.dart';
import '../models/school_billing_settings_model.dart';
import '../models/school_invoice_model.dart';
import '../models/school_student_count_summary.dart';
import '../services/school_billing_service.dart';

final schoolBillingServiceProvider = Provider<SchoolBillingService>((ref) {
  return SchoolBillingService();
});

final schoolBillingRepositoryProvider = Provider<SchoolBillingRepository>((ref) {
  return SchoolBillingRepository(ref.watch(schoolBillingServiceProvider));
});

/// Riverpod family provider for a school's live student counts and academic years
final schoolStudentCountsProvider =
    FutureProvider.family.autoDispose<SchoolStudentCountSummary, String>((ref, schoolId) async {
  final repo = ref.watch(schoolBillingRepositoryProvider);
  final result = await repo.getStudentCountSummary(schoolId);
  if (result.isFailure) {
    throw Exception(result.errorOrNull ?? 'Failed to load student counts');
  }
  return result.dataOrNull ?? SchoolStudentCountSummary.empty(schoolId);
});

/// Riverpod family provider for a school's billing settings (rate, cycle)
final schoolBillingSettingsProvider =
    FutureProvider.family.autoDispose<SchoolBillingSettingsModel, String>((ref, schoolId) async {
  final repo = ref.watch(schoolBillingRepositoryProvider);
  final result = await repo.getBillingSettings(schoolId);
  if (result.isFailure) {
    throw Exception(result.errorOrNull ?? 'Failed to load billing settings');
  }
  return result.dataOrNull ?? SchoolBillingSettingsModel.defaultForSchool(schoolId);
});

/// Riverpod family provider for a school's invoice history
final schoolInvoicesProvider =
    FutureProvider.family.autoDispose<List<SchoolInvoiceModel>, String>((ref, schoolId) async {
  final repo = ref.watch(schoolBillingRepositoryProvider);
  final result = await repo.getInvoices(schoolId);
  if (result.isFailure) {
    throw Exception(result.errorOrNull ?? 'Failed to load invoices');
  }
  return result.dataOrNull ?? [];
});

/// Riverpod family provider for a school's financial summary (current bill, paid, outstanding, overdue)
final schoolFinancialSummaryProvider =
    FutureProvider.family.autoDispose<SchoolBillingFinancialSummary, String>((ref, schoolId) async {
  final repo = ref.watch(schoolBillingRepositoryProvider);
  final result = await repo.getSchoolFinancialSummary(schoolId);
  if (result.isFailure) {
    throw Exception(result.errorOrNull ?? 'Failed to load financial summary');
  }
  return result.dataOrNull ??
      SchoolBillingFinancialSummary.fromInvoices(schoolId, const []);
});

/// Riverpod family provider for high-level billing overview for school cards in directory
final schoolBillingOverviewProvider =
    FutureProvider.family.autoDispose<SchoolBillingOverview, String>((ref, schoolId) async {
  final repo = ref.watch(schoolBillingRepositoryProvider);
  final result = await repo.getSchoolBillingOverview(schoolId);
  if (result.isFailure) {
    throw Exception(result.errorOrNull ?? 'Failed to load billing overview');
  }
  return result.dataOrNull ?? SchoolBillingOverview(schoolId: schoolId, studentCount: 0);
});

/// Riverpod family provider for single invoice details
final invoiceDetailsProvider =
    FutureProvider.family.autoDispose<SchoolInvoiceModel?, String>((ref, invoiceId) async {
  final repo = ref.watch(schoolBillingRepositoryProvider);
  final result = await repo.getInvoiceById(invoiceId);
  if (result.isFailure) {
    throw Exception(result.errorOrNull ?? 'Failed to load invoice');
  }
  return result.dataOrNull;
});

/// Riverpod family provider for invoice payment ledger
final invoicePaymentsProvider =
    FutureProvider.family.autoDispose<List<InvoicePaymentModel>, String>((ref, invoiceId) async {
  final repo = ref.watch(schoolBillingRepositoryProvider);
  final result = await repo.getInvoicePayments(invoiceId);
  if (result.isFailure) {
    throw Exception(result.errorOrNull ?? 'Failed to load payments');
  }
  return result.dataOrNull ?? [];
});

/// Riverpod family provider for executive billing dashboard summary
final billingDashboardSummaryProvider =
    FutureProvider.family.autoDispose<BillingDashboardSummary, String?>((ref, period) async {
  final repo = ref.watch(schoolBillingRepositoryProvider);
  final result = await repo.getGlobalBillingDashboard(period: period);
  if (result.isFailure) {
    throw Exception(result.errorOrNull ?? 'Failed to load billing dashboard');
  }
  return result.dataOrNull ?? BillingDashboardSummary.empty();
});

class InvoiceFilterParams {
  final String? schoolId;
  final String? billingPeriod;
  final String? statusFilter;
  final String? searchQuery;

  const InvoiceFilterParams({
    this.schoolId,
    this.billingPeriod,
    this.statusFilter,
    this.searchQuery,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InvoiceFilterParams &&
          runtimeType == other.runtimeType &&
          schoolId == other.schoolId &&
          billingPeriod == other.billingPeriod &&
          statusFilter == other.statusFilter &&
          searchQuery == other.searchQuery;

  @override
  int get hashCode => Object.hash(schoolId, billingPeriod, statusFilter, searchQuery);
}

/// Riverpod family provider for filtered invoices
final filteredInvoicesProvider =
    FutureProvider.family.autoDispose<List<SchoolInvoiceModel>, InvoiceFilterParams>((ref, params) async {
  final repo = ref.watch(schoolBillingRepositoryProvider);
  final result = await repo.getFilteredInvoices(
    schoolId: params.schoolId,
    billingPeriod: params.billingPeriod,
    statusFilter: params.statusFilter,
    searchQuery: params.searchQuery,
  );
  if (result.isFailure) {
    throw Exception(result.errorOrNull ?? 'Failed to load filtered invoices');
  }
  return result.dataOrNull ?? [];
});

class SchoolBillingRepository {
  final SchoolBillingService _service;

  SchoolBillingRepository(this._service);

  Future<ApiResult<SchoolStudentCountSummary>> getStudentCountSummary(
    String schoolId, {
    String? academicYearId,
  }) =>
      _service.fetchStudentCountSummary(schoolId, academicYearId: academicYearId);

  Future<ApiResult<SchoolBillingSettingsModel>> getBillingSettings(String schoolId) =>
      _service.fetchBillingSettings(schoolId);

  Future<ApiResult<SchoolBillingSettingsModel>> updateBillingRate(
    String schoolId,
    double newRate,
  ) =>
      _service.updateBillingRate(schoolId, newRate);

  Future<ApiResult<List<SchoolInvoiceModel>>> getInvoices(String schoolId) =>
      _service.fetchInvoices(schoolId);

  Future<ApiResult<SchoolBillingFinancialSummary>> getSchoolFinancialSummary(String schoolId) =>
      _service.fetchSchoolFinancialSummary(schoolId);

  Future<ApiResult<SchoolInvoiceModel>> getInvoiceById(String invoiceId) =>
      _service.fetchInvoiceById(invoiceId);

  Future<ApiResult<List<InvoicePaymentModel>>> getInvoicePayments(String invoiceId) =>
      _service.fetchInvoicePayments(invoiceId);

  Future<ApiResult<BillingDashboardSummary>> getGlobalBillingDashboard({String? period}) =>
      _service.fetchGlobalBillingDashboard(billingPeriod: period);

  Future<ApiResult<List<SchoolInvoiceModel>>> getFilteredInvoices({
    String? schoolId,
    String? billingPeriod,
    String? statusFilter,
    String? searchQuery,
  }) =>
      _service.fetchFilteredInvoices(
        schoolId: schoolId,
        billingPeriod: billingPeriod,
        statusFilter: statusFilter,
        searchQuery: searchQuery,
      );

  Future<ApiResult<SchoolInvoiceModel>> generateInvoice({
    required String schoolId,
    String? academicYearId,
    required DateTime billingPeriodStart,
    required DateTime billingPeriodEnd,
    required DateTime dueDate,
    String? notes,
    String? invoiceNumber,
  }) =>
      _service.generateInvoice(
        schoolId: schoolId,
        academicYearId: academicYearId,
        billingPeriodStart: billingPeriodStart,
        billingPeriodEnd: billingPeriodEnd,
        dueDate: dueDate,
        notes: notes,
        invoiceNumber: invoiceNumber,
      );

  Future<ApiResult<SchoolInvoiceModel>> recordPayment({
    required String invoiceId,
    required double amount,
    required PaymentMethod paymentMethod,
    DateTime? paymentDate,
    String? paymentReference,
    String? notes,
  }) =>
      _service.recordPayment(
        invoiceId: invoiceId,
        amount: amount,
        paymentMethod: paymentMethod,
        paymentDate: paymentDate,
        paymentReference: paymentReference,
        notes: notes,
      );

  Future<ApiResult<SchoolInvoiceModel>> markAsUnpaid({
    required String invoiceId,
  }) =>
      _service.markAsUnpaid(invoiceId: invoiceId);

  Future<ApiResult<SchoolInvoiceModel>> cancelInvoice({
    required String invoiceId,
    String? reason,
  }) =>
      _service.cancelInvoice(invoiceId: invoiceId, reason: reason);

  Future<ApiResult<SchoolBillingOverview>> getSchoolBillingOverview(String schoolId) =>
      _service.fetchSchoolBillingOverview(schoolId);
}
