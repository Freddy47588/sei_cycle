import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sei_cycle/app/app_shell.dart';
import 'package:sei_cycle/features/circular_flow/screen/circular_flow_screen.dart';
import 'package:sei_cycle/features/circular_flow/services/circular_flow_service.dart';
import 'package:sei_cycle/features/finance/screen/finance_screen.dart';
import 'package:sei_cycle/features/finance/services/finance_service.dart';
import 'package:sei_cycle/features/profile/models/app_user.dart';
import 'package:sei_cycle/features/inventory/models/inventory_item.dart';
import 'package:sei_cycle/features/logbook/screen/logbook_screen.dart';
import 'package:sei_cycle/features/logbook/services/logbook_service.dart';
import 'package:sei_cycle/features/profile/screen/profile_screen.dart';
import 'package:sei_cycle/features/sales/screen/sales_screen.dart';
import 'package:sei_cycle/features/sales/services/sales_service.dart';
import 'package:sei_cycle/features/sales/models/sale.dart';
import 'package:sei_cycle/theme/app_theme.dart';
import 'phase03_batch_ui_test.dart' show batchDoc;
import 'phase06_services_test.dart' show user, seedHarvest, saleInput;
import 'support/memory_firestore.dart';

const capture = bool.fromEnvironment('CAPTURE_UI');
final boundary = GlobalKey();

class ControlledFinance extends FinanceService {
  ControlledFinance(MemoryFirestore db) : super(firestore: db);
  Completer<void>? pending;
  bool fail = true;
  final requests = <String?>[];
  @override
  Future<void> save({
    String? id,
    String? requestId,
    DateTime? expectedUpdatedAt,
    required String type,
    required String category,
    required double amount,
    required DateTime date,
    required String note,
    String paymentMethod = '',
    String moduleType = '',
    required String userId,
  }) async {
    requests.add(requestId);
    if (pending != null) await pending!.future;
    if (fail) {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
    return super.save(
      id: id,
      requestId: requestId,
      expectedUpdatedAt: expectedUpdatedAt,
      type: type,
      category: category,
      amount: amount,
      date: date,
      note: note,
      paymentMethod: paymentMethod,
      moduleType: moduleType,
      userId: userId,
    );
  }
}

Future<void> pump(
  WidgetTester t,
  Widget page, {
  double width = 360,
  double keyboard = 0,
}) async {
  t.view.physicalSize = Size(width, 900);
  t.view.devicePixelRatio = 1;
  t.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  addTearDown(t.view.resetViewInsets);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(1.4)),
        child: RepaintBoundary(key: boundary, child: child!),
      ),
      home: Scaffold(body: page),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> dialog(
  WidgetTester t,
  Widget form, {
  double width = 360,
  double keyboard = 0,
}) async {
  await pump(
    t,
    Builder(
      builder: (context) => FilledButton(
        onPressed: () => showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => form,
        ),
        child: const Text('Buka Form'),
      ),
    ),
    width: width,
    keyboard: keyboard,
  );
  await t.tap(find.text('Buka Form'));
  await t.pumpAndSettle();
}

Future<void> shot(WidgetTester t, String name) async {
  if (!capture) return;
  await t.runAsync(() async {
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await render.toImage();
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/phase06/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    img.dispose();
  });
}

void main() {
  testWidgets(
    'sales filter input and expansion survive scrolling a long paged list',
    (t) async {
      final db = MemoryFirestore();
      seedHarvest(db, stock: 200);
      final service = SalesService(firestore: db);
      for (var i = 0; i < 22; i++) {
        await service.create(
          requestId: 'sale-$i',
          userId: 'field',
          input: saleInput(),
        );
      }
      await pump(t, SalesScreen(profile: user('admin'), service: service));
      await t.tap(find.byType(ExpansionTile));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'Lele');
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Muat berikutnya'),
        500,
        maxScrolls: 30,
        scrollable: find.byType(Scrollable).first,
      );
      await t.drag(find.byType(ListView), const Offset(0, 20000));
      await t.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(
        t.widget<EditableText>(find.byType(EditableText)).controller.text,
        'Lele',
      );
      expect(t.takeException(), isNull);
    },
  );
  setUpAll(() async {
    await initializeDateFormatting('id_ID');
    if (capture) {
      final root = Platform.environment['FLUTTER_ROOT'];
      if (root == null) return;
      for (final (family, file) in [
        ('Roboto', 'Roboto-Regular.ttf'),
        ('Ahem', 'Roboto-Regular.ttf'),
        ('MaterialIcons', 'materialicons-regular.otf'),
      ]) {
        final f = File('$root/bin/cache/artifacts/material_fonts/$file');
        if (f.existsSync()) {
          await (FontLoader(family)..addFont(
                Future.value(ByteData.sublistView(f.readAsBytesSync())),
              ))
              .load();
        }
      }
    }
  });
  for (final width in [320.0, 360.0, 393.0, 768.0, 1280.0]) {
    testWidgets('paid sale quantities money and detail fit $width', (t) async {
      final db = MemoryFirestore();
      seedHarvest(db);
      final service = SalesService(firestore: db);
      await service.create(
        requestId: 'receipt',
        userId: 'field',
        input: saleInput(),
      );
      await pump(
        t,
        SalesScreen(profile: user('admin'), service: service),
        width: width,
      );
      expect(find.text('Lele Panen'), findsOneWidget);
      expect(t.takeException(), isNull);
      await shot(t, 'sales-record-${width.toInt()}');
      final sale = Sale.fromDocument(
        await db.collection('sales').doc('receipt').get(),
      );
      await pump(
        t,
        SaleDetailScreen(sale: sale, profile: user('admin')),
        width: width,
      );
      expect(t.takeException(), isNull);
      expect(find.textContaining('Lunas'), findsOneWidget);
      await shot(t, 'sales-detail-${width.toInt()}');
    });
    for (final page in ['finance', 'sales', 'flow', 'profile']) {
      testWidgets('$page fits $width at text scale 1.4', (t) async {
        final db = MemoryFirestore();
        seedHarvest(db);
        final widget = switch (page) {
          'finance' => FinanceScreen(
            profile: user('admin'),
            service: FinanceService(firestore: db),
          ),
          'sales' => SalesScreen(
            profile: user('admin'),
            service: SalesService(firestore: db),
          ),
          'flow' => CircularFlowScreen(
            profile: user('admin'),
            service: CircularFlowService(firestore: db),
          ),
          _ => ProfileScreen(profile: user('admin')),
        };
        await pump(t, widget, width: width);
        expect(t.takeException(), isNull);
        expect(find.text('Seed sampel'), findsNothing);
        expect(find.text('Hapus sampel'), findsNothing);
        await shot(t, '$page-${width.toInt()}');
        if (page == 'profile') {
          await t.scrollUntilVisible(
            find.text('Siapkan modul'),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.text('Siapkan modul'), findsOneWidget);
        } else {
          await t.tap(find.byType(ExpansionTile));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          await shot(t, '$page-filters-${width.toInt()}');
        }
      });
    }
    for (final form in ['finance', 'sale', 'flow']) {
      testWidgets('$form form fits $width at text scale 1.4', (t) async {
        final db = MemoryFirestore();
        seedHarvest(db);
        final product = InventoryItem.fromDocument(
          await db.collection('inventory').doc('harvest').get(),
        );
        await dialog(t, switch (form) {
          'finance' => FinanceFormDialog(
            service: FinanceService(firestore: db),
            userId: 'field',
          ),
          'sale' => SaleForm(
            service: SalesService(firestore: db),
            userId: 'field',
            initialProduct: product,
          ),
          _ => CircularFlowForm(
            service: CircularFlowService(firestore: db),
            userId: 'field',
          ),
        }, width: width);
        expect(t.takeException(), isNull);
        await shot(t, '$form-form-${width.toInt()}');
        final save = find.text(
          form == 'finance'
              ? 'Simpan'
              : form == 'sale'
              ? 'Simpan Penjualan'
              : 'Simpan Aliran',
        );
        expect(save, findsOneWidget);
        expect(t.getRect(save).bottom, lessThanOrEqualTo(900));
      });
    }
  }
  testWidgets(
    'finance save failure preserves fields, pending blocks double submit, retry reuses ID',
    (t) async {
      final db = MemoryFirestore();
      seedHarvest(db);
      final service = ControlledFinance(db);
      service.pending = Completer<void>();
      await dialog(t, FinanceFormDialog(service: service, userId: 'field'));
      await t.enterText(
        find.widgetWithText(TextFormField, 'Kategori'),
        'Pakan',
      );
      await t.enterText(find.widgetWithText(TextFormField, 'Nominal'), '50000');
      await t.tap(find.text('Simpan'));
      await t.pump();
      expect(find.text('Menyimpan...'), findsOneWidget);
      await t.tap(find.text('Menyimpan...'));
      await t.pump();
      expect(service.requests, hasLength(1));
      service.pending!.complete();
      await t.pumpAndSettle();
      expect(find.textContaining('Koneksi terputus'), findsOneWidget);
      expect(find.text('Pakan'), findsOneWidget);
      expect(find.text('50000'), findsOneWidget);
      service.pending = null;
      service.fail = false;
      await t.tap(find.text('Simpan'));
      await t.pumpAndSettle();
      expect(find.byType(FinanceFormDialog), findsNothing);
      expect(service.requests, hasLength(2));
      expect(service.requests[0], service.requests[1]);
      expect(
        db.documents.keys.where((k) => k.startsWith('finance_transactions/')),
        hasLength(1),
      );
    },
  );
  testWidgets('finance invalid nominal stays in form without writes', (
    t,
  ) async {
    final db = MemoryFirestore();
    seedHarvest(db);
    final service = ControlledFinance(db);
    await dialog(t, FinanceFormDialog(service: service, userId: 'field'));
    await t.enterText(find.widgetWithText(TextFormField, 'Kategori'), 'Pakan');
    await t.enterText(
      find.widgetWithText(TextFormField, 'Nominal'),
      'Infinity',
    );
    await t.tap(find.text('Simpan'));
    await t.pumpAndSettle();
    expect(service.requests, isEmpty);
    expect(find.byType(FinanceFormDialog), findsOneWidget);
  });
  testWidgets('finance keyboard leaves save reachable on 320px', (t) async {
    final db = MemoryFirestore();
    seedHarvest(db);
    await dialog(
      t,
      FinanceFormDialog(
        service: FinanceService(firestore: db),
        userId: 'field',
      ),
      width: 320,
      keyboard: 320,
    );
    expect(t.takeException(), isNull);
    expect(t.getRect(find.text('Simpan')).bottom, lessThanOrEqualTo(580));
  });
  testWidgets('sale-linked finance row hides manual edit and deletion', (
    t,
  ) async {
    final db = MemoryFirestore();
    seedHarvest(db);
    db.documents['finance_transactions/linked'] = {
      'id': 'linked',
      'saleId': 'receipt',
      'type': 'income',
      'category': 'Penjualan',
      'amount': 125000,
      'date': Timestamp.fromDate(DateTime.now()),
      'isDeleted': false,
    };
    await pump(
      t,
      FinanceScreen(
        profile: user('admin'),
        service: FinanceService(firestore: db),
      ),
    );
    await t.scrollUntilVisible(
      find.text('Penjualan'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byTooltip('Edit transaksi'), findsNothing);
    expect(find.byTooltip('Hapus transaksi'), findsNothing);
  });
  for (final role in ['operator_lapangan', 'mitra', 'peserta_edukasi']) {
    testWidgets('$role cannot query finance sales screens', (t) async {
      final db = MemoryFirestore();
      await pump(
        t,
        FinanceScreen(
          profile: user(role),
          service: FinanceService(firestore: db),
        ),
      );
      await pump(
        t,
        SalesScreen(
          profile: user(role),
          service: SalesService(firestore: db),
        ),
      );
      expect(db.queries, isEmpty);
    });
  }
  testWidgets(
    'shell preserves Logbook date batch slider and text across main navigation, account clears draft',
    (t) async {
      final db = MemoryFirestore();
      seedHarvest(db);
      db.documents['batches/AYAM-A'] = batchDoc(
        'AYAM-A',
        module: 'ayam_kampung',
      );
      Widget shell(String uid) {
        final p = user('admin');
        return AppShell(
          profile: uid == 'field'
              ? p
              : AppUser(
                  uid: uid,
                  name: 'Baru',
                  email: '',
                  photoUrl: '',
                  role: 'admin',
                  isActive: true,
                  createdAt: DateTime(2026),
                  updatedAt: DateTime(2026),
                ),
          unreadCountStream: Stream.value(0),
          pageBuilder: (name) => name == 'Logbook'
              ? LogbookScreen(
                  profile: p,
                  service: LogbookService(firestore: db),
                )
              : Text('Halaman $name'),
        );
      }

      await pump(t, shell('field'));
      await t.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Logbook'),
        ),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Pilih batch ayam yang aktif'));
      await t.pumpAndSettle();
      await t.tap(find.text('Pilih batch ayam yang aktif'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Pilih Batch'));
      await t.pumpAndSettle();
      await t.tap(find.text('Pilih Batch'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextFormField).first, '17');
      final sliders = find.byType(Slider);
      await t.ensureVisible(sliders.first);
      await t.pumpAndSettle();
      final slider = t.widget<Slider>(sliders.first);
      slider.onChanged!((slider.min + slider.max) / 2);
      await t.pumpAndSettle();
      final values = t
          .widgetList<TextFormField>(find.byType(TextFormField))
          .map((f) => f.controller?.text ?? f.initialValue)
          .toList();
      final storedSlider = t.widget<Slider>(find.byType(Slider).first).value;
      for (final name in ['Dashboard', 'Notifikasi']) {
        await t.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(name),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text('Logbook'),
          ),
        );
        await t.pumpAndSettle();
        expect(
          t
              .widgetList<TextFormField>(find.byType(TextFormField))
              .map((f) => f.controller?.text ?? f.initialValue)
              .toList(),
          values,
        );
        expect(t.widget<Slider>(find.byType(Slider).first).value, storedSlider);
        expect(find.text('Siklus AYAM-A (AYAM-A)'), findsOneWidget);
      }
      expect(
        db.documents.keys.where((k) => k.startsWith('logbooks/')),
        isEmpty,
      );
      await pump(t, shell('new-account'));
      await t.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Logbook'),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('17'), findsNothing);
      expect(find.text('Siklus AYAM-A (AYAM-A)'), findsNothing);
    },
  );
}
