import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sei_cycle/core/models/firestore_page.dart';
import 'package:sei_cycle/core/widgets/firestore_paged_list.dart';

void main() {
  testWidgets(
    'live deletion or seed isolation removes a row from its loaded page',
    (tester) async {
      final updates = StreamController<List<int>>.broadcast();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FirestorePagedList<int>(
              queryKey: 'inventory',
              idOf: (value) => '$value',
              watchPage: (_) => updates.stream,
              load: (_) async => const FirestorePage([1, 2], null, false),
              itemBuilder: (value) => Text('Record $value'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(updates.hasListener, true);
      updates.add([2]);
      await tester.pumpAndSettle();
      expect(find.text('Record 1'), findsNothing);
      expect(find.text('Record 2'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(updates.hasListener, false);
      await updates.close();
    },
  );
  testWidgets(
    'failed first page with filters never renders a false empty count; retry preserves filters',
    (tester) async {
      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FirestorePagedList<int>(
              queryKey: 'finance',
              header: const TextField(
                decoration: InputDecoration(labelText: 'Filter'),
              ),
              load: (_) async {
                if (++attempts == 1) {
                  throw FirebaseException(
                    plugin: 'cloud_firestore',
                    code: 'permission-denied',
                  );
                }
                return const FirestorePage([1], null, false);
              },
              itemBuilder: (value) => Text('Record $value'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('ditampilkan dari'), findsNothing);
      expect(find.textContaining('Belum ada data yang sesuai'), findsNothing);
      expect(find.textContaining('Akses ditolak'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'kept');
      await tester.tap(find.text('Coba lagi'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(find.text('kept'), findsOneWidget);
      expect(find.text('Record 1'), findsOneWidget);
      expect(find.textContaining('1 ditampilkan dari 1'), findsOneWidget);
      expect(find.textContaining('Akses ditolak'), findsNothing);
    },
  );
}
