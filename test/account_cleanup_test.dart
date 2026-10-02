import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/features/profile/data/account_repository.dart';

class RecentToken implements IdTokenResult {
  @override
  DateTime? get authTime => DateTime.now();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: must_be_immutable
class RecentUser extends MockUser {
  RecentUser() : super(uid: 'alice', isAnonymous: false);
  @override
  Future<IdTokenResult> getIdTokenResult([bool forceRefresh = false]) async =>
      RecentToken();
  @override
  Future<void> delete() =>
      throw StateError('Only the server deletes Auth accounts.');
}

void main() {
  test(
    'clears local drafts and detaches push, but signs out only after durable server acceptance',
    () async {
      final auth = MockFirebaseAuth(mockUser: RecentUser(), signedIn: true);
      final accepted = Completer<void>();
      final calls = <String>[];
      final repo = AccountRepository(
        auth: auth,
        deleteLocalDrafts: (uid) async {
          calls.add('drafts:$uid');
        },
        detachPush: () async {
          calls.add('push');
        },
        requestDeletion: (_) {
          calls.add('request');
          return accepted.future;
        },
      );
      final deleting = repo.deleteAccount();
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['drafts:alice', 'push', 'request']);
      expect(auth.currentUser?.uid, 'alice');
      accepted.complete();
      await deleting;
      expect(auth.currentUser, isNull);
    },
  );
  test(
    'failed acceptance remains signed in and can be retried safely',
    () async {
      final auth = MockFirebaseAuth(mockUser: RecentUser(), signedIn: true);
      var fail = true;
      final repo = AccountRepository(
        auth: auth,
        deleteLocalDrafts: (_) async {},
        detachPush: () async {},
        requestDeletion: (_) async {
          if (fail) throw StateError('offline');
        },
      );
      await expectLater(repo.deleteAccount(), throwsStateError);
      expect(auth.currentUser?.uid, 'alice');
      fail = false;
      await repo.deleteAccount();
      expect(auth.currentUser, isNull);
    },
  );
  test(
    'old authentication and signed-out callers cannot request cleanup',
    () async {
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'alice'),
        signedIn: true,
      );
      final repo = AccountRepository(
        auth: auth,
        requestDeletion: (_) => throw StateError('Must not request'),
      );
      await expectLater(
        repo.deleteAccount(),
        throwsA(
          isA<FirebaseAuthException>().having(
            (e) => e.code,
            'code',
            'requires-recent-login',
          ),
        ),
      );
      await auth.signOut();
      await expectLater(repo.deleteAccount(), throwsStateError);
    },
  );
  test(
    'an account switch during local cleanup cannot delete the next account',
    () async {
      final auth = MockFirebaseAuth(mockUser: RecentUser(), signedIn: true);
      var requested = false;
      final repo = AccountRepository(
        auth: auth,
        deleteLocalDrafts: (_) => auth.signOut(),
        detachPush: () async {},
        requestDeletion: (_) async {
          requested = true;
        },
      );
      await expectLater(
        repo.deleteAccount(),
        throwsA(
          isA<FirebaseAuthException>().having(
            (e) => e.code,
            'code',
            'user-mismatch',
          ),
        ),
      );
      expect(requested, false);
    },
  );
}
