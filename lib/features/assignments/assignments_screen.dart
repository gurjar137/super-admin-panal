import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../models/product_model.dart';
import '../../models/school_app_model.dart';
import '../../models/school_model.dart';
import '../../repositories/school_app_repository.dart';
import '../../routing/app_routes.dart';
import '../../theme/app_colors.dart';
import '../../widgets/empty_state_view.dart';
import '../../widgets/error_state_view.dart';
import '../applications/applications_screen.dart';
import '../schools/schools_screen.dart';

final schoolAppsListProvider = FutureProvider.autoDispose<List<SchoolAppModel>>((ref) async {
  final repo = ref.watch(schoolAppRepositoryProvider);
  final result = await repo.getSchoolApps();
  if (result.isFailure) {
    throw Exception(result.errorOrNull ?? 'Failed to load school apps');
  }
  return result.dataOrNull ?? [];
});

class AssignmentsScreen extends ConsumerStatefulWidget {
  const AssignmentsScreen({super.key});

  @override
  ConsumerState<AssignmentsScreen> createState() => _AssignmentsScreenState();
}

class _AssignmentsScreenState extends ConsumerState<AssignmentsScreen> {
  String? _selectedSchoolId;

  void _showAssignDialog(
    BuildContext context,
    List<SchoolModel> schools,
    List<ProductModel> products,
  ) {
    String? pickedSchoolId = _selectedSchoolId ?? (schools.isNotEmpty ? schools.first.id : null);
    String? pickedProductId = products.isNotEmpty ? products.first.id : null;
    final appNameController = TextEditingController();
    final packageController = TextEditingController();
    String? localError;

    // Default app name if school is chosen
    if (pickedSchoolId != null && pickedProductId != null) {
      final s = schools.firstWhere((e) => e.id == pickedSchoolId, orElse: () => schools.first);
      final p = products.firstWhere((e) => e.id == pickedProductId, orElse: () => products.first);
      appNameController.text = '${s.name} ${p.displayName}';
      packageController.text = 'com.schoolos.${s.schoolCode.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')}.${p.productCode}';
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: const Text('Assign Product to School'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Map a platform product/app to a tenant school. Creates an independent subscription and access lifecycle.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                if (localError != null) ...[
                  Text(localError!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
                  const SizedBox(height: 8),
                ],
                const Text('Target School *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: pickedSchoolId,
                  items: schools.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setModalState(() {
                        pickedSchoolId = val;
                        final s = schools.firstWhere((e) => e.id == val);
                        final p = products.firstWhere((e) => e.id == pickedProductId, orElse: () => products.first);
                        appNameController.text = '${s.name} ${p.displayName}';
                        packageController.text = 'com.schoolos.${s.schoolCode.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')}.${p.productCode}';
                      });
                    }
                  },
                ),
                const SizedBox(height: 14),
                const Text('Product / Application *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: pickedProductId,
                  items: products.map((p) => DropdownMenuItem(value: p.id, child: Text(p.displayName))).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setModalState(() {
                        pickedProductId = val;
                        final s = schools.firstWhere((e) => e.id == pickedSchoolId, orElse: () => schools.first);
                        final p = products.firstWhere((e) => e.id == val);
                        appNameController.text = '${s.name} ${p.displayName}';
                        packageController.text = 'com.schoolos.${s.schoolCode.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')}.${p.productCode}';
                      });
                    }
                  },
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: appNameController,
                  decoration: const InputDecoration(labelText: 'Branded App Display Name *'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: packageController,
                  decoration: const InputDecoration(labelText: 'Package Name (Android)', hintText: 'com.schoolos.tenant.product'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (pickedSchoolId == null || pickedProductId == null || appNameController.text.trim().isEmpty) {
                  setModalState(() => localError = 'Please select both a school and a product.');
                  return;
                }

                Navigator.pop(ctx);
                final repo = ref.read(schoolAppRepositoryProvider);
                final res = await repo.createSchoolApp(
                  schoolId: pickedSchoolId!,
                  appName: appNameController.text.trim(),
                  packageName: packageController.text.trim(),
                  appIdentifier: 'APP_${DateTime.now().millisecondsSinceEpoch}',
                );

                if (context.mounted) {
                  if (res.isSuccess) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Assigned "${res.dataOrNull?.appName}" successfully!'), backgroundColor: AppColors.success),
                    );
                    ref.invalidate(schoolAppsListProvider);
                    ref.invalidate(schoolsListProvider);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(res.errorOrNull ?? 'Failed to assign product'), backgroundColor: AppColors.error),
                    );
                  }
                }
              },
              child: const Text('Assign Application'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleAccess(SchoolAppModel app) async {
    final nextState = !app.isActive;
    final repo = ref.read(schoolAppRepositoryProvider);
    final res = await repo.toggleAppAccess(appId: app.id, isActive: nextState);

    if (mounted) {
      if (res.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${app.appName} access set to ${nextState ? 'ACTIVE' : 'INACTIVE'}'),
            backgroundColor: AppColors.success,
          ),
        );
        ref.invalidate(schoolAppsListProvider);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res.errorOrNull ?? 'Failed to update access'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final schoolsAsync = ref.watch(schoolsListProvider);
    final productsAsync = ref.watch(productsListProvider);
    final appsAsync = ref.watch(schoolAppsListProvider);

    final schools = schoolsAsync.asData?.value ?? [];
    final products = productsAsync.asData?.value ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('School-to-App Assignments'),
        actions: [
          ElevatedButton.icon(
            onPressed: (schools.isNotEmpty && products.isNotEmpty)
                ? () => _showAssignDialog(context, schools, products)
                : null,
            icon: const Icon(Icons.add_link_rounded, size: 18),
            label: const Text('Assign Product'),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(schoolAppsListProvider),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: CenteredContentWrapper(
        child: Column(
          children: [
            const SizedBox(height: 16),
            // Filter by School Dropdown Row
            if (schools.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.filter_list_rounded, size: 18, color: AppColors.primary),
                      const SizedBox(width: 10),
                      const Text('Filter by School:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String?>(
                            value: _selectedSchoolId,
                            isExpanded: true,
                            hint: const Text('All Registered Schools'),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('All Schools (Showing all assignments)'),
                              ),
                              ...schools.map(
                                (s) => DropdownMenuItem<String?>(
                                  value: s.id,
                                  child: Text('${s.name} (${s.schoolCode})'),
                                ),
                              ),
                            ],
                            onChanged: (val) {
                              setState(() => _selectedSchoolId = val);
                            },
                          ),
                        ),
                      ),
                      if (_selectedSchoolId != null)
                        IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () => setState(() => _selectedSchoolId = null),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),

            // Assignments List
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => ref.invalidate(schoolAppsListProvider),
                child: appsAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
                  error: (err, _) => ErrorStateView(
                    title: 'Unable to Load Assignments',
                    message: err.toString().replaceFirst('Exception: ', ''),
                    onRetry: () => ref.invalidate(schoolAppsListProvider),
                  ),
                  data: (apps) {
                    final filtered = _selectedSchoolId != null
                        ? apps.where((a) => a.schoolId == _selectedSchoolId).toList()
                        : apps;

                    if (filtered.isEmpty) {
                      return EmptyStateView(
                        icon: Icons.link_off_rounded,
                        title: 'No App Assignments Found',
                        message: _selectedSchoolId != null
                            ? 'No products have been assigned to this school yet.'
                            : 'No schools have been mapped to SaaS products yet.',
                        actionLabel: 'Create First Assignment',
                        onAction: () => _showAssignDialog(context, schools, products),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: filtered.length,
                      separatorBuilder: (ctx, i) => const SizedBox(height: 12),
                      itemBuilder: (ctx, index) {
                        final app = filtered[index];
                        return _buildAssignmentCard(context, app);
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

  Widget _buildAssignmentCard(BuildContext context, SchoolAppModel app) {
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
                  child: const Icon(Icons.smartphone_rounded, color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        app.appName,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'School: ${app.schoolName}',
                        style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: app.isActive ? AppColors.successSubtle : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: app.isActive ? AppColors.success.withValues(alpha: 0.3) : AppColors.borderLight),
                  ),
                  child: Text(
                    app.isActive ? 'ACTIVE' : 'INACTIVE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: app.isActive ? AppColors.successText : AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.dividerLight),
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(4)),
                  child: Text(
                    app.productDisplayName,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Pkg: ${app.packageName ?? 'Developer unassigned'}',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => _toggleAccess(app),
                  child: Text(
                    app.isActive ? 'Deactivate' : 'Activate',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: app.isActive ? AppColors.error : AppColors.success,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                OutlinedButton(
                  onPressed: () => context.go(AppRoutes.appDetailsPath(app.id)),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                  child: const Text('App Details', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
