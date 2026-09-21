import 'dart:async';
import 'package:mooddare/features/profile/data/social_repository.dart';
import 'package:mooddare/models/user_model.dart';

class MemorySocial implements SocialRepository {
  @override
  String? currentUserId = 'viewer';
  final following = <String, Set<String>>{};
  final followers = <String, Set<String>>{};
  final users = <String, UserModel>{};
  final changed = StreamController<void>.broadcast();
  bool fail = false, failPeople = false;
  int writes = 0;
  final reports = <(String, UserReportReason)>[];
  Completer<void>? reportGate;
  @override
  Future<void> reportUser(String target, UserReportReason reason) async {
    if (reportGate != null) await reportGate!.future;
    if (fail) throw StateError('Offline');
    reports.add((target, reason));
  }

  final blockedIds = <String>{};
  @override
  Stream<Set<String>> blocked() async* {
    yield Set.of(blockedIds);
    yield* changed.stream.map((_) => Set.of(blockedIds));
  }

  @override
  Stream<Set<String>> connections(
    String uid, {
    required bool followers,
  }) async* {
    Set<String> value() =>
        Set.of((followers ? this.followers : following)[uid] ?? {});
    yield value();
    yield* changed.stream.map((_) => value());
  }

  @override
  Future<List<UserModel>> people(Set<String> ids) async {
    if (failPeople) throw StateError('Offline');
    return ids.map((id) => users[id]).whereType<UserModel>().toList();
  }

  @override
  Future<void> setFollowing(String target, bool follow) async {
    writes++;
    if (fail) throw StateError('Offline');
    if (follow) {
      following.putIfAbsent(currentUserId!, () => {}).add(target);
      followers.putIfAbsent(target, () => {}).add(currentUserId!);
    } else {
      following[currentUserId]?.remove(target);
      followers[target]?.remove(currentUserId);
    }
    changed.add(null);
  }

  @override
  Future<void> block(String target) async {
    if (fail) throw StateError('Offline');
    blockedIds.add(target);
    await setFollowing(target, false);
    following[target]?.remove(currentUserId);
    followers[currentUserId]?.remove(target);
    changed.add(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
