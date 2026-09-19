import 'package:flutter/services.dart';
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
}) => PostModel(
  id: id,
  dareText: 'A moment worth sharing: $id',
  mediaUrl: url ?? 'https://example.invalid/$id',
  mediaType: type,
  authorId: 'author',
  createdAt: Timestamp.now(),
  expiresAt: Timestamp.fromDate(
    DateTime.now().add(Duration(hours: expired ? -1 : 24)),
  ),
  likedBy: [],
);

class MemoryPosts implements PostRepository {
  final List<PostModel> posts;
  int likes = 0, reports = 0;
  MemoryPosts(this.posts);
  @override
  String? get currentUserId => 'viewer';
  @override
  Future<UserModel?> getAuthor(String uid) async => null;
  @override
  Stream<List<PostModel>> getPosts() => Stream.value(posts);
  @override
  Stream<Set<String>> blockedAuthors() => Stream.value({});
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
  Future<void> setVolume(int playerId, double volume) async {}
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
