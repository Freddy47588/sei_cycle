import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sei_cycle/features/notification/services/notification_service.dart';

import 'support/memory_firestore.dart';

final _createdAt = Timestamp.fromDate(DateTime(2026, 10, 16, 15));
const _role = 'operator_lapangan';

Map<String, dynamic> _notification({String userId = '', String role = 'all'}) =>
    {
      'title': 'Pengingat uji',
      'body': 'Catatan terverifikasi',
      'type': 'system',
      'targetRole': role,
      'userId': userId,
      'isRead': false,
      'isDeleted': false,
      'createdAt': _createdAt,
    };

void main() {
  test(
    'unchanged generic notification preserves read state and timestamp',
    () async {
      final db = MemoryFirestore();
      final service = NotificationService(firestore: db);
      Future<String> create(String body) => service.create(
        id: 'stable',
        title: 'Pengingat uji',
        body: body,
        type: 'system',
        userId: 'field',
        targetRole: _role,
      );
      await create('Catatan terverifikasi');
      db.documents['notifications/stable']!.addAll({
        'createdAt': _createdAt,
        'isRead': true,
        'readAt': _createdAt,
      });
      final before = Map<String, dynamic>.from(
        db.documents['notifications/stable']!,
      );

      await create('Catatan terverifikasi');
      expect(db.documents['notifications/stable'], before);

      await create('Catatan berubah');
      expect(db.documents['notifications/stable']!['isRead'], false);
      expect(
        db.documents['notifications/stable']!['createdAt'],
        isNot(_createdAt),
      );
      expect(
        db.documents.keys.where((p) => p.startsWith('notifications/')),
        hasLength(1),
      );
    },
  );

  test(
    'broadcast receipt is personal and a newer broadcast becomes unread',
    () async {
      final db = MemoryFirestore();
      db.documents['notifications/broadcast'] = {
        ..._notification(),
        // Legacy global state must not mark the broadcast read for everyone.
        'isRead': true,
      };
      db.documents['notifications/own'] = _notification(userId: 'field');
      db.documents['notifications/other'] = _notification(
        userId: 'other',
        role: _role,
      );
      db.documents['notifications/admin'] = _notification(role: 'admin');
      final service = NotificationService(firestore: db);
      Future<bool> broadcastRead(String uid) async =>
          (await service.watchNotifications(userId: uid, role: _role).first)
              .singleWhere((n) => n.id == 'broadcast')
              .isRead;

      final initial = await service
          .watchNotifications(userId: 'field', role: _role)
          .first;
      expect(initial.map((n) => n.id), unorderedEquals(['own', 'broadcast']));
      expect(await broadcastRead('field'), false);
      await service.markAsRead('broadcast', userId: 'field');
      expect(await broadcastRead('field'), true);
      expect(await broadcastRead('other'), false);
      expect(db.documents['notifications/broadcast']!['isRead'], true);
      expect(
        db.documents.containsKey('notification_receipts/other/items/broadcast'),
        false,
      );

      db.documents['notifications/broadcast']!['createdAt'] =
          Timestamp.fromDate(DateTime(2026, 10, 16, 17));
      expect(await broadcastRead('field'), false);
    },
  );

  test(
    'mark all reads every eligible item beyond fifty without cross-user writes',
    () async {
      final db = MemoryFirestore();
      for (var i = 0; i < 60; i++) {
        db.documents['notifications/n$i'] = _notification(
          userId: i.isEven ? 'field' : '',
        );
      }
      db.documents['notifications/private'] = _notification(userId: 'other');
      final service = NotificationService(firestore: db);
      await service.markAllAsRead(userId: 'field', role: _role);

      final ownInbox = await service
          .watchNotifications(userId: 'field', role: _role)
          .first;
      expect(ownInbox, hasLength(60));
      expect(ownInbox.every((n) => n.isRead), true);
      expect(db.documents['notifications/private']!['isRead'], false);
      expect(
        db.documents.keys.where(
          (p) => p.startsWith('notification_receipts/field/items/'),
        ),
        hasLength(30),
      );
      expect(
        db.documents.keys.where(
          (p) => p.startsWith('notification_receipts/other/'),
        ),
        isEmpty,
      );
    },
  );

  for (final broadcast in [false, true]) {
    test(
      'oversized ${broadcast ? 'broadcast' : 'targeted'} inbox rejects mark all before writes',
      () async {
        final db = MemoryFirestore();
        for (var i = 0; i < 501; i++) {
          db.documents['notifications/n$i'] = _notification(
            userId: broadcast ? '' : 'field',
          );
        }
        final service = NotificationService(firestore: db);
        await expectLater(
          service.markAllAsRead(userId: 'field', role: _role),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('batas baca'),
            ),
          ),
        );
        expect(db.documents.values.every((d) => d['isRead'] == false), true);
        expect(
          db.documents.keys.any((p) => p.startsWith('notification_receipts/')),
          false,
        );
      },
    );
  }
}
