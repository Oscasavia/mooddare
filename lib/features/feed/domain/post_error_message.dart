import 'dart:io';
import 'package:firebase_core/firebase_core.dart';

String postErrorMessage(Object error) {
  if (error is FormatException) return error.message;
  if (error is FirebaseException) {
    return switch (error.code.replaceFirst('storage/', '')) {
      'unauthorized' || 'permission-denied' =>
        'Your upload was blocked. Please try again later or contact support.',
      'unauthenticated' => 'Please sign in again before posting.',
      'canceled' ||
      'cancelled' => 'Upload cancelled. Your capture is still here.',
      'quota-exceeded' =>
        'Posting is temporarily unavailable. Please try again later.',
      'retry-limit-exceeded' || 'unavailable' || 'network-request-failed' =>
        'Could not reach the server. Check your connection and try again.',
      _ => 'Could not post. Your capture is still here—please try again.',
    };
  }
  if (error is SocketException) {
    return 'Could not reach the server. Check your connection and try again.';
  }
  return 'Could not post. Your capture is still here—please try again.';
}
