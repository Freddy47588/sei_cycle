import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/firestore_fields.dart';

class FinanceRecord {
  const FinanceRecord({
    this.legacyReadOnly = false,
    this.requiresProvenanceReview = false,
    this.saleId = '',
    this.version = 0,
    required this.id,
    required this.type,
    required this.category,
    required this.amount,
    required this.date,
    required this.notes,
    required this.paymentMethod,
    required this.moduleType,
    required this.createdBy,
    required this.updatedBy,
    required this.createdAt,
    required this.updatedAt,
    required this.isDeleted,
  });

  final bool legacyReadOnly;
  final bool requiresProvenanceReview;
  final String saleId;
  final int version;
  bool get isSaleLinked => saleId.isNotEmpty;
  final String id;
  final String type;
  final String category;
  final double amount;
  final DateTime date;
  final String notes;
  final String paymentMethod;
  final String moduleType;
  final String createdBy;
  final String updatedBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;

  String get note => notes;

  factory FinanceRecord.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return FinanceRecord(
      requiresProvenanceReview:
          data['createdBy'] != 'sample_seed' &&
          (data['isSampleData'] == true || data['sampleVersion'] == 'v2'),
      legacyReadOnly:
          document.reference.path.split('/').first != 'finance_transactions',
      saleId: stringField(data, const ['saleId']),
      version: (data['version'] as num?)?.toInt() ?? 0,
      id: document.id,
      type: stringField(data, const ['type'], fallback: 'expense'),
      category: stringField(data, const ['category', 'title']),
      amount: requiredNumberField(data, const ['amount']),
      date: dateTimeField(data, const ['date']),
      notes: stringField(data, const ['notes', 'description', 'note']),
      paymentMethod: stringField(data, const [
        'paymentMethod',
        'payment_method',
      ]),
      moduleType: stringField(data, const ['moduleType', 'module_type']),
      createdBy: stringField(data, const ['createdBy', 'created_by']),
      updatedBy: stringField(data, const ['updatedBy', 'updated_by']),
      createdAt: dateTimeField(data, const ['createdAt', 'created_at']),
      updatedAt: dateTimeField(data, const ['updatedAt', 'updated_at']),
      isDeleted: boolField(data, const ['isDeleted', 'is_deleted']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      if (saleId.isNotEmpty) 'saleId': saleId,
      'version': version,
      'id': id,
      'type': type,
      'category': category,
      'amount': amount,
      'date': Timestamp.fromDate(date),
      'description': notes,
      'notes': notes,
      'paymentMethod': paymentMethod,
      'moduleType': moduleType,
      'createdBy': createdBy,
      'updatedBy': updatedBy,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'isDeleted': isDeleted,
    };
  }
}
