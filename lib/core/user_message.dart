import 'package:firebase_auth/firebase_auth.dart';

String userMessage(Object error) {
  if (error is FirebaseAuthException) {
    return switch (error.code) {
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' => 'The email or password is incorrect.',
      'email-already-in-use' || 'credential-already-in-use' =>
        'This account already exists. Please sign in.',
      'weak-password' =>
        'Choose a stronger password with at least 8 characters.',
      'invalid-email' => 'Enter a valid email address.',
      'network-request-failed' =>
        'Check your internet connection and try again.',
      'too-many-requests' =>
        'Too many attempts. Please wait a little and try again.',
      'requires-recent-login' =>
        'Please sign in again before making this change.',
      'operation-not-allowed' => 'This sign-in method is not available yet.',
      _ => 'Could not sign in. Please try again.',
    };
  }
  if (error is FormatException) return error.message;
  return 'Something went wrong. Check your connection and try again.';
}
