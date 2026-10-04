import '../core/constants/billing_constants.dart';
import 'invoice_payment_model.dart';

enum InvoiceStatus {
  draft,
  generated,
  unpaid,
  paid,
  overdue,
  cancelled;

  static InvoiceStatus fromString(String? raw) {
    switch (raw?.toUpperCase().trim()) {
      case 'DRAFT':
        return InvoiceStatus.draft;
      case 'GENERATED':
        return InvoiceStatus.generated;
      case 'PAID':
        return InvoiceStatus.paid;
      case 'OVERDUE':
        return InvoiceStatus.overdue;
      case 'CANCELLED':
        return InvoiceStatus.cancelled;
      case 'UNPAID':
      default:
        return InvoiceStatus.unpaid;
    }
  }

  String get dbValue => name.toUpperCase();
  String get displayName => name[0].toUpperCase() + name.substring(1);
}

class SchoolInvoiceModel {
  final String id;
  final String? invoiceNumber;
  final String schoolId;
  final String? academicYearId;
  final DateTime billingPeriodStart;
  final DateTime billingPeriodEnd;
  final int studentCount;
  final double ratePerStudent;
  final String currency;
  final double subtotal;
  final double totalAmount;
  final InvoiceStatus status;
  final DateTime dueDate;
  final DateTime? paidAt;
  final String? paidBy;
  final DateTime? cancelledAt;
  final String? cancelledBy;
  final String? createdBy;
  final String? notes;
  final DateTime createdAt;
  final DateTime? updatedAt;

  // Joined metadata (Optional)
  final String? schoolName;
  final String? academicYearName;
  final List<InvoicePaymentModel> payments;

  const SchoolInvoiceModel({
    required this.id,
    this.invoiceNumber,
    required this.schoolId,
    this.academicYearId,
    required this.billingPeriodStart,
    required this.billingPeriodEnd,
    required this.studentCount,
    this.ratePerStudent = BillingConstants.defaultRatePerStudent,
    this.currency = BillingConstants.defaultCurrency,
    required this.subtotal,
    required this.totalAmount,
    this.status = InvoiceStatus.unpaid,
    required this.dueDate,
    this.paidAt,
    this.paidBy,
    this.cancelledAt,
    this.cancelledBy,
    this.createdBy,
    this.notes,
    required this.createdAt,
    this.updatedAt,
    this.schoolName,
    this.academicYearName,
    this.payments = const [],
  });

  bool get isPaid => status == InvoiceStatus.paid;

  bool get isOverdue {
    if (isPaid || status == InvoiceStatus.cancelled) return false;
    final now = DateTime.now();
    return dueDate.isBefore(DateTime(now.year, now.month, now.day));
  }

  InvoiceStatus get effectiveStatus {
    if (isPaid) return InvoiceStatus.paid;
    if (status == InvoiceStatus.cancelled) return InvoiceStatus.cancelled;
    if (isOverdue) return InvoiceStatus.overdue;
    return status;
  }

  String get displayInvoiceNumber {
    if (invoiceNumber != null && invoiceNumber!.trim().isNotEmpty) {
      return invoiceNumber!;
    }
    if (id.isNotEmpty) {
      final suffix = id.length >= 8 ? id.substring(0, 8).toUpperCase() : id.toUpperCase();
      return 'INV-$suffix';
    }
    return 'INV-PENDING';
  }

  double get outstandingAmount {
    if (isPaid || status == InvoiceStatus.cancelled) return 0.0;
    return totalAmount;
  }

  bool get canCancel => status != InvoiceStatus.paid && status != InvoiceStatus.cancelled;
  bool get canMarkPaid => status != InvoiceStatus.paid && status != InvoiceStatus.cancelled;

  factory SchoolInvoiceModel.fromJson(Map<String, dynamic> json) {
    final schoolMap = json['schools'];
    final schoolName = schoolMap is Map
        ? schoolMap['name']?.toString()
        : json['school_name']?.toString();

    final ayMap = json['academic_years'];
    final ayName = ayMap is Map
        ? ayMap['name']?.toString()
        : json['academic_year_name']?.toString();

    final rawStudentCount = json['student_count'];
    final studentCount = rawStudentCount is num
        ? rawStudentCount.toInt()
        : int.tryParse(rawStudentCount?.toString() ?? '0') ?? 0;

    final rawRate = json['rate_per_student'];
    final rate = rawRate is num
        ? rawRate.toDouble()
        : double.tryParse(rawRate?.toString() ?? '20.0') ?? BillingConstants.defaultRatePerStudent;

    final rawSubtotal = json['subtotal'];
    final subtotal = rawSubtotal is num
        ? rawSubtotal.toDouble()
        : double.tryParse(rawSubtotal?.toString() ?? '0.0') ??
            BillingConstants.calculateTotalAmount(studentCount: studentCount, ratePerStudent: rate);

    final rawTotal = json['total_amount'];
    final totalAmount = rawTotal is num
        ? rawTotal.toDouble()
        : double.tryParse(rawTotal?.toString() ?? '0.0') ?? subtotal;

    final rawPayments = json['invoice_payments'] ?? json['payments'];
    List<InvoicePaymentModel> paymentsList = [];
    if (rawPayments is List) {
      paymentsList = rawPayments
          .map((item) => InvoicePaymentModel.fromJson(item as Map<String, dynamic>))
          .toList();
    }

    return SchoolInvoiceModel(
      id: json['id']?.toString() ?? '',
      invoiceNumber: json['invoice_number']?.toString(),
      schoolId: json['school_id']?.toString() ?? '',
      academicYearId: json['academic_year_id']?.toString(),
      billingPeriodStart: json['billing_period_start'] != null
          ? DateTime.tryParse(json['billing_period_start'].toString()) ?? DateTime.now()
          : DateTime.now(),
      billingPeriodEnd: json['billing_period_end'] != null
          ? DateTime.tryParse(json['billing_period_end'].toString()) ?? DateTime.now()
          : DateTime.now(),
      studentCount: studentCount,
      ratePerStudent: rate,
      currency: json['currency']?.toString() ?? BillingConstants.defaultCurrency,
      subtotal: subtotal,
      totalAmount: totalAmount,
      status: InvoiceStatus.fromString(json['status']?.toString()),
      dueDate: json['due_date'] != null
          ? DateTime.tryParse(json['due_date'].toString()) ?? DateTime.now()
          : DateTime.now(),
      paidAt: json['paid_at'] != null ? DateTime.tryParse(json['paid_at'].toString()) : null,
      paidBy: json['paid_by']?.toString(),
      cancelledAt: json['cancelled_at'] != null
          ? DateTime.tryParse(json['cancelled_at'].toString())
          : null,
      cancelledBy: json['cancelled_by']?.toString(),
      createdBy: json['created_by']?.toString(),
      notes: json['notes']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
      schoolName: schoolName,
      academicYearName: ayName,
      payments: paymentsList,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id.isNotEmpty) 'id': id,
      if (invoiceNumber != null && invoiceNumber!.isNotEmpty) 'invoice_number': invoiceNumber,
      'school_id': schoolId,
      if (academicYearId != null && academicYearId!.isNotEmpty) 'academic_year_id': academicYearId,
      'billing_period_start': billingPeriodStart.toIso8601String().split('T')[0],
      'billing_period_end': billingPeriodEnd.toIso8601String().split('T')[0],
      'student_count': studentCount,
      'rate_per_student': ratePerStudent,
      'currency': currency,
      'subtotal': subtotal,
      'total_amount': totalAmount,
      'status': status.dbValue,
      'due_date': dueDate.toIso8601String().split('T')[0],
      if (paidAt != null) 'paid_at': paidAt!.toIso8601String(),
      if (paidBy != null) 'paid_by': paidBy,
      if (cancelledAt != null) 'cancelled_at': cancelledAt!.toIso8601String(),
      if (cancelledBy != null) 'cancelled_by': cancelledBy,
      if (createdBy != null) 'created_by': createdBy,
      if (notes != null) 'notes': notes,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  SchoolInvoiceModel copyWith({
    String? id,
    String? invoiceNumber,
    String? schoolId,
    String? academicYearId,
    DateTime? billingPeriodStart,
    DateTime? billingPeriodEnd,
    int? studentCount,
    double? ratePerStudent,
    String? currency,
    double? subtotal,
    double? totalAmount,
    InvoiceStatus? status,
    DateTime? dueDate,
    DateTime? paidAt,
    String? paidBy,
    DateTime? cancelledAt,
    String? cancelledBy,
    String? createdBy,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? schoolName,
    String? academicYearName,
    List<InvoicePaymentModel>? payments,
  }) {
    return SchoolInvoiceModel(
      id: id ?? this.id,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      schoolId: schoolId ?? this.schoolId,
      academicYearId: academicYearId ?? this.academicYearId,
      billingPeriodStart: billingPeriodStart ?? this.billingPeriodStart,
      billingPeriodEnd: billingPeriodEnd ?? this.billingPeriodEnd,
      studentCount: studentCount ?? this.studentCount,
      ratePerStudent: ratePerStudent ?? this.ratePerStudent,
      currency: currency ?? this.currency,
      subtotal: subtotal ?? this.subtotal,
      totalAmount: totalAmount ?? this.totalAmount,
      status: status ?? this.status,
      dueDate: dueDate ?? this.dueDate,
      paidAt: paidAt ?? this.paidAt,
      paidBy: paidBy ?? this.paidBy,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      cancelledBy: cancelledBy ?? this.cancelledBy,
      createdBy: createdBy ?? this.createdBy,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      schoolName: schoolName ?? this.schoolName,
      academicYearName: academicYearName ?? this.academicYearName,
      payments: payments ?? this.payments,
    );
  }
}
