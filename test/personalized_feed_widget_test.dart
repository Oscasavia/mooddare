import 'dart:async';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/features/feed/data/feed_preferences.dart';
import 'package:mooddare/features/feed/data/feed_ranker.dart';
import 'package:mooddare/features/feed/presentation/widgets/dare_proof_card.dart';
import 'package:mooddare/models/post_model.dart';
import 'moments_test.dart' show openFeed, tapMedia;
import 'support/moments_fakes.dart';

class UpdatingPosts extends MemoryPosts {
  UpdatingPosts(super.posts);
  final updates = StreamController<List<PostModel>>.broadcast();
  @override
  Stream<List<PostModel>> getPosts({String? moodId}) async* {
    yield List.of(posts);
    yield* updates.stream;
  }
}

class MovingVideo extends MemoryVideo {
  Duration position = Duration.zero;
  @override
  Future<Duration> getPosition(int playerId) async => position;
}

void main() {
  late FakeFirebaseFirestore db;
  late FeedPreferences preferences;
  setUp(() {
    db = FakeFirebaseFirestore();
    preferences = FeedPreferences(
      db: db,
      uid: 'viewer',
      isCurrentUser: () => true,
    );
  });
  testWidgets(
    'video learning excludes stalled playback and seeking, and caps completion',
    (tester) async {
      final video = MovingVideo();
      final repo = MemoryPosts([moment('clip', type: 'video')]);
      await openFeed(tester, repo, video: video, preferences: preferences);
      await tester.pump(const Duration(seconds: 6));
      expect(preferences.history, isEmpty);
      video.position = const Duration(seconds: 9);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        preferences.history,
        isEmpty,
        reason: 'Seeking to the end is not completion',
      );
      for (var second = 0; second <= 9; second++) {
        video.position = Duration(seconds: second);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(preferences.history['clip']!.viewed, isTrue);
      expect(preferences.history['clip']!.completed, isTrue);
      final weight = preferences.history['clip']!.weight;
      await tester.pump(const Duration(seconds: 20));
      expect(preferences.history['clip']!.weight, weight);
    },
  );
  testWidgets(
    'For you ranks learned moods; Latest is available and survives reopening',
    (tester) async {
      final repo = MemoryPosts([
        moment('relaxed', moodId: 'relaxed'),
        moment('creative', moodId: 'creative'),
      ]);
      await tester.runAsync(() async {
        await preferences.load();
        await preferences.record(
          moment('prior', moodId: 'creative'),
          FeedActivity.saved,
        );
      });
      await openFeed(tester, repo, preferences: preferences);
      expect(
        find.text('A moment worth sharing: creative').hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Filter by mood'));
      await tester.pumpAndSettle();
      expect(find.text('For you'), findsOneWidget);
      await tester.tap(find.text('Latest'));
      await tester.pumpAndSettle();
      expect(preferences.order, FeedOrder.latest);
      expect(
        (await tester.runAsync(
          () => db.doc('users/viewer/preferences/feed').get(),
        ))!.data()!['order'],
        'latest',
      );
      await tester.pump(const Duration(seconds: 8));
      expect(preferences.history.keys, ['prior']);
    },
  );
  testWidgets(
    'photo dwell excludes background and modal time; successful like learns once',
    (tester) async {
      final repo = MemoryPosts([moment('photo')]);
      await openFeed(tester, repo, preferences: preferences);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 8));
      expect(preferences.history, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.tap(find.byTooltip('Filter by mood'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 8));
      expect(preferences.history, isEmpty);
      Navigator.of(tester.element(find.text('For you'))).pop();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 6));
      expect(preferences.history['photo']!.viewed, isTrue);
      await tester.tap(find.byTooltip('Like'));
      await tester.pumpAndSettle();
      expect(preferences.history['photo']!.liked, isTrue);
      await tester.tap(find.byTooltip('Unlike'));
      await tester.pumpAndSettle();
      expect(preferences.history['photo']!.liked, isFalse);
    },
  );
  testWidgets(
    'not interested in full viewer closes it, removes moment and persists feedback',
    (tester) async {
      final repo = MemoryPosts([moment('one')]);
      await openFeed(tester, repo, preferences: preferences);
      await tapMedia(tester);
      await tester.tap(find.byTooltip('Moment options').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not interested'));
      await tester.pumpAndSettle();
      expect(preferences.history['one']!.notInterested, isTrue);
      expect(find.byType(DareProofCard), findsNothing);
    },
  );
  testWidgets(
    'feed reset asks first, preserves likes and clears private history',
    (tester) async {
      final repo = MemoryPosts([moment('one')]);
      await openFeed(tester, repo, preferences: preferences);
      await tester.runAsync(
        () => preferences.record(repo.posts.first, FeedActivity.like),
      );
      await tester.tap(find.byTooltip('Filter by mood'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset feed preferences'));
      await tester.pumpAndSettle();
      expect(preferences.history, isNotEmpty);
      await tester.tap(find.text('Reset feed'));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      for (var i = 0; i < 20 && preferences.history.isNotEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(preferences.history, isEmpty);
      expect(repo.likes, 0);
    },
  );
  testWidgets(
    'live arrivals do not reorder current moment; removal before it preserves anchor',
    (tester) async {
      final repo = UpdatingPosts([moment('first'), moment('second')]);
      addTearDown(repo.updates.close);
      await openFeed(tester, repo, preferences: preferences);
      final shown = tester
          .widget<DareProofCard>(find.byType(DareProofCard).first)
          .post
          .id;
      final other = shown == 'first' ? 'second' : 'first';
      await tester.drag(find.byType(PageView), const Offset(0, -650));
      await tester.pumpAndSettle();
      expect(
        find.text('A moment worth sharing: $other').hitTestable(),
        findsOneWidget,
      );
      repo.updates.add([repo.posts.firstWhere((p) => p.id == other)]);
      await tester.pumpAndSettle();
      expect(
        find.text('A moment worth sharing: $other').hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
