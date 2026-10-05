import 'dart:async';
import 'dart:io';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'event_queue.dart';

class ProductAnalytics {
  static final instance = ProductAnalytics();
  static String version = const String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.0.0_3',
  );
  static String get environment => kReleaseMode ? 'production' : 'development';
  final Future<void> Function(Map<String, String>)? send;
  final bool Function()? signedIn;
  final String Function()? eventId;
  final AnalyticsQueue queue;
  bool _flushing = false;
  final String _session = const Uuid().v4();
  ProductAnalytics({
    this.send,
    this.signedIn,
    this.eventId,
    AnalyticsQueue? queue,
  }) : queue = queue ?? AnalyticsQueue();
  static const publicEvents = {
    'signup_started',
    'login_started',
    'auth_failed',
  };
  String? get _uid {
    if (Firebase.apps.isEmpty) return null;
    final user = FirebaseAuth.instance.currentUser;
    return user == null || user.isAnonymous ? null : user.uid;
  }

  Future<void> moodSelected(String moodId) async {
    if (send != null) {
      try {
        if (signedIn?.call() ?? false) {
          await send!({
            'eventId': eventId?.call() ?? const Uuid().v4(),
            'moodId': moodId,
          });
        }
      } catch (_) {}
      return;
    }
    await track('mood_selected', moodId: moodId);
  }

  Future<void> track(
    String name, {
    String? moodId,
    String? weekId,
    String? postId,
    int? durationMs,
    String? error,
  }) async {
    try {
      if (Firebase.apps.isEmpty) return;
      final uid = _uid;
      if (uid == null && !publicEvents.contains(name)) return;
      await queue.add({
        'id': const Uuid().v4(),
        'name': name,
        'at': DateTime.now().millisecondsSinceEpoch,
        'owner': uid,
        'environment': environment,
        'version': version,
        'platform': Platform.isAndroid
            ? 'android'
            : Platform.isIOS
            ? 'ios'
            : 'other',
        'session': _session,
        if (moodId != null) 'moodId': moodId,
        if (weekId != null) 'weekId': weekId,
        if (postId != null) 'postId': postId,
        if (durationMs != null) 'durationMs': durationMs.clamp(0, 3600000),
        if (error != null) 'error': error,
      });
      unawaited(flush());
    } catch (_) {
      /* Collection never blocks a feature. */
    }
  }

  Future<void> flush() async {
    if (_flushing || Firebase.apps.isEmpty) return;
    _flushing = true;
    try {
      final uid = _uid;
      final pending = await queue.pending(uid);
      final groups = <String, List<Map<String, dynamic>>>{};
      for (final item in pending) {
        final key =
            '${item['owner']}:${item['environment']}:${item['version']}:${item['platform']}:${item['session']}';
        (groups[key] ??= []).add(item);
      }
      for (final items in groups.values) {
        final first = items.first;
        for (var offset = 0; offset < items.length; offset += 20) {
          if (_uid != uid) return;
          final events = items
              .skip(offset)
              .take(20)
              .map(
                (e) => Map<String, dynamic>.from(e)
                  ..removeWhere(
                    (k, v) => [
                      'owner',
                      'environment',
                      'version',
                      'platform',
                      'session',
                    ].contains(k),
                  ),
              )
              .toList();
          final result =
              await FirebaseFunctions.instanceFor(region: 'us-central1')
                  .httpsCallable(
                    'recordProductEvents',
                    options: HttpsCallableOptions(
                      timeout: const Duration(seconds: 10),
                    ),
                  )
                  .call<Map<String, dynamic>>({
                    'events': events,
                    'environment': first['environment'],
                    'version': first['version'],
                    'platform': first['platform'],
                    'session': first['session'],
                    'anonymous': first['owner'] == null,
                    'expectedUid': uid,
                  });
          final acked =
              (result.data['acked'] as List?)?.whereType<String>().toList() ??
              <String>[];
          await queue.acknowledge(acked);
        }
      }
    } catch (_) {
      /* Retry on resume/next event; original IDs and times survive. */
    } finally {
      _flushing = false;
    }
  }

  static String errorCode(Object error) {
    if (error is FirebaseException) {
      if ([
        'network-request-failed',
        'unavailable',
        'deadline-exceeded',
      ].contains(error.code)) {
        return 'network';
      }
      if ([
        'permission-denied',
        'unauthorized',
        'unauthenticated',
      ].contains(error.code)) {
        return 'permission';
      }
      if (error.code.contains('cancel')) return 'cancelled';
      return 'firebase';
    }
    return 'unknown';
  }
}
