import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/firestore_fields.dart';

class InventoryItem {
  InventoryItem({
    this.legacyReadOnly = false,
    this.requiresProvenanceReview = false,
    this.productType = 'operational',
    this.isSellable = false,
    required this.id,
    required this.name,
    String? itemKey,
    this.moduleType = '',
    required this.category,
    required this.unit,
    required this.currentStock,
    required this.minStock,
    required this.isLowStock,
    this.location = '',
    required this.createdBy,
    required this.updatedBy,
    required this.createdAt,
    required this.updatedAt,
    required this.isDeleted,
  }) : itemKey = itemKey ?? _fallbackItemKey(name);

  final bool legacyReadOnly;
  final bool requiresProvenanceReview;
  final String productType;
  final bool isSellable;
  final String id;
  final String name;
  final String itemKey;
  final String moduleType;
  final String category;
  final String unit;
  final double currentStock;
  final double minStock;
  final bool isLowStock;
  final String location;
  final String createdBy;
  final String updatedBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;

  factory InventoryItem.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    final currentStock = requiredNumberField(data, const [
      'currentStock',
      'current_stock',
    ]);
    final minStock = requiredNumberField(data, const ['minStock', 'min_stock']);
    return InventoryItem(
      requiresProvenanceReview:
          data['createdBy'] != 'sample_seed' &&
          (data['isSampleData'] == true || data['sampleVersion'] == 'v2'),
      legacyReadOnly: document.reference.path.split('/').first != 'inventory',
      productType: stringField(data, const [
        'productType',
      ], fallback: 'operational'),
      isSellable:
          data['isSellable'] == true && data['productType'] == 'harvest',
      id: document.id,
      name: stringField(data, const ['name']),
      itemKey: stringField(data, const [
        'itemKey',
        'item_key',
      ], fallback: _fallbackItemKey(stringField(data, const ['name']))),
      moduleType: stringField(data, const ['moduleType', 'module_type']),
      category: stringField(data, const ['category']),
      unit: stringField(data, const ['unit']),
      currentStock: currentStock,
      minStock: minStock,
      isLowStock: currentStock <= minStock,
      location: stringField(data, const ['location']),
      createdBy: stringField(data, const ['createdBy', 'created_by']),
      updatedBy: stringField(data, const ['updatedBy', 'updated_by']),
      createdAt: dateTimeField(data, const ['createdAt', 'created_at']),
      updatedAt: dateTimeField(data, const ['updatedAt', 'updated_at']),
      isDeleted: boolField(data, const ['isDeleted', 'is_deleted']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'productType': productType,
      'isSellable': isSellable,
      'id': id,
      'name': name,
      'itemKey': itemKey,
      'moduleType': moduleType,
      'category': category,
      'unit': unit,
      'currentStock': currentStock,
      'minStock': minStock,
      'isLowStock': isLowStock,
      'location': location,
      'createdBy': createdBy,
      'updatedBy': updatedBy,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'isDeleted': isDeleted,
    };
  }
}

String _fallbackItemKey(String name) {
  return name
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}
