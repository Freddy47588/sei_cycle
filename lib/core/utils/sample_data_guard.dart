import 'package:cloud_firestore/cloud_firestore.dart';

bool hasSampleMarker(Map<String, dynamic> d) =>
    d['isSampleData'] == true ||
    d['createdBy'] == 'sample_seed' ||
    d['sampleVersion'] == 'v2';

void requireOperationalData(
  Iterable<DocumentSnapshot<Map<String, dynamic>>> docs,
) {
  if (docs.any((doc) => hasSampleMarker(doc.data() ?? {}))) {
    throw StateError(
      'Data bertanda sampel terdeteksi. Pengelola perlu meninjau dataset sebelum ringkasan operasional digunakan.',
    );
  }
}

/// Legacy real records may lack isSampleData, so a != false filter would hide
/// legitimate data. Fail visibly when markers exist instead of publishing demo KPIs.
Future<void> requireNoSampleData(
  FirebaseFirestore db,
  Iterable<String> collections,
) async {
  await Future.wait([
    for (final name in collections)
      for (final marker in [
        ('isSampleData', true),
        ('createdBy', 'sample_seed'),
        ('sampleVersion', 'v2'),
      ])
        db
            .collection(name)
            .where(marker.$1, isEqualTo: marker.$2)
            .limit(1)
            .get()
            .then((result) => requireOperationalData(result.docs)),
  ]);
}
