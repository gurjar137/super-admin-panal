import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/constants/billing_constants.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../models/school_model.dart';
import '../../models/school_invoice_model.dart';
import '../../repositories/school_billing_repository.dart';
import '../../repositories/school_repository.dart';
import '../../routing/app_routes.dart';
import '../../theme/app_colors.dart';
import '../../widgets/empty_state_view.dart';
import '../../widgets/error_state_view.dart';
import '../../widgets/status_chip.dart';

// State for search and filter
class SchoolFilterState {
  final String searchQuery;
  final SchoolStatus? statusFilter;

  const SchoolFilterState({
    this.searchQuery = '',
    this.statusFilter,
  });

  SchoolFilterState copyWith({
    String? searchQuery,
    SchoolStatus? Function()? statusFilter,
  }) {
    return SchoolFilterState(
      searchQuery: searchQuery ?? this.searchQuery,
      statusFilter: statusFilter != null ? statusFilter() : this.statusFilter,
    );
  }
}

final schoolFilterProvider = StateProvider.autoDispose<SchoolFilterState>((ref) {
  return const SchoolFilterState();
});

final schoolsListProvider = FutureProvider.autoDispose<List<SchoolModel>>((ref) async {
  final repo = ref.watch(schoolRepositoryProvider);
  final filter = ref.watch(schoolFilterProvider);

  final result = await repo.getSchools(
    searchQuery: filter.searchQuery,
    statusFilter: filter.statusFilter,
  );

  if (result.isFailure) {
    throw Exception(result.errorOrNull ?? 'Failed to load schools');
  }

  return result.dataOrNull ?? [];
});

class SchoolsScreen extends ConsumerStatefulWidget {
  const SchoolsScreen({super.key});

  @override
  ConsumerState<SchoolsScreen> createState() => _SchoolsScreenState();
}

class _SchoolsScreenState extends ConsumerState<SchoolsScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(schoolFilterProvider);
    final schoolsAsync = ref.watch(schoolsListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Schools Directory'),
        actions: [
          ElevatedButton.icon(
            onPressed: () => context.go(AppRoutes.provision),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Provision'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: CenteredContentWrapper(
        child: Column(
          children: [
            const SizedBox(height: 16),
            // Search Bar & Filter Chips Header
            _buildSearchAndFilterBar(context, filter),
            const SizedBox(height: 16),

            // Schools List Area
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => ref.invalidate(schoolsListProvider),
                child: schoolsAsync.when(
                  loading: () => const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(strokeWidth: 2.5),
                        SizedBox(height: 16),
                        Text(
                          'Loading schools...',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  error: (err, stack) => ErrorStateView(
                    title: 'Failed to Retrieve Schools',
                    message: err.toString().replaceFirst('Exception: ', ''),
                    onRetry: () => ref.invalidate(schoolsListProvider),
                  ),
                  data: (schools) {
                    if (schools.isEmpty) {
                      final hasFilter = filter.searchQuery.isNotEmpty || filter.statusFilter != null;
                      return EmptyStateView(
                        icon: Icons.search_off_rounded,
                        title: hasFilter ? 'No Matching Schools' : 'No Schools Found',
                        message: hasFilter
                            ? 'No tenant schools matched your filter or search criteria.'
                            : 'No institutions have been provisioned in the multi-tenant system yet.',
                        actionLabel: hasFilter ? 'Clear Filters' : 'Provision School',
                        onAction: () {
                          if (hasFilter) {
                            _searchController.clear();
                            ref.read(schoolFilterProvider.notifier).state =
                                const SchoolFilterState();
                          } else {
                            context.go(AppRoutes.provision);
                          }
                        },
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: schools.length,
                      separatorBuilder: (ctx, i) => const SizedBox(height: 12),
                      itemBuilder: (ctx, index) {
                        final school = schools[index];
                        return _buildSchoolCard(context, school);
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

  Widget _buildSearchAndFilterBar(BuildContext context, SchoolFilterState filter) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search Input
        TextField(
          controller: _searchController,
          onChanged: (val) {
            ref.read(schoolFilterProvider.notifier).state =
                filter.copyWith(searchQuery: val);
          },
          decoration: InputDecoration(
            hintText: 'Search by school name, code or email...',
            prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.textMuted),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    onPressed: () {
                      _searchController.clear();
                      ref.read(schoolFilterProvider.notifier).state =
                          filter.copyWith(searchQuery: '');
                    },
                  )
                : null,
          ),
        ),
        const SizedBox(height: 12),

        // Status Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildFilterChip(
                label: 'All Schools',
                isSelected: filter.statusFilter == null,
                onSelected: () {
                  ref.read(schoolFilterProvider.notifier).state =
                      filter.copyWith(statusFilter: () => null);
                },
              ),
              const SizedBox(width: 8),
              _buildFilterChip(
                label: 'Active',
                isSelected: filter.statusFilter == SchoolStatus.active,
                color: AppColors.success,
                onSelected: () {
                  ref.read(schoolFilterProvider.notifier).state =
                      filter.copyWith(statusFilter: () => SchoolStatus.active);
                },
              ),
              const SizedBox(width: 8),
              _buildFilterChip(
                label: 'Inactive',
                isSelected: filter.statusFilter == SchoolStatus.inactive,
                color: AppColors.textSecondary,
                onSelected: () {
                  ref.read(schoolFilterProvider.notifier).state =
                      filter.copyWith(statusFilter: () => SchoolStatus.inactive);
                },
              ),
              const SizedBox(width: 8),
              _buildFilterChip(
                label: 'Suspended',
                isSelected: filter.statusFilter == SchoolStatus.suspended,
                color: AppColors.warning,
                onSelected: () {
                  ref.read(schoolFilterProvider.notifier).state =
                      filter.copyWith(statusFilter: () => SchoolStatus.suspended);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    Color? color,
    required VoidCallback onSelected,
  }) {
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
      side: BorderSide(
        color: isSelected ? themeColor : AppColors.borderLight,
        width: isSelected ? 1.5 : 1,
      ),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }

  Widget _buildSchoolCard(BuildContext context, SchoolModel school) {
    final dateFormat = DateFormat.yMMMd();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.borderLight),
      ),
      child: InkWell(
        onTap: () => context.go(AppRoutes.schoolDetailsPath(school.id)),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Avatar/Name + Status Chip
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppColors.primarySubtle,
                    child: Text(
                      school.name.isNotEmpty ? school.name[0].toUpperCase() : 'S',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          school.name,
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                school.schoolCode,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondary,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Created: ${dateFormat.format(school.createdAt)}',
                              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  StatusChip(status: school.status),
                ],
              ),
              // Middle Row: Admin & App Access Indicator
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.borderLight),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.person_outline_rounded, size: 15, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Text(
                          school.adminName != null && school.adminName!.isNotEmpty
                              ? school.adminName!
                              : 'Admin Pending',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Icon(Icons.smartphone_rounded, size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          'Manage App in Details →',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Billing Overview Strip (Per-Student Billing)
              _buildBillingStrip(school.id),
              const SizedBox(height: 10),
              const Divider(height: 1, color: AppColors.dividerLight),
              const SizedBox(height: 8),

              // Bottom Info: Contact & Action Links
              Row(
                children: [
                  if (school.email != null && school.email!.isNotEmpty) ...[
                    const Icon(Icons.mail_outline_rounded, size: 14, color: AppColors.textMuted),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        school.email!,
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ] else ...[
                    const Icon(Icons.location_on_outlined, size: 14, color: AppColors.textMuted),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        school.address ?? 'No address registered',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => context.go(AppRoutes.schoolDetailsPath(school.id)),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 14),
                    label: const Text('Manage School', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBillingStrip(String schoolId) {
    final billingAsync = ref.watch(schoolBillingOverviewProvider(schoolId));

    return billingAsync.when(
      loading: () => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: const Row(
          children: [
            SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5)),
            SizedBox(width: 8),
            Text('Calculating billing metrics...', style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
          ],
        ),
      ),
      error: (err, stack) => const SizedBox.shrink(),
      data: (billing) {
        final amountText = billing.hasInvoices && billing.latestBillAmount != null
            ? BillingConstants.formatCurrency(billing.latestBillAmount!)
            : BillingConstants.formatCurrency(billing.estimatedBillAmount);

        final statusText = billing.hasInvoices
            ? (billing.latestStatus?.dbValue ?? 'UNPAID')
            : 'UNBILLED';

        final isPaid = billing.latestStatus == InvoiceStatus.paid;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              // Students & Rate
              Expanded(
                flex: 4,
                child: Row(
                  children: [
                    const Icon(Icons.school_outlined, size: 15, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Students: ${NumberFormat('#,###').format(billing.studentCount)}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                        ),
                        Text(
                          'Rate: ${BillingConstants.formatCurrency(billing.ratePerStudent)}/student',
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Current/Latest Bill & Amount
              Expanded(
                flex: 4,
                child: Row(
                  children: [
                    const Icon(Icons.receipt_long_outlined, size: 15, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          billing.hasInvoices ? 'Current Bill: $amountText' : 'Est. Bill: $amountText',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                        ),
                        Text(
                          billing.latestBillingPeriod != null
                              ? 'Period: ${billing.latestBillingPeriod}'
                              : 'Current Cycle',
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Billing Status Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isPaid
                      ? AppColors.successSubtle
                      : (billing.hasInvoices ? const Color(0xFFFEE2E2) : const Color(0xFFF1F5F9)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isPaid
                        ? AppColors.successText
                        : (billing.hasInvoices ? AppColors.error : AppColors.textSecondary),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
