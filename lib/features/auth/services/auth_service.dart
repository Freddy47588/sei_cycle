import 'package:firebase_auth/firebase_auth.dart';

import '../../profile/services/user_profile_service.dart';

class AuthService {
  AuthService({FirebaseAuth? auth, UserProfileService? userProfileService})
    : _auth = auth ?? FirebaseAuth.instance,
      _userProfileService = userProfileService ?? UserProfileService();

  final FirebaseAuth _auth;
  final UserProfileService _userProfileService;

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await _ensureProfile(credential);
    return credential;
  }

  Future<UserCredential> registerWithEmailAndPassword({
    required String name,
    required String email,
    required String password,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await credential.user?.updateDisplayName(name.trim());
    await _ensureProfile(credential, name: name);
    return credential;
  }

  Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());

  Future<void> signOut() => _auth.signOut();

  Future<void> _ensureProfile(UserCredential credential, {String? name}) async {
    final user = credential.user;
    if (user != null) {
      await _userProfileService.ensureUserDocument(user, name: name);
    }
  }
}
