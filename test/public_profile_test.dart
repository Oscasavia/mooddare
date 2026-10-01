import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/features/user/data/repositories/user_repository.dart';

class UserWithoutMetadata extends Fake implements User {
  @override
  String get uid => 'new';
  @override
  String? get email => 'private@example.invalid';
  @override
  String? get displayName => null;
  @override
  String? get photoURL => null;
}

void main() {
  for (final photo in [
    'https://example.invalid/avatar.jpg',
    'http://example.invalid/avatar.jpg',
    'https://${'x' * 2050}',
  ]) {
    test(
      'first sign-in keeps provider metadata within public profile limits: ${photo.length}',
      () async {
        final db = FakeFirebaseFirestore();
        final user = MockUser(
          uid: 'new',
          email: 'private@example.invalid',
          displayName: 'N' * 70,
          photoURL: photo,
        );
        final repo = UserRepository(
          firestore: db,
          auth: MockFirebaseAuth(mockUser: user, signedIn: true),
          storage: MockFirebaseStorage(),
        );
        await repo.upsertUser(user);
        final data = (await db.doc('users/new').get()).data()!;
        expect(data.keys.toSet(), {'id', 'name', 'photoUrl', 'createdAt'});
        expect(data['name'], 'N' * 50);
        expect(
          data['photoUrl'],
          photo.startsWith('https://') && photo.length <= 2048 ? photo : null,
        );
        expect(data['createdAt'], isA<Timestamp>());
        await db.doc('users/new').update({
          'name': 'My own name',
          'bio': 'Keep my edits',
        });
        await repo.upsertUser(user);
        expect(
          (await db.doc('users/new').get()).data()!['name'],
          'My own name',
        );
        expect(
          (await db.doc('users/new').get()).data()!['bio'],
          'Keep my edits',
        );
      },
    );
  }
  test(
    'missing optional provider metadata does not copy private email',
    () async {
      final db = FakeFirebaseFirestore();
      final user = UserWithoutMetadata();
      final repo = UserRepository(
        firestore: db,
        auth: MockFirebaseAuth(),
        storage: MockFirebaseStorage(),
      );
      await repo.upsertUser(user);
      final data = (await db.doc('users/new').get()).data()!;
      expect(data.containsKey('email'), false);
      expect(data['name'], isNull);
      expect(data['photoUrl'], isNull);
    },
  );
}
