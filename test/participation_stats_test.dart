import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:mooddare/features/feed/data/repositories/post_repository.dart';
import 'package:mooddare/features/profile/presentation/widgets/stats_and_badges.dart';

void main() {
  test(
    'stats count unique moods and weeks, ignore likes and handle legacy posts',
    () async {
      final db = FakeFirebaseFirestore();
      final repo = PostRepository(
        firestore: db,
        auth: MockFirebaseAuth(),
        storage: MockFirebaseStorage(),
      );
      expect(await repo.getUserStats('alice'), {
        'daresCompleted': 0,
        'moodsExplored': 0,
        'weeklyDaresCompleted': 0,
      });
      final moments = [
        {'moodId': 'happy', 'weeklyDareId': 'week1'},
        {'moodId': 'happy', 'weeklyDareId': 'week1'},
        {'moodId': 'relaxed', 'weeklyDareId': 'week2'},
        <String, Object>{},
        {'moodId': ' ', 'weeklyDareId': ''},
        {'moodId': 123, 'weeklyDareId': false},
      ];
      for (var i = 0; i < moments.length; i++) {
        await db.doc('posts/p$i').set({'authorId': 'alice', ...moments[i]});
      }
      await db.doc('posts/other').set({
        'authorId': 'bob',
        'moodId': 'other',
        'weeklyDareId': 'week3',
      });
      final expected = {
        'daresCompleted': 6,
        'moodsExplored': 2,
        'weeklyDaresCompleted': 2,
      };
      expect(await repo.getUserStats('alice'), expected);
      await db.doc('posts/p0').update({
        'likedBy': List.generate(200, (i) => 'u$i'),
      });
      expect(await repo.getUserStats('alice'), expected);
      await db.doc('posts/p0').delete();
      expect(await repo.getUserStats('alice'), {
        ...expected,
        'daresCompleted': 5,
      });
    },
  );
  for (final count in [0, 9, 10, 21]) {
    testWidgets(
      'level progress for $count moments excludes social popularity',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatsAndBadges(
                daresCompleted: count,
                moodsExplored: 3,
                weeklyDaresCompleted: 4,
              ),
            ),
          ),
        );
        expect(find.text('Likes'), findsNothing);
        expect(find.text('Moods explored'), findsOneWidget);
        expect(find.text('Community weeks'), findsOneWidget);
        expect(find.text('Level ${count ~/ 10 + 1}'), findsOneWidget);
        expect(
          tester
              .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator),
              )
              .value,
          (count % 10) / 10,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'stats and earned milestones remain readable on narrow screens with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: const Scaffold(
            body: StatsAndBadges(
              daresCompleted: 10,
              moodsExplored: 3,
              weeklyDaresCompleted: 4,
            ),
          ),
        ),
      );
      await tester.scrollUntilVisible(find.text('A little of everything'), 300);
      expect(find.text('Share moments from 3 different moods'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
