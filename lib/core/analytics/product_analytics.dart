import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:uuid/uuid.dart';

/// Explicit selections only. No screen views, free text or private feed history.
/// Best effort: analytics must never interrupt a dare or delay navigation.
class ProductAnalytics {
  final Future<void> Function(Map<String, String>)? send;
  final bool Function()? signedIn;
  final String Function()? eventId;
  ProductAnalytics({this.send, this.signedIn, this.eventId});

  Future<void> moodSelected(String moodId) async {
    try {
      final allowed =
          signedIn?.call() ??
          (Firebase.apps.isNotEmpty &&
              FirebaseAuth.instance.currentUser != null &&
              !FirebaseAuth.instance.currentUser!.isAnonymous);
      if (!allowed) return;
      final data = {
        'eventId': eventId?.call() ?? const Uuid().v4(),
        'moodId': moodId,
      };
      if (send != null) {
        await send!(data).timeout(const Duration(seconds: 5));
      } else {
        await FirebaseFunctions.instanceFor(region: 'us-central1')
            .httpsCallable(
              'recordMoodSelection',
              options: HttpsCallableOptions(
                timeout: const Duration(seconds: 5),
              ),
            )
            .call<void>(data);
      }
    } catch (_) {
      // Offline selections are intentionally not queued or replayed on another account.
    }
  }
}
