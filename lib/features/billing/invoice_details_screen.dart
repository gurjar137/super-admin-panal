import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/constants/billing_constants.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../models/invoice_payment_model.dart';
import '../../models/school_invoice_model.dart';
import '../../repositories/school_billing_repository.dart';
import '../../theme/app_colors.dart';

class InvoiceDetailsScreen extends ConsumerStatefulWidget {
  final String invoiceId;

  const InvoiceDetailsScreen({
    super.key,
    required this.invoiceId,
  });

  @override
  ConsumerState<InvoiceDetailsScreen> createState() => _InvoiceDetailsScreenState();
}

class _InvoiceDetailsScreenState extends ConsumerState<InvoiceDetailsScreen> {
  bool _isProcessing = false;

  void _showPaymentDialog(BuildContext context, SchoolInvoiceModel invoice) {
    DateTime selectedDate = DateTime.now();
    PaymentMethod selectedMethod = PaymentMethod.bankTransfer;
    final referenceCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    bool dialogLoading = false;

    showDialog(
      context: context,
      barrierDismissible: !dialogLoading,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.payments_rounded, color: AppColors.success, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Record Full Payment',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Full payment notice banner
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.info.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline_rounded, color: AppColors.info, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Full payment only',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.info),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Payment amount is fixed to the exact invoice balance of ${BillingConstants.formatCurrency(invoice.totalAmount)}.',
                                style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Amount display (Fixed)
                  const Text('Payment Amount', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.borderLight),
                    ),
                    child: Text(
                      BillingConstants.formatCurrency(invoice.totalAmount),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Payment Method Dropdown
                  const Text('Payment Method', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<PaymentMethod>(
                    initialValue: selectedMethod,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    items: PaymentMethod.values.map((method) {
                      return DropdownMenuItem<PaymentMethod>(
                        value: method,
                        child: Row(
                          children: [
                            Icon(method.icon, size: 18, color: AppColors.textPrimary),
                            const SizedBox(width: 10),
                            Text(method.displayName),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedMethod = val);
                    },
                  ),
                  const SizedBox(height: 16),

                  // Payment Date
                  const Text('Payment Date', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setDialogState(() => selectedDate = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.borderLight),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded, size: 16, color: AppColors.textMuted),
                          const SizedBox(width: 10),
                          Text(DateFormat('dd MMM yyyy').format(selectedDate)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Reference No.
                  const Text('Payment Reference (UTR / Cheque / Txn ID)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: referenceCtrl,
                    decoration: InputDecoration(
                      hintText: 'e.g. UPI/2026/09/12345678 or NEFT987654',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Notes
                  const Text('Notes (Optional)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Internal note or payment details...',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: dialogLoading ? null : () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: dialogLoading
                  ? null
                  : () async {
                      setDialogState(() => dialogLoading = true);
                      final messenger = ScaffoldMessenger.of(context);
                      final repo = ref.read(schoolBillingRepositoryProvider);
                      final result = await repo.recordPayment(
                        invoiceId: invoice.id,
                        amount: invoice.totalAmount,
                        paymentMethod: selectedMethod,
                        paymentDate: selectedDate,
                        paymentReference: referenceCtrl.text.trim(),
                        notes: notesCtrl.text.trim(),
                      );

                      if (dialogCtx.mounted) {
                        Navigator.pop(dialogCtx);
                      }
                      if (result.isSuccess) {
                        ref.invalidate(invoiceDetailsProvider(invoice.id));
                        ref.invalidate(invoicePaymentsProvider(invoice.id));
                        ref.invalidate(schoolInvoicesProvider(invoice.schoolId));
                        ref.invalidate(schoolFinancialSummaryProvider(invoice.schoolId));
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('Payment recorded for ${invoice.displayInvoiceNumber}'),
                            backgroundColor: AppColors.success,
                          ),
                        );
                      } else {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(result.errorOrNull ?? 'Failed to record payment'),
                            backgroundColor: AppColors.error,
                          ),
                        );
                      }
                    },
              icon: dialogLoading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_circle_rounded, size: 18),
              label: const Text('Confirm Payment'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMarkUnpaidDialog(BuildContext context, SchoolInvoiceModel invoice) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.undo_rounded, color: AppColors.warning),
            SizedBox(width: 10),
            Text('Revert Payment Status'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to mark ${invoice.displayInvoiceNumber} as UNPAID?',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Payment record will be preserved in audit history and marked as voided.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              setState(() => _isProcessing = true);
              final messenger = ScaffoldMessenger.of(context);
              final repo = ref.read(schoolBillingRepositoryProvider);
              final result = await repo.markAsUnpaid(invoiceId: invoice.id);
              if (mounted) setState(() => _isProcessing = false);

              if (result.isSuccess) {
                ref.invalidate(invoiceDetailsProvider(invoice.id));
                ref.invalidate(invoicePaymentsProvider(invoice.id));
                ref.invalidate(schoolInvoicesProvider(invoice.schoolId));
                ref.invalidate(schoolFinancialSummaryProvider(invoice.schoolId));
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Invoice marked as UNPAID'),
                    backgroundColor: AppColors.info,
                  ),
                );
              } else {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(result.errorOrNull ?? 'Failed to revert payment'),
                    backgroundColor: AppColors.error,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning, foregroundColor: Colors.white),
            child: const Text('Confirm Unpaid'),
          ),
        ],
      ),
    );
  }

  void _showCancelDialog(BuildContext context, SchoolInvoiceModel invoice) {
    if (invoice.isPaid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Paid invoices cannot be cancelled.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final reasonCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.cancel_outlined, color: AppColors.error),
            SizedBox(width: 10),
            Text('Cancel Invoice'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to cancel ${invoice.displayInvoiceNumber}?',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'This invoice will remain in the database for audit history with status CANCELLED and will no longer be billable.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
            ),
            const SizedBox(height: 14),
            const Text('Reason for Cancellation (Optional)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
            const SizedBox(height: 6),
            TextField(
              controller: reasonCtrl,
              decoration: InputDecoration(
                hintText: 'e.g. Duplicate period generated or school requested revised terms',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Keep Active'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              setState(() => _isProcessing = true);
              final messenger = ScaffoldMessenger.of(context);
              final repo = ref.read(schoolBillingRepositoryProvider);
              final result = await repo.cancelInvoice(
                invoiceId: invoice.id,
                reason: reasonCtrl.text.trim(),
              );
              if (mounted) setState(() => _isProcessing = false);

              if (result.isSuccess) {
                ref.invalidate(invoiceDetailsProvider(invoice.id));
                ref.invalidate(schoolInvoicesProvider(invoice.schoolId));
                ref.invalidate(schoolFinancialSummaryProvider(invoice.schoolId));
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Invoice cancelled successfully'),
                    backgroundColor: AppColors.sidebarDark,
                  ),
                );
              } else {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(result.errorOrNull ?? 'Failed to cancel invoice'),
                    backgroundColor: AppColors.error,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            child: const Text('Cancel Invoice'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(InvoiceStatus status, bool isOverdue) {
    Color bg;
    Color fg;
    String label;
    IconData icon;

    if (status == InvoiceStatus.paid) {
      bg = AppColors.success.withValues(alpha: 0.12);
      fg = AppColors.success;
      label = 'PAID';
      icon = Icons.check_circle_rounded;
    } else if (status == InvoiceStatus.cancelled) {
      bg = Colors.grey.shade200;
      fg = Colors.grey.shade700;
      label = 'CANCELLED';
      icon = Icons.cancel_outlined;
    } else if (isOverdue) {
      bg = AppColors.error.withValues(alpha: 0.12);
      fg = AppColors.error;
      label = 'OVERDUE';
      icon = Icons.warning_amber_rounded;
    } else {
      bg = AppColors.warning.withValues(alpha: 0.12);
      fg = AppColors.warning;
      label = 'UNPAID';
      icon = Icons.schedule_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final invoiceAsync = ref.watch(invoiceDetailsProvider(widget.invoiceId));
    final paymentsAsync = ref.watch(invoicePaymentsProvider(widget.invoiceId));
    final isWide = ResponsiveLayout.isWideScreen(context);

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        title: const Text('Invoice Details', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/schools');
            }
          },
        ),
      ),
      body: invoiceAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 48),
              const SizedBox(height: 12),
              Text('Failed to load invoice: $err', style: const TextStyle(color: AppColors.textPrimary)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(invoiceDetailsProvider(widget.invoiceId)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (invoice) {
          if (invoice == null) {
            return const Center(child: Text('Invoice not found'));
          }

          final payments = paymentsAsync.asData?.value ?? invoice.payments;
          final dateFormat = DateFormat('dd MMM yyyy');

          return Stack(
            children: [
              SingleChildScrollView(
                padding: EdgeInsets.all(isWide ? 32.0 : 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Bar with Invoice No & Action Buttons
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: AppColors.borderLight),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.receipt_long_rounded, color: AppColors.primary, size: 28),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        invoice.displayInvoiceNumber,
                                        style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      _buildStatusChip(invoice.status, invoice.isOverdue),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    invoice.schoolName != null
                                        ? '${invoice.schoolName} (${invoice.schoolId})'
                                        : invoice.schoolId,
                                    style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                                  ),
                                ],
                              ),
                            ),
                            // Quick Action Buttons
                            if (invoice.canMarkPaid) ...[
                              ElevatedButton.icon(
                                onPressed: () => _showPaymentDialog(context, invoice),
                                icon: const Icon(Icons.payments_rounded, size: 18),
                                label: const Text('Mark as Paid'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.success,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            if (invoice.isPaid) ...[
                              OutlinedButton.icon(
                                onPressed: () => _showMarkUnpaidDialog(context, invoice),
                                icon: const Icon(Icons.undo_rounded, size: 18),
                                label: const Text('Mark as Unpaid'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.warning,
                                  side: const BorderSide(color: AppColors.warning),
                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            if (invoice.canCancel) ...[
                              OutlinedButton.icon(
                                onPressed: () => _showCancelDialog(context, invoice),
                                icon: const Icon(Icons.cancel_outlined, size: 18),
                                label: const Text('Cancel'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.error,
                                  side: const BorderSide(color: AppColors.error),
                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Grid / Two Column Cards
                    if (isWide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildSnapshotCard(invoice, dateFormat)),
                          const SizedBox(width: 24),
                          Expanded(child: _buildLifecycleCard(invoice, dateFormat)),
                        ],
                      )
                    else ...[
                      _buildSnapshotCard(invoice, dateFormat),
                      const SizedBox(height: 16),
                      _buildLifecycleCard(invoice, dateFormat),
                    ],
                    const SizedBox(height: 24),

                    // Payment History Section
                    _buildPaymentHistoryCard(payments, dateFormat),
                  ],
                ),
              ),
              if (_isProcessing)
                Container(
                  color: Colors.black26,
                  child: const Center(child: CircularProgressIndicator()),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSnapshotCard(SchoolInvoiceModel invoice, DateFormat dateFormat) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.borderLight),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.lock_outline_rounded, size: 20, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Frozen Invoice Snapshot',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'IMMUTABLE',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.info),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.verified_outlined, size: 18, color: Colors.amber.shade900),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Snapshot values were permanently frozen on ${dateFormat.format(invoice.createdAt)}.',
                      style: TextStyle(fontSize: 12, color: Colors.amber.shade900, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _infoRow('School Name', invoice.schoolName ?? '—'),
            _infoRow('School ID', invoice.schoolId),
            if (invoice.academicYearName != null)
              _infoRow('Academic Year', invoice.academicYearName!),
            _infoRow(
              'Billing Period',
              '${dateFormat.format(invoice.billingPeriodStart)} — ${dateFormat.format(invoice.billingPeriodEnd)}',
            ),
            const Divider(height: 24),
            _infoRow('Billable Student Count', '${invoice.studentCount} students'),
            _infoRow('Billing Rate', '${BillingConstants.formatCurrency(invoice.ratePerStudent)} / student'),
            _infoRow('Subtotal', BillingConstants.formatCurrency(invoice.subtotal)),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total Invoice Amount', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text(
                  BillingConstants.formatCurrency(invoice.totalAmount),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: AppColors.primary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLifecycleCard(SchoolInvoiceModel invoice, DateFormat dateFormat) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.borderLight),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.timeline_rounded, size: 20, color: AppColors.primary),
                SizedBox(width: 8),
                Text(
                  'Lifecycle & Audit Information',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _infoRow('Due Date', dateFormat.format(invoice.dueDate)),
            _infoRow('Outstanding Balance', BillingConstants.formatCurrency(invoice.outstandingAmount)),
            _infoRow('Generated At', dateFormat.format(invoice.createdAt)),
            if (invoice.createdBy != null) _infoRow('Generated By', invoice.createdBy!),
            if (invoice.isPaid) ...[
              const Divider(height: 20),
              _infoRow('Paid Date', invoice.paidAt != null ? dateFormat.format(invoice.paidAt!) : '—'),
              if (invoice.paidBy != null) _infoRow('Paid Recorded By', invoice.paidBy!),
            ],
            if (invoice.status == InvoiceStatus.cancelled) ...[
              const Divider(height: 20),
              _infoRow('Cancelled Date', invoice.cancelledAt != null ? dateFormat.format(invoice.cancelledAt!) : '—'),
              if (invoice.cancelledBy != null) _infoRow('Cancelled By', invoice.cancelledBy!),
            ],
            if (invoice.notes != null && invoice.notes!.isNotEmpty) ...[
              const Divider(height: 20),
              const Text('Notes & Memo:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.borderLight),
                ),
                child: Text(invoice.notes!, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentHistoryCard(List<InvoicePaymentModel> payments, DateFormat dateFormat) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.borderLight),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.history_rounded, size: 20, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Payment History & Audit Trail',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const Spacer(),
                Text(
                  '${payments.length} record(s)',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (payments.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.borderLight),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.payment_outlined, size: 36, color: AppColors.textMuted),
                    SizedBox(height: 8),
                    Text(
                      'No payment records found',
                      style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'When this invoice is marked as paid, the manual transaction record will appear here.',
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ],
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Date', style: TextStyle(fontWeight: FontWeight.w700))),
                    DataColumn(label: Text('Amount', style: TextStyle(fontWeight: FontWeight.w700))),
                    DataColumn(label: Text('Method', style: TextStyle(fontWeight: FontWeight.w700))),
                    DataColumn(label: Text('Reference', style: TextStyle(fontWeight: FontWeight.w700))),
                    DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.w700))),
                    DataColumn(label: Text('Recorded By', style: TextStyle(fontWeight: FontWeight.w700))),
                    DataColumn(label: Text('Notes', style: TextStyle(fontWeight: FontWeight.w700))),
                  ],
                  rows: payments.map((pay) {
                    final isVoided = pay.status == PaymentStatus.voided;
                    return DataRow(
                      cells: [
                        DataCell(Text(dateFormat.format(pay.paymentDate))),
                        DataCell(
                          Text(
                            BillingConstants.formatCurrency(pay.amount),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              decoration: isVoided ? TextDecoration.lineThrough : null,
                            ),
                          ),
                        ),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(pay.paymentMethod.icon, size: 16, color: AppColors.textPrimary),
                              const SizedBox(width: 6),
                              Text(pay.paymentMethod.displayName),
                            ],
                          ),
                        ),
                        DataCell(Text(pay.paymentReference ?? '—')),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isVoided ? Colors.grey.shade200 : AppColors.success.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              pay.status.displayName.toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isVoided ? Colors.grey.shade700 : AppColors.success,
                              ),
                            ),
                          ),
                        ),
                        DataCell(Text(pay.createdBy ?? '—')),
                        DataCell(Text(pay.notes ?? '—')),
                      ],
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
