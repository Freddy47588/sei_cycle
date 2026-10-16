import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/firestore_fields.dart';

class ScheduleItem {
  const ScheduleItem({
    this.batchId,
    this.completedAt,
    this.completedBy = '',
    this.skippedAt,
    this.skippedBy = '',
    this.skipReason = '',
    required this.id,
    required this.title,
    required this.moduleId,
    required this.scheduleType,
    required this.scheduledAt,
    required this.status,
    required this.note,
    required this.createdBy,
    required this.updatedBy,
    required this.createdAt,
    required this.updatedAt,
    required this.isDeleted,
  });

  final String? batchId;
  final DateTime? completedAt, skippedAt;
  final String completedBy, skippedBy, skipReason;
  final String id;
  final String title;
  final String moduleId;
  final String scheduleType;
  final DateTime scheduledAt;
  final String status;
  final String note;
  final String createdBy;
  final String updatedBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;

  factory ScheduleItem.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return ScheduleItem(
      id: document.id,
      batchId: data['batchId'] as String?,
      completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
      completedBy: stringField(data, const ['completedBy']),
      skippedAt: (data['skippedAt'] as Timestamp?)?.toDate(),
      skippedBy: stringField(data, const ['skippedBy']),
      skipReason: stringField(data, const ['skipReason']),
      title: stringField(data, const ['title']),
      moduleId: stringField(data, const ['moduleType', 'module_id']),
      scheduleType: stringField(data, const ['type', 'schedule_type']),
      scheduledAt: dateTimeField(data, const [
        'date',
        'scheduledAt',
        'scheduled_at',
      ]),
      status: stringField(data, const ['status'], fallback: 'pending'),
      note: stringField(data, const ['notes', 'note']),
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
      'batchId': ?batchId,
      if (completedAt != null) 'completedAt': Timestamp.fromDate(completedAt!),
      if (completedBy.isNotEmpty) 'completedBy': completedBy,
      if (skippedAt != null) 'skippedAt': Timestamp.fromDate(skippedAt!),
      if (skippedBy.isNotEmpty) 'skippedBy': skippedBy,
      if (skipReason.isNotEmpty) 'skipReason': skipReason,
      'title': title,
      'moduleType': moduleId,
      'type': scheduleType,
      'date': Timestamp.fromDate(scheduledAt),
      'status': status,
      'notes': note,
      'createdBy': createdBy,
      'updatedBy': updatedBy,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'isDeleted': isDeleted,
    };
  }
}
