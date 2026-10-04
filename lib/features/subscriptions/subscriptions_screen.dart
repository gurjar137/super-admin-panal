import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../models/product_model.dart';
import '../../models/school_model.dart';
import '../../models/subscription_model.dart';
import '../../repositories/subscription_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/empty_state_view.dart';
import '../../widgets/error_state_view.dart';
import '../applications/applications_screen.dart';
import '../schools/schools_screen.dart';

final subscriptionsListProvider =
    FutureProvider.autoDispose<List<SubscriptionModel>>((ref) async {
  final repo = ref.watch(subscriptionRepositoryProvider);
  final result = await repo.getSubscriptions();
  if (result.isFailure) {
    throw Exception(result.errorOrNull ?? 'Failed to load subscriptions');
  }
  return result.dataOrNull ?? [];
});

class SubscriptionsScreen extends ConsumerStatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  ConsumerState<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends ConsumerState<SubscriptionsScreen> {
  SubscriptionStatus? _selectedStatusFilter;

  void _showCreateSubscriptionDialog(
    BuildContext context,
    List<SchoolModel> schools,
    List<ProductModel> products,
  ) {
    String? pickedSchoolId = schools.isNotEmpty ? schools.first.id : null;
    String? pickedProductId = products.isNotEmpty ? products.first.id : null;
    DateTime startDate = DateTime.now();
    DateTime endDate = DateTime.now().add(const Duration(days: 365));
    SubscriptionStatus status = SubscriptionStatus.active;
    String planType = 'ANNUAL';
    final notesController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: const Text('Provision Subscription'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Set independent subscription validity for a specific school and SaaS product. Expired subscriptions restrict access without modifying school data.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                const Text('School Tenant *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: pickedSchoolId,
                  items: schools.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
                  onChanged: (val) => setModalState(() => pickedSchoolId = val),
                ),
                const SizedBox(height: 14),
                const Text('Product / Application *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: pickedProductId,
                  items: products.map((p) => DropdownMenuItem(value: p.id, child: Text(p.displayName))).toList(),
                  onChanged: (val) => setModalState(() => pickedProductId = val),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Start Date', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          InkWell(
                            onTap: () async {
                              final p = await showDatePicker(context: context, initialDate: startDate, firstDate: DateTime(2020), lastDate: DateTime(2040));
                              if (p != null) setModalState(() => startDate = p);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(border: Border.all(color: AppColors.borderLight), borderRadius: BorderRadius.circular(6)),
                              child: Text(DateFormat.yMMMd().format(startDate), style: const TextStyle(fontSize: 12)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('End Date', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          InkWell(
                            onTap: () async {
                              final p = await showDatePicker(context: context, initialDate: endDate, firstDate: DateTime(2020), lastDate: DateTime(2040));
                              if (p != null) setModalState(() => endDate = p);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(border: Border.all(color: AppColors.borderLight), borderRadius: BorderRadius.circular(6)),
                              child: Text(DateFormat.yMMMd().format(endDate), style: const TextStyle(fontSize: 12)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text('Plan Type', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: planType,
                  items: const [
                    DropdownMenuItem(value: 'TRIAL', child: Text('Trial License (30 Days)')),
                    DropdownMenuItem(value: 'MONTHLY', child: Text('Monthly License')),
                    DropdownMenuItem(value: 'ANNUAL', child: Text('Annual Enterprise License')),
                  ],
                  onChanged: (val) {
                    if (val != null) setModalState(() => planType = val);
                  },
                ),
                const SizedBox(height: 14),
                const Text('Initial Status', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                DropdownButtonFormField<SubscriptionStatus>(
                  initialValue: status,
                  items: SubscriptionStatus.values.map((st) => DropdownMenuItem(value: st, child: Text(st.displayName))).toList(),
                  onChanged: (val) {
                    if (val != null) setModalState(() => status = val);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(labelText: 'Notes / Contract ID', hintText: 'e.g. Contract #2026-X'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (pickedSchoolId == null || pickedProductId == null) return;
                Navigator.pop(ctx);
                final repo = ref.read(subscriptionRepositoryProvider);
                final res = await repo.upsertSubscription(
                  schoolId: pickedSchoolId!,
                  productId: pickedProductId!,
                  startDate: startDate,
                  endDate: endDate,
                  status: status,
                  planType: planType,
                  notes: notesController.text.trim(),
                );

                if (context.mounted) {
                  if (res.isSuccess) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Subscription successfully provisioned!'), backgroundColor: AppColors.success),
                    );
                    ref.invalidate(subscriptionsListProvider);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(res.errorOrNull ?? 'Failed to save subscription'), backgroundColor: AppColors.error),
                    );
                  }
                }
              },
              child: const Text('Save Subscription'),
            ),
          ],
        ),
      ),
    );
  }

  void _showRenewDialog(BuildContext context, SubscriptionModel sub) {
    DateTime newEndDate = sub.endDate.isBefore(DateTime.now())
        ? DateTime.now().add(const Duration(days: 365))
        : sub.endDate.add(const Duration(days: 365));

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: const Text('Extend Subscription Term'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('School: ${sub.schoolName}\nProduct: ${sub.productDisplayName}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 14),
              const Text('Current Expiry:', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              Text(DateFormat.yMMMMd().format(sub.endDate), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              const Text('New Expiration Date:', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(context: context, initialDate: newEndDate, firstDate: DateTime.now(), lastDate: DateTime(2040));
                  if (picked != null) setModalState(() => newEndDate = picked);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(border: Border.all(color: AppColors.borderLight), borderRadius: BorderRadius.circular(6)),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month_rounded, size: 16, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text(DateFormat.yMMMMd().format(newEndDate), style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final repo = ref.read(subscriptionRepositoryProvider);
                final res = await repo.extendSubscription(subscriptionId: sub.id, newEndDate: newEndDate);
                if (context.mounted) {
                  if (res.isSuccess) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Subscription extended successfully!'), backgroundColor: AppColors.success),
                    );
                    ref.invalidate(subscriptionsListProvider);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(res.errorOrNull ?? 'Failed to extend subscription'), backgroundColor: AppColors.error),
                    );
                  }
                }
              },
              child: const Text('Extend Term'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final subsAsync = ref.watch(subscriptionsListProvider);
    final schoolsAsync = ref.watch(schoolsListProvider);
    final productsAsync = ref.watch(productsListProvider);

    final schools = schoolsAsync.asData?.value ?? [];
    final products = productsAsync.asData?.value ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscriptions Management'),
        actions: [
          ElevatedButton.icon(
            onPressed: (schools.isNotEmpty && products.isNotEmpty)
                ? () => _showCreateSubscriptionDialog(context, schools, products)
                : null,
            icon: const Icon(Icons.add_card_rounded, size: 18),
            label: const Text('New Subscription'),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(subscriptionsListProvider),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: CenteredContentWrapper(
        child: Column(
          children: [
            const SizedBox(height: 16),
            // Filter by Status Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip(label: 'All Subscriptions', isSelected: _selectedStatusFilter == null, onSelected: () => setState(() => _selectedStatusFilter = null)),
                  const SizedBox(width: 8),
                  _filterChip(label: 'Active', isSelected: _selectedStatusFilter == SubscriptionStatus.active, color: AppColors.success, onSelected: () => setState(() => _selectedStatusFilter = SubscriptionStatus.active)),
                  const SizedBox(width: 8),
                  _filterChip(label: 'Expired', isSelected: _selectedStatusFilter == SubscriptionStatus.expired, color: AppColors.error, onSelected: () => setState(() => _selectedStatusFilter = SubscriptionStatus.expired)),
                  const SizedBox(width: 8),
                  _filterChip(label: 'Suspended', isSelected: _selectedStatusFilter == SubscriptionStatus.suspended, color: AppColors.warning, onSelected: () => setState(() => _selectedStatusFilter = SubscriptionStatus.suspended)),
                  const SizedBox(width: 8),
                  _filterChip(label: 'Inactive', isSelected: _selectedStatusFilter == SubscriptionStatus.inactive, color: AppColors.textSecondary, onSelected: () => setState(() => _selectedStatusFilter = SubscriptionStatus.inactive)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Subscriptions List
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => ref.invalidate(subscriptionsListProvider),
                child: subsAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
                  error: (err, _) => ErrorStateView(
                    title: 'Unable to Load Subscriptions',
                    message: err.toString().replaceFirst('Exception: ', ''),
                    onRetry: () => ref.invalidate(subscriptionsListProvider),
                  ),
                  data: (subs) {
                    final filtered = _selectedStatusFilter != null
                        ? subs.where((s) => s.status == _selectedStatusFilter).toList()
                        : subs;

                    if (filtered.isEmpty) {
                      return EmptyStateView(
                        icon: Icons.card_membership_rounded,
                        title: 'No Subscriptions Found',
                        message: _selectedStatusFilter != null
                            ? 'No subscriptions match the selected status filter.'
                            : 'No subscription terms have been configured in the database yet.',
                        actionLabel: 'Create Subscription',
                        onAction: () => _showCreateSubscriptionDialog(context, schools, products),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: filtered.length,
                      separatorBuilder: (ctx, i) => const SizedBox(height: 12),
                      itemBuilder: (ctx, index) {
                        final sub = filtered[index];
                        return _buildSubscriptionCard(context, sub);
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip({required String label, required bool isSelected, Color? color, required VoidCallback onSelected}) {
    final themeColor = color ?? AppColors.primary;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onSelected(),
      labelStyle: TextStyle(
        fontSize: 12.5,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        color: isSelected ? themeColor : AppColors.textSecondary,
      ),
      backgroundColor: Colors.white,
      selectedColor: themeColor.withValues(alpha: 0.12),
      side: BorderSide(color: isSelected ? themeColor : AppColors.borderLight, width: isSelected ? 1.5 : 1),
      showCheckmark: false,
    );
  }

  Widget _buildSubscriptionCard(BuildContext context, SubscriptionModel sub) {
    final dateFormat = DateFormat.yMMMd();
    Color statusColor;
    Color statusBg;

    switch (sub.status) {
      case SubscriptionStatus.active:
        statusColor = AppColors.successText;
        statusBg = AppColors.successSubtle;
        break;
      case SubscriptionStatus.expired:
        statusColor = AppColors.errorText;
        statusBg = AppColors.errorSubtle;
        break;
      case SubscriptionStatus.suspended:
        statusColor = AppColors.warningText;
        statusBg = AppColors.warningSubtle;
        break;
      case SubscriptionStatus.inactive:
        statusColor = AppColors.textSecondary;
        statusBg = const Color(0xFFF1F5F9);
        break;
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.borderLight),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.primarySubtle,
                  child: const Icon(Icons.card_membership_rounded, color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sub.schoolName,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Product: ${sub.productDisplayName} • Plan: ${sub.planType}',
                        style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    sub.status.displayName.toUpperCase(),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.dividerLight),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.date_range_rounded, size: 14, color: AppColors.textMuted),
                    const SizedBox(width: 6),
                    Text(
                      'Term: ${dateFormat.format(sub.startDate)} - ${dateFormat.format(sub.endDate)}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: () => _showRenewDialog(context, sub),
                  icon: const Icon(Icons.update_rounded, size: 14),
                  label: const Text('Extend Term', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
