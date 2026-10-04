import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../models/product_model.dart';
import '../../repositories/product_repository.dart';
import '../../routing/app_routes.dart';
import '../../theme/app_colors.dart';
import '../../widgets/empty_state_view.dart';
import '../../widgets/error_state_view.dart';

final productsListProvider = FutureProvider.autoDispose<List<ProductModel>>((ref) async {
  final repo = ref.watch(productRepositoryProvider);
  final result = await repo.getProducts();
  if (result.isFailure) {
    throw Exception(result.errorOrNull ?? 'Failed to load products');
  }
  return result.dataOrNull ?? [];
});

class ApplicationsScreen extends ConsumerWidget {
  const ApplicationsScreen({super.key});

  void _showAddProductDialog(BuildContext context, WidgetRef ref) {
    final codeController = TextEditingController();
    final nameController = TextEditingController();
    final descController = TextEditingController();
    String? localError;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: const Text('Add SaaS Application/Product'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Define a platform SaaS product offering that can be assigned to school tenants.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                if (localError != null) ...[
                  Text(localError!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
                  const SizedBox(height: 8),
                ],
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Display Name *', hintText: 'e.g. Hostel Management OS'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: codeController,
                  decoration: const InputDecoration(labelText: 'Product Code (Slug) *', hintText: 'e.g. hostel_management'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Description', hintText: 'Modules and capability notes'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final code = codeController.text.trim();
                if (name.isEmpty || code.isEmpty) {
                  setModalState(() => localError = 'Display Name and Product Code are required.');
                  return;
                }

                Navigator.pop(ctx);
                final repo = ref.read(productRepositoryProvider);
                final res = await repo.createProduct(
                  productCode: code,
                  displayName: name,
                  description: descController.text.trim(),
                );

                if (context.mounted) {
                  if (res.isSuccess) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Product "${res.dataOrNull?.displayName}" registered successfully!'), backgroundColor: AppColors.success),
                    );
                    ref.invalidate(productsListProvider);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(res.errorOrNull ?? 'Failed to create product'), backgroundColor: AppColors.error),
                    );
                  }
                }
              },
              child: const Text('Create Product'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('SaaS Products & Applications'),
        actions: [
          ElevatedButton.icon(
            onPressed: () => _showAddProductDialog(context, ref),
            icon: const Icon(Icons.add_box_rounded, size: 18),
            label: const Text('Add Product'),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Products',
            onPressed: () => ref.invalidate(productsListProvider),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(productsListProvider),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: CenteredContentWrapper(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Multi-Product Catalog',
                    style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Manage centrally offered software platforms. Each school can be independently assigned one or multiple products with distinct subscriptions.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.35),
                  ),
                  const SizedBox(height: 20),

                  productsAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 60),
                      child: Center(
                        child: Column(
                          children: [
                            CircularProgressIndicator(strokeWidth: 2.5),
                            SizedBox(height: 16),
                            Text('Loading product catalog...', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                    error: (err, stack) => ErrorStateView(
                      title: 'Unable to Load Products',
                      message: err.toString().replaceFirst('Exception: ', ''),
                      onRetry: () => ref.invalidate(productsListProvider),
                    ),
                    data: (products) {
                      if (products.isEmpty) {
                        return EmptyStateView(
                          icon: Icons.apps_rounded,
                          title: 'No Products Configured',
                          message: 'No platform applications exist yet in the database.',
                          actionLabel: 'Add First Product',
                          onAction: () => _showAddProductDialog(context, ref),
                        );
                      }

                      return ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: products.length,
                        separatorBuilder: (ctx, i) => const SizedBox(height: 14),
                        itemBuilder: (ctx, index) {
                          final product = products[index];
                          return _buildProductCard(context, product);
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProductCard(BuildContext context, ProductModel product) {
    final dateFormat = DateFormat.yMMMd();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.borderLight),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primarySubtle,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_getProductIcon(product.productCode), color: AppColors.primary, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.displayName,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(4)),
                            child: Text(
                              product.productCode,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('Platform: ${product.platform.toUpperCase()}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: product.status == ProductStatus.active ? AppColors.successSubtle : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: product.status == ProductStatus.active ? AppColors.success.withValues(alpha: 0.3) : AppColors.borderLight),
                  ),
                  child: Text(
                    product.status.displayName.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: product.status == ProductStatus.active ? AppColors.successText : AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            if (product.description != null && product.description!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                product.description!,
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
              ),
            ],
            const SizedBox(height: 14),
            const Divider(height: 1, color: AppColors.dividerLight),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.apartment_rounded, size: 16, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text(
                      'Assigned Schools: ${product.assignedSchoolsCount}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text('Registered: ${dateFormat.format(product.createdAt)}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    const SizedBox(width: 14),
                    OutlinedButton.icon(
                      onPressed: () => context.go(AppRoutes.assignments),
                      icon: const Icon(Icons.link_rounded, size: 15),
                      label: const Text('Manage Assignments', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _getProductIcon(String code) {
    if (code.contains('finance') || code.contains('fee')) return Icons.account_balance_wallet_rounded;
    if (code.contains('transport') || code.contains('bus')) return Icons.directions_bus_rounded;
    if (code.contains('library') || code.contains('book')) return Icons.menu_book_rounded;
    return Icons.school_rounded;
  }
}
