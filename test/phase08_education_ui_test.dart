import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sei_cycle/features/education/models/education_content.dart';
import 'package:sei_cycle/features/education/screen/education_screen.dart';
import 'package:sei_cycle/features/education/services/education_service.dart';
import 'package:sei_cycle/features/profile/models/app_user.dart';
import 'package:sei_cycle/theme/app_theme.dart';

import 'support/memory_firestore.dart';

AppUser _profile([String role = 'admin']) => AppUser(
  uid: 'admin-fixture',
  name: 'Tim',
  email: '',
  photoUrl: '',
  role: role,
  isActive: true,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

class _BlockingFirestore extends MemoryFirestore {
  Completer<void>? pending;
  int writes = 0;
  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    writes++;
    await pending?.future;
    return super.runTransaction(
      transactionHandler,
      timeout: timeout,
      maxAttempts: maxAttempts,
    );
  }
}

Future<void> _pump(
  WidgetTester tester,
  MemoryFirestore db, {
  double width = 393,
  double textScale = 1,
  String role = 'admin',
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: EducationScreen(
          profile: _profile(role),
          educationService: EducationService(firestore: db),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _field(String name) => find.byKey(ValueKey('education-$name'));

Future<void> _enter(WidgetTester tester, String name, String text) async {
  await tester.ensureVisible(_field(name));
  await tester.enterText(_field(name), text);
  await tester.pumpAndSettle();
}

Future<void> _select(WidgetTester tester, String name, String label) async {
  await tester.ensureVisible(_field(name));
  await tester.tap(_field(name));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Iterable<MapEntry<String, Map<String, dynamic>>> _contents(
  MemoryFirestore db,
) => db.documents.entries.where(
  (entry) => entry.key.startsWith('education_contents/'),
);

Future<void> _openNew(WidgetTester tester) async {
  await tester.tap(find.text('Tambah konten'));
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.text('Simpan'));
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [320.0, 360.0, 393.0, 768.0, 1280.0]) {
    for (final type in EducationType.values) {
      testWidgets(
        'Admin creates $type at $width enlarged text using real service',
        (tester) async {
          final db = MemoryFirestore();
          await _pump(tester, db, width: width, textScale: 1.4);
          await _openNew(tester);
          await _enter(tester, 'title', 'Panduan $type');
          await _select(tester, 'type', EducationType.label(type));
          await _select(tester, 'module', 'Cacing Tanah');
          await _enter(
            tester,
            'content',
            type == 'sop'
                ? 'Siapkan alat\nBersihkan area'
                : 'Isi materi terverifikasi',
          );
          if (type == 'video') {
            await _enter(tester, 'url', 'https://example.test/panduan');
          }
          await _select(tester, 'status', 'Terbit');
          await _save(tester);
          expect(find.text('Tambah Edukasi'), findsNothing);
          expect(_contents(db), hasLength(1));
          final saved = _contents(db).single.value;
          expect(saved['title'], 'Panduan $type');
          expect(saved['type'], type);
          expect(saved['status'], 'published');
          expect(saved['moduleType'], 'cacing_tanah');
          if (type == 'sop') {
            expect(saved['steps'], ['Siapkan alat', 'Bersihkan area']);
          } else if (type == 'video') {
            expect(saved['externalVideoUrl'], 'https://example.test/panduan');
          }
          expect(find.text('Panduan $type'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'save failure retains draft; lost acknowledgement retry creates one record',
    (tester) async {
      final db = MemoryFirestore()..commitThenDeny = true;
      await _pump(tester, db);
      await _openNew(tester);
      await _enter(tester, 'title', 'Materi tetap tersimpan');
      await _enter(tester, 'content', 'Jangan hilangkan tulisan ini');
      await _save(tester);
      expect(find.text('Tambah Edukasi'), findsOneWidget);
      expect(find.textContaining('Konten gagal disimpan:'), findsOneWidget);
      expect(find.text('Materi tetap tersimpan'), findsOneWidget);
      expect(find.text('Jangan hilangkan tulisan ini'), findsOneWidget);
      expect(_contents(db), hasLength(1));
      db.commitThenDeny = false;
      await _save(tester);
      expect(find.text('Tambah Edukasi'), findsNothing);
      expect(_contents(db), hasLength(1));
      expect(
        db.documents.keys.where((key) => key.startsWith('education_edits/')),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'busy save prevents duplicate taps, cancellation, and back dismissal',
    (tester) async {
      final db = _BlockingFirestore()..pending = Completer<void>();
      await _pump(tester, db);
      await _openNew(tester);
      await _enter(tester, 'title', 'Simpan sekali');
      await _enter(tester, 'content', 'Materi');
      await tester.tap(find.text('Simpan'));
      await tester.pump();
      expect(find.text('Menyimpan...'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Menyimpan...'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Batal'))
            .onPressed,
        isNull,
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Tambah Edukasi'), findsOneWidget);
      expect(db.writes, 1);
      db.pending!.complete();
      await tester.pumpAndSettle();
      expect(_contents(db), hasLength(1));
      expect(find.text('Tambah Edukasi'), findsNothing);
    },
  );

  testWidgets(
    'narrow keyboard form keeps save reachable and validates video URL',
    (tester) async {
      final db = MemoryFirestore();
      await _pump(tester, db, width: 320, textScale: 1.4);
      await _openNew(tester);
      await _save(tester);
      expect(find.text('Wajib diisi'), findsNWidgets(2));
      await _enter(tester, 'title', 'Video aman');
      await _select(tester, 'type', 'Video');
      await _enter(tester, 'content', 'Deskripsi panduan');
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await _enter(tester, 'url', 'javascript:alert(1)');
      expect(find.text('Simpan').hitTestable(), findsOneWidget);
      await _save(tester);
      expect(find.text('Masukkan URL video HTTPS yang valid.'), findsOneWidget);
      expect(_contents(db), isEmpty);
      await _enter(tester, 'url', 'https://example.test/video');
      await _save(tester);
      expect(_contents(db), hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  for (final type in EducationType.values) {
    testWidgets(
      'Admin edits $type without clearing hidden metadata, then cancels/confirms delete',
      (tester) async {
        final db = MemoryFirestore();
        final content = EducationContent(
          id: 'existing',
          title: 'Materi awal',
          type: type,
          status: 'draft',
          moduleType: 'lele',
          category: 'Keselamatan',
          tags: const ['budidaya', 'aman'],
          authorId: 'admin-fixture',
          createdBy: 'admin-fixture',
          updatedBy: 'admin-fixture',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          isDeleted: false,
          content: 'Isi awal',
          summary: 'Ringkasan awal',
          thumbnailUrl: 'https://example.test/thumbnail.png',
          externalVideoUrl: 'https://example.test/video',
          duration: '12 menit',
          steps: const ['Langkah pertama', 'Langkah kedua'],
          toolsNeeded: const ['Sarung tangan', 'Ember'],
          safetyNotes: 'Cuci tangan setelah bekerja.',
        );
        db.documents['education_contents/existing'] = content.toFirestore();
        await _pump(tester, db, width: 393, textScale: 1.4);
        await tester.ensureVisible(find.byTooltip('Opsi konten'));
        await tester.tap(find.byTooltip('Opsi konten'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit konten'));
        await tester.pumpAndSettle();
        await _enter(tester, 'title', 'Materi diperbarui');
        await _select(tester, 'module', 'Tanaman');
        await _select(tester, 'status', 'Diarsipkan');
        await _save(tester);
        expect(find.text('Edit Edukasi'), findsNothing);
        final saved = db.documents['education_contents/existing']!;
        expect(saved['title'], 'Materi diperbarui');
        expect(saved['moduleType'], 'tanaman');
        expect(saved['status'], 'archived');
        expect(saved['category'], content.category);
        expect(saved['tags'], content.tags);
        expect(saved['thumbnailUrl'], content.thumbnailUrl);
        expect(saved['duration'], content.duration);
        expect(saved['toolsNeeded'], content.toolsNeeded);
        expect(saved['safetyNotes'], content.safetyNotes);
        await tester.ensureVisible(find.byTooltip('Opsi konten'));
        await tester.tap(find.byTooltip('Opsi konten'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Hapus konten'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Batal'));
        await tester.pumpAndSettle();
        expect(
          db.documents['education_contents/existing']!['isDeleted'],
          false,
        );
        await tester.tap(find.byTooltip('Opsi konten'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Hapus konten'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Hapus').last);
        await tester.pumpAndSettle();
        expect(db.documents['education_contents/existing']!['isDeleted'], true);
        expect(find.text('Materi diperbarui'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('non-admin has no create edit or delete controls', (
    tester,
  ) async {
    final db = MemoryFirestore();
    await EducationService(firestore: db).save(
      title: 'Panduan terbit',
      type: EducationType.article,
      content: 'Materi untuk semua pengguna aktif',
      status: EducationStatus.published,
      userId: 'admin-fixture',
    );
    await _pump(tester, db, role: 'operator_lapangan');
    expect(find.text('Panduan terbit'), findsOneWidget);
    expect(find.text('Tambah konten'), findsNothing);
    expect(find.byTooltip('Opsi konten'), findsNothing);
  });
}
