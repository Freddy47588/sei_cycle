import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/firestore_collections.dart';
import '../../../core/utils/firestore_validators.dart';
import '../../inventory/models/inventory_item.dart';
import '../models/app_notification.dart';

class NotificationService {
  NotificationService({FirebaseFirestore? firestore, Uuid? uuid})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _uuid = uuid ?? const Uuid();

  final FirebaseFirestore _firestore;
  final Uuid _uuid;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(FirestoreCollections.notifications);

  /// Streams the count of unread notifications for the given user/role.
  /// Useful for showing a badge count in navigation.
  Stream<int> watchUnreadCount({required String userId, required String role}) {
    requireTrimmed(userId, 'userId');
    requireTrimmed(role, 'role');

    final ownQuery = _collection
        .where('isDeleted', isEqualTo: false)
        .where('isRead', isEqualTo: false)
        .where('userId', isEqualTo: userId);
    final roleQuery = _collection
        .where('isDeleted', isEqualTo: false)
        .where('isRead', isEqualTo: false)
        .where('targetRole', whereIn: [role, 'all']);

    return _watchCombined(ownQuery, roleQuery).map((docs) => docs.length);
  }

  Stream<List<AppNotification>> watchNotifications({
    required String userId,
    required String role,
    String? type,
  }) {
    requireTrimmed(userId, 'userId');
    requireTrimmed(role, 'role');

    Query<Map<String, dynamic>> ownQuery = _collection
        .where('isDeleted', isEqualTo: false)
        .where('userId', isEqualTo: userId);
    Query<Map<String, dynamic>> roleQuery = _collection
        .where('isDeleted', isEqualTo: false)
        .where('targetRole', whereIn: [role, 'all']);
    if (type != null && type.trim().isNotEmpty) {
      ownQuery = ownQuery.where('type', isEqualTo: type.trim());
      roleQuery = roleQuery.where('type', isEqualTo: type.trim());
    }

    return _watchCombined(
      ownQuery.orderBy('createdAt', descending: true),
      roleQuery.orderBy('createdAt', descending: true),
    ).map((docs) {
      final notifications = docs.map(AppNotification.fromDocument).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return notifications;
    });
  }

  Future<void> markAsRead(String id) {
    requireTrimmed(id, 'id');
    return _collection.doc(id).update({
      'isRead': true,
      'readAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> delete(String id, {required String userId}) {
    requireTrimmed(id, 'id');
    requireTrimmed(userId, 'userId');
    return _collection.doc(id).update({
      'isDeleted': true,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': userId,
    });
  }

  Future<void> markAllAsRead({
    required String userId,
    required String role,
  }) async {
    final ownSnapshot = await _collection
        .where('isDeleted', isEqualTo: false)
        .where('isRead', isEqualTo: false)
        .where('userId', isEqualTo: userId)
        .limit(50)
        .get();
    final roleSnapshot = await _collection
        .where('isDeleted', isEqualTo: false)
        .where('isRead', isEqualTo: false)
        .where('targetRole', whereIn: [role, 'all'])
        .limit(50)
        .get();

    final documents = {
      for (final document in ownSnapshot.docs) document.id: document,
      for (final document in roleSnapshot.docs) document.id: document,
    }.values;

    if (documents.isEmpty) return;
    final batch = _firestore.batch();
    for (final document in documents) {
      batch.update(document.reference, {
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<String> create({
    String? id,
    required String title,
    required String body,
    required String type,
    String targetRole = 'all',
    String userId = '',
    String relatedCollection = '',
    String relatedId = '',
    DateTime? scheduledAt,
  }) async {
    requireTrimmed(title, 'title');
    requireTrimmed(body, 'body');
    requireTrimmed(type, 'type');

    final documentId = id ?? _uuid.v4();
    await _collection.doc(documentId).set({
      'id': documentId,
      'title': title.trim(),
      'body': body.trim(),
      'type': type.trim(),
      'targetRole': targetRole.trim().isEmpty ? 'all' : targetRole.trim(),
      'userId': userId.trim(),
      'relatedCollection': relatedCollection.trim(),
      'relatedId': relatedId.trim(),
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
      if (scheduledAt != null) 'scheduledAt': Timestamp.fromDate(scheduledAt),
      'isDeleted': false,
    }, SetOptions(merge: true));
    return documentId;
  }

  Future<void> createLowStockAlerts({
    required String userId,
    required String role,
    required Iterable<InventoryItem> items,
  }) async {
    for (final item in items.take(20)) {
      await createLowStockAlert(
        userId: userId,
        role: role,
        itemId: item.id,
        name: item.name,
        currentStock: item.currentStock,
        minStock: item.minStock,
        unit: item.unit,
      );
    }
  }

  Future<void> createLowStockAlert({
    required String userId,
    required String role,
    required String itemId,
    required String name,
    required double currentStock,
    required double minStock,
    required String unit,
  }) async {
    requireTrimmed(userId, 'userId');
    requireTrimmed(role, 'role');
    requireTrimmed(itemId, 'itemId');
    requireTrimmed(name, 'name');

    final id = 'low_stock_${userId}_$itemId';
    await _firestore.runTransaction((tx) async {
      final item = await tx.get(_firestore.collection('inventory').doc(itemId));
      final existing = await tx.get(_collection.doc(id));
      if (!item.exists) return;
      final actual = InventoryItem.fromDocument(item);
      if (!actual.isLowStock || actual.isDeleted) {
        if (existing.exists && existing.data()?['isDeleted'] != true) {
          tx.update(existing.reference, {
            'isDeleted': true,
            'updatedBy': userId,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        return;
      }
      final title = actual.currentStock <= 0
          ? 'Stok ${actual.name} habis'
          : 'Stok ${actual.name} rendah';
      final body =
          'Saat diperiksa: ${_number(actual.currentStock)} ${actual.unit}, minimum ${_number(actual.minStock)} ${actual.unit}. Buka Inventaris untuk kondisi terbaru.';
      if (existing.exists &&
          existing.data()?['isDeleted'] != true &&
          existing.data()?['title'] == title &&
          existing.data()?['body'] == body) {
        return;
      }
      tx.set(_collection.doc(id), {
        'id': id,
        'title': title,
        'body': body,
        'type': 'low_stock',
        'targetRole': role,
        'userId': userId,
        'relatedCollection': FirestoreCollections.inventory,
        'relatedId': itemId,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
        'isDeleted': false,
      });
    });
  }

  Future<void> createLowStockNotificationIfNeeded({
    required String userId,
    required String itemId,
    required String name,
    required double currentStock,
    required double minStock,
    required String unit,
    String targetRole = 'admin',
  }) async {
    await createLowStockAlert(
      userId: userId,
      role: targetRole,
      itemId: itemId,
      name: name,
      currentStock: currentStock,
      minStock: minStock,
      unit: unit,
    );
  }

  Future<void> createScheduleOverdueAlert({
    required String scheduleId,
    required String title,
    required String userId,
    required String role,
  }) async {
    requireTrimmed(scheduleId, 'scheduleId');
    requireTrimmed(userId, 'userId');
    requireTrimmed(role, 'role');

    final id = 'schedule_overdue_${userId}_$scheduleId';
    await _firestore.runTransaction((tx) async {
      final schedule = await tx.get(
        _firestore.collection('schedules').doc(scheduleId),
      );
      final old = await tx.get(_collection.doc(id));
      final d = schedule.data();
      final date = (d?['date'] as Timestamp?)?.toDate();
      if (!schedule.exists ||
          d?['isDeleted'] == true ||
          d?['status'] != 'pending' ||
          date == null ||
          !date.isBefore(DateTime.now())) {
        if (old.exists && old.data()?['isDeleted'] != true) {
          tx.update(old.reference, {
            'isDeleted': true,
            'updatedBy': userId,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        return;
      }
      final body =
          'Saat diperiksa, jadwal ${d?['title']} (${date.toIso8601String()}) melewati waktu dan masih pending. Periksa kalender untuk status terbaru.';
      if (old.exists &&
          old.data()?['isDeleted'] != true &&
          old.data()?['body'] == body) {
        return;
      }
      tx.set(_collection.doc(id), {
        'id': id,
        'title': 'Jadwal Terlewat',
        'body': body,
        'type': 'schedule_overdue',
        'targetRole': role,
        'userId': userId,
        'relatedCollection': FirestoreCollections.schedules,
        'relatedId': scheduleId,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
        'isDeleted': false,
      });
    });
  }

  Future<void> createProductionReminder({
    required String scheduleId,
    required String title,
    required String userId,
    required String role,
    DateTime? scheduledAt,
  }) {
    return create(
      id: 'production_reminder_${userId}_$scheduleId',
      title: 'Pengingat produksi',
      body: title,
      type: 'production_reminder',
      targetRole: role,
      userId: userId,
      relatedCollection: FirestoreCollections.schedules,
      relatedId: scheduleId,
      scheduledAt: scheduledAt,
    );
  }

  Future<void> createSystemAlert({
    required String title,
    required String body,
    String targetRole = 'all',
  }) {
    return create(
      title: title,
      body: body,
      type: 'system',
      targetRole: targetRole,
    );
  }
}

String _number(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(1);

Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _watchCombined(
  Query<Map<String, dynamic>> first,
  Query<Map<String, dynamic>> second,
) {
  late final StreamController<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  controller;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? firstSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? secondSubscription;
  QuerySnapshot<Map<String, dynamic>>? firstSnapshot;
  QuerySnapshot<Map<String, dynamic>>? secondSnapshot;

  void emit() {
    final first = firstSnapshot;
    final second = secondSnapshot;
    if (first == null || second == null || controller.isClosed) return;

    controller.add(
      {
        for (final document in first.docs) document.id: document,
        for (final document in second.docs) document.id: document,
      }.values.toList(),
    );
  }

  controller =
      StreamController<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        onListen: () {
          firstSubscription = first.snapshots().listen((snapshot) {
            firstSnapshot = snapshot;
            emit();
          }, onError: controller.addError);
          secondSubscription = second.snapshots().listen((snapshot) {
            secondSnapshot = snapshot;
            emit();
          }, onError: controller.addError);
        },
        onCancel: () async {
          await firstSubscription?.cancel();
          await secondSubscription?.cancel();
        },
      );

  return controller.stream;
}
