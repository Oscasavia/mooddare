import 'package:mooddare/features/dares/data/weekly_dare_preferences.dart';
import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/features/dares/data/repositories/weekly_dare_repository.dart';
import 'package:mooddare/features/dares/presentation/widgets/weekly_dare_card.dart';
import 'package:mooddare/features/feed/data/repositories/post_repository.dart';
import 'package:mooddare/features/profile/presentation/widgets/stats_and_badges.dart';

Map<String, dynamic> schedule(DateTime now) => {
  'title': 'A little joy',
  'dareText': 'Capture one small thing that made you smile today.',
  'moodId': 'happy',
  'moodName': 'Happy',
  'startsAt': Timestamp.fromDate(WeeklyDare.weekStart(now)),
  'endsAt': Timestamp.fromDate(
    WeeklyDare.weekStart(now).add(const Duration(days: 7)),
  ),
};

class TestWeekly extends WeeklyDareRepository {
  final changes = StreamController<WeeklyDare?>.broadcast();
  final progress = StreamController<bool>.broadcast();
  final weeks = <String>[];
  @override
  Stream<WeeklyDare?> watch(DateTime now) {
    weeks.add(WeeklyDare.weekId(now));
    return changes.stream;
  }

  @override
  Stream<bool> completed(String weekId) => progress.stream;
  Future<void> close() async {
    await changes.close();
    await progress.close();
  }
}

class MemoryPreference extends WeeklyDarePreferences {
  String? value;
  bool fail = false;
  final writes = <String?>[];
  @override
  Future<String?> load() async {
    if (fail) throw FileSystemException('Unavailable');
    return value;
  }

  @override
  Future<void> save(String? week) async {
    if (fail) throw FileSystemException('Unavailable');
    writes.add(week);
    value = week;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final date = DateTime.utc(2026, 9, 23, 12);
  final id = WeeklyDare.weekId(date);
  final dare = WeeklyDare.parse(id, schedule(date))!;
  test('UTC Monday identity crosses time zones and year boundaries', () {
    expect(id, '2026-09-21');
    expect(
      WeeklyDare.weekId(DateTime.parse('2026-09-27T20:00:00-05:00')),
      '2026-09-28',
    );
    expect(WeeklyDare.weekId(DateTime.utc(2027, 1, 1)), '2026-12-28');
    expect(dare.isActive(dare.startsAt), true);
    expect(
      dare.isActive(dare.startsAt.subtract(const Duration(microseconds: 1))),
      false,
    );
    expect(dare.isActive(dare.endsAt), false);
    expect(
      dare.isActive(dare.endsAt.subtract(const Duration(microseconds: 1))),
      true,
    );
  });
  test(
    'malformed and unpublished schedules cannot appear as playable dares',
    () {
      expect(WeeklyDare.parse(id, null), isNull);
      for (final broken in <Map<String, dynamic>>[
        {},
        {...schedule(date), 'dareText': 5},
        {...schedule(date), 'moodId': null},
        {...schedule(date), 'moodName': ''},
        {...schedule(date), 'title': ''},
        {...schedule(date), 'startsAt': 'yesterday'},
        {...schedule(date), 'endsAt': Timestamp.fromDate(date)},
        {...schedule(date), 'startsAt': Timestamp.fromDate(date)},
      ]) {
        expect(WeeklyDare.parse(id, broken), isNull);
      }
      expect(WeeklyDare.parse('2026-09-22', schedule(date)), isNull);
    },
  );
  test(
    'schedule and personal participation streams update; another user does not mark completion',
    () async {
      final db = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'alice'),
        signedIn: true,
      );
      final repo = WeeklyDareRepository(firestore: db, auth: auth);
      expect(await repo.watch(date).first, isNull);
      await db.doc('weeklyDares/$id').set(schedule(date));
      expect((await repo.watch(date).first)!.id, id);
      expect(await repo.completed(id).first, false);
      await db.doc('posts/bob').set({'authorId': 'bob', 'weeklyDareId': id});
      expect(await repo.completed(id).first, false);
      await db.doc('posts/alice').set({
        'authorId': 'alice',
        'weeklyDareId': id,
      });
      expect(await repo.completed(id).first, true);
      await db.doc('posts/alice').delete();
      expect(await repo.completed(id).first, false);
      await auth.signOut();
      expect(await repo.completed(id).first, false);
    },
  );
  for (final type in ['image', 'video']) {
    test(
      '$type upload awards only the active matching dare, deduplicates weeks, preserves ordinary captures',
      () async {
        final db = FakeFirebaseFirestore();
        final auth = MockFirebaseAuth(
          mockUser: MockUser(uid: 'alice'),
          signedIn: true,
        );
        final posts = PostRepository(
          firestore: db,
          auth: auth,
          storage: MockFirebaseStorage(),
        );
        final now = DateTime.now().toUtc(),
            week = WeeklyDare.weekId(DateTime.now());
        await db.doc('weeklyDares/$week').set(schedule(now));
        final temp = await Directory.systemTemp.createTemp('weekly-test-');
        try {
          final file = await File(
            '${temp.path}/capture',
          ).writeAsBytes([1, 2, 3]);
          Future<void> create(String postId, {String? weekly, String? text}) =>
              posts.createPost(
                dareText: text ?? schedule(now)['dareText'] as String,
                mediaFile: file,
                mediaType: type,
                moodId: 'happy',
                moodName: 'Happy',
                postId: postId,
                weeklyDareId: weekly,
              );
          await expectLater(
            create('bad', weekly: '../bad'),
            throwsFormatException,
          );
          await expectLater(
            create('mismatch', weekly: week, text: 'Another dare'),
            throwsFormatException,
          );
          await create('first', weekly: week);
          await create('first', weekly: week);
          await create('repeat', weekly: week);
          await create('ordinary');
          expect(
            (await db.doc('posts/first').get()).data()!['weeklyDareId'],
            week,
          );
          expect(
            (await db.doc('posts/ordinary').get()).data()!.containsKey(
              'weeklyDareId',
            ),
            false,
          );
          expect(
            (await posts.getUserStats('alice'))['weeklyDaresCompleted'],
            1,
          );
          final prior = now.subtract(const Duration(days: 7)),
              old = WeeklyDare.weekId(now.subtract(const Duration(days: 7)));
          await db.doc('weeklyDares/$old').set(schedule(prior));
          await create('late', weekly: old);
          expect(
            (await db.doc('posts/late').get()).data()!.containsKey(
              'weeklyDareId',
            ),
            false,
          );
          await create('missing', weekly: '2000-01-03');
          expect(
            (await db.doc('posts/missing').get()).data()!.containsKey(
              'weeklyDareId',
            ),
            false,
          );
          final data = (await db.doc('posts/first').get()).data()!;
          final lifetime = (data['expiresAt'] as Timestamp).toDate().difference(
            now,
          );
          expect(lifetime.inHours, 24);
          // Historical credit is retained on a post when it leaves the feed.
          await db.doc('posts/historical').set({...data, 'weeklyDareId': old});
          expect(
            (await posts.getUserStats('alice'))['weeklyDaresCompleted'],
            2,
          );
          await db.doc('posts/first').delete();
          expect(
            (await posts.getUserStats('alice'))['weeklyDaresCompleted'],
            2,
          );
          await db.doc('posts/repeat').delete();
          expect(
            (await posts.getUserStats('alice'))['weeklyDaresCompleted'],
            1,
          );
        } finally {
          await temp.delete(recursive: true);
        }
      },
    );
  }
  for (final width in [320.0, 390.0, 768.0]) {
    testWidgets(
      'weekly card fits width $width with large text; joining carries exact challenge and does not award credit',
      (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = TestWeekly();
        addTearDown(repo.close);
        WeeklyDare? opened;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: ListView(
                children: [
                  WeeklyDareCard(
                    preferences: MemoryPreference(),
                    repository: repo,
                    now: () => date,
                    cameraBuilder: (value) {
                      opened = value;
                      return const Scaffold(body: Text('Capture'));
                    },
                  ),
                ],
              ),
            ),
          ),
        );
        repo.changes.add(dare);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('A little joy'), findsOneWidget);
        await Scrollable.ensureVisible(
          tester.element(find.text('Join this week')),
          alignment: .5,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Join this week'));
        await tester.pumpAndSettle();
        expect(opened!.id, id);
        expect(opened!.prompt.text, dare.prompt.text);
        Navigator.of(tester.element(find.text('Capture'))).pop();
        await tester.pumpAndSettle();
        repo.changes.add(dare);
        await tester.pumpAndSettle();
        expect(find.text('✓ You joined this week'), findsNothing);
        repo.progress.add(true);
        await tester.pumpAndSettle();
        expect(find.text('✓ You joined this week'), findsOneWidget);
        expect(find.text('Make another moment'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'error retry, absent schedule, countdown, resumed week rollover and expired tap',
    (tester) async {
      var now = date;
      final repo = TestWeekly();
      addTearDown(repo.close);
      var opens = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: WeeklyDareCard(
                preferences: MemoryPreference(),
                repository: repo,
                now: () => now,
                cameraBuilder: (_) {
                  opens++;
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      repo.changes.addError(StateError('Offline'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry'));
      await tester.pump();
      repo.changes.add(null);
      await tester.pumpAndSettle();
      expect(find.text('Join this week'), findsNothing);
      repo.changes.add(dare);
      await tester.pumpAndSettle();
      expect(find.text('4d left'), findsOneWidget);
      now = dare.endsAt.subtract(const Duration(hours: 2));
      await tester.pump(const Duration(minutes: 1));
      expect(find.text('2h left'), findsOneWidget);
      now = dare.endsAt.subtract(const Duration(minutes: 10));
      await tester.pump(const Duration(minutes: 1));
      expect(find.text('10m left'), findsOneWidget);
      now = dare.endsAt;
      await tester.tap(find.text('Join this week'));
      await tester.pumpAndSettle();
      expect(opens, 0);
      expect(repo.weeks.last, '2026-09-28');
      expect(find.text('Join this week'), findsNothing);
      now = now.add(const Duration(days: 7));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(repo.weeks.last, '2026-10-05');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'weekly milestones distinguish first participation and four nonconsecutive weeks',
    (tester) async {
      for (final weeks in [0, 1, 4]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatsAndBadges(
                daresCompleted: 0,
                moodsExplored: 0,
                weeklyDaresCompleted: weeks,
              ),
            ),
          ),
        );
        await tester.scrollUntilVisible(find.text('Showing up together'), 180);
        final first = find.ancestor(
          of: find.text('Part of the moment'),
          matching: find.byType(ListTile),
        );
        final four = find.ancestor(
          of: find.text('Showing up together'),
          matching: find.byType(ListTile),
        );
        expect(
          find.descendant(of: first, matching: find.byIcon(Icons.check_circle)),
          weeks > 0 ? findsOneWidget : findsNothing,
        );
        expect(
          find.descendant(of: four, matching: find.byIcon(Icons.check_circle)),
          weeks >= 4 ? findsOneWidget : findsNothing,
        );
      }
    },
  );
}
