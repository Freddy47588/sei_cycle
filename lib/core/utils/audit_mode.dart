/// Local debug smoke testing must not synchronize profiles or FCM metadata.
/// Build explicitly with --dart-define=SEICYCLE_READ_ONLY_AUDIT=true.
const readOnlyAudit = bool.fromEnvironment('SEICYCLE_READ_ONLY_AUDIT');

void requireWritesEnabled() {
  if (readOnlyAudit) {
    throw StateError('Mode audit baca saja: perubahan data dinonaktifkan.');
  }
}
