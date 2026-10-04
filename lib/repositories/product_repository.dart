import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_result.dart';
import '../models/product_model.dart';
import '../services/product_service.dart';

final productServiceProvider = Provider<ProductService>((ref) => ProductService());

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return ProductRepository(ref.watch(productServiceProvider));
});

class ProductRepository {
  final ProductService _service;

  ProductRepository(this._service);

  Future<ApiResult<List<ProductModel>>> getProducts() => _service.fetchProducts();

  Future<ApiResult<ProductModel>> createProduct({
    required String productCode,
    required String displayName,
    String? description,
    String platform = 'android',
  }) =>
      _service.createProduct(
        productCode: productCode,
        displayName: displayName,
        description: description,
        platform: platform,
      );
}
