enum ProductStatus {
  active,
  inactive;

  static ProductStatus fromString(String? raw) {
    return raw?.toUpperCase().trim() == 'INACTIVE'
        ? ProductStatus.inactive
        : ProductStatus.active;
  }

  String get dbValue => this == ProductStatus.active ? 'ACTIVE' : 'INACTIVE';
  String get displayName => this == ProductStatus.active ? 'Active' : 'Inactive';
}

class ProductModel {
  final String id;
  final String productCode;
  final String displayName;
  final String? description;
  final String platform;
  final ProductStatus status;
  final int assignedSchoolsCount;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const ProductModel({
    required this.id,
    required this.productCode,
    required this.displayName,
    this.description,
    this.platform = 'android',
    this.status = ProductStatus.active,
    this.assignedSchoolsCount = 0,
    required this.createdAt,
    this.updatedAt,
  });

  factory ProductModel.fromJson(Map<String, dynamic> json, {int assignedSchoolsCount = 0}) {
    return ProductModel(
      id: json['id']?.toString() ?? '',
      productCode: json['product_code']?.toString() ?? '',
      displayName: json['display_name']?.toString() ?? 'Product',
      description: json['description']?.toString(),
      platform: json['platform']?.toString() ?? 'android',
      status: ProductStatus.fromString(json['status']?.toString()),
      assignedSchoolsCount: assignedSchoolsCount,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product_code': productCode,
      'display_name': displayName,
      'description': description,
      'platform': platform,
      'status': status.dbValue,
      'created_at': createdAt.toIso8601String(),
    };
  }

  ProductModel copyWith({
    String? displayName,
    String? description,
    ProductStatus? status,
    int? assignedSchoolsCount,
  }) {
    return ProductModel(
      id: id,
      productCode: productCode,
      displayName: displayName ?? this.displayName,
      description: description ?? this.description,
      platform: platform,
      status: status ?? this.status,
      assignedSchoolsCount: assignedSchoolsCount ?? this.assignedSchoolsCount,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
