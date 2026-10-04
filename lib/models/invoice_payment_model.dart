import 'package:flutter/material.dart';

enum PaymentMethod {
  cash,
  bankTransfer,
  upi,
  other;

  static PaymentMethod fromString(String? raw) {
    switch (raw?.toUpperCase().trim()) {
      case 'CASH':
        return PaymentMethod.cash;
      case 'BANK_TRANSFER':
        return PaymentMethod.bankTransfer;
      case 'UPI':
        return PaymentMethod.upi;
      case 'OTHER':
      default:
        return PaymentMethod.other;
    }
  }

  String get dbValue {
    switch (this) {
      case PaymentMethod.cash:
        return 'CASH';
      case PaymentMethod.bankTransfer:
        return 'BANK_TRANSFER';
      case PaymentMethod.upi:
        return 'UPI';
      case PaymentMethod.other:
        return 'OTHER';
    }
  }

  String get displayName {
    switch (this) {
      case PaymentMethod.cash:
        return 'Cash';
      case PaymentMethod.bankTransfer:
        return 'Bank Transfer';
      case PaymentMethod.upi:
        return 'UPI';
      case PaymentMethod.other:
        return 'Other';
    }
  }

  IconData get icon {
    switch (this) {
      case PaymentMethod.cash:
        return Icons.payments_outlined;
      case PaymentMethod.bankTransfer:
        return Icons.account_balance_outlined;
      case PaymentMethod.upi:
        return Icons.qr_code_rounded;
      case PaymentMethod.other:
        return Icons.receipt_long_outlined;
    }
  }
}

enum PaymentStatus {
  completed,
  voided;

  static PaymentStatus fromString(String? raw) {
    switch (raw?.toUpperCase().trim()) {
      case 'VOIDED':
        return PaymentStatus.voided;
      case 'COMPLETED':
      default:
        return PaymentStatus.completed;
    }
  }

  String get dbValue => name.toUpperCase();
  String get displayName => name[0].toUpperCase() + name.substring(1);
}

class InvoicePaymentModel {
  final String id;
  final String invoiceId;
  final double amount;
  final DateTime paymentDate;
  final PaymentMethod paymentMethod;
  final String? paymentReference;
  final String? notes;
  final PaymentStatus status;
  final String? createdBy;
  final DateTime createdAt;

  const InvoicePaymentModel({
    required this.id,
    required this.invoiceId,
    required this.amount,
    required this.paymentDate,
    required this.paymentMethod,
    this.paymentReference,
    this.notes,
    this.status = PaymentStatus.completed,
    this.createdBy,
    required this.createdAt,
  });

  bool get isCompleted => status == PaymentStatus.completed;
  bool get isVoided => status == PaymentStatus.voided;

  factory InvoicePaymentModel.fromJson(Map<String, dynamic> json) {
    final rawAmount = json['amount'];
    final amount = rawAmount is num
        ? rawAmount.toDouble()
        : double.tryParse(rawAmount?.toString() ?? '0.0') ?? 0.0;

    return InvoicePaymentModel(
      id: json['id']?.toString() ?? '',
      invoiceId: json['invoice_id']?.toString() ?? '',
      amount: amount,
      paymentDate: json['payment_date'] != null
          ? DateTime.tryParse(json['payment_date'].toString()) ?? DateTime.now()
          : DateTime.now(),
      paymentMethod: PaymentMethod.fromString(json['payment_method']?.toString()),
      paymentReference: json['payment_reference']?.toString(),
      notes: json['notes']?.toString(),
      status: PaymentStatus.fromString(json['status']?.toString()),
      createdBy: json['created_by']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id.isNotEmpty) 'id': id,
      'invoice_id': invoiceId,
      'amount': amount,
      'payment_date': paymentDate.toIso8601String(),
      'payment_method': paymentMethod.dbValue,
      if (paymentReference != null && paymentReference!.isNotEmpty)
        'payment_reference': paymentReference,
      if (notes != null && notes!.isNotEmpty) 'notes': notes,
      'status': status.dbValue,
      if (createdBy != null && createdBy!.isNotEmpty) 'created_by': createdBy,
    };
  }
}
