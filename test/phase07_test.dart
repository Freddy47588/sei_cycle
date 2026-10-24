import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sei_cycle/features/auth/screen/login_screen.dart';
import 'package:sei_cycle/features/auth/screen/register_screen.dart';
import 'package:sei_cycle/features/auth/services/auth_service.dart';
import 'package:sei_cycle/features/profile/services/user_profile_service.dart';
import 'package:sei_cycle/features/profile/models/app_user.dart';
import 'package:sei_cycle/features/education/models/education_content.dart';
import 'package:sei_cycle/features/education/services/education_service.dart';
import 'package:sei_cycle/features/education/screen/education_screen.dart';
import 'package:sei_cycle/features/recommendations/services/recommendation_service.dart';
import 'package:sei_cycle/features/admin/screen/admin_management_screen.dart';
import 'package:sei_cycle/features/admin/services/admin_management_service.dart';
import 'package:sei_cycle/core/widgets/operational_reference_screen.dart';
import 'package:sei_cycle/theme/app_theme.dart';
import 'package:sei_cycle/core/utils/legacy_firestore.dart';
import 'support/memory_firestore.dart';

class _Auth implements FirebaseAuth {
  String? error, email, password;
  int loginCalls = 0;
  Completer<void>? pending;
  final _events = StreamController<User?>.broadcast();
  User? _user;
  @override
  User? get currentUser => _user;
  @override
  Stream<User?> authStateChanges() => _events.stream;
  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    loginCalls++;
    this.email = email;
    this.password = password;
    if (pending != null) await pending!.future;
    if (error != null) throw FirebaseAuthException(code: error!);
    _user = _User();
    _events.add(_user);
    return _Credential(_user!);
  }

  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) => signInWithEmailAndPassword(email: email, password: password);
  @override
  Future<void> signOut() async {
    _user = null;
    _events.add(null);
  }

  @override
  Future<void> sendPasswordResetEmail({
    required String email,
    ActionCodeSettings? actionCodeSettings,
  }) async {
    this.email = email;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _User implements User {
  String? name;
  @override
  String get uid => 'fixture-user';
  @override
  Future<void> updateDisplayName(String? displayName) async {
    name = displayName;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Credential implements UserCredential {
  _Credential(this.user);
  @override
  final User user;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Profiles extends UserProfileService {
  _Profiles() : super(firestore: MemoryFirestore());
  int synchronized = 0;
  @override
  Future<void> ensureUserDocument(User user, {String? name}) async {
    synchronized++;
  }
}

AppUser user(String role, {bool active = true}) => AppUser(
  uid: 'fixture-user',
  name: 'Tim',
  email: '',
  photoUrl: '',
  role: role,
  isActive: active,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);
EducationContent content(String status, {String type = 'artikel'}) =>
    EducationContent(
      id: status,
      title: 'Materi $status',
      type: type,
      status: status,
      moduleType: '',
      category: '',
      tags: const [],
      authorId: 'admin',
      createdBy: 'admin',
      updatedBy: 'admin',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      isDeleted: false,
      content: 'Isi materi lengkap yang dapat dibaca.',
    );

void main() {
  test(
    'education save and delete keep atomic audit; stale editor cannot overwrite a newer version',
    () async {
      final db = MemoryFirestore();
      final service = EducationService(firestore: db);
      final id = await service.save(
        title: 'Materi',
        type: 'artikel',
        content: 'Isi terverifikasi',
        status: 'draft',
        userId: 'admin',
      );
      expect(
        db.documents.keys.where((p) => p.startsWith('education_edits/')).length,
        1,
      );
      final before = Map<String, dynamic>.from(
        db.documents['education_contents/$id']!,
      );
      await expectLater(
        service.save(
          id: id,
          expectedUpdatedAt: DateTime(2000),
          title: 'Stale',
          type: 'artikel',
          content: 'Isi lama',
          status: 'draft',
          userId: 'admin',
        ),
        throwsStateError,
      );
      expect(db.documents['education_contents/$id'], before);
      db.failCommit = true;
      await expectLater(service.delete(id, userId: 'admin'), throwsStateError);
      expect(db.documents['education_contents/$id']?['isDeleted'], false);
      db.failCommit = false;
      await service.delete(id, userId: 'admin');
      expect(db.documents['education_contents/$id']?['isDeleted'], true);
      expect(
        db.documents.keys.where((p) => p.startsWith('education_edits/')).length,
        2,
      );
    },
  );

  for (final confirm in [false, true]) {
    testWidgets(
      'Admin delete preview requires explicit confirmation: $confirm',
      (tester) async {
        final memory = MemoryFirestore();
        memory.documents['batches/EMPTY'] = {
          'name': 'Batch kosong',
          'status': 'planned',
        };
        final service = _AdminService(memory);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: AdminManagementScreen(
                profile: user('admin'),
                service: service,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Lihat dan kelola'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit / koreksi metadata'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.text('Hapus permanen (setelah dependensi selesai)').last,
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Alasan tindakan Admin (wajib)'),
          'Batch salah dibuat',
        );
        await tester.ensureVisible(find.text('Periksa dampak'));
        await tester.tap(find.text('Periksa dampak'));
        await tester.pumpAndSettle();
        expect(service.previews, 1);
        expect(service.executions, 0);
        expect(find.text('batches/EMPTY'), findsWidgets);
        await tester.tap(
          find.text(confirm ? 'Konfirmasi tindakan' : 'Batal').last,
        );
        await tester.pumpAndSettle();
        expect(service.executions, confirm ? 1 : 0);
        expect(memory.documents.containsKey('batches/EMPTY'), !confirm);
        expect(tester.takeException(), isNull);
      },
    );
  }

  test(
    'cancellation excludes totals while reversed ledger history remains readable',
    () async {
      expect(
        isOperationalRecord({'status': 'cancelled', 'adminReversed': true}),
        false,
      );
      expect(
        isOperationalRecord({'adminReversed': true, 'isReversed': true}),
        true,
      );
      final db = MemoryFirestore();
      db.documents['inventory_transactions/old'] = {
        'itemId': 'retired',
        'logbookId': 'removed',
        'adminReversed': true,
        'isReversed': true,
      };
      await OperationalIntegrity(
        db,
      ).check((await db.collection('inventory_transactions').get()).docs);
      db.documents['inventory_transactions/bad'] = {
        'itemId': 'retired',
        'logbookId': 'missing',
        'isReversed': false,
      };
      await expectLater(
        OperationalIntegrity(
          db,
        ).check((await db.collection('inventory_transactions').get()).docs),
        throwsStateError,
      );
    },
  );

  setUpAll(() => initializeDateFormatting('id_ID'));
  test(
    'email login, profile sync, registration, persistence stream and logout keep identity',
    () async {
      final auth = _Auth(), profiles = _Profiles();
      final service = AuthService(auth: auth, userProfileService: profiles);
      await service.signInWithEmailAndPassword(
        email: '  operator@example.test ',
        password: 'rahasia',
      );
      expect(auth.email, 'operator@example.test');
      expect(profiles.synchronized, 1);
      expect(service.currentUser?.uid, 'fixture-user');
      final event = service.authStateChanges.first;
      await service.signOut();
      expect(await event, isNull);
      expect(service.currentUser, isNull);
      await service.registerWithEmailAndPassword(
        name: ' Tim ',
        email: 'new@example.test',
        password: 'rahasia',
      );
      expect((service.currentUser as _User).name, 'Tim');
      expect(profiles.synchronized, 2);
    },
  );
  for (final code in [
    'invalid-credential',
    'invalid-email',
    'user-disabled',
    'network-request-failed',
  ]) {
    testWidgets('email login surfaces $code without Google entry point', (
      tester,
    ) async {
      final auth = _Auth()..error = code;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: LoginScreen(
            authService: AuthService(
              auth: auth,
              userProfileService: _Profiles(),
            ),
          ),
        ),
      );
      expect(find.text('Masuk dengan Google'), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'user@example.test',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'rahasia',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Masuk'));
      await tester.pumpAndSettle();
      expect(auth.loginCalls, 1);
      expect(serviceError(code), isNotEmpty);
      expect(find.text(serviceError(code)), findsOneWidget);
    });
  }
  testWidgets(
    'loading blocks duplicate submit and registration remains reachable',
    (tester) async {
      final auth = _Auth()..pending = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: LoginScreen(
            authService: AuthService(
              auth: auth,
              userProfileService: _Profiles(),
            ),
          ),
        ),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'user@example.test',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'rahasia',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Masuk'));
      await tester.pump();
      expect(find.text('Sedang masuk...'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(auth.loginCalls, 1);
      auth.pending!.complete();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Belum punya akun? Daftar di sini'));
      await tester.tap(find.text('Belum punya akun? Daftar di sini'));
      await tester.pumpAndSettle();
      expect(find.byType(RegisterScreen), findsOneWidget);
    },
  );
  testWidgets(
    'invalid email rejected before network; reset uses the existing account email',
    (tester) async {
      final auth = _Auth();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: LoginScreen(
            authService: AuthService(
              auth: auth,
              userProfileService: _Profiles(),
            ),
          ),
        ),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'invalid',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Masuk'));
      await tester.pumpAndSettle();
      expect(auth.loginCalls, 0);
      expect(find.text('Masukkan email yang valid.'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'existing@example.test',
      );
      await tester.ensureVisible(
        find.text('Lupa password / atur password akun lama'),
      );
      await tester.tap(find.text('Lupa password / atur password akun lama'));
      await tester.pumpAndSettle();
      expect(auth.email, 'existing@example.test');
      expect(auth.loginCalls, 0);
    },
  );
  test('education rejects executable URLs and blank SOP steps', () async {
    for (final url in [
      'javascript:alert(1)',
      'file:///private',
      'http://example.test',
      'https://u:p@example.test',
    ]) {
      expect(isSafeEducationUrl(url), false);
    }
    expect(isSafeEducationUrl('https://example.test/video'), true);
    final service = EducationService(firestore: MemoryFirestore());
    await expectLater(
      service.saveSop(
        title: 'Uji',
        moduleType: '',
        steps: ['  '],
        status: 'draft',
        userId: 'admin',
      ),
      throwsArgumentError,
    );
  });
  for (final width in [320.0, 360.0, 393.0, 768.0, 1280.0]) {
    testWidgets(
      'education reader at $width preserves publication visibility and no overflow',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: EducationScreen(
                profile: user('operator_lapangan'),
                contents: Stream.value([
                  content('published'),
                  content('draft'),
                  content('archived'),
                ]),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Materi draft'), findsNothing);
        expect(find.text('Materi archived'), findsNothing);
        await tester.tap(find.text('Materi published'));
        await tester.pumpAndSettle();
        expect(find.text('Materi edukasi'), findsOneWidget);
        expect(
          find.text('Isi materi lengkap yang dapat dibaca.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('inactive and non-admin cannot open management', (tester) async {
    for (final profile in [
      user('operator_lapangan'),
      user('admin', active: false),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AdminManagementScreen(profile: profile)),
        ),
      );
      await tester.pump();
      expect(find.text('Akses hanya untuk Admin aktif.'), findsOneWidget);
    }
  });
  test(
    'recommendations require recorded harvest dates and preserve priority/data honesty',
    () {
      final now = DateTime(2026, 10, 17);
      final recommendations = RecommendationService.generateFromData(
        logbooks: [],
        lowStockItems: [],
        overdueSchedules: [],
        financeRecords: [],
        includeFinance: false,
        now: now,
      );
      expect(
        recommendations.single.title,
        'Data belum cukup untuk menghasilkan rekomendasi yang akurat.',
      );
      for (final module in [
        'ayam_kampung',
        'maggot_bsf',
        'cacing_tanah',
        'tanaman',
        'lele',
      ]) {
        final list = RecommendationService.generateFromData(
          logbooks: [],
          lowStockItems: [],
          overdueSchedules: [],
          financeRecords: [],
          includeFinance: false,
          batches: [
            {
              'id': 'b',
              'moduleType': module,
              'status': 'active',
              'expectedHarvestAt': Timestamp.fromDate(
                now.add(const Duration(days: 2)),
              ),
            },
          ],
          now: now,
        );
        expect(list.single.type, 'harvest_prediction');
        expect(list.single.moduleType, module);
        expect(list.single.priority, 'medium');
        expect(list.single.recommendedAction, isNotEmpty);
      }
    },
  );
  test(
    'sample batches, deleted records, finance and unsafe references stay isolated',
    () {
      final result = RecommendationService.generateFromData(
        logbooks: [],
        lowStockItems: [],
        overdueSchedules: [],
        financeRecords: [],
        includeFinance: false,
        batches: [
          {'id': 'seed', 'status': 'active', 'createdBy': 'sample_seed'},
          {'id': 'deleted', 'status': 'active', 'isDeleted': true},
        ],
      );
      expect(result.single.id, 'rec_insufficient');
      expect(
        canOpenOperationalReference(
          user('operator_lapangan'),
          'finance_transactions',
          'cash',
        ),
        false,
      );
      expect(
        canOpenOperationalReference(user('admin'), 'users', 'person'),
        false,
      );
      expect(
        canOpenOperationalReference(user('admin'), 'logbooks', '../private'),
        false,
      );
    },
  );
  test(
    'source query failure remains a failure and finance is never fetched for field role',
    () async {
      final db = MemoryFirestore()
        ..queryErrors['batches'] = StateError('denied');
      await expectLater(
        RecommendationService(firestore: db).generate(includeFinance: false),
        throwsStateError,
      );
      expect(db.queries, isNot(contains('finance_transactions')));
    },
  );
}

String serviceError(String code) => const {
  'invalid-credential': 'Email atau password tidak valid.',
  'invalid-email': 'Format email tidak valid.',
  'user-disabled': 'Akun ini dinonaktifkan.',
  'network-request-failed': 'Tidak dapat terhubung ke internet.',
}[code]!;

class _AdminService extends AdminManagementService {
  _AdminService(this.memory) : super(firestore: memory, auth: _Auth());
  final MemoryFirestore memory;
  int previews = 0, executions = 0;
  @override
  Future<QuerySnapshot<Map<String, dynamic>>> page(
    String category, {
    DocumentSnapshot<Map<String, dynamic>>? after,
  }) => memory.collection(category).get();
  @override
  Future<Map<String, dynamic>> submit({
    required String requestId,
    required String kind,
    required String targetPath,
    required String operation,
    required String reason,
    Map<String, dynamic> patch = const {},
    String previewId = '',
  }) async {
    if (kind == 'preview') {
      previews++;
      return {
        'status': 'ready',
        'affected': [targetPath],
        'related': [],
        'consequences': 'Batch tanpa dependensi akan dihapus.',
      };
    }
    executions++;
    memory.documents.remove(targetPath);
    return {'status': 'succeeded'};
  }
}
