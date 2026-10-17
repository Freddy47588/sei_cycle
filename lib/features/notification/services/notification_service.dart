import '../../../core/utils/audit_mode.dart';
import '../../../core/utils/legacy_firestore.dart';
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
    return watchNotifications(
      userId: userId,
      role: role,
    ).map((items) => items.where((n) => !n.isRead).length);
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
        .where('targetRole', whereIn: [role, 'all'])
        .where('userId', isEqualTo: '');
    if (type != null && type.trim().isNotEmpty) {
      ownQuery = ownQuery.where('type', isEqualTo: type.trim());
      roleQuery = roleQuery.where('type', isEqualTo: type.trim());
    }

    return _watchCombined(
      ownQuery.orderBy('createdAt', descending: true),
      roleQuery.orderBy('createdAt', descending: true),
      receipts: _firestore
          .collection('notification_receipts')
          .doc(userId)
          .collection('items'),
    ).asyncMap(_excludeSeedReferences).asyncMap((docs) async {
      final notifications = <AppNotification>[];
      for (final doc in docs) {
        final data = doc.data();
        bool? override;
        if (data['userId'] == '') {
          final receipt = await _firestore
              .collection('notification_receipts')
              .doc(userId)
              .collection('items')
              .doc(doc.id)
              .get();
          final readAt = receipt.data()?['readAt'];
          final createdAt = data['createdAt'];
          override =
              readAt is Timestamp &&
              createdAt is Timestamp &&
              readAt.compareTo(createdAt) >= 0;
        }
        notifications.add(
          AppNotification.fromDocument(doc, readOverride: override),
        );
      }
      notifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return notifications;
    });
  }

  // Historical alerts generated from seed masters are not operational signals.
  // The source records and alerts remain untouched for the integrity audit.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _excludeSeedReferences(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final parents = <String, DocumentSnapshot<Map<String, dynamic>>>{};
    final visible = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final doc in docs) {
      final d = doc.data();
      final collection = d['relatedCollection'], id = d['relatedId'];
      if (collection is String &&
          {
            'inventory',
            'schedules',
            'logbooks',
            'batches',
          }.contains(collection) &&
          id is String &&
          id.isNotEmpty &&
          !id.contains('/')) {
        final path = '$collection/$id';
        final parent = parents[path] ??= await _firestore
            .collection(collection)
            .doc(id)
            .get(const GetOptions(source: Source.server));
        if (parent.exists && !isOperationalRecord(parent.data() ?? {})) {
          continue;
        }
      }
      visible.add(doc);
    }
    return visible;
  }

  Future<void> markAsRead(String id, {required String userId}) async {
    requireWritesEnabled();
    requireTrimmed(id, 'id');
    requireTrimmed(userId, 'userId');
    await _firestore.runTransaction((tx) async {
      final notification = await tx.get(_collection.doc(id));
      if (!notification.exists) throw StateError('Notifikasi tidak ditemukan.');
      if (notification.data()?['userId'] == userId) {
        tx.update(notification.reference, {
          'isRead': true,
          'readAt': FieldValue.serverTimestamp(),
        });
      } else {
        tx.set(
          _firestore
              .collection('notification_receipts')
              .doc(userId)
              .collection('items')
              .doc(id),
          {'readAt': FieldValue.serverTimestamp()},
        );
      }
    });
  }

  Future<void> delete(String id, {required String userId}) {
    requireWritesEnabled();
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
    requireWritesEnabled();
    final items = await watchNotifications(userId: userId, role: role).first;
    // The bounded stream rejects incomplete input instead of claiming all were read.
    for (final item in items.where((n) => !n.isRead)) {
      await markAsRead(item.id, userId: userId);
    }
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
    requireWritesEnabled();
    requireTrimmed(title, 'title');
    requireTrimmed(body, 'body');
    requireTrimmed(type, 'type');

    final documentId = id ?? _uuid.v4();
    await _firestore.runTransaction((tx) async {
      final ref = _collection.doc(documentId);
      final old = await tx.get(ref);
      if (old.exists &&
          old.data()?['title'] == title.trim() &&
          old.data()?['body'] == body.trim() &&
          old.data()?['type'] == type &&
          old.data()?['userId'] == userId &&
          old.data()?['targetRole'] == targetRole &&
          old.data()?['scheduledAt'] ==
              (scheduledAt == null ? null : Timestamp.fromDate(scheduledAt))) {
        return;
      }
      if (relatedCollection == 'schedules') {
        final schedule = await tx.get(
          _firestore.collection('schedules').doc(relatedId),
        );
        if (!schedule.exists ||
            !isOperationalRecord(schedule.data()!) ||
            schedule.data()?['status'] != 'pending') {
          return;
        }
      }
      tx.set(ref, {
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
      });
    });
    return documentId;
  }

  Future<void> createLowStockAlerts({
    required String userId,
    required String role,
    required Iterable<InventoryItem> items,
  }) async {
    requireWritesEnabled();
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
    requireWritesEnabled();
    requireTrimmed(userId, 'userId');
    requireTrimmed(role, 'role');
    requireTrimmed(itemId, 'itemId');
    requireTrimmed(name, 'name');

    final id = 'low_stock_${userId}_$itemId';
    await _firestore.runTransaction((tx) async {
      final item = await tx.get(_firestore.collection('inventory').doc(itemId));
      final existing = await tx.get(_collection.doc(id));
      if (!item.exists || !isOperationalRecord(item.data()!)) return;
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
    requireWritesEnabled();
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
    requireWritesEnabled();
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
          !isOperationalRecord(d ?? {}) ||
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
  Query<Map<String, dynamic>> second, {
  Query<Map<String, dynamic>>? receipts,
}) {
  late final StreamController<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  controller;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? firstSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? secondSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? receiptSubscription;
  QuerySnapshot<Map<String, dynamic>>? firstSnapshot;
  QuerySnapshot<Map<String, dynamic>>? secondSnapshot;

  void emit() {
    final first = firstSnapshot;
    final second = secondSnapshot;
    if (first == null || second == null || controller.isClosed) return;
    if (first.docs.length > 500 || second.docs.length > 500) {
      controller.addError(
        StateError(
          'Jumlah notifikasi belum dapat dihitung: batas baca terlampaui.',
        ),
      );
      return;
    }

    controller.add(
      {
        for (final document in first.docs) document.id: document,
        for (final document in second.docs) document.id: document,
      }.values.where((d) => isOperationalRecord(d.data())).toList(),
    );
  }

  controller =
      StreamController<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        onListen: () {
          receiptSubscription = receipts?.snapshots().listen(
            (_) => emit(),
            onError: controller.addError,
          );
          firstSubscription = first.limit(501).snapshots().listen((snapshot) {
            firstSnapshot = snapshot;
            emit();
          }, onError: controller.addError);
          secondSubscription = second.limit(501).snapshots().listen((snapshot) {
            secondSnapshot = snapshot;
            emit();
          }, onError: controller.addError);
        },
        onCancel: () async {
          await receiptSubscription?.cancel();
          await firstSubscription?.cancel();
          await secondSubscription?.cancel();
        },
      );

  return controller.stream;
}
