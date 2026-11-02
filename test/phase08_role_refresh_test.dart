import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sei_cycle/app/app_shell.dart';
import 'package:sei_cycle/features/auth/screen/auth_gate.dart';
import 'package:sei_cycle/features/auth/screen/login_screen.dart';
import 'package:sei_cycle/features/auth/services/auth_service.dart';
import 'package:sei_cycle/features/notification/models/app_notification.dart';
import 'package:sei_cycle/features/notification/screen/notification_screen.dart';
import 'package:sei_cycle/features/notification/services/notification_service.dart';
import 'package:sei_cycle/features/profile/models/app_user.dart';
import 'package:sei_cycle/features/profile/services/user_profile_service.dart';
import 'package:sei_cycle/theme/app_theme.dart';

import 'support/memory_firestore.dart';

AppUser _profile(
  String role, {
  String uid = 'member',
  String name = 'Tim',
  bool active = true,
}) => AppUser(
  uid: uid,
  name: name,
  email: '',
  photoUrl: '',
  role: role,
  isActive: active,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

AppNotification _notification(String title) => AppNotification(
  id: title,
  title: title,
  body: 'Pemberitahuan untuk peran saat ini',
  type: 'system',
  targetRole: 'all',
  userId: '',
  relatedCollection: '',
  relatedId: '',
  isRead: true,
  createdAt: DateTime(2026),
  scheduledAt: null,
  isDeleted: false,
);

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(body: child),
  ),
);

class _Notifications extends NotificationService {
  _Notifications() : super(firestore: MemoryFirestore());
  final requests = <(String, String, String?)>[];
  final streams = <StreamController<List<AppNotification>>>[];

  @override
  Stream<List<AppNotification>> watchNotifications({
    required String userId,
    required String role,
    String? type,
  }) {
    requests.add((userId, role, type));
    final controller = StreamController<List<AppNotification>>();
    streams.add(controller);
    return controller.stream;
  }
}

class _Auth implements FirebaseAuth {
  final events = StreamController<User?>.broadcast();
  @override
  Stream<User?> authStateChanges() => events.stream;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _User implements User {
  @override
  String get uid => 'member';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Profiles extends UserProfileService {
  _Profiles() : super(firestore: MemoryFirestore());
  final events = StreamController<AppUser?>.broadcast();
  @override
  Future<void> ensureUserDocument(User user, {String? name}) async {}
  @override
  Stream<AppUser?> watchProfile(String uid) => events.stream;
}

class _CachedAccess extends StatefulWidget {
  const _CachedAccess(this.profile, this.onDispose);
  final AppUser profile;
  final VoidCallback onDispose;
  @override
  State<_CachedAccess> createState() => _CachedAccessState();
}

class _CachedAccessState extends State<_CachedAccess> {
  late final bool _finance = widget.profile.canViewFinance;
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        Text(_finance ? 'Ringkasan keuangan rahasia' : 'Ringkasan lapangan'),
        TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => Scaffold(
                body: Column(
                  children: [
                    const Text('Detail keuangan rahasia'),
                    TextButton(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => const AlertDialog(
                          content: Text('Dialog keuangan rahasia'),
                        ),
                      ),
                      child: const Text('Buka dialog'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          child: const Text('Buka detail'),
        ),
      ],
    ),
  );
}

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  testWidgets(
    'badge replaces subscription and clears old role count immediately',
    (tester) async {
      final admin = StreamController<int>();
      final field = StreamController<int>();
      Widget shell(AppUser profile, Stream<int> stream) => AppShell(
        profile: profile,
        unreadCountStream: stream,
        pageBuilder: (label) => Text('Halaman $label'),
      );
      await _pump(tester, shell(_profile('admin'), admin.stream));
      admin.add(17);
      await tester.pumpAndSettle();
      expect(find.text('17'), findsOneWidget);
      await _pump(tester, shell(_profile('operator_lapangan'), field.stream));
      expect(admin.hasListener, false);
      expect(field.hasListener, true);
      expect(find.text('17'), findsNothing);
      admin.add(99);
      field.add(2);
      await tester.pumpAndSettle();
      expect(find.text('99'), findsNothing);
      expect(find.text('2'), findsOneWidget);
      await _pump(tester, const SizedBox());
      unawaited(admin.close());
      unawaited(field.close());
    },
  );

  testWidgets(
    'notification queries change role and UID and stop when inactive',
    (tester) async {
      final service = _Notifications();
      Widget inbox(AppUser profile) =>
          NotificationScreen(profile: profile, notificationService: service);
      await _pump(tester, inbox(_profile('admin')));
      service.streams.last.add([_notification('Pesan admin rahasia')]);
      await tester.pumpAndSettle();
      expect(find.text('Pesan admin rahasia'), findsOneWidget);
      await _pump(tester, inbox(_profile('operator_lapangan')));
      expect(service.requests.last, ('member', 'operator_lapangan', null));
      expect(service.streams.first.hasListener, false);
      expect(find.text('Pesan admin rahasia'), findsNothing);
      service.streams.last.add([_notification('Pesan lapangan')]);
      await tester.pumpAndSettle();
      expect(find.text('Pesan lapangan'), findsOneWidget);
      await _pump(tester, inbox(_profile('operator_lapangan', uid: 'other')));
      expect(service.requests.last, ('other', 'operator_lapangan', null));
      expect(find.text('Pesan lapangan'), findsNothing);
      await _pump(
        tester,
        inbox(_profile('operator_lapangan', uid: 'other', active: false)),
      );
      await tester.pumpAndSettle();
      expect(service.requests, hasLength(3));
      expect(service.streams.last.hasListener, false);
      expect(find.text('Belum ada notifikasi'), findsOneWidget);
      await _pump(tester, const SizedBox());
      for (final stream in service.streams) {
        unawaited(stream.close());
      }
    },
  );

  testWidgets('ordinary profile updates retain draft, role change clears it', (
    tester,
  ) async {
    final unread = Stream<int>.value(0).asBroadcastStream();
    Widget shell(AppUser profile, {Stream<int>? stream}) => AppShell(
      profile: profile,
      unreadCountStream: stream ?? unread,
      pageBuilder: (label) => label == 'Logbook'
          ? const TextField(key: ValueKey('draft'))
          : Text('Halaman $label'),
    );
    await _pump(tester, shell(_profile('operator_lapangan')));
    await tester.tap(find.text('Logbook').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('draft')),
      'Catatan belum disimpan',
    );
    await _pump(
      tester,
      shell(_profile('operator_lapangan', name: 'Nama diperbarui')),
    );
    expect(find.text('Catatan belum disimpan'), findsOneWidget);
    await _pump(
      tester,
      shell(_profile('operator_lapangan'), stream: Stream.value(3)),
    );
    expect(find.text('Catatan belum disimpan'), findsOneWidget);
    await _pump(tester, shell(_profile('operator_keuangan')));
    expect(find.text('Halaman Dashboard'), findsOneWidget);
    await tester.tap(find.text('Logbook').last);
    await tester.pumpAndSettle();
    expect(find.text('Catatan belum disimpan'), findsNothing);
  });

  for (final change in [
    'role',
    'inactive',
    'logout',
    'missing',
    'profile error',
  ]) {
    testWidgets(
      'AuthGate revokes cached finance, open detail and dialog on $change',
      (tester) async {
        final auth = _Auth();
        final profiles = _Profiles();
        var disposed = 0;
        await _pump(
          tester,
          AuthGate(
            authService: AuthService(auth: auth, userProfileService: profiles),
            profileService: profiles,
            appBuilder: (profile) => _CachedAccess(profile, () => disposed++),
          ),
        );
        auth.events.add(_User());
        await tester.pump();
        await tester.pump();
        profiles.events.add(_profile('admin'));
        await tester.pumpAndSettle();
        expect(find.text('Ringkasan keuangan rahasia'), findsOneWidget);
        // A harmless profile update must preserve the cached screen and drafts.
        profiles.events.add(_profile('admin', name: 'Nama diperbarui'));
        await tester.pumpAndSettle();
        expect(disposed, 0);
        await tester.tap(find.text('Buka detail'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Buka dialog'));
        await tester.pumpAndSettle();
        expect(find.text('Dialog keuangan rahasia'), findsOneWidget);
        switch (change) {
          case 'role':
            profiles.events.add(_profile('operator_lapangan'));
          case 'inactive':
            profiles.events.add(_profile('admin', active: false));
          case 'logout':
            auth.events.add(null);
          case 'missing':
            profiles.events.add(null);
          case 'profile error':
            profiles.events.addError(StateError('Profile permission denied'));
        }
        await tester.pumpAndSettle();
        expect(find.text('Dialog keuangan rahasia'), findsNothing);
        expect(find.text('Detail keuangan rahasia'), findsNothing);
        expect(find.text('Ringkasan keuangan rahasia'), findsNothing);
        expect(disposed, 1);
        if (change == 'role') {
          expect(find.text('Ringkasan lapangan'), findsOneWidget);
        } else if (change == 'logout') {
          expect(find.byType(LoginScreen), findsOneWidget);
        } else if (change == 'inactive') {
          expect(find.text('Akun dinonaktifkan'), findsOneWidget);
        }
        await _pump(tester, const SizedBox());
        unawaited(auth.events.close());
        unawaited(profiles.events.close());
        expect(tester.takeException(), isNull);
      },
    );
  }
}
