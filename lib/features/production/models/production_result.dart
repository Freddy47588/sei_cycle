import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/firestore_fields.dart';

class ProductionResult {
  const ProductionResult({
    required this.id,
    required this.logbookId,
    required this.moduleType,
    required this.productName,
    required this.quantity,
    required this.unit,
    required this.qualityStatus,
    required this.harvestDate,
    required this.notes,
    required this.createdBy,
    required this.createdAt,
  });

  final String id;
  final String logbookId;
  final String moduleType;
  final String productName;
  final double quantity;
  final String unit;
  final String qualityStatus;
  final DateTime harvestDate;
  final String notes;
  final String createdBy;
  final DateTime createdAt;

  factory ProductionResult.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return ProductionResult(
      id: stringField(data, const ['id'], fallback: document.id),
      logbookId: stringField(data, const ['logbookId']),
      moduleType: stringField(data, const ['moduleType']),
      productName: stringField(data, const ['productName']),
      quantity: doubleField(data, const ['quantity']),
      unit: stringField(data, const ['unit']),
      qualityStatus: stringField(data, const ['qualityStatus']),
      harvestDate: dateTimeField(data, const ['harvestDate']),
      notes: stringField(data, const ['notes']),
      createdBy: stringField(data, const ['createdBy']),
      createdAt: dateTimeField(data, const ['createdAt']),
    );
  }
}
