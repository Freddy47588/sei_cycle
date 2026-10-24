import 'package:flutter/material.dart';

Future<bool> runOperationWithFeedback(
  BuildContext context, {
  required Future<void> Function() operation,
  required String successMessage,
}) async {
  try {
    await operation();
    if (!context.mounted) return true;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(successMessage)));
    return true;
  } catch (error) {
    if (!context.mounted) return false;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Operasi gagal: $error')));
    return false;
  }
}
