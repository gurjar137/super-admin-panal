import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../models/dashboard_stats.dart';
import '../../models/school_model.dart';
import '../../repositories/school_repository.dart';
import '../../routing/app_routes.dart';
import '../../theme/app_colors.dart';
import '../../widgets/empty_state_view.dart';
import '../../widgets/error_state_view.dart';
import '../../widgets/metric_card.dart';
import '../../widgets/status_chip.dart';

final dashboardStatsProvider = FutureProvider.autoDispose<DashboardStats>((ref) async {
  final repo = ref.watch(schoolRepositoryProvider);
  final result = await repo.getDashboardStats();
  if (result.isFailure) {
    throw Exception(result.errorOrNull ?? 'Failed to load metrics');
  }
  return result.dataOrNull ?? DashboardStats.empty;
});

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(dashboardStatsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Super Admin Central Control'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Metrics',
            onPressed: () => ref.invalidate(dashboardStatsProvider),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(dashboardStatsProvider),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: CenteredContentWrapper(
            child: statsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 80),
                child: Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(strokeWidth: 2.5),
                      SizedBox(height: 16),
                      Text(
                        'Aggregating live multi-tenant SaaS metrics...',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
              error: (err, stack) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 60),
                child: ErrorStateView(
                  title: 'Metrics Unavailable',
                  message: err.toString().replaceFirst('Exception: ', ''),
                  onRetry: () => ref.invalidate(dashboardStatsProvider),
                ),
              ),
              data: (stats) => _buildDashboardContent(context, stats),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardContent(BuildContext context, DashboardStats stats) {
    final isDesktop = ResponsiveLayout.isDesktop(context);
    final isWide = ResponsiveLayout.isWideScreen(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header description
          const Text(
            'Central SaaS Management Control Center',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),

          // Metrics Grid (Schools, Products, Assignments, Subscriptions)
          _buildMetricsGrid(context, stats, isDesktop, isWide),
          const SizedBox(height: 24),

          // Quick Action Cards
          const Text(
            'Central Operations',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          _buildQuickActions(context),
          const SizedBox(height: 28),

          // Recent Schools Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent School Onboarding',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              TextButton.icon(
                onPressed: () => context.go(AppRoutes.schools),
                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                label: const Text('View All Schools'),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Recent Schools List
          if (stats.recentSchools.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: EmptyStateView(
                  icon: Icons.apartment_rounded,
                  title: 'No Schools Provisioned',
                  message: 'No tenant schools have been created in the Supabase database yet.',
                  actionLabel: 'Provision First School',
                  onAction: () => context.go(AppRoutes.provision),
                ),
              ),
            )
          else
            Card(
              clipBehavior: Clip.antiAlias,
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: stats.recentSchools.length,
                separatorBuilder: (ctx, i) => const Divider(height: 1),
                itemBuilder: (ctx, index) {
                  final school = stats.recentSchools[index];
                  return _buildRecentSchoolTile(context, school);
                },
              ),
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildMetricsGrid(
    BuildContext context,
    DashboardStats stats,
    bool isDesktop,
    bool isWide,
  ) {
    final cards = [
      MetricCard(
        title: 'Total Schools',
        value: stats.totalSchools.toString(),
        icon: Icons.apartment_rounded,
        iconColor: AppColors.primary,
        iconBgColor: AppColors.primarySubtle,
        subtitle: 'Registered Tenants',
      ),
      MetricCard(
        title: 'Active Schools',
        value: stats.activeSchools.toString(),
        icon: Icons.check_circle_outline_rounded,
        iconColor: AppColors.success,
        iconBgColor: AppColors.successSubtle,
        subtitle: 'Live Operations',
      ),
      MetricCard(
        title: 'Inactive Schools',
        value: stats.inactiveSchools.toString(),
        icon: Icons.pause_circle_outline_rounded,
        iconColor: AppColors.textSecondary,
        iconBgColor: const Color(0xFFF1F5F9),
        subtitle: 'Temporarily Inactive',
      ),
      MetricCard(
        title: 'Management Apps',
        value: stats.totalApps.toString(),
        icon: Icons.apps_rounded,
        iconColor: AppColors.secondary,
        iconBgColor: const Color(0xFFE0F2FE),
        subtitle: '${stats.activeApps} Active Dedicated Apps',
      ),
      MetricCard(
        title: 'Active Subscriptions',
        value: stats.activeSubscriptions.toString(),
        icon: Icons.link_rounded,
        iconColor: AppColors.accent,
        iconBgColor: const Color(0xFFF3E8FF),
        subtitle: '${stats.totalSubscriptions} Total Subscriptions',
      ),
      MetricCard(
        title: 'Expired Subscriptions',
        value: stats.expiredSubscriptions.toString(),
        icon: Icons.warning_amber_rounded,
        iconColor: AppColors.error,
        iconBgColor: AppColors.errorSubtle,
        subtitle: 'Access Blocked',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        int crossAxisCount;
        double childAspectRatio;

        if (width >= 860) {
          crossAxisCount = 4;
          childAspectRatio = 1.4;
        } else if (width >= 580) {
          crossAxisCount = 2;
          childAspectRatio = 2.0;
        } else {
          crossAxisCount = 1;
          childAspectRatio = 2.4;
        }

        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: childAspectRatio,
          children: cards,
        );
      },
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _quickActionChip(
          context,
          icon: Icons.add_business_rounded,
          title: 'Provision School',
          color: AppColors.primary,
          onTap: () => context.go(AppRoutes.provision),
        ),
        _quickActionChip(
          context,
          icon: Icons.apartment_rounded,
          title: 'Schools Directory',
          color: AppColors.secondary,
          onTap: () => context.go(AppRoutes.schools),
        ),
        _quickActionChip(
          context,
          icon: Icons.receipt_long_rounded,
          title: 'Billing & Invoices',
          color: AppColors.accent,
          onTap: () => context.go(AppRoutes.billing),
        ),
        _quickActionChip(
          context,
          icon: Icons.manage_accounts_rounded,
          title: 'Settings & Profile',
          color: AppColors.success,
          onTap: () => context.go(AppRoutes.profile),
        ),
      ],
    );
  }

  Widget _quickActionChip(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentSchoolTile(BuildContext context, SchoolModel school) {
    final dateFormat = DateFormat.yMMMd();

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: AppColors.primarySubtle,
        child: Text(
          school.name.isNotEmpty ? school.name[0].toUpperCase() : 'S',
          style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              school.name,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          StatusChip(status: school.status),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          'Code: ${school.schoolCode} • Created: ${dateFormat.format(school.createdAt)}',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
      onTap: () => context.go(AppRoutes.schoolDetailsPath(school.id)),
    );
  }
}
