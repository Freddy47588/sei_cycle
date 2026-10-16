import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/async_state_widgets.dart';
import '../../profile/models/app_user.dart';
import '../../profile/services/user_profile_service.dart';
import '../../../app/app_shell.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final AuthService _authService;
  late final UserProfileService _profileService;
  Future<void>? _ensureProfileFuture;
  String? _ensuredUid;

  @override
  void initState() {
    super.initState();
    _profileService = UserProfileService();
    _authService = AuthService(userProfileService: _profileService);
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
          _ensuredUid = null;
          _ensureProfileFuture = null;
          return LoginScreen(authService: _authService);
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
                  return Scaffold(body: state);
                }
                final profile = profileSnapshot.requireData;
                if (profile == null) {
                  return const Scaffold(
                    body: ErrorState(
                      message: 'Dokumen profil pengguna tidak ditemukan.',
                    ),
                  );
                }
                if (!profile.isActive) {
                  return _InactiveAccount(authService: _authService);
                }
                return AppShell(key: ValueKey(profile.uid), profile: profile);
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
