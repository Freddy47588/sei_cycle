import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/firestore_fields.dart';

class RecommendationModel {
  const RecommendationModel({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.priority,
    required this.createdAt,
    required this.isResolved,
    this.recommendedAction = '',
    this.sourceDate,
    this.moduleType,
    this.sourceCollection,
    this.sourceId,
    this.validUntil,
  });

  final String recommendedAction;
  final DateTime? sourceDate;
  final String id;
  final String title;
  final String description;
  final String type;
  final String priority;
  final String? moduleType;
  final String? sourceCollection;
  final String? sourceId;
  final DateTime createdAt;
  final DateTime? validUntil;
  final bool isResolved;

  factory RecommendationModel.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    final validUntil = data['validUntil'] ?? data['valid_until'];
    return RecommendationModel(
      id: document.id,
      recommendedAction: stringField(data, const ['recommendedAction']),
      sourceDate: data['sourceDate'] is Timestamp
          ? (data['sourceDate'] as Timestamp).toDate()
          : null,
      title: stringField(data, const ['title']),
      description: stringField(data, const ['description']),
      type: stringField(data, const ['type'], fallback: 'insight'),
      priority: stringField(data, const ['priority'], fallback: 'normal'),
      moduleType: _optionalString(data, const ['moduleType', 'module_type']),
      sourceCollection: _optionalString(data, const [
        'sourceCollection',
        'source_collection',
      ]),
      sourceId: _optionalString(data, const ['sourceId', 'source_id']),
      createdAt: dateTimeField(data, const ['createdAt', 'created_at']),
      validUntil: validUntil is Timestamp ? validUntil.toDate() : null,
      isResolved: boolField(data, const ['isResolved', 'is_resolved']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'recommendedAction': recommendedAction,
      if (sourceDate != null) 'sourceDate': Timestamp.fromDate(sourceDate!),
      'title': title,
      'description': description,
      'type': type,
      'priority': priority,
      if (moduleType != null) 'moduleType': moduleType,
      if (sourceCollection != null) 'sourceCollection': sourceCollection,
      if (sourceId != null) 'sourceId': sourceId,
      'createdAt': Timestamp.fromDate(createdAt),
      if (validUntil != null) 'validUntil': Timestamp.fromDate(validUntil!),
      'isResolved': isResolved,
    };
  }
}

String? _optionalString(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}
