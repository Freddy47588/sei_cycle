import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/firestore_fields.dart';

class InventoryTransaction {
  const InventoryTransaction({
    this.batchId,
    this.source = '',
    required this.id,
    required this.itemId,
    required this.itemName,
    required this.itemKey,
    required this.moduleType,
    required this.logbookId,
    required this.type,
    required this.quantity,
    required this.unit,
    required this.beforeStock,
    required this.afterStock,
    required this.notes,
    required this.transactionDate,
    required this.createdBy,
    required this.createdAt,
    required this.isReversed,
    required this.reversedAt,
    required this.reversedBy,
  });

  final String? batchId;
  final String source;
  final String id;
  final String itemId;
  final String itemName;
  final String itemKey;
  final String moduleType;
  final String logbookId;
  final String type;
  final double quantity;
  final String unit;
  final double beforeStock;
  final double afterStock;
  final String notes;
  final DateTime transactionDate;
  final String createdBy;
  final DateTime createdAt;
  final bool isReversed;
  final DateTime? reversedAt;
  final String reversedBy;

  factory InventoryTransaction.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    final reversedValue = fieldValue(data, const ['reversedAt']);
    return InventoryTransaction(
      id: document.id,
      batchId: data['batchId'] as String?,
      source: stringField(data, const [
        'source',
      ], fallback: data['logbookId'] == null ? 'legacy' : 'logbook'),
      itemId: stringField(data, const ['itemId']),
      itemName: stringField(data, const ['itemName']),
      itemKey: stringField(data, const ['itemKey']),
      moduleType: stringField(data, const ['moduleType']),
      logbookId: stringField(data, const ['logbookId']),
      type: stringField(data, const ['type']),
      quantity: doubleField(data, const ['quantity']),
      unit: stringField(data, const ['unit']),
      beforeStock: doubleField(data, const ['beforeStock']),
      afterStock: doubleField(data, const ['afterStock']),
      notes: stringField(data, const ['notes']),
      transactionDate: dateTimeField(data, const ['transactionDate']),
      createdBy: stringField(data, const ['createdBy']),
      createdAt: dateTimeField(data, const ['createdAt']),
      isReversed: boolField(data, const ['isReversed']),
      reversedAt: reversedValue == null
          ? null
          : dateTimeField(data, const ['reversedAt']),
      reversedBy: stringField(data, const ['reversedBy']),
    );
  }
}
