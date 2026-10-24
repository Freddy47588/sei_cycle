import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/firestore_fields.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.targetRole,
    required this.userId,
    required this.relatedCollection,
    required this.relatedId,
    required this.isRead,
    required this.createdAt,
    required this.scheduledAt,
    required this.isDeleted,
  });

  final String id;
  final String title;
  final String body;
  final String type;
  final String targetRole;
  final String userId;
  final String relatedCollection;
  final String relatedId;
  final bool isRead;
  final DateTime createdAt;
  final DateTime? scheduledAt;
  final bool isDeleted;

  factory AppNotification.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document, {
    bool? readOverride,
  }) {
    final data = document.data() ?? const <String, dynamic>{};
    final scheduledValue = fieldValue(data, const ['scheduledAt']);
    return AppNotification(
      id: document.id,
      title: stringField(data, const ['title']),
      body: stringField(data, const ['body', 'description']),
      type: stringField(data, const ['type'], fallback: 'system'),
      targetRole: stringField(data, const ['targetRole'], fallback: 'all'),
      userId: stringField(data, const ['userId']),
      relatedCollection: stringField(data, const ['relatedCollection']),
      relatedId: stringField(data, const ['relatedId']),
      isRead: readOverride ?? boolField(data, const ['isRead']),
      createdAt: dateTimeField(data, const ['createdAt']),
      scheduledAt: scheduledValue == null
          ? null
          : dateTimeField(data, const ['scheduledAt']),
      isDeleted: boolField(data, const ['isDeleted']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'type': type,
      'targetRole': targetRole,
      'userId': userId,
      'relatedCollection': relatedCollection,
      'relatedId': relatedId,
      'isRead': isRead,
      'createdAt': Timestamp.fromDate(createdAt),
      if (scheduledAt != null) 'scheduledAt': Timestamp.fromDate(scheduledAt!),
      'isDeleted': isDeleted,
    };
  }
}
