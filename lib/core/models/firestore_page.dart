import 'package:cloud_firestore/cloud_firestore.dart';

class FirestorePage<T> {
  const FirestorePage(this.items, this.cursor, this.hasMore);
  final List<T> items;
  final DocumentSnapshot<Map<String, dynamic>>? cursor;
  final bool hasMore;
}
