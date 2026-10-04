import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/constants/billing_constants.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../models/school_invoice_model.dart';
import '../../repositories/school_billing_repository.dart';
import '../../theme/app_colors.dart';

class BillingDashboardScreen extends ConsumerStatefulWidget {
  const BillingDashboardScreen({super.key});

  @override
  ConsumerState<BillingDashboardScreen> createState() => _BillingDashboardScreenState();
}

class _BillingDashboardScreenState extends ConsumerState<BillingDashboardScreen> {
  String _selectedPeriod = 'All Time';
  String _statusFilter = 'ALL';
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  final List<String> _periods = [
    'All Time',
    'September 2026',
    'August 2026',
    'July 2026',
    'June 2026',
  ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    String? subtitle,
  }) {
    return Card(
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
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 11),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = ResponsiveLayout.isWideScreen(context);
    final dashboardAsync = ref.watch(billingDashboardSummaryProvider(_selectedPeriod));

    final filterParams = InvoiceFilterParams(
      statusFilter: _statusFilter,
      searchQuery: _searchQuery,
      billingPeriod: _selectedPeriod == 'All Time' ? null : _selectedPeriod,
    );
    final invoicesAsync = ref.watch(filteredInvoicesProvider(filterParams));
    final dateFormat = DateFormat('dd MMM yyyy');

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SingleChildScrollView(
        padding: EdgeInsets.all(isWide ? 32.0 : 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title Header & Period Selector
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Billing & Revenue Command Center',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Live enterprise financial metrics, immutable invoice ledger, and manual payment tracking',
                        style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                // Period Dropdown
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedPeriod,
                      items: _periods.map((p) {
                        return DropdownMenuItem(value: p, child: Text(p, style: const TextStyle(fontWeight: FontWeight.w600)));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedPeriod = val);
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Executive KPI Grid (6 metrics)
            dashboardAsync.when(
              loading: () => const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
              error: (err, _) => Center(child: Text('Failed to load metrics: $err')),
              data: (summary) {
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final crossAxisCount = isWide ? 3 : 1;
                    return GridView.count(
                      crossAxisCount: crossAxisCount,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: isWide ? 2.6 : 3.0,
                      children: [
                        _buildMetricCard(
                          title: 'Total Schools Active',
                          value: '${summary.totalSchools}',
                          icon: Icons.apartment_rounded,
                          color: AppColors.primary,
                          subtitle: 'Connected tenant institutions',
                        ),
                        _buildMetricCard(
                          title: 'Students Billed',
                          value: '${summary.totalStudentsBilled}',
                          icon: Icons.groups_rounded,
                          color: const Color(0xFF7C3AED),
                          subtitle: 'Billable student enrollments',
                        ),
                        _buildMetricCard(
                          title: 'Total Billed',
                          value: BillingConstants.formatCurrency(summary.totalBilled),
                          icon: Icons.receipt_long_rounded,
                          color: const Color(0xFF2563EB),
                          subtitle: 'Gross revenue generated',
                        ),
                        _buildMetricCard(
                          title: 'Total Paid',
                          value: BillingConstants.formatCurrency(summary.totalPaid),
                          icon: Icons.check_circle_rounded,
                          color: AppColors.success,
                          subtitle: 'Realized collections to date',
                        ),
                        _buildMetricCard(
                          title: 'Total Outstanding',
                          value: BillingConstants.formatCurrency(summary.totalOutstanding),
                          icon: Icons.pending_actions_rounded,
                          color: AppColors.warning,
                          subtitle: 'Awaiting payment confirmation',
                        ),
                        _buildMetricCard(
                          title: 'Total Overdue',
                          value: BillingConstants.formatCurrency(summary.totalOverdue),
                          icon: Icons.warning_amber_rounded,
                          color: AppColors.error,
                          subtitle: 'Past due date invoices',
                        ),
                      ],
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 32),

            // Invoices Ledger & Filter Bar
            Card(
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
                    // Search & Filter Header
                    Row(
                      children: [
                        const Icon(Icons.table_chart_rounded, size: 22, color: AppColors.primary),
                        const SizedBox(width: 10),
                        const Text(
                          'Invoice Ledger',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                        ),
                        const Spacer(),
                        // Search Box
                        SizedBox(
                          width: 280,
                          height: 40,
                          child: TextField(
                            controller: _searchCtrl,
                            decoration: InputDecoration(
                              hintText: 'Search invoice no or school...',
                              hintStyle: const TextStyle(fontSize: 12.5),
                              prefixIcon: const Icon(Icons.search_rounded, size: 18),
                              suffixIcon: _searchCtrl.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 16),
                                      onPressed: () {
                                        _searchCtrl.clear();
                                        setState(() => _searchQuery = '');
                                      },
                                    )
                                  : null,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onChanged: (val) => setState(() => _searchQuery = val),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Status Filter Chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _filterChip('ALL', 'All Invoices'),
                          const SizedBox(width: 8),
                          _filterChip('UNPAID', 'Unpaid'),
                          const SizedBox(width: 8),
                          _filterChip('PAID', 'Paid'),
                          const SizedBox(width: 8),
                          _filterChip('OVERDUE', 'Overdue'),
                          const SizedBox(width: 8),
                          _filterChip('CANCELLED', 'Cancelled'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Invoice Table
                    invoicesAsync.when(
                      loading: () => const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
                      error: (err, _) => Center(child: Text('Error loading invoices: $err')),
                      data: (invoices) {
                        if (invoices.isEmpty) {
                          return Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(36),
                            alignment: Alignment.center,
                            child: const Column(
                              children: [
                                Icon(Icons.inbox_outlined, size: 40, color: AppColors.textMuted),
                                SizedBox(height: 8),
                                Text(
                                  'No invoices match your selected filters',
                                  style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textMuted),
                                ),
                              ],
                            ),
                          );
                        }

                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            headingTextStyle: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                            columns: const [
                              DataColumn(label: Text('Invoice No.')),
                              DataColumn(label: Text('School')),
                              DataColumn(label: Text('Billing Period')),
                              DataColumn(label: Text('Students')),
                              DataColumn(label: Text('Amount')),
                              DataColumn(label: Text('Due Date')),
                              DataColumn(label: Text('Status')),
                              DataColumn(label: Text('Actions')),
                            ],
                            rows: invoices.map((inv) {
                              return DataRow(
                                cells: [
                                  DataCell(
                                    Text(
                                      inv.displayInvoiceNumber,
                                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary),
                                    ),
                                    onTap: () => context.push('/invoices/${inv.id}'),
                                  ),
                                  DataCell(
                                    Text(inv.schoolName ?? inv.schoolId),
                                    onTap: () => context.push('/invoices/${inv.id}'),
                                  ),
                                  DataCell(
                                    Text(
                                      '${dateFormat.format(inv.billingPeriodStart)} - ${dateFormat.format(inv.billingPeriodEnd)}',
                                      style: const TextStyle(fontSize: 12.5),
                                    ),
                                  ),
                                  DataCell(Text('${inv.studentCount}')),
                                  DataCell(
                                    Text(
                                      BillingConstants.formatCurrency(inv.totalAmount),
                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  DataCell(Text(dateFormat.format(inv.dueDate))),
                                  DataCell(_buildStatusChip(inv.status, inv.isOverdue)),
                                  DataCell(
                                    ElevatedButton(
                                      onPressed: () => context.push('/invoices/${inv.id}'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.white,
                                        foregroundColor: AppColors.primary,
                                        side: const BorderSide(color: AppColors.primary),
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        minimumSize: Size.zero,
                                      ),
                                      child: const Text('View Details', style: TextStyle(fontSize: 12)),
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String statusKey, String label) {
    final isSelected = _statusFilter == statusKey;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) setState(() => _statusFilter = statusKey);
      },
      selectedColor: AppColors.primary,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : AppColors.textPrimary,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        fontSize: 12.5,
      ),
      backgroundColor: Colors.grey.shade100,
      side: BorderSide(color: isSelected ? AppColors.primary : AppColors.borderLight),
    );
  }
}
