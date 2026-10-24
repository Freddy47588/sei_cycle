import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/firestore_fields.dart';

class CircularFlow {
  const CircularFlow({
    this.createdByName = '',
    this.createdBy = '',
    this.sourceType = 'legacy',
    this.sourceBatchId,
    this.destinationBatchId,
    this.logbookId,
    this.inventoryTransactionId,
    this.isSampleData = false,
    required this.id,
    required this.sourceModuleType,
    required this.destinationModuleType,
    required this.materialName,
    required this.quantity,
    required this.unit,
    required this.flowDate,
    required this.notes,
    required this.createdAt,
  });

  final String createdByName;
  final String createdBy, sourceType;
  final String? sourceBatchId,
      destinationBatchId,
      logbookId,
      inventoryTransactionId;
  final bool isSampleData;
  bool get isActual =>
      sourceType == 'manual' && createdBy.isNotEmpty && !isSampleData;
  final String id;
  final String sourceModuleType;
  final String destinationModuleType;
  final String materialName;
  final double quantity;
  final String unit;
  final DateTime flowDate;
  final String notes;
  final DateTime createdAt;

  factory CircularFlow.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return CircularFlow(
      createdByName: stringField(data, const ['createdByName']),
      createdBy: stringField(data, const ['createdBy']),
      sourceType: stringField(data, const ['sourceType'], fallback: 'legacy'),
      sourceBatchId: data['sourceBatchId'] as String?,
      destinationBatchId: data['destinationBatchId'] as String?,
      logbookId: data['logbookId'] as String?,
      inventoryTransactionId: data['inventoryTransactionId'] as String?,
      isSampleData:
          data['isSampleData'] == true ||
          data['createdBy'] == 'sample_seed' ||
          data['sampleVersion'] == 'v2',
      id: stringField(data, const ['id'], fallback: document.id),
      sourceModuleType: stringField(data, const ['sourceModuleType']),
      destinationModuleType: stringField(data, const ['destinationModuleType']),
      materialName: stringField(data, const ['materialName']),
      quantity: doubleField(data, const ['quantity']),
      unit: stringField(data, const ['unit']),
      flowDate: dateTimeField(data, const ['flowDate']),
      notes: stringField(data, const ['notes']),
      createdAt: dateTimeField(data, const ['createdAt']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'createdBy': createdBy,
      'sourceType': sourceType,
      if (sourceBatchId != null) 'sourceBatchId': sourceBatchId,
      if (destinationBatchId != null) 'destinationBatchId': destinationBatchId,
      if (logbookId != null) 'logbookId': logbookId,
      if (inventoryTransactionId != null)
        'inventoryTransactionId': inventoryTransactionId,
      'id': id,
      'sourceModuleType': sourceModuleType,
      'destinationModuleType': destinationModuleType,
      'materialName': materialName,
      'quantity': quantity,
      'unit': unit,
      'flowDate': Timestamp.fromDate(flowDate),
      'notes': notes,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
