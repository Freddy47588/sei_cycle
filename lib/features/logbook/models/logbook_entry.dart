import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/firestore_fields.dart';

class LogbookEntry {
  const LogbookEntry({
    required this.id,
    this.batchId,
    String? title,
    required this.moduleId,
    required this.activityType,
    required this.activityDate,
    required this.quantity,
    this.hasQuantity = true,
    required this.unit,
    String? status,
    String? condition,
    required this.note,
    Map<String, dynamic>? details,
    required this.createdBy,
    required this.updatedBy,
    required this.createdAt,
    required this.updatedAt,
    required this.isDeleted,
  }) : title = title ?? activityType,
       status = status ?? condition ?? '',
       details = details ?? const <String, dynamic>{};

  final String id;
  final String? batchId;
  final String title;
  final String moduleId;
  final String activityType;
  final DateTime activityDate;
  final double quantity;
  final bool hasQuantity;
  final String unit;
  final String status;
  final String note;
  final Map<String, dynamic> details;
  final String createdBy;
  final String updatedBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;

  String get condition => status;

  factory LogbookEntry.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return LogbookEntry(
      id: document.id,
      batchId: data['batchId'] as String?,
      title: stringField(data, const ['title'], fallback: 'Catatan Logbook'),
      moduleId: stringField(data, const ['moduleType', 'module_id']),
      activityType: stringField(data, const ['activityType', 'activity_type']),
      activityDate: dateTimeField(data, const [
        'activityDate',
        'activity_date',
      ]),
      quantity: doubleField(data, const ['quantity']),
      hasQuantity: data['quantity'] is num,
      unit: stringField(data, const ['unit']),
      status: stringField(data, const ['status', 'condition']),
      note: stringField(data, const ['notes', 'note']),
      details: _mapField(data, const ['details']),
      createdBy: stringField(data, const ['createdBy', 'created_by']),
      updatedBy: stringField(data, const ['updatedBy', 'updated_by']),
      createdAt: dateTimeField(data, const ['createdAt', 'created_at']),
      updatedAt: dateTimeField(data, const ['updatedAt', 'updated_at']),
      isDeleted: boolField(data, const ['isDeleted', 'is_deleted']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      if (batchId != null) 'batchId': batchId,
      'title': title,
      'moduleType': moduleId,
      'activityDate': Timestamp.fromDate(activityDate),
      'activityType': activityType,
      'quantity': hasQuantity ? quantity : null,
      'unit': unit,
      'status': status,
      'notes': note,
      'details': details,
      'createdBy': createdBy,
      'updatedBy': updatedBy,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'isDeleted': isDeleted,
    };
  }
}

Map<String, dynamic> _mapField(Map<String, dynamic> data, List<String> keys) {
  final value = fieldValue(data, keys);
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const <String, dynamic>{};
}
