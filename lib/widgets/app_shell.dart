import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/responsive/responsive_layout.dart';
import '../repositories/auth_repository.dart';
import '../routing/app_routes.dart';
import '../theme/app_colors.dart';

class AppShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const AppShell({
    super.key,
    required this.navigationShell,
  });

  void _onNavigate(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWide = ResponsiveLayout.isWideScreen(context);

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            // Enterprise SaaS Left Sidebar
            _buildSidebar(context, ref),
            const VerticalDivider(width: 1, thickness: 1, color: AppColors.borderLight),
            // Main Content Area
            Expanded(
              child: navigationShell,
            ),
          ],
        ),
      );
    }

    // Mobile Layout: Top App Bar + Body + Bottom Navigation Bar
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex.clamp(0, 3),
        onDestinationSelected: _onNavigate,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.apartment_outlined),
            selectedIcon: Icon(Icons.apartment_rounded),
            label: 'Schools',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded),
            label: 'Billing',
          ),
          NavigationDestination(
            icon: Icon(Icons.manage_accounts_outlined),
            selectedIcon: Icon(Icons.manage_accounts_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(BuildContext context, WidgetRef ref) {
    final currentIndex = navigationShell.currentIndex;

    return Container(
      width: 260,
      color: AppColors.sidebarDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header / Logo
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.admin_panel_settings_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Super Admin',
                        style: TextStyle(
                          color: AppColors.textOnDark,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Central Control OS',
                        style: TextStyle(
                          color: AppColors.textOnDarkMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: AppColors.borderDark, height: 1),
          const SizedBox(height: 16),

          // Nav Items
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                _sidebarItem(
                  index: 0,
                  currentIndex: currentIndex,
                  icon: Icons.dashboard_rounded,
                  label: 'Dashboard',
                  onTap: () => _onNavigate(0),
                ),
                const SizedBox(height: 4),
                _sidebarItem(
                  index: 1,
                  currentIndex: currentIndex,
                  icon: Icons.apartment_rounded,
                  label: 'Schools',
                  onTap: () => _onNavigate(1),
                ),
                const SizedBox(height: 4),
                _sidebarItem(
                  index: 2,
                  currentIndex: currentIndex,
                  icon: Icons.receipt_long_rounded,
                  label: 'Billing & Invoices',
                  onTap: () => _onNavigate(2),
                ),
                const SizedBox(height: 4),
                _sidebarItem(
                  index: 3,
                  currentIndex: currentIndex,
                  icon: Icons.manage_accounts_rounded,
                  label: 'Settings & Profile',
                  onTap: () => _onNavigate(3),
                ),
                const SizedBox(height: 4),
                _sidebarDirectItem(
                  icon: Icons.history_edu_rounded,
                  label: 'Audit Logs',
                  onTap: () => context.go(AppRoutes.auditLogs),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => context.go(AppRoutes.provision),
                      icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
                      label: const Text(
                        'Provision School',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Footer / Super Admin Session Badge
          const Divider(color: AppColors.borderDark, height: 1),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.sidebarHover,
                  child: Icon(Icons.person_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Master Console',
                        style: TextStyle(
                          color: AppColors.textOnDark,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'SUPER ADMIN',
                        style: TextStyle(
                          color: AppColors.success,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.logout_rounded, color: AppColors.textOnDarkMuted, size: 18),
                  tooltip: 'Log out',
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Confirm Logout'),
                        content: const Text('Are you sure you want to sign out of the Super Admin console?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Log Out'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true && context.mounted) {
                      await ref.read(authRepositoryProvider).signOut();
                      if (context.mounted) {
                        context.go(AppRoutes.login);
                      }
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sidebarItem({
    required int index,
    required int currentIndex,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final isSelected = index == currentIndex;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? Colors.white : AppColors.textOnDarkMuted,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : AppColors.textOnDarkMuted,
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sidebarDirectItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: AppColors.textOnDarkMuted,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textOnDarkMuted,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
