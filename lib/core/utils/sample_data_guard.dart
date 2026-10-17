import 'package:cloud_firestore/cloud_firestore.dart';

class SampleDataException extends StateError {
  SampleDataException()
    : super(
        'Data bertanda sampel terdeteksi. Minta pengelola meninjau data; jangan gunakan sampel sebagai data operasional.',
      );
}

bool hasSampleMarker(Map<String, dynamic> d) =>
    d['isSampleData'] == true ||
    d['createdBy'] == 'sample_seed' ||
    d['sampleVersion'] == 'v2';

/// Only provenance proves seed origin. Flags on a real UID require review.
bool isSeedOrigin(Map<String, dynamic> d) => d['createdBy'] == 'sample_seed';

void requireOperationalData(
  Iterable<DocumentSnapshot<Map<String, dynamic>>> docs,
) {
  if (docs.any((doc) => hasSampleMarker(doc.data() ?? {}))) {
    throw SampleDataException();
  }
}
