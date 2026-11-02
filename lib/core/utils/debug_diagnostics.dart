import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Never logs exception messages or document contents: they can contain PII.
void logLoadFailure(
  String service,
  String operation,
  Object error,
  StackTrace stack,
) {
  if (!kDebugMode) return;
  debugPrint(
    '[SeiCycle] ${DateTime.now().toUtc().toIso8601String()} '
    'service=$service operation=$operation type=${error.runtimeType} '
    'code=${error is FirebaseException ? error.code : "none"}',
  );
  debugPrint(stack.toString());
}

Future<T> diagnoseLoad<T>(
  String service,
  String operation,
  Future<T> Function() load,
) async {
  try {
    return await load().timeout(const Duration(seconds: 20));
  } catch (error, stack) {
    logLoadFailure(service, operation, error, stack);
    rethrow;
  }
}
