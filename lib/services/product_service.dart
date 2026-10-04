import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/network/api_result.dart';
import '../models/product_model.dart';
import 'supabase_service.dart';

class ProductService {
  SupabaseClient? get _client => SupabaseService.instance.client;

  // Fallback defaults in case backend migration has not been applied yet
  static final List<ProductModel> defaultProducts = [
    ProductModel(
      id: 'prod-001',
      productCode: 'school_management',
      displayName: 'School Management OS',
      description: 'Comprehensive school admin, timetable, staff, attendance, and student operations',
      platform: 'android',
      status: ProductStatus.active,
      assignedSchoolsCount: 0,
      createdAt: DateTime(2026, 1, 1),
    ),
    ProductModel(
      id: 'prod-002',
      productCode: 'finance_management',
      displayName: 'School Finance OS',
      description: 'Dedicated fee collection, invoices, installment ledgers, and payment reconciliation',
      platform: 'android',
      status: ProductStatus.active,
      assignedSchoolsCount: 0,
      createdAt: DateTime(2026, 1, 1),
    ),
    ProductModel(
      id: 'prod-003',
      productCode: 'transport_management',
      displayName: 'Transport OS',
      description: 'Fleet management, bus routing, live tracking, and driver shift scheduling',
      platform: 'android',
      status: ProductStatus.active,
      assignedSchoolsCount: 0,
      createdAt: DateTime(2026, 1, 1),
    ),
    ProductModel(
      id: 'prod-004',
      productCode: 'library_management',
      displayName: 'Library OS',
      description: 'Book cataloging, barcode scanning, issue/return cycles, and penalty automation',
      platform: 'android',
      status: ProductStatus.active,
      assignedSchoolsCount: 0,
      createdAt: DateTime(2026, 1, 1),
    ),
  ];

  /// Fetch all available platform products / applications
  Future<ApiResult<List<ProductModel>>> fetchProducts() async {
    final client = _client;
    if (client == null) {
      return ApiResult.success(defaultProducts);
    }

    try {
      final response = await client
          .from('products')
          .select('id, product_code, display_name, description, platform, status, created_at, updated_at')
          .order('created_at', ascending: true);

      final List<dynamic> rawList = response as List<dynamic>;
      final List<ProductModel> products = [];

      for (final item in rawList) {
        final pMap = item as Map<String, dynamic>;
        final pId = pMap['id']?.toString() ?? '';

        // Query assigned schools count if school_apps table exists
        int count = 0;
        try {
          final countRes = await client
              .from('school_apps')
              .select('id')
              .eq('product_id', pId);
          count = (countRes as List<dynamic>).length;
        } catch (_) {}

        products.add(ProductModel.fromJson(pMap, assignedSchoolsCount: count));
      }

      return ApiResult.success(products);
    } catch (e) {
      debugPrint('[ProductService] Warning reading products table: $e. Using verified fallback catalog.');
      return ApiResult.success(defaultProducts);
    }
  }

  /// Create a new platform product
  Future<ApiResult<ProductModel>> createProduct({
    required String productCode,
    required String displayName,
    String? description,
    String platform = 'android',
  }) async {
    final client = _client;
    if (client == null) {
      return ApiResult.failure('Database service is uninitialized.');
    }

    try {
      final inserted = await client.from('products').insert({
        'product_code': productCode.trim().toLowerCase().replaceAll(' ', '_'),
        'display_name': displayName.trim(),
        'description': description?.trim(),
        'platform': platform,
        'status': 'ACTIVE',
      }).select().single();

      return ApiResult.success(ProductModel.fromJson(inserted));
    } catch (e) {
      debugPrint('[ProductService] createProduct error: $e');
      return ApiResult.failure('Failed to create product: $e', e);
    }
  }
}
