import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:path_provider/path_provider.dart';
import 'capture_draft.dart';

/// Account-scoped private storage. Originals are copied before camera cleanup;
/// atomic manifests preserve edits across process death without uploading media.
class DraftRepository {
  static final instance = DraftRepository(
    currentUserId: () =>
        Firebase.apps.isEmpty ? null : FirebaseAuth.instance.currentUser?.uid,
  );
  final String? Function() currentUserId;
  final Future<Directory> Function() directory;
  final _changes = StreamController<String>.broadcast();
  Future<void> _pending = Future.value();
  DraftRepository({
    required this.currentUserId,
    Future<Directory> Function()? directory,
  }) : directory = directory ?? getApplicationSupportDirectory;
  void _authorize(String owner) {
    if (owner.isEmpty || currentUserId() != owner) {
      throw StateError('Sign in to the account that saved this draft.');
    }
  }

  Future<Directory> _folder(String owner) async => Directory(
    '${(await directory()).path}/mooddare-drafts/${base64Url.encode(utf8.encode(owner))}',
  );
  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<List<CaptureDraft>> list(String owner) async {
    await _pending;
    return _read(owner);
  }

  Future<List<CaptureDraft>> _read(String owner) async {
    _authorize(owner);
    final folder = await _folder(owner);
    if (!await folder.exists()) return [];
    final drafts = <CaptureDraft>[];
    await for (final entry in folder.list(followLinks: false)) {
      if (entry is! Directory) continue;
      try {
        final manifest = File('${entry.path}/draft.json');
        if (!await manifest.exists() || await manifest.length() > 65536) {
          continue;
        }
        final data =
            jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
        final file = File(
          '${entry.path}/capture.${data['mediaType'] == 'image' ? 'jpg' : 'mp4'}',
        );
        final draft = CaptureDraft.fromJson(data, file);
        if (draft.ownerId != owner ||
            entry.path.split(Platform.pathSeparator).last != draft.id ||
            !await file.exists() ||
            await file.length() == 0 ||
            await File('${entry.path}/posted').exists()) {
          continue;
        }
        drafts.add(draft);
      } on FormatException {
        continue;
      } on FileSystemException {
        continue;
      } on TypeError {
        continue;
      }
    }
    _authorize(owner);
    drafts.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return drafts;
  }

  Stream<List<CaptureDraft>> watch(String owner) => Stream.multi((sink) {
    var active = true;
    var revision = 0;
    void refresh() {
      final current = ++revision;
      list(owner).then(
        (items) {
          if (active && current == revision) sink.add(items);
        },
        onError: (Object error, StackTrace stack) {
          if (active && current == revision) sink.addError(error, stack);
        },
      );
    }

    final subscription = _changes.stream
        .where((id) => id == owner)
        .listen((_) => refresh());
    refresh();
    sink.onCancel = () {
      active = false;
      return subscription.cancel();
    };
  });
  Future<void> save(CaptureDraft draft) => _serial(() async {
    _authorize(draft.ownerId);
    // Validate data and IDs before using either to construct a path.
    CaptureDraft.fromJson(draft.toJson(), draft.mediaFile);
    final folder = Directory(
      '${(await _folder(draft.ownerId)).path}/${draft.id}',
    );
    final original = File(
      '${folder.path}/capture.${draft.mediaType == 'image' ? 'jpg' : 'mp4'}',
    );
    if (await File('${folder.path}/posted').exists()) {
      throw StateError('This draft has already been posted.');
    }
    if (!await original.exists()) {
      final drafts = await _read(draft.ownerId);
      var used = 0;
      for (final item in drafts) {
        used += await item.mediaFile.length();
      }
      final size = await draft.mediaFile.length();
      if (size == 0) throw const FormatException('The capture is empty.');
      if (drafts.length >= 20 || used + size > 300 * 1024 * 1024) {
        throw StateError(
          'Drafts are full. Delete an older draft to make room.',
        );
      }
      await folder.create(recursive: true);
      final copying = File('${original.path}.tmp');
      await draft.mediaFile.copy(copying.path);
      await copying.rename(original.path);
    }
    _authorize(draft.ownerId);
    final temp = File('${folder.path}/draft.json.tmp');
    await temp.writeAsString(jsonEncode(draft.toJson()), flush: true);
    _authorize(draft.ownerId);
    await temp.rename('${folder.path}/draft.json');
    _changes.add(draft.ownerId);
  });
  Future<void> delete(String owner, String id, {bool posted = false}) =>
      _serial(() async {
        _authorize(owner);
        if (!CaptureDraft.validId(id)) {
          throw const FormatException('Invalid draft.');
        }
        final folder = Directory('${(await _folder(owner)).path}/$id');
        if (await folder.exists()) {
          if (posted) {
            await File('${folder.path}/posted').writeAsString('1', flush: true);
          }
          await folder.delete(recursive: true);
        }
        _changes.add(owner);
      });
  Future<void> clear(String owner) => _serial(() async {
    _authorize(owner);
    final folder = await _folder(owner);
    if (await folder.exists()) await folder.delete(recursive: true);
    _changes.add(owner);
  });
}
