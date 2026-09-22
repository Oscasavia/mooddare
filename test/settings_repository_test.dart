import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mooddare/features/auth/data/repositories/auth_repository.dart';
import 'package:mooddare/features/user/data/repositories/user_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/features/settings/data/settings_repository.dart';

class ProviderInfo implements UserInfo {
  @override
  final String providerId;
  ProviderInfo(this.providerId);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestCredential implements UserCredential {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestUser implements User {
  @override
  String uid = 'member';
  @override
  String? email = 'member@example.com';
  @override
  bool isAnonymous = false;
  @override
  List<UserInfo> providerData = [ProviderInfo('password')];
  bool rejectPassword = false;
  final operations = <String>[];
  AuthCredential? credential;
  @override
  Future<UserCredential> reauthenticateWithCredential(
    AuthCredential value,
  ) async {
    operations.add('reauth');
    credential = value;
    if (rejectPassword) throw FirebaseAuthException(code: 'wrong-password');
    return TestCredential();
  }

  @override
  Future<void> updatePassword(String password) async {
    operations.add('update:$password');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestAuth implements FirebaseAuth {
  @override
  User? currentUser;
  String? resetEmail;
  bool failSignOut = false;
  int signOuts = 0;
  @override
  Future<void> signOut() async {
    signOuts++;
    if (failSignOut) {
      throw FirebaseAuthException(code: 'network-request-failed');
    }
    currentUser = null;
  }

  TestAuth(this.currentUser);
  @override
  Future<void> sendPasswordResetEmail({
    required String email,
    ActionCodeSettings? actionCodeSettings,
  }) async {
    resetEmail = email;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestGoogle implements GoogleSignIn {
  @override
  Future<GoogleSignInAccount?> signOut() async =>
      throw StateError('Provider unavailable');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class UnusedUsers implements UserRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class DeleteGoogleTokens implements GoogleSignInAuthentication {
  @override
  String? get accessToken => 'access';
  @override
  String? get idToken => 'id';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class DeleteGoogleAccount implements GoogleSignInAccount {
  @override
  Future<GoogleSignInAuthentication> get authentication async =>
      DeleteGoogleTokens();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class DeleteGoogle implements GoogleSignIn {
  bool cancel = false;
  void Function()? beforeReturn;
  @override
  Future<GoogleSignInAccount?> signIn() async {
    beforeReturn?.call();
    return cancel ? null : DeleteGoogleAccount();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'deletion verification uses exact current password without changing session or password',
    () async {
      final user = TestUser(), auth = TestAuth(null);
      auth.currentUser = user;
      expect(
        await SettingsRepository(
          auth: auth,
        ).reauthenticateForDeletion(password: ' exact password '),
        isTrue,
      );
      expect(user.operations, ['reauth']);
      expect(auth.signOuts, 0);
      expect(auth.currentUser, same(user));
      expect(
        (user.credential as EmailAuthCredential).password,
        ' exact password ',
      );
    },
  );
  test(
    'Google deletion verification cancels safely, verifies existing user and rejects account switches',
    () async {
      final user = TestUser()..providerData = [ProviderInfo('google.com')];
      final auth = TestAuth(user), google = DeleteGoogle()..cancel = true;
      final repo = SettingsRepository(auth: auth, googleSignIn: google);
      expect(await repo.reauthenticateForDeletion(), isFalse);
      expect(user.operations, isEmpty);
      google.cancel = false;
      expect(await repo.reauthenticateForDeletion(), isTrue);
      expect(user.credential!.providerId, 'google.com');
      expect(auth.signOuts, 0);
      google.beforeReturn = () =>
          auth.currentUser = TestUser()..uid = 'different';
      await expectLater(
        repo.reauthenticateForDeletion(),
        throwsA(
          isA<FirebaseAuthException>().having(
            (e) => e.code,
            'code',
            'user-mismatch',
          ),
        ),
      );
      expect(user.operations, ['reauth']);
    },
  );
  test(
    'wrong deletion password, unsupported provider and signed-out state never verify',
    () async {
      final user = TestUser()..rejectPassword = true;
      final auth = TestAuth(user);
      final repo = SettingsRepository(auth: auth);
      await expectLater(
        repo.reauthenticateForDeletion(password: 'wrong'),
        throwsA(isA<FirebaseAuthException>()),
      );
      user.providerData = [];
      await expectLater(
        repo.reauthenticateForDeletion(),
        throwsFormatException,
      );
      auth.currentUser = null;
      await expectLater(repo.reauthenticateForDeletion(), throwsStateError);
    },
  );
  test(
    'provider failure still signs out Firebase without a misleading error',
    () async {
      final auth = TestAuth(TestUser());
      final repo = AuthRepository(
        firebaseAuth: auth,
        googleSignIn: TestGoogle(),
        userRepository: UnusedUsers(),
      );
      await repo.signOut();
      expect(auth.currentUser, isNull);
      expect(auth.signOuts, 1);
    },
  );
  test(
    'failed Firebase signout still surfaces its error and preserves the session',
    () async {
      final auth = TestAuth(TestUser())..failSignOut = true;
      final repo = AuthRepository(
        firebaseAuth: auth,
        googleSignIn: TestGoogle(),
        userRepository: UnusedUsers(),
      );
      await expectLater(repo.signOut(), throwsA(isA<FirebaseAuthException>()));
      expect(auth.currentUser, isNotNull);
    },
  );
  test(
    'password changes reauthenticate the current account before updating',
    () async {
      final user = TestUser();
      final repo = SettingsRepository(auth: TestAuth(user));
      await repo.changePassword(' exact current ', ' exact new password ');
      expect(user.operations, ['reauth', 'update: exact new password ']);
      final credential = user.credential as EmailAuthCredential;
      expect(credential.email, user.email);
      expect(credential.password, ' exact current ');
    },
  );
  test('failed reauthentication never changes the password', () async {
    final user = TestUser()..rejectPassword = true;
    final repo = SettingsRepository(auth: TestAuth(user));
    await expectLater(
      repo.changePassword('wrong', 'valid new password'),
      throwsA(isA<FirebaseAuthException>()),
    );
    expect(user.operations, ['reauth']);
  });
  test(
    'provider and guest accounts cannot accidentally gain a password',
    () async {
      final user = TestUser()..providerData = [ProviderInfo('google.com')];
      final auth = TestAuth(user);
      final repo = SettingsRepository(auth: auth);
      expect(repo.account.google, isTrue);
      await expectLater(
        repo.changePassword('anything', 'new password'),
        throwsFormatException,
      );
      await expectLater(repo.resetPassword(), throwsFormatException);
      expect(user.operations, isEmpty);
      expect(auth.resetEmail, isNull);
      auth.currentUser = null;
      expect(repo.account.guest, isTrue);
      await expectLater(
        repo.changePassword('anything', 'new password'),
        throwsFormatException,
      );
    },
  );
  test('password reset goes only to the signed-in password account', () async {
    final auth = TestAuth(TestUser());
    await SettingsRepository(auth: auth).resetPassword();
    expect(auth.resetEmail, 'member@example.com');
  });
  test(
    'native settings bridge handles version, notifications and allowed links',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SettingsRepository.channel, (call) async {
            calls.add(call);
            return call.method == 'version' ? '1.0.0 (1)' : null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SettingsRepository.channel, null),
      );
      final repo = SettingsRepository(auth: TestAuth(null));
      expect(await repo.version(), '1.0.0 (1)');
      await repo.notificationSettings();
      await repo.openUrl(Uri.parse('mailto:oscasavia@gmail.com?subject=Help'));
      await expectLater(
        repo.openUrl(Uri.parse('file:///private/data')),
        throwsFormatException,
      );
      expect(calls.map((c) => c.method), [
        'version',
        'notifications',
        'openUrl',
      ]);
      expect(calls.last.arguments, 'mailto:oscasavia@gmail.com?subject=Help');
    },
  );
}
