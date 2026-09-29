import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Notification messages are displayed by the OS in the background. Foreground
/// messages use an in-app banner; opening either resolves an owner-only inbox ID.
class PushService {
  static PushService? instance;
  final FirebaseAuth auth;
  final FirebaseFirestore db;
  final FirebaseMessaging messaging;
  final Stream<RemoteMessage>? openedMessages, foregroundMessages;
  final pending = ValueNotifier<Map<String, String>?>(null);
  final foreground = ValueNotifier<Map<String, String>?>(null);
  StreamSubscription<User?>? _authSub;
  StreamSubscription<String>? _tokenSub;
  StreamSubscription<RemoteMessage>? _openSub, _messageSub;
  String? _token;
  bool _suspended = false;
  int _generation = 0;
  Future<void> _writes = Future.value();
  PushService({
    required this.auth,
    required this.db,
    required this.messaging,
    this.openedMessages,
    this.foregroundMessages,
  });
  Future<void> start() async {
    _authSub = auth.authStateChanges().listen((user) {
      _generation++;
      _suspended = false;
      if (user == null || user.isAnonymous) {
        pending.value = null;
        foreground.value = null;
        return;
      }
      unawaited(refresh().catchError((Object _) {}));
    });
    _tokenSub = messaging.onTokenRefresh.listen((token) {
      unawaited(_bind(token).catchError((Object _) {}));
    }, onError: (Object _) {});
    _openSub = (openedMessages ?? FirebaseMessaging.onMessageOpenedApp).listen(
      (m) => _receive(m, pending),
    );
    _messageSub = (foregroundMessages ?? FirebaseMessaging.onMessage).listen(
      (m) => _receive(m, foreground),
    );
    try {
      final initial = await messaging.getInitialMessage();
      if (initial != null) _receive(initial, pending);
    } catch (_) {}
  }

  void _receive(RemoteMessage m, ValueNotifier<Map<String, String>?> target) {
    final recipient = m.data['recipientId'];
    final id = m.data['notificationId'];
    if (recipient is String &&
        id is String &&
        !id.contains('/') &&
        recipient == auth.currentUser?.uid &&
        !_suspended) {
      target.value = {'recipientId': recipient, 'notificationId': id};
    }
  }

  Future<bool> enable() async {
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      return false;
    }
    await refresh();
    return true;
  }

  Future<void> refresh() async {
    final user = auth.currentUser;
    if (user == null || user.isAnonymous || _suspended) return;
    final settings = await messaging.getNotificationSettings();
    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      return;
    }
    if (Platform.isIOS && await messaging.getAPNSToken() == null) return;
    final token = await messaging.getToken();
    if (token != null) await _bind(token);
  }

  Future<void> _bind(String token) {
    final user = auth.currentUser;
    final generation = _generation;
    if (user == null || user.isAnonymous || _suspended) return Future.value();
    final next = _writes.catchError((Object _) {}).then((_) async {
      if (_suspended ||
          generation != _generation ||
          auth.currentUser?.uid != user.uid) {
        return;
      }
      final old = _token;
      if (old != null && old != token) {
        await db.collection('pushTokens').doc(old).delete();
      }
      await db.collection('pushTokens').doc(token).set({
        'uid': user.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _token = token;
    });
    _writes = next;
    return next;
  }

  /// Called BEFORE sign-out/deletion while the current account can unbind.
  /// If Firestore is unavailable, invalidate the token with FCM instead.
  Future<void> detach() async {
    _suspended = true;
    _generation++;
    pending.value = null;
    foreground.value = null;
    try {
      await _writes
          .catchError((Object _) {})
          .timeout(const Duration(seconds: 5));
      final token = _token ?? await messaging.getToken();
      if (token != null) {
        await db
            .collection('pushTokens')
            .doc(token)
            .delete()
            .timeout(const Duration(seconds: 5));
      }
    } catch (_) {
      await messaging.deleteToken();
    }
    _token = null;
  }

  Future<void> dispose() async {
    await _authSub?.cancel();
    await _tokenSub?.cancel();
    await _openSub?.cancel();
    await _messageSub?.cancel();
    pending.dispose();
    foreground.dispose();
  }
}
