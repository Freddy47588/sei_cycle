import '../../../core/utils/audit_mode.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../core/constants/app_roles.dart';
import '../../../core/constants/firestore_collections.dart';
import '../../../core/utils/firestore_validators.dart';
import '../models/app_user.dart';

class UserProfileService {
  UserProfileService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection(FirestoreCollections.users);

  Future<void> ensureUserDocument(User user, {String? name}) async {
    if (readOnlyAudit) return;
    try {
      final reference = _users.doc(user.uid);
      final snapshot = await reference.get();
      final now = FieldValue.serverTimestamp();

      if (!snapshot.exists) {
        await reference.set({
          'id': user.uid,
          'uid': user.uid,
          'name': name?.trim().isNotEmpty == true
              ? name!.trim()
              : (user.displayName?.trim().isNotEmpty == true
                    ? user.displayName!.trim()
                    : 'Pengguna SeiCycle'),
          'email': user.email ?? '',
          'photoUrl': user.photoURL ?? '',
          'role': AppRoles.defaultRole,
          'isActive': true,
          'createdAt': now,
          'updatedAt': now,
        });
        return;
      }

      final resolvedName = name?.trim().isNotEmpty == true
          ? name!.trim()
          : user.displayName?.trim();

      await reference.set({
        'id': user.uid,
        'uid': user.uid,
        'email': user.email ?? '',
        'photoUrl': user.photoURL ?? '',
        if (resolvedName?.isNotEmpty == true) 'name': resolvedName,
        'updatedAt': now,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Gagal menyinkronkan data profil (permission-denied): $e');
    }
  }

  Stream<AppUser?> watchProfile(String uid) {
    return _users
        .doc(uid)
        .snapshots()
        .map(
          (snapshot) => snapshot.exists ? AppUser.fromDocument(snapshot) : null,
        );
  }

  Stream<List<AppUser>> watchUsers() {
    return _users
        .orderBy('name')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(AppUser.fromDocument).toList());
  }

  Future<void> updateName(String uid, String name) {
    requireWritesEnabled();
    requireTrimmed(uid, 'uid');
    requireTrimmed(name, 'name');
    return _users.doc(uid).update({
      'name': name.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateRole({
    required String uid,
    required String role,
    bool? isActive,
  }) {
    requireWritesEnabled();
    requireTrimmed(uid, 'uid');
    final assignableRole = AppRoles.assignableRole(role);
    if (!AppRoles.isAssignable(assignableRole)) {
      throw ArgumentError.value(role, 'role', 'Role tidak dapat diberikan.');
    }

    return _users.doc(uid).update({
      'role': assignableRole,
      ...(isActive == null
          ? const <String, Object?>{}
          : {'isActive': isActive}),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
