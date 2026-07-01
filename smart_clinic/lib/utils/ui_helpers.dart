import 'package:flutter/material.dart';

void showErrorSnackBar(BuildContext context, Object error) {
  final message = error.toString().replaceFirst('Exception: ', '');
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), backgroundColor: Theme.of(context).colorScheme.error),
  );
}

void showSuccessSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), backgroundColor: const Color(0xFF388E3C)),
  );
}

String extractApiError(Object error) {
  return error.toString().replaceFirst('Exception: ', '');
}
