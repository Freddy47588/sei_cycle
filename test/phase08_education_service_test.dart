import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sei_cycle/features/education/models/education_content.dart';
import 'package:sei_cycle/features/education/services/education_service.dart';

import 'support/memory_firestore.dart';

void main() {
  for (final type in EducationType.values) {
    test(
      '$type create, edit, publish, archive and soft delete keep audit',
      () async {
        final db = MemoryFirestore();
        final service = EducationService(firestore: db);
        Future<String> save({String? id, String title = 'Materi'}) =>
            service.save(
              id: id,
              requestId: 'stable-$type',
              title: title,
              type: type,
              content: 'Langkah pertama\nLangkah kedua',
              externalUrl: 'https://example.test/tutorial',
              status: EducationStatus.draft,
              moduleType: 'lele',
              category: 'Panduan',
              tags: const ['Budidaya'],
              toolsNeeded: const ['Sarung tangan'],
              safetyNotes: 'Gunakan alat dengan aman.',
              duration: '05:00',
              thumbnailUrl: 'https://example.test/thumbnail.png',
              userId: 'admin',
            );
        final id = await save();
        expect(id, 'stable-$type');
        expect((await service.getById(id))?.tags, ['Budidaya']);
        expect(
          (await service.watchContents(includeDrafts: false).first),
          isEmpty,
        );
        await save(id: id, title: 'Materi diperbarui');
        expect((await service.getById(id))?.title, 'Materi diperbarui');
        await service.updateStatus(
          id,
          status: EducationStatus.published,
          userId: 'admin',
        );
        expect(
          (await service.watchContents(includeDrafts: false).first).single.id,
          id,
        );
        await service.updateStatus(
          id,
          status: EducationStatus.archived,
          userId: 'admin',
        );
        expect(
          await service.watchContents(includeDrafts: false).first,
          isEmpty,
        );
        await service.delete(id, userId: 'admin');
        expect(await service.watchContents(includeDrafts: true).first, isEmpty);
        final audits = db.documents.entries
            .where((entry) => entry.key.startsWith('education_edits/'))
            .toList();
        expect(audits, hasLength(5));
        expect(audits.last.value['operation'], 'softDelete');
        expect((audits.last.value['before'] as Map)['isDeleted'], false);
        expect((audits.last.value['after'] as Map)['isDeleted'], true);
      },
    );

    test(
      '$type retry after committed response failure creates one receipt',
      () async {
        final db = MemoryFirestore()..denyNextCommittedWrite = true;
        final service = EducationService(firestore: db);
        Future<String> save({String title = 'Materi'}) => service.save(
          requestId: 'retry-$type',
          title: title,
          type: type,
          content: 'Isi atau langkah terverifikasi',
          externalUrl: 'https://example.test/tutorial',
          tags: const ['Tag'],
          status: EducationStatus.draft,
          userId: 'admin',
        );
        await expectLater(save(), throwsA(isA<FirebaseException>()));
        final before = Map<String, dynamic>.from(
          db.documents['education_contents/retry-$type']!,
        );
        expect(await save(), 'retry-$type');
        expect(db.documents['education_contents/retry-$type'], before);
        expect(
          db.documents.keys.where(
            (path) => path.startsWith('education_edits/'),
          ),
          hasLength(1),
        );
        await expectLater(save(title: 'Permintaan berbeda'), throwsStateError);
        expect(db.documents['education_contents/retry-$type'], before);
        expect(
          db.documents.keys.where(
            (path) => path.startsWith('education_edits/'),
          ),
          hasLength(1),
        );
      },
    );
  }

  test(
    'failed education commit retains original content and audit count',
    () async {
      final db = MemoryFirestore();
      final service = EducationService(firestore: db);
      final id = await service.save(
        title: 'Awal',
        type: 'artikel',
        content: 'Isi',
        status: 'draft',
        userId: 'admin',
      );
      final before = Map<String, dynamic>.from(
        db.documents['education_contents/$id']!,
      );
      db.failCommit = true;
      await expectLater(service.delete(id, userId: 'admin'), throwsStateError);
      expect(db.documents['education_contents/$id'], before);
      expect(
        db.documents.keys.where((path) => path.startsWith('education_edits/')),
        hasLength(1),
      );
    },
  );

  test('education create rejects path-like retry IDs before a write', () async {
    final db = MemoryFirestore();
    final service = EducationService(firestore: db);
    await expectLater(
      service.save(
        title: 'Materi',
        type: 'artikel',
        content: 'Isi',
        status: 'draft',
        userId: 'admin',
        requestId: 'nested/path',
      ),
      throwsArgumentError,
    );
    expect(db.documents, isEmpty);
  });
}
