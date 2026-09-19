import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:mooddare/features/auth/data/repositories/auth_repository.dart';
import 'package:mooddare/features/profile/data/account_repository.dart';

class SettingsAccount {
  final String? email;
  final bool guest, password, google;
  const SettingsAccount({
    this.email,
    this.guest = false,
    this.password = false,
    this.google = false,
  });
}

/// Account operations and OS handoffs are isolated for regression testing.
class SettingsRepository {
  final FirebaseAuth? auth;
  SettingsRepository({this.auth});
  FirebaseAuth get _auth => auth ?? FirebaseAuth.instance;
  static const channel = MethodChannel('mooddare/settings');
  static const supportEmail = String.fromEnvironment(
    'SUPPORT_EMAIL',
    defaultValue: 'oscasavia@gmail.com',
  );
  static const appUrl = String.fromEnvironment(
    'APP_SHARE_URL',
    defaultValue: 'https://mooddare.example',
  );

  SettingsAccount get account {
    final user = _auth.currentUser;
    return SettingsAccount(
      email: user?.email,
      guest: user == null || user.isAnonymous,
      password:
          user?.providerData.any((p) => p.providerId == 'password') ?? false,
      google:
          user?.providerData.any((p) => p.providerId == 'google.com') ?? false,
    );
  }

  Future<void> changePassword(String current, String next) async {
    final user = _auth.currentUser;
    if (user == null || !account.password || user.email == null) {
      throw const FormatException(
        'Use your sign-in provider to manage your password.',
      );
    }
    if (next.length < 8) {
      throw const FormatException('Use at least 8 characters.');
    }
    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: user.email!, password: current),
    );
    await user.updatePassword(next);
  }

  Future<void> resetPassword() async {
    if (!account.password || account.email == null) {
      throw const FormatException(
        'This account does not use an email password.',
      );
    }
    await _auth.sendPasswordResetEmail(email: account.email!);
  }

  Future<void> signOut() => AuthRepository().signOut();
  Future<void> deleteAccount() => AccountRepository().deleteAccount();
  Future<String> version() async =>
      await channel.invokeMethod<String>('version') ?? 'Development build';
  Future<void> notificationSettings() =>
      channel.invokeMethod<void>('notifications');
  Future<void> openUrl(Uri url) async {
    if (!['https', 'mailto'].contains(url.scheme)) {
      throw const FormatException('This link is not supported.');
    }
    await channel.invokeMethod<void>('openUrl', url.toString());
  }

  Future<void> shareApp(Rect origin) async {
    final link = Uri.tryParse(appUrl);
    final suffix =
        link != null && link.scheme == 'https' && link.host.isNotEmpty
        ? link.host.endsWith('.example')
              ? '\nPreview link (download coming soon): $link'
              : '\n$link'
        : '';
    await Share.share(
      'Try MoodDare with me — pick a mood, take on a dare, and share your moment.$suffix',
      subject: 'MoodDare',
      sharePositionOrigin: origin,
    );
  }

  Future<void> copy(String value) =>
      Clipboard.setData(ClipboardData(text: value));
}
