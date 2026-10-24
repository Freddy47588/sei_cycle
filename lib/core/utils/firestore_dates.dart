import 'package:cloud_firestore/cloud_firestore.dart';

DateTime dateTimeFromFirestore(Object? value, {DateTime? fallback}) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return fallback ?? DateTime.fromMillisecondsSinceEpoch(0);
}
