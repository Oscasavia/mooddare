import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/features/notifications/data/push_service.dart';

class Permission extends Fake implements NotificationSettings {
  @override
  final AuthorizationStatus authorizationStatus;
  Permission(this.authorizationStatus);
}

class Messaging extends Fake implements FirebaseMessaging {
  String token = 'device_token';
  int deletes = 0, requests = 0;
  AuthorizationStatus status = AuthorizationStatus.authorized;
  RemoteMessage? initial;
  final refreshes = StreamController<String>.broadcast();
  @override
  Stream<String> get onTokenRefresh => refreshes.stream;
  @override
  Future<String?> getToken({String? vapidKey}) async => token;
  @override
  Future<void> deleteToken() async {
    deletes++;
  }

  @override
  Future<RemoteMessage?> getInitialMessage() async => initial;
  @override
  Future<NotificationSettings> getNotificationSettings() async =>
      Permission(status);
  @override
  Future<NotificationSettings> requestPermission({
    bool alert = true,
    bool announcement = false,
    bool badge = true,
    bool carPlay = false,
    bool criticalAlert = false,
    bool provisional = false,
    bool sound = true,
    bool providesAppNotificationSettings = false,
  }) async {
    requests++;
    return Permission(status);
  }
}

void main() {
  late FakeFirebaseFirestore db;
  late MockFirebaseAuth auth;
  late Messaging messaging;
  late PushService service;
  late StreamController<RemoteMessage> opened, foreground;
  setUp(() {
    db = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'alice'));
    messaging = Messaging();
    opened = StreamController.broadcast();
    foreground = StreamController.broadcast();
    service = PushService(
      auth: auth,
      db: db,
      messaging: messaging,
      openedMessages: opened.stream,
      foregroundMessages: foreground.stream,
    );
  });
  tearDown(() async {
    await service.dispose();
    await messaging.refreshes.close();
    await opened.close();
    await foreground.close();
  });
  Future<void> settle() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  test(
    'startup silently registers only already-authorized devices; rotation removes old token',
    () async {
      await service.start();
      await settle();
      expect(messaging.requests, 0);
      expect(
        (await db.doc('pushTokens/device_token').get()).data()?['uid'],
        'alice',
      );
      messaging.refreshes.add('new_token');
      await settle();
      expect((await db.doc('pushTokens/device_token').get()).exists, false);
      expect(
        (await db.doc('pushTokens/new_token').get()).data()?['uid'],
        'alice',
      );
    },
  );
  test(
    'denied permission does not register and enable reports denial',
    () async {
      messaging.status = AuthorizationStatus.denied;
      await service.start();
      await settle();
      expect((await db.collection('pushTokens').get()).docs, isEmpty);
      expect(await service.enable(), false);
      messaging.status = AuthorizationStatus.authorized;
      expect(await service.enable(), true);
      expect((await db.doc('pushTokens/device_token').get()).exists, true);
    },
  );
  test(
    'detach unbinds before signout and late refresh cannot restore binding',
    () async {
      await service.start();
      await settle();
      await service.detach();
      messaging.refreshes.add('late_token');
      await settle();
      expect((await db.collection('pushTokens').get()).docs, isEmpty);
      await auth.signOut();
      await settle();
      await service.refresh();
      expect((await db.collection('pushTokens').get()).docs, isEmpty);
    },
  );
  test(
    'cold, background and foreground taps reject wrong account and malformed paths',
    () async {
      messaging.initial = const RemoteMessage(
        data: {'recipientId': 'alice', 'notificationId': 'cold'},
      );
      await service.start();
      await settle();
      expect(service.pending.value?['notificationId'], 'cold');
      service.pending.value = null;
      opened.add(
        const RemoteMessage(
          data: {'recipientId': 'bob', 'notificationId': 'private'},
        ),
      );
      await settle();
      expect(service.pending.value, null);
      opened.add(
        const RemoteMessage(
          data: {'recipientId': 'alice', 'notificationId': '../private'},
        ),
      );
      await settle();
      expect(service.pending.value, null);
      opened.add(
        const RemoteMessage(
          data: {'recipientId': 'alice', 'notificationId': 'background'},
        ),
      );
      await settle();
      expect(service.pending.value?['notificationId'], 'background');
      foreground.add(
        const RemoteMessage(
          data: {'recipientId': 'alice', 'notificationId': 'foreground'},
        ),
      );
      await settle();
      expect(service.foreground.value?['notificationId'], 'foreground');
      await service.detach();
      expect(service.pending.value, null);
      expect(service.foreground.value, null);
    },
  );
}
