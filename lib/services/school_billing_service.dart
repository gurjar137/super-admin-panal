import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants/billing_constants.dart';
import '../core/network/api_result.dart';
import '../models/billing_dashboard_summary.dart';
import '../models/invoice_payment_model.dart';
import '../models/school_billing_financial_summary.dart';
import '../models/school_billing_overview.dart';
import '../models/school_billing_settings_model.dart';
import '../models/school_invoice_model.dart';
import '../models/school_student_count_summary.dart';
import 'audit_log_service.dart';
import 'supabase_service.dart';

class SchoolBillingService {
  final SupabaseClient? _customClient;
  final AuditLogService _auditLogService;

  SchoolBillingService({
    SupabaseClient? client,
    AuditLogService? auditLogService,
  })  : _customClient = client,
        _auditLogService = auditLogService ?? AuditLogService(client: client);

  SupabaseClient? get _client => _customClient ?? SupabaseService.instance.client;
  AuditLogService get auditLogService => _auditLogService;

  String? get _currentActor {
    final user = _client?.auth.currentUser;
    return user?.email ?? user?.id;
  }

  /// Fetches live academic years and student count breakdown for a school.
  Future<ApiResult<SchoolStudentCountSummary>> fetchStudentCountSummary(
    String schoolId, {
    String? academicYearId,
  }) async {
    final client = _client;
    if (client == null) {
      return ApiResult.success(SchoolStudentCountSummary.empty(schoolId));
    }

    try {
      // 1. Fetch available academic years for the school
      List<AcademicYearOption> academicYears = [];
      try {
        final ayResponse = await client
            .from('academic_years')
            .select('id, name, status, start_date, end_date')
            .eq('school_id', schoolId)
            .order('start_date', ascending: false);

        academicYears = (ayResponse as List)
            .map((item) => AcademicYearOption.fromJson(item as Map<String, dynamic>))
            .toList();
      } catch (ayErr) {
        debugPrint('[SchoolBillingService] academic_years query warning: $ayErr');
      }

      // Determine active / selected academic year
      String? targetAyId = academicYearId;
      String? targetAyName;
      if (targetAyId == null && academicYears.isNotEmpty) {
        final resolvedAy = AcademicYearOption.resolveCurrent(academicYears);
        if (resolvedAy != null) {
          targetAyId = resolvedAy.id;
          targetAyName = resolvedAy.name;
        }
      } else if (targetAyId != null) {
        final match = academicYears.where((ay) => ay.id == targetAyId).toList();
        if (match.isNotEmpty) targetAyName = match.first.name;
      }

      // 2. Fetch live students for the school
      final studentsQuery = client
          .from('students')
          .select('id, academic_year_id, status')
          .eq('school_id', schoolId);

      final studentsList = await studentsQuery as List;
      final totalStudents = studentsList.length;

      // Filter billable students:
      // Must be ACTIVE and strictly assigned to the resolved/selected academic year.
      // If no academic year is resolved, billable students is 0.
      final int billableStudents;
      if (targetAyId == null || targetAyId.isEmpty) {
        billableStudents = 0;
      } else {
        billableStudents = studentsList.where((st) {
          final status = st['status']?.toString().toUpperCase() ?? '';
          final isActive = status == 'ACTIVE';
          if (!isActive) return false;

          final studentAyId = st['academic_year_id']?.toString();
          return studentAyId == targetAyId;
        }).length;
      }

      return ApiResult.success(
        SchoolStudentCountSummary(
          schoolId: schoolId,
          totalStudents: totalStudents,
          billableStudents: billableStudents,
          selectedAcademicYearId: targetAyId,
          selectedAcademicYearName: targetAyName,
          availableAcademicYears: academicYears,
        ),
      );
    } catch (e) {
      debugPrint('[SchoolBillingService] fetchStudentCountSummary error: $e');
      return ApiResult.failure('Failed to load student count summary: $e', e);
    }
  }

  /// Fetches billing configuration for a school, defaulting to ₹20 if unconfigured.
  Future<ApiResult<SchoolBillingSettingsModel>> fetchBillingSettings(String schoolId) async {
    final client = _client;
    if (client == null) {
      return ApiResult.success(SchoolBillingSettingsModel.defaultForSchool(schoolId));
    }

    try {
      final response = await client
          .from('school_billing_settings')
          .select('id, school_id, rate_per_student, currency, billing_cycle, active, created_at, updated_at')
          .eq('school_id', schoolId)
          .maybeSingle();

      if (response == null) {
        return ApiResult.success(SchoolBillingSettingsModel.defaultForSchool(schoolId));
      }

      return ApiResult.success(SchoolBillingSettingsModel.fromJson(response));
    } catch (e) {
      debugPrint('[SchoolBillingService] fetchBillingSettings warning (using default): $e');
      return ApiResult.success(SchoolBillingSettingsModel.defaultForSchool(schoolId));
    }
  }

  /// Updates or inserts billing settings for a school without altering old invoices.
  Future<ApiResult<SchoolBillingSettingsModel>> updateBillingRate(
    String schoolId,
    double newRate,
  ) async {
    final client = _client;
    if (client == null) {
      return ApiResult.failure('Supabase client not initialized');
    }

    try {
      final payload = {
        'school_id': schoolId,
        'rate_per_student': newRate,
        'currency': BillingConstants.defaultCurrency,
        'billing_cycle': BillingConstants.defaultBillingCycle,
        'active': true,
        'updated_at': DateTime.now().toIso8601String(),
      };

      final response = await client
          .from('school_billing_settings')
          .upsert(payload, onConflict: 'school_id')
          .select()
          .single();

      return ApiResult.success(SchoolBillingSettingsModel.fromJson(response));
    } catch (e) {
      debugPrint('[SchoolBillingService] updateBillingRate error: $e');
      return ApiResult.failure('Failed to update billing settings: $e', e);
    }
  }

  /// Generates the next human-readable invoice number: INV-YYYY-XXXXXX.
  Future<String> generateNextInvoiceNumber({int? year}) async {
    final targetYear = year ?? DateTime.now().year;
    final prefix = 'INV-$targetYear-';

    final client = _client;
    if (client == null) {
      return '$prefix${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    }

    try {
      final existing = await client
          .from('school_invoices')
          .select('invoice_number')
          .like('invoice_number', '$prefix%')
          .order('invoice_number', ascending: false)
          .limit(1);

      if (existing.isNotEmpty) {
        final lastNumber = existing.first['invoice_number']?.toString() ?? '';
        final parts = lastNumber.split('-');
        if (parts.length >= 3) {
          final seq = int.tryParse(parts[2]) ?? 0;
          final nextSeq = (seq + 1).toString().padLeft(6, '0');
          return '$prefix$nextSeq';
        }
      }

      // Count fallback
      final countResponse = await client
          .from('school_invoices')
          .select('id')
          .like('invoice_number', '$prefix%');
      final count = (countResponse as List).length + 1;
      return '$prefix${count.toString().padLeft(6, '0')}';
    } catch (e) {
      debugPrint('[SchoolBillingService] generateNextInvoiceNumber error: $e');
      final randomSuffix = DateTime.now().millisecondsSinceEpoch.toString().substring(7);
      return '$prefix$randomSuffix';
    }
  }

  /// Generates a new invoice with an immutable student snapshot and duplicate prevention.
  /// Strictly requires a resolvable current academic year and active billable students from live data.
  Future<ApiResult<SchoolInvoiceModel>> generateInvoice({
    required String schoolId,
    String? academicYearId,
    required DateTime billingPeriodStart,
    required DateTime billingPeriodEnd,
    required DateTime dueDate,
    String? notes,
    String? invoiceNumber,
  }) async {
    final client = _client;
    if (client == null) {
      return ApiResult.failure('Supabase client not initialized');
    }

    final startStr = billingPeriodStart.toIso8601String().split('T')[0];
    final endStr = billingPeriodEnd.toIso8601String().split('T')[0];

    try {
      // 1. Duplicate Prevention Check
      final duplicateCheck = await client
          .from('school_invoices')
          .select('id')
          .eq('school_id', schoolId)
          .eq('billing_period_start', startStr)
          .eq('billing_period_end', endStr)
          .maybeSingle();

      if (duplicateCheck != null) {
        return ApiResult.failure(
          'An invoice already exists for this school for the period $startStr to $endStr.',
        );
      }

      // 2. Resolve Academic Year and Fetch live student count
      final summaryResult = await fetchStudentCountSummary(schoolId, academicYearId: academicYearId);
      if (summaryResult.isFailure) {
        return ApiResult.failure(summaryResult.errorOrNull ?? 'Failed to read live student data');
      }

      final summary = summaryResult.dataOrNull;
      final targetAyId = summary?.selectedAcademicYearId;

      // RULE 3: If no resolvable current academic year, block generation with clear error
      if (targetAyId == null || targetAyId.isEmpty) {
        return ApiResult.failure('Academic year is not configured for this school.');
      }

      // RULE 4: If zero billable students found, block generation with clear error
      final liveStudentCount = summary?.billableStudents ?? 0;
      if (liveStudentCount <= 0) {
        return ApiResult.failure('No billable students found for the selected academic year.');
      }

      // 3. Fetch active rate
      final settingsResult = await fetchBillingSettings(schoolId);
      final rate = settingsResult.dataOrNull?.ratePerStudent ?? BillingConstants.defaultRatePerStudent;

      // 4. Decimal-safe bill calculation (LIVE STUDENT COUNT × RATE)
      final totalAmount = BillingConstants.calculateTotalAmount(
        studentCount: liveStudentCount,
        ratePerStudent: rate,
      );

      // 5. Generate human-readable invoice number if not provided
      final assignedNumber = invoiceNumber ?? await generateNextInvoiceNumber(year: billingPeriodStart.year);

      // 6. Create immutable invoice snapshot
      final payload = {
        'invoice_number': assignedNumber,
        'school_id': schoolId,
        'academic_year_id': targetAyId,
        'billing_period_start': startStr,
        'billing_period_end': endStr,
        'student_count': liveStudentCount,
        'rate_per_student': rate,
        'currency': BillingConstants.defaultCurrency,
        'subtotal': totalAmount,
        'total_amount': totalAmount,
        'status': 'UNPAID',
        'due_date': dueDate.toIso8601String().split('T')[0],
        'notes': notes?.trim(),
        'created_by': _currentActor,
      };

      final response = await client
          .from('school_invoices')
          .insert(payload)
          .select(
            'id, invoice_number, school_id, academic_year_id, billing_period_start, billing_period_end, '
            'student_count, rate_per_student, currency, subtotal, total_amount, status, '
            'due_date, paid_at, paid_by, cancelled_at, cancelled_by, created_by, notes, created_at, updated_at, '
            'schools(name), academic_years(name), invoice_payments(*)',
          )
          .single();

      final invoiceModel = SchoolInvoiceModel.fromJson(response);

      // Persistent Audit Logging (Record only after DB insert succeeds)
      try {
        await _auditLogService.recordAuditEvent(
          action: 'invoice_created',
          entityType: 'invoice',
          entityId: invoiceModel.id,
          schoolId: invoiceModel.schoolId,
          metadata: {
            'invoice_number': invoiceModel.invoiceNumber,
            'total_amount': invoiceModel.totalAmount,
            'student_count': invoiceModel.studentCount,
            'rate_per_student': invoiceModel.ratePerStudent,
          },
        );
      } catch (auditErr) {
        debugPrint('[SchoolBillingService] Audit event logging notice: $auditErr');
      }

      return ApiResult.success(invoiceModel);
    } catch (e) {
      debugPrint('[SchoolBillingService] generateInvoice error: $e');
      if (e is PostgrestException && e.code == '23505') {
        return ApiResult.failure('An invoice already exists for this school and billing period.');
      }
      return ApiResult.failure('Failed to generate invoice: $e', e);
    }
  }

  /// Records a manual full payment for an invoice with strict atomic financial integrity.
  Future<ApiResult<SchoolInvoiceModel>> recordPayment({
    required String invoiceId,
    required double amount,
    required PaymentMethod paymentMethod,
    DateTime? paymentDate,
    String? paymentReference,
    String? notes,
  }) async {
    final client = _client;
    if (client == null) {
      return ApiResult.failure('Supabase client not initialized');
    }

    try {
      // 1. Fetch current invoice snapshot and pre-validate
      final invResult = await fetchInvoiceById(invoiceId);
      final invoice = invResult.dataOrNull;
      if (invoice == null) {
        return ApiResult.failure('Invoice not found');
      }

      if (invoice.isPaid) {
        return ApiResult.failure('Invoice is already paid');
      }
      if (invoice.status == InvoiceStatus.cancelled) {
        return ApiResult.failure('Cannot record payment for a cancelled invoice');
      }

      // 2. Validate payment amount: Full payment only
      if (amount <= 0) {
        return ApiResult.failure('Payment amount must be greater than zero');
      }

      // Full payment validation (allowing <= 0.01 tolerance for minor float discrepancies)
      if ((amount - invoice.totalAmount).abs() > 0.01) {
        return ApiResult.failure(
          'Full payment only: Payment amount (${BillingConstants.formatCurrency(amount)}) must exactly match invoice total (${BillingConstants.formatCurrency(invoice.totalAmount)})',
        );
      }

      final paymentTime = paymentDate ?? DateTime.now();
      // 3. ATOMIC SERVER-SIDE EXECUTION:
      // Primary & Exclusive: Call the authoritative PostgreSQL stored procedure `record_invoice_payment_atomic`.
      // The entire operation (caller verification, row locking, payment insertion, invoice update)
      // is executed within a single database transaction. If any part fails, PostgreSQL
      // rolls back completely, ensuring no partial state.
      try {
        final rpcParams = {
          'p_invoice_id': invoiceId,
          'p_amount': amount,
          'p_payment_method': paymentMethod.dbValue,
          if (paymentReference != null && paymentReference.trim().isNotEmpty)
            'p_payment_reference': paymentReference.trim(),
          if (notes != null && notes.trim().isNotEmpty) 'p_notes': notes.trim(),
          'p_payment_date': paymentTime.toIso8601String(),
        };

        await client.rpc('record_invoice_payment_atomic', params: rpcParams);
      } on PostgrestException catch (pe) {
        final isMissingRpc = pe.code == 'PGRST202' ||
            pe.message.contains('Could not find the function') ||
            pe.message.contains('schema cache');
        if (isMissingRpc) {
          debugPrint('[SchoolBillingService] record_invoice_payment_atomic RPC not found: ${pe.message}');
          return ApiResult.failure('Payment service is temporarily unavailable.');
        }
        debugPrint('[SchoolBillingService] record_invoice_payment_atomic rejection: ${pe.message}');
        return ApiResult.failure(pe.message, pe);
      } catch (e) {
        final errStr = e.toString();
        if (errStr.contains('PGRST202') || errStr.contains('Could not find the function')) {
          return ApiResult.failure('Payment service is temporarily unavailable.');
        }
        debugPrint('[SchoolBillingService] RPC invocation failure: $e');
        return ApiResult.failure('Failed to record payment: $e', e);
      }

      // Persistent Audit Logging (Record only after atomic payment transaction succeeds)
      try {
        await _auditLogService.recordAuditEvent(
          action: 'payment_recorded',
          entityType: 'payment',
          entityId: invoiceId,
          schoolId: invoice.schoolId,
          metadata: {
            'action_category': 'billing_payment',
            'amount': amount,
            'payment_method': paymentMethod.dbValue,
            'invoice_number': invoice.invoiceNumber,
            if (paymentReference != null) 'payment_reference': paymentReference.trim(),
          },
        );
      } catch (auditErr) {
        debugPrint('[SchoolBillingService] Audit event logging notice: $auditErr');
      }

      // 4. Reload full invoice and payment history from database
      return fetchInvoiceById(invoiceId);
    } catch (e) {
      debugPrint('[SchoolBillingService] recordPayment error: $e');
      return ApiResult.failure('Failed to record payment: $e', e);
    }
  }

  /// Reverts an invoice to UNPAID status without deleting historical payment records.
  Future<ApiResult<SchoolInvoiceModel>> markAsUnpaid({
    required String invoiceId,
  }) async {
    final client = _client;
    if (client == null) {
      return ApiResult.failure('Supabase client not initialized');
    }

    try {
      final invResult = await fetchInvoiceById(invoiceId);
      final invoice = invResult.dataOrNull;
      if (invoice == null) return ApiResult.failure('Invoice not found');

      if (!invoice.isPaid) {
        return ApiResult.failure('Invoice is not marked as paid');
      }

      // 1. Mark existing completed payments as VOIDED (Preserves audit history)
      try {
        await client
            .from('invoice_payments')
            .update({
              'status': 'VOIDED',
              'notes': 'Voided on ${DateTime.now().toIso8601String()} by ${_currentActor ?? "admin"}',
            })
            .eq('invoice_id', invoiceId)
            .eq('status', 'COMPLETED');
      } catch (payErr) {
        debugPrint('[SchoolBillingService] Void payment warning: $payErr');
      }

      // 2. Revert invoice status to UNPAID
      await client.from('school_invoices').update({
        'status': 'UNPAID',
        'paid_at': null,
        'paid_by': null,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', invoiceId);

      // Persistent Audit Logging
      try {
        await _auditLogService.recordAuditEvent(
          action: 'invoice_marked_unpaid',
          entityType: 'invoice',
          entityId: invoiceId,
          schoolId: invoice.schoolId,
          metadata: {
            'action_category': 'invoice_marked_unpaid',
            'invoice_number': invoice.invoiceNumber,
            'previous_status': 'PAID',
            'new_status': 'UNPAID',
          },
        );
      } catch (auditErr) {
        debugPrint('[SchoolBillingService] Audit event logging notice: $auditErr');
      }

      return fetchInvoiceById(invoiceId);
    } catch (e) {
      debugPrint('[SchoolBillingService] markAsUnpaid error: $e');
      return ApiResult.failure('Failed to mark invoice as unpaid: $e', e);
    }
  }

  /// Cancels an unpaid invoice. A paid invoice cannot be cancelled.
  Future<ApiResult<SchoolInvoiceModel>> cancelInvoice({
    required String invoiceId,
    String? reason,
  }) async {
    final client = _client;
    if (client == null) {
      return ApiResult.failure('Supabase client not initialized');
    }

    try {
      final invResult = await fetchInvoiceById(invoiceId);
      final invoice = invResult.dataOrNull;
      if (invoice == null) return ApiResult.failure('Invoice not found');

      if (invoice.isPaid) {
        return ApiResult.failure('Cannot cancel a paid invoice. Please mark as unpaid before cancelling.');
      }
      if (invoice.status == InvoiceStatus.cancelled) {
        return ApiResult.failure('Invoice is already cancelled');
      }

      final now = DateTime.now();
      final actor = _currentActor;
      final existingNotes = invoice.notes ?? '';
      final updatedNotes = reason != null && reason.trim().isNotEmpty
          ? (existingNotes.isNotEmpty ? '$existingNotes\n[Cancelled]: ${reason.trim()}' : '[Cancelled]: ${reason.trim()}')
          : existingNotes;

      await client.from('school_invoices').update({
        'status': 'CANCELLED',
        'cancelled_at': now.toIso8601String(),
        'cancelled_by': actor,
        if (updatedNotes.isNotEmpty) 'notes': updatedNotes,
        'updated_at': now.toIso8601String(),
      }).eq('id', invoiceId);

      // Persistent Audit Logging
      try {
        await _auditLogService.recordAuditEvent(
          action: 'invoice_cancelled',
          entityType: 'invoice',
          entityId: invoiceId,
          schoolId: invoice.schoolId,
          metadata: {
            'action_category': 'invoice_cancelled',
            'invoice_number': invoice.invoiceNumber,
            if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
          },
        );
      } catch (auditErr) {
        debugPrint('[SchoolBillingService] Audit event logging notice: $auditErr');
      }

      return fetchInvoiceById(invoiceId);
    } catch (e) {
      debugPrint('[SchoolBillingService] cancelInvoice error: $e');
      return ApiResult.failure('Failed to cancel invoice: $e', e);
    }
  }

  /// Fetches a single invoice by ID with joined school and payments.
  Future<ApiResult<SchoolInvoiceModel>> fetchInvoiceById(String invoiceId) async {
    final client = _client;
    if (client == null) {
      return ApiResult.failure('Supabase client not initialized');
    }

    try {
      final response = await client
          .from('school_invoices')
          .select(
            'id, invoice_number, school_id, academic_year_id, billing_period_start, billing_period_end, '
            'student_count, rate_per_student, currency, subtotal, total_amount, status, '
            'due_date, paid_at, paid_by, cancelled_at, cancelled_by, created_by, notes, created_at, updated_at, '
            'schools(name), academic_years(name), invoice_payments(*)',
          )
          .eq('id', invoiceId)
          .single();

      return ApiResult.success(SchoolInvoiceModel.fromJson(response));
    } catch (e) {
      debugPrint('[SchoolBillingService] fetchInvoiceById error: $e');
      return ApiResult.failure('Failed to load invoice: $e', e);
    }
  }

  /// Fetches payment records for an invoice.
  Future<ApiResult<List<InvoicePaymentModel>>> fetchInvoicePayments(String invoiceId) async {
    final client = _client;
    if (client == null) return ApiResult.success([]);

    try {
      final response = await client
          .from('invoice_payments')
          .select('*')
          .eq('invoice_id', invoiceId)
          .order('payment_date', ascending: false);

      final list = (response as List)
          .map((item) => InvoicePaymentModel.fromJson(item as Map<String, dynamic>))
          .toList();

      return ApiResult.success(list);
    } catch (e) {
      debugPrint('[SchoolBillingService] fetchInvoicePayments warning: $e');
      return ApiResult.success([]);
    }
  }

  /// Fetches invoice history for a school.
  Future<ApiResult<List<SchoolInvoiceModel>>> fetchInvoices(String schoolId) async {
    final client = _client;
    if (client == null) {
      return ApiResult.success([]);
    }

    try {
      final response = await client
          .from('school_invoices')
          .select(
            'id, invoice_number, school_id, academic_year_id, billing_period_start, billing_period_end, '
            'student_count, rate_per_student, currency, subtotal, total_amount, status, '
            'due_date, paid_at, paid_by, cancelled_at, cancelled_by, created_by, notes, created_at, updated_at, '
            'schools(name), academic_years(name), invoice_payments(*)',
          )
          .eq('school_id', schoolId)
          .order('billing_period_start', ascending: false);

      final list = (response as List)
          .map((item) => SchoolInvoiceModel.fromJson(item as Map<String, dynamic>))
          .toList();

      return ApiResult.success(list);
    } catch (e) {
      debugPrint('[SchoolBillingService] fetchInvoices error: $e');
      return ApiResult.success([]);
    }
  }

  /// Fetches school billing financial summary (Current Bill, Total Billed, Total Paid, Outstanding, Overdue).
  Future<ApiResult<SchoolBillingFinancialSummary>> fetchSchoolFinancialSummary(String schoolId) async {
    final invoicesResult = await fetchInvoices(schoolId);
    final invoices = invoicesResult.dataOrNull ?? [];
    return ApiResult.success(SchoolBillingFinancialSummary.fromInvoices(schoolId, invoices));
  }

  /// Fetches searchable & filterable invoices with server-side pagination for the Super Admin Invoice List.
  Future<ApiResult<List<SchoolInvoiceModel>>> fetchFilteredInvoices({
    String? schoolId,
    String? billingPeriod,
    String? statusFilter,
    String? searchQuery,
    int? page,
    int? pageSize,
  }) async {
    final client = _client;
    if (client == null) return ApiResult.success([]);

    try {
      var query = client.from('school_invoices').select(
            'id, invoice_number, school_id, academic_year_id, billing_period_start, billing_period_end, '
            'student_count, rate_per_student, currency, subtotal, total_amount, status, '
            'due_date, paid_at, paid_by, cancelled_at, cancelled_by, created_by, notes, created_at, updated_at, '
            'schools(name), academic_years(name), invoice_payments(*)',
          );

      if (schoolId != null && schoolId.isNotEmpty) {
        query = query.eq('school_id', schoolId);
      }

      if (statusFilter != null && statusFilter.isNotEmpty && statusFilter != 'ALL') {
        if (statusFilter == 'PAID') {
          query = query.eq('status', 'PAID');
        } else if (statusFilter == 'CANCELLED') {
          query = query.eq('status', 'CANCELLED');
        } else if (statusFilter == 'UNPAID') {
          query = query.eq('status', 'UNPAID');
        } else if (statusFilter == 'OVERDUE') {
          final today = DateTime.now().toIso8601String().split('T').first;
          query = query.neq('status', 'PAID').neq('status', 'CANCELLED').lt('due_date', today);
        }
      }

      if (billingPeriod != null && billingPeriod.isNotEmpty && billingPeriod != 'All Time') {
        try {
          final parts = billingPeriod.trim().split(' ');
          if (parts.length == 2) {
            final monthName = parts[0];
            final year = int.tryParse(parts[1]);
            const months = {
              'january': 1, 'february': 2, 'march': 3, 'april': 4,
              'may': 5, 'june': 6, 'july': 7, 'august': 8,
              'september': 9, 'october': 10, 'november': 11, 'december': 12,
            };
            final month = months[monthName.toLowerCase()];
            if (month != null && year != null) {
              final start = DateTime(year, month, 1);
              final end = DateTime(year, month + 1, 0, 23, 59, 59);
              query = query
                  .gte('billing_period_start', start.toIso8601String())
                  .lte('billing_period_start', end.toIso8601String());
            }
          }
        } catch (_) {}
      }

      // Server-side search filter across invoice_number and notes evaluated BEFORE range/pagination
      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final term = searchQuery.trim().replaceAll(RegExp(r'[%_]'), '');
        if (term.isNotEmpty) {
          query = query.or('invoice_number.ilike.%$term%,notes.ilike.%$term%');
        }
      }

      // Stable ordering: billing_period_start DESC, created_at DESC, id DESC as tie-breaker
      final orderedQuery = query
          .order('billing_period_start', ascending: false)
          .order('created_at', ascending: false)
          .order('id', ascending: false);

      final PostgrestTransformBuilder finalQuery;
      if (page != null || pageSize != null) {
        final p = page ?? 0;
        final ps = pageSize ?? 25;
        final offset = p * ps;
        finalQuery = orderedQuery.range(offset, offset + ps - 1);
      } else {
        finalQuery = orderedQuery;
      }

      final response = await finalQuery;

      final list = (response as List)
          .map((item) => SchoolInvoiceModel.fromJson(item as Map<String, dynamic>))
          .toList();

      return ApiResult.success(list);
    } catch (e) {
      debugPrint('[SchoolBillingService] fetchFilteredInvoices error: $e');
      return ApiResult.success([]);
    }
  }

  /// Fetches total count of filtered invoices matching current criteria.
  Future<ApiResult<int>> fetchFilteredInvoicesCount({
    String? schoolId,
    String? billingPeriod,
    String? statusFilter,
    String? searchQuery,
  }) async {
    final client = _client;
    if (client == null) return ApiResult.success(0);

    try {
      var query = client.from('school_invoices').select('id');

      if (schoolId != null && schoolId.isNotEmpty) {
        query = query.eq('school_id', schoolId);
      }

      if (statusFilter != null && statusFilter.isNotEmpty && statusFilter != 'ALL') {
        if (statusFilter == 'PAID') {
          query = query.eq('status', 'PAID');
        } else if (statusFilter == 'CANCELLED') {
          query = query.eq('status', 'CANCELLED');
        } else if (statusFilter == 'UNPAID') {
          query = query.eq('status', 'UNPAID');
        } else if (statusFilter == 'OVERDUE') {
          final today = DateTime.now().toIso8601String().split('T').first;
          query = query.neq('status', 'PAID').neq('status', 'CANCELLED').lt('due_date', today);
        }
      }

      if (billingPeriod != null && billingPeriod.isNotEmpty && billingPeriod != 'All Time') {
        try {
          final parts = billingPeriod.trim().split(' ');
          if (parts.length == 2) {
            final monthName = parts[0];
            final year = int.tryParse(parts[1]);
            const months = {
              'january': 1, 'february': 2, 'march': 3, 'april': 4,
              'may': 5, 'june': 6, 'july': 7, 'august': 8,
              'september': 9, 'october': 10, 'november': 11, 'december': 12,
            };
            final month = months[monthName.toLowerCase()];
            if (month != null && year != null) {
              final start = DateTime(year, month, 1);
              final end = DateTime(year, month + 1, 0, 23, 59, 59);
              query = query
                  .gte('billing_period_start', start.toIso8601String())
                  .lte('billing_period_start', end.toIso8601String());
            }
          }
        } catch (_) {}
      }

      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final term = searchQuery.trim().replaceAll(RegExp(r'[%_]'), '');
        if (term.isNotEmpty) {
          query = query.or('invoice_number.ilike.%$term%,notes.ilike.%$term%');
        }
      }

      final res = await query.count(CountOption.exact);
      return ApiResult.success(res.count);
    } catch (e) {
      debugPrint('[SchoolBillingService] fetchFilteredInvoicesCount error: $e');
      return ApiResult.success(0);
    }
  }

  /// Fetches global billing dashboard summary across all schools.
  Future<ApiResult<BillingDashboardSummary>> fetchGlobalBillingDashboard({String? billingPeriod}) async {
    final client = _client;
    if (client == null) {
      return ApiResult.success(BillingDashboardSummary.empty());
    }

    try {
      // 1. Total schools count
      int totalSchools = 0;
      try {
        final schoolsRes = await client.from('schools').select('id');
        totalSchools = (schoolsRes as List).length;
      } catch (_) {}

      // 2. Query invoices
      final invoicesRes = await client
          .from('school_invoices')
          .select('id, student_count, total_amount, status, due_date, billing_period_start, billing_period_end')
          .order('billing_period_start', ascending: false);

      final invoicesList = invoicesRes as List;

      int totalStudents = 0;
      double totalBilled = 0.0;
      double totalPaid = 0.0;
      double totalOverdue = 0.0;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      for (final raw in invoicesList) {
        final status = raw['status']?.toString().toUpperCase() ?? 'UNPAID';
        if (status == 'CANCELLED') continue;

        final rawTotal = raw['total_amount'];
        final amount = rawTotal is num ? rawTotal.toDouble() : (double.tryParse(rawTotal?.toString() ?? '0') ?? 0.0);

        final rawCount = raw['student_count'];
        final count = rawCount is num ? rawCount.toInt() : (int.tryParse(rawCount?.toString() ?? '0') ?? 0);

        totalStudents += count;
        totalBilled += amount;

        if (status == 'PAID') {
          totalPaid += amount;
        } else if (status == 'UNPAID') {
          final rawDue = raw['due_date']?.toString();
          final dueDate = rawDue != null ? DateTime.tryParse(rawDue) : null;
          if (dueDate != null && dueDate.isBefore(today)) {
            totalOverdue += amount;
          }
        }
      }

      final totalOutstanding = (totalBilled - totalPaid).clamp(0.0, double.infinity);

      return ApiResult.success(
        BillingDashboardSummary(
          totalSchools: totalSchools,
          totalStudentsBilled: totalStudents,
          totalBilled: totalBilled,
          totalPaid: totalPaid,
          totalOutstanding: totalOutstanding,
          totalOverdue: totalOverdue,
          selectedPeriod: billingPeriod ?? 'All Time',
        ),
      );
    } catch (e) {
      debugPrint('[SchoolBillingService] fetchGlobalBillingDashboard error: $e');
      return ApiResult.success(BillingDashboardSummary.empty());
    }
  }

  /// Fetches a high-level billing overview for a single school.
  Future<ApiResult<SchoolBillingOverview>> fetchSchoolBillingOverview(String schoolId) async {
    final client = _client;
    if (client == null) {
      return ApiResult.success(SchoolBillingOverview(schoolId: schoolId, studentCount: 0));
    }

    try {
      // 1. Live student count
      final studentsList = await client
          .from('students')
          .select('id, status')
          .eq('school_id', schoolId) as List;

      final billableCount = studentsList.where((st) => (st['status']?.toString().toUpperCase() ?? '') == 'ACTIVE').length;

      // 2. Billing settings
      final settings = await fetchBillingSettings(schoolId);
      final rate = settings.dataOrNull?.ratePerStudent ?? BillingConstants.defaultRatePerStudent;

      // 3. Latest invoice
      SchoolInvoiceModel? latestInvoice;
      try {
        final invResponse = await client
            .from('school_invoices')
            .select('*')
            .eq('school_id', schoolId)
            .order('billing_period_start', ascending: false)
            .limit(1)
            .maybeSingle();

        if (invResponse != null) {
          latestInvoice = SchoolInvoiceModel.fromJson(invResponse);
        }
      } catch (_) {}

      return ApiResult.success(
        SchoolBillingOverview(
          schoolId: schoolId,
          studentCount: billableCount,
          ratePerStudent: rate,
          latestBillAmount: latestInvoice?.totalAmount,
          latestBillingPeriod: latestInvoice != null
              ? '${latestInvoice.billingPeriodStart.month}/${latestInvoice.billingPeriodStart.year}'
              : null,
          latestStatus: latestInvoice?.status,
          hasInvoices: latestInvoice != null,
        ),
      );
    } catch (e) {
      debugPrint('[SchoolBillingService] fetchSchoolBillingOverview error: $e');
      return ApiResult.success(SchoolBillingOverview(schoolId: schoolId, studentCount: 0));
    }
  }
}
