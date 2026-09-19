import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:mooddare/features/settings/data/settings_repository.dart';

class MemorySettings implements SettingsRepository {
  @override
  SettingsAccount account = const SettingsAccount(
    email: 'person@example.com',
    password: true,
  );
  int signOuts = 0,
      deletions = 0,
      changes = 0,
      resets = 0,
      notifications = 0,
      shares = 0;
  bool failAction = false,
      failPassword = false,
      failOpen = false,
      failShare = false;
  Future<void>? actionGate;
  String? currentPassword, newPassword, copied;
  final urls = <Uri>[];
  Rect? shareOrigin;
  @override
  Future<String> version() async => '1.0.0 (42)';
  @override
  Future<void> changePassword(String current, String next) async {
    changes++;
    currentPassword = current;
    newPassword = next;
    if (failPassword) throw const FormatException('Wrong current password.');
  }

  @override
  Future<void> resetPassword() async {
    resets++;
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    await actionGate;
    if (failAction) throw StateError('Offline');
  }

  @override
  Future<void> deleteAccount() async {
    deletions++;
    await actionGate;
    if (failAction) throw StateError('Offline');
  }

  @override
  Future<void> notificationSettings() async {
    notifications++;
    if (failOpen) throw StateError('Unavailable');
  }

  @override
  Future<void> openUrl(Uri url) async {
    urls.add(url);
    if (failOpen) throw StateError('No handler');
  }

  @override
  Future<void> copy(String text) async {
    copied = text;
  }

  @override
  Future<void> shareApp(Rect origin) async {
    shares++;
    shareOrigin = origin;
    if (failShare) throw StateError('No handler');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
