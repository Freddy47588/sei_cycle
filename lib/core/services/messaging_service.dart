import '../utils/audit_mode.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../constants/firestore_collections.dart';

class MessagingService {
  MessagingService({FirebaseMessaging? messaging, FirebaseFirestore? firestore})
    : _messaging = messaging ?? FirebaseMessaging.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseMessaging _messaging;
  final FirebaseFirestore _firestore;

  Future<String?> requestPermissionAndGetToken() async {
    final settings = await _messaging.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      return null;
    }
    return _messaging.getToken();
  }

  Future<String?> requestPermissionAndSaveToken(String userId) async {
    if (readOnlyAudit) return null;
    final token = await requestPermissionAndGetToken();
    if (token == null || token.isEmpty) return null;

    await _firestore.collection(FirestoreCollections.users).doc(userId).set({
      'fcmToken': token,
      'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return token;
  }
}
