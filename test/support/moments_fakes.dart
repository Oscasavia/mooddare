import 'dart:async';
import 'package:flutter/services.dart';
import 'package:mooddare/models/comment_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:mooddare/features/feed/data/repositories/post_repository.dart';
import 'package:mooddare/models/post_model.dart';
import 'package:mooddare/models/user_model.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

PostModel moment(
  String id, {
  String type = 'image',
  String? url,
  bool expired = false,
  String? moodId,
  String? moodName,
  List<String> likedBy = const [],
}) => PostModel(
  id: id,
  moodId: moodId,
  moodName: moodName,
  dareText: 'A moment worth sharing: $id',
  mediaUrl: url ?? 'https://example.invalid/$id',
  mediaType: type,
  authorId: 'author',
  createdAt: Timestamp.now(),
  expiresAt: Timestamp.fromDate(
    DateTime.now().add(Duration(hours: expired ? -1 : 24)),
  ),
  likedBy: likedBy,
);

class MemoryPosts implements PostRepository {
  final List<PostModel> posts;
  int likes = 0, reports = 0, reads = 0;
  final comments = <CommentModel>[];
  final commentChanges = StreamController<List<CommentModel>>.broadcast();
  final submissions = <String>[];
  String? selectedMood;
  bool failComments = false,
      failSending = false,
      failEdit = false,
      failCommentLike = false;
  int? commentCount;
  int commentLikes = 0;
  bool failLikers = false;
  List<String>? likerIds;
  final authors = <String, UserModel>{};
  final authorReads = <String>[];
  String? uid = 'viewer';
  Set<String> blocked = {};
  MemoryPosts(this.posts);
  @override
  String? get currentUserId => uid;
  @override
  Future<UserModel?> getAuthor(String uid) async {
    authorReads.add(uid);
    return authors[uid];
  }

  @override
  Future<List<String>> getPostLikerIds(String postId) async {
    if (failLikers) throw StateError('Offline');
    return likerIds ?? posts.firstWhere((p) => p.id == postId).likedBy;
  }

  @override
  Future<Map<String, String>> getMoodOptions() async => {};
  @override
  Stream<List<PostModel>> getPosts({String? moodId}) {
    reads++;
    selectedMood = moodId;
    return Stream.value(
      posts.where((p) => moodId == null || p.moodId == moodId).toList(),
    );
  }

  @override
  Stream<List<CommentModel>> getComments(String id) async* {
    if (failComments) throw StateError('Offline');
    yield List.of(comments);
    yield* commentChanges.stream;
  }

  @override
  Future<void> addComment(String postId, String commentId, String text) async {
    submissions.add(commentId);
    if (failSending) throw StateError('Offline');
    comments.insert(0, CommentModel(id: commentId, authorId: uid!, text: text));
    commentChanges.add(List.of(comments));
  }

  @override
  Future<int> getCommentCount(String id) async =>
      commentCount ?? comments.length;

  @override
  Future<void> editComment(String postId, String commentId, String text) async {
    if (failEdit) throw StateError('Offline');
    final index = comments.indexWhere((c) => c.id == commentId);
    final old = comments[index];
    comments[index] = CommentModel(
      id: old.id,
      authorId: old.authorId,
      text: text,
      createdAt: old.createdAt,
      editedAt: DateTime.now(),
      likedBy: old.likedBy,
    );
    commentChanges.add(List.of(comments));
  }

  @override
  Future<void> toggleCommentLike(String postId, String commentId) async {
    commentLikes++;
    if (failCommentLike) throw StateError('Offline');
    final index = comments.indexWhere((c) => c.id == commentId);
    final old = comments[index];
    final likes = List<String>.of(old.likedBy);
    if (likes.contains(uid)) {
      likes.remove(uid);
    } else {
      likes.add(uid!);
    }
    comments[index] = CommentModel(
      id: old.id,
      authorId: old.authorId,
      text: old.text,
      createdAt: old.createdAt,
      editedAt: old.editedAt,
      likedBy: likes,
    );
    commentChanges.add(List.of(comments));
  }

  @override
  Future<void> deleteComment(String postId, String commentId) async {
    comments.removeWhere((c) => c.id == commentId);
    commentChanges.add(List.of(comments));
  }

  @override
  Stream<Set<String>> blockedAuthors() => Stream.value(blocked);
  @override
  Future<void> toggleLike(String id, String uid) async {
    likes++;
  }

  @override
  Future<void> reportPost(String id) async {
    reports++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MemoryVideo extends VideoPlayerPlatform {
  final Size size;
  final bool failToLoad;
  MemoryVideo({this.size = const Size(720, 1280), this.failToLoad = false});
  int created = 0;
  final calls = <String>[];
  final playing = <int, bool>{};
  final volumes = <int, double>{};
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = ++created;
    playing[id] = false;
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => failToLoad
      ? Stream.error(
          PlatformException(code: 'VideoError', message: 'Video unavailable'),
        )
      : Stream.value(
          VideoEvent(
            eventType: VideoEventType.initialized,
            duration: const Duration(seconds: 10),
            size: size,
          ),
        );
  @override
  Future<void> dispose(int playerId) async {
    calls.add('dispose $playerId');
    playing.remove(playerId);
    volumes.remove(playerId);
  }

  @override
  Future<void> play(int playerId) async {
    calls.add('play $playerId');
    playing[playerId] = true;
  }

  @override
  Future<void> pause(int playerId) async {
    calls.add('pause $playerId');
    playing[playerId] = false;
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {
    calls.add('volume $playerId $volume');
    volumes[playerId] = volume;
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> seekTo(int playerId, Duration position) async {}
  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;
  @override
  Widget buildViewWithOptions(VideoViewOptions options) => ColoredBox(
    key: ValueKey('video_${options.playerId}'),
    color: Colors.teal,
  );
}
