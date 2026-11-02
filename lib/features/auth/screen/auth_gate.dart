import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/async_state_widgets.dart';
import '../../profile/models/app_user.dart';
import '../../profile/services/user_profile_service.dart';
import '../../../app/app_shell.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({
    this.authService,
    this.profileService,
    this.appBuilder,
    super.key,
  });

  final AuthService? authService;
  final UserProfileService? profileService;
  final Widget Function(AppUser profile)? appBuilder;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final AuthService _authService;
  late final UserProfileService _profileService;
  Future<void>? _ensureProfileFuture;
  String? _ensuredUid;
  (String, String, bool)? _visibleSession;

  @override
  void initState() {
    super.initState();
    _profileService = widget.profileService ?? UserProfileService();
    _authService =
        widget.authService ?? AuthService(userProfileService: _profileService);
  }

  void _updateVisibleSession((String, String, bool)? identity) {
    final previous = _visibleSession;
    _visibleSession = identity;
    if (previous == null || previous == identity) return;
    // Detail routes and root dialogs hold the profile that opened them. Revoke
    // those routes alongside the shell when its authorization changes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(
        context,
        rootNavigator: true,
      ).popUntil((route) => route.isFirst);
    });
  }

  Future<void> _ensureProfile(User user) {
    if (_ensuredUid != user.uid || _ensureProfileFuture == null) {
      _ensuredUid = user.uid;
      _ensureProfileFuture = _profileService.ensureUserDocument(user);
    }
    return _ensureProfileFuture!;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authService.authStateChanges,
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: LoadingState());
        }

        final user = authSnapshot.data;
        if (user == null) {
          _updateVisibleSession(null);
          _ensuredUid = null;
          _ensureProfileFuture = null;
          return LoginScreen(authService: _authService);
        }
        if (_visibleSession != null && _visibleSession!.$1 != user.uid) {
          _updateVisibleSession(null);
        }

        return FutureBuilder<void>(
          future: _ensureProfile(user),
          builder: (context, ensureSnapshot) {
            if (ensureSnapshot.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: LoadingState(label: 'Menyiapkan profil...'),
              );
            }
            if (ensureSnapshot.hasError) {
              return Scaffold(
                body: ErrorState(
                  message:
                      'Profil Firestore gagal disiapkan: ${ensureSnapshot.error}',
                  onRetry: () => setState(() {
                    _ensureProfileFuture = null;
                  }),
                ),
              );
            }

            return StreamBuilder<AppUser?>(
              stream: _profileService.watchProfile(user.uid),
              builder: (context, profileSnapshot) {
                final state = asyncSnapshotState(
                  profileSnapshot,
                  loadingLabel: 'Memuat hak akses...',
                  errorMessage: (error) =>
                      'Profil gagal dimuat dari Firestore: $error',
                  allowNullData: true,
                );
                if (state != null) {
                  if (profileSnapshot.hasError) _updateVisibleSession(null);
                  return Scaffold(body: state);
                }
                final profile = profileSnapshot.data;
                if (profile == null) {
                  _updateVisibleSession(null);
                  return const Scaffold(
                    body: ErrorState(
                      message: 'Dokumen profil pengguna tidak ditemukan.',
                    ),
                  );
                }
                if (!profile.isActive) {
                  _updateVisibleSession(null);
                  return _InactiveAccount(authService: _authService);
                }
                final identity = (
                  profile.uid,
                  profile.effectiveRole,
                  profile.isActive,
                );
                _updateVisibleSession(identity);
                return KeyedSubtree(
                  key: ValueKey(identity),
                  child:
                      widget.appBuilder?.call(profile) ??
                      AppShell(profile: profile),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _InactiveAccount extends StatelessWidget {
  const _InactiveAccount({required this.authService});

  final AuthService authService;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.block, size: 64),
              const SizedBox(height: 12),
              Text(
                'Akun dinonaktifkan',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text('Hubungi admin Kebun Sei untuk mengaktifkan akun.'),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: authService.signOut,
                child: const Text('Keluar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
