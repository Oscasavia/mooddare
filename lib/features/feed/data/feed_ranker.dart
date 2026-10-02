import 'dart:math' as math;
import 'package:mooddare/models/post_model.dart';

enum FeedOrder { forYou, latest }

enum FeedActivity { viewed, completed, like, unlike, saved, notInterested }

/// One bounded contribution per moment: looping or repeated taps cannot farm
/// affinity. These are preferences, never a measure of a person's mental state.
class FeedSignal {
  final String postId, authorId;
  final String? moodId;
  final DateTime updatedAt;
  final bool viewed, completed, liked, saved, notInterested;
  const FeedSignal({
    required this.postId,
    required this.authorId,
    this.moodId,
    required this.updatedAt,
    this.viewed = false,
    this.completed = false,
    this.liked = false,
    this.saved = false,
    this.notInterested = false,
  });

  double get weight => notInterested
      ? -5
      : (viewed ? .4 : 0) +
            (completed ? .8 : 0) +
            (liked ? 3 : 0) +
            (saved ? 4 : 0);

  FeedSignal withActivity(FeedActivity activity, DateTime now) => FeedSignal(
    postId: postId,
    authorId: authorId,
    moodId: moodId,
    updatedAt: now,
    viewed: viewed || activity == FeedActivity.viewed,
    completed: completed || activity == FeedActivity.completed,
    liked: activity == FeedActivity.like
        ? true
        : activity == FeedActivity.unlike
        ? false
        : liked,
    saved: saved || activity == FeedActivity.saved,
    notInterested: notInterested || activity == FeedActivity.notInterested,
  );
}

class FeedRanker {
  static const historyDays = 30;
  static List<PostModel> rank(
    Iterable<PostModel> candidates, {
    required DateTime now,
    required String? viewerId,
    Iterable<FeedSignal> history = const [],
    Set<String> following = const {},
    Set<String> blocked = const {},
    FeedOrder order = FeedOrder.forYou,
  }) {
    final signals = {
      for (final signal in history)
        if (now.difference(signal.updatedAt).inDays < historyDays &&
            !signal.updatedAt.isAfter(now.add(const Duration(minutes: 5))) &&
            signal.authorId != viewerId &&
            !blocked.contains(signal.authorId))
          signal.postId: signal,
    };
    final moods = <String, double>{}, authors = <String, double>{};
    for (final signal in signals.values) {
      final days = math.max(0, now.difference(signal.updatedAt).inHours / 24);
      final contribution = signal.weight * math.pow(.5, days / 7);
      authors.update(
        signal.authorId,
        (v) => v + contribution,
        ifAbsent: () => contribution,
      );
      if (signal.moodId != null) {
        moods.update(
          signal.moodId!,
          (v) => v + contribution,
          ifAbsent: () => contribution,
        );
      }
    }
    final remaining = {for (final p in candidates) p.id: p}.values
        .where(
          (p) =>
              !p.deleting &&
              !blocked.contains(p.authorId) &&
              p.expiresAt.toDate().isAfter(now) &&
              signals[p.id]?.notInterested != true,
        )
        .toList();
    int newest(PostModel a, PostModel b) {
      final age = b.createdAt.compareTo(a.createdAt);
      return age == 0 ? a.id.compareTo(b.id) : age;
    }

    remaining.sort(newest);
    if (order == FeedOrder.latest) return remaining;

    double score(PostModel p) {
      final age = math.max(
        0,
        now.difference(p.createdAt.toDate()).inMinutes / 60,
      );
      return 3 * math.exp(-age / 12) +
          (moods[p.moodId] ?? 0).clamp(-6, 6) * .65 +
          (authors[p.authorId] ?? 0).clamp(-4, 4) * .4 +
          (following.contains(p.authorId) ? .8 : 0) -
          (signals[p.id]?.viewed == true ? 1.5 : 0);
    }

    final result = <PostModel>[];
    while (remaining.isNotEmpty) {
      // Every fifth slot explores a fresh, unseen moment. Elsewhere, penalize
      // repeats within the last three slots so one creator cannot fill a page.
      final recent = result.reversed.take(3);
      double adjusted(PostModel p) =>
          score(p) -
          recent.where((r) => r.authorId == p.authorId).length * 3 -
          recent.where((r) => r.moodId != null && r.moodId == p.moodId).length *
              .8;
      var pick = remaining.first;
      if (result.length % 5 == 4) {
        pick = remaining.firstWhere(
          (p) =>
              signals[p.id] == null &&
              !recent.any((r) => r.authorId == p.authorId),
          orElse: () => remaining.first,
        );
      } else {
        for (final p in remaining.skip(1)) {
          if (adjusted(p) > adjusted(pick)) pick = p;
        }
      }
      remaining.remove(pick);
      result.add(pick);
    }
    return result;
  }
}
