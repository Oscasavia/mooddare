import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/features/drafts/data/capture_draft.dart';
import 'package:mooddare/features/drafts/data/draft_repository.dart';
import 'package:mooddare/features/camera/data/video_editor.dart';
import 'package:mooddare/features/camera/domain/photo_processing.dart';

void main() {
  late Directory dir;
  late File original;
  String? owner = 'alice';
  late DraftRepository repo;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('drafts-test-');
    original = await File('${dir.path}/original.jpg').writeAsBytes([1, 2, 3]);
    owner = 'alice';
    repo = DraftRepository(
      currentUserId: () => owner,
      directory: () async => dir,
    );
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  CaptureDraft draft({
    String id = 'first',
    String uid = 'alice',
    String type = 'image',
    double warmth = .4,
  }) => CaptureDraft(
    id: id,
    ownerId: uid,
    mediaType: type,
    dareText: 'Take a deep breath',
    mediaFile: original,
    moodId: 'relaxed',
    moodName: 'Relaxed',
    weeklyDareId: '2026-09-28',
    liveLens: 'Golden Hour',
    adjustments: PhotoAdjustments(
      smoothing: .5,
      brightness: .2,
      warmth: warmth,
    ),
    crop: const Rect.fromLTRB(.1, .2, .8, .9),
    videoEdits: type == 'video'
        ? const VideoEdits(startMs: 1200, endMs: 4500, muted: true)
        : null,
    updatedAt: DateTime.utc(2026, 10, 1),
  );
  test(
    'a draft survives source cleanup and process restart with editable photo settings and metadata',
    () async {
      await repo.save(draft());
      await original.delete();
      final restarted = DraftRepository(
        currentUserId: () => owner,
        directory: () async => dir,
      );
      final saved = (await restarted.list('alice')).single;
      expect(await saved.mediaFile.readAsBytes(), [1, 2, 3]);
      expect(saved.id, 'first');
      expect(saved.dareText, 'Take a deep breath');
      expect(saved.moodId, 'relaxed');
      expect(saved.weeklyDareId, '2026-09-28');
      expect(saved.liveLens, 'Golden Hour');
      expect(saved.crop, const Rect.fromLTRB(.1, .2, .8, .9));
      expect(saved.adjustments.smoothing, .5);
      expect(saved.adjustments.warmth, .4);
    },
  );
  test(
    'video trim and mute round-trip without baking away the original',
    () async {
      await repo.save(draft(type: 'video'));
      final saved = (await repo.list('alice')).single;
      expect(saved.videoEdits!.startMs, 1200);
      expect(saved.videoEdits!.endMs, 4500);
      expect(saved.videoEdits!.muted, true);
      expect(await saved.mediaFile.readAsBytes(), [1, 2, 3]);
    },
  );
  test(
    'serialized saves keep latest settings and deletion cannot resurrect a queued draft',
    () async {
      final first = repo.save(draft(warmth: .1));
      final latest = repo.save(draft(warmth: .8));
      await Future.wait([first, latest]);
      expect((await repo.list('alice')).single.adjustments.warmth, .8);
      final saving = repo.save(draft(warmth: .2));
      final deletion = repo.delete('alice', 'first');
      await Future.wait([saving, deletion]);
      expect(await repo.list('alice'), isEmpty);
    },
  );
  test(
    'accounts cannot read, save or delete each others drafts; sign-in restores only their own',
    () async {
      await repo.save(draft());
      owner = 'bob';
      expect(await repo.list('bob'), isEmpty);
      await expectLater(repo.list('alice'), throwsStateError);
      await expectLater(repo.save(draft()), throwsStateError);
      await expectLater(repo.delete('alice', 'first'), throwsStateError);
      owner = null;
      await expectLater(repo.list('alice'), throwsStateError);
      owner = 'alice';
      expect(await repo.list('alice'), hasLength(1));
    },
  );
  test(
    'account switch during a save cannot publish another account draft manifest',
    () async {
      final switched = DraftRepository(
        currentUserId: () => owner,
        directory: () async {
          owner = 'bob';
          return dir;
        },
      );
      await expectLater(switched.save(draft()), throwsStateError);
      owner = 'alice';
      expect(await repo.list('alice'), isEmpty);
    },
  );
  test(
    'invalid metadata, path traversal and empty captures are rejected',
    () async {
      await expectLater(
        repo.save(draft(id: '../elsewhere')),
        throwsFormatException,
      );
      await expectLater(
        repo.delete('alice', '../elsewhere'),
        throwsFormatException,
      );
      await original.writeAsBytes([]);
      await expectLater(repo.save(draft()), throwsFormatException);
      expect(await repo.list('alice'), isEmpty);
    },
  );
  test(
    'corrupt manifests and partial writes do not hide healthy drafts; posted markers prevent duplicates',
    () async {
      await repo.save(draft());
      final first = (await repo.list('alice')).single;
      final folder = first.mediaFile.parent;
      final bad = Directory('${folder.parent.path}/broken');
      await bad.create();
      await File('${bad.path}/draft.json').writeAsString('{broken');
      await File('${folder.path}/draft.json.tmp').writeAsString('unfinished');
      expect(await repo.list('alice'), hasLength(1));
      await File('${folder.path}/posted').writeAsString('1');
      expect(await repo.list('alice'), isEmpty);
      await expectLater(repo.save(draft()), throwsStateError);
    },
  );
  test(
    'a manifest cannot point to a different owner or external path',
    () async {
      await repo.save(draft());
      final d = (await repo.list('alice')).single;
      final file = File('${d.mediaFile.parent.path}/draft.json');
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      data['ownerId'] = 'bob';
      await file.writeAsString(jsonEncode(data));
      expect(await repo.list('alice'), isEmpty);
    },
  );
  test(
    'saving failure is retryable and does not poison subsequent writes',
    () async {
      await original.delete();
      await expectLater(
        repo.save(draft()),
        throwsA(isA<FileSystemException>()),
      );
      await original.writeAsBytes([1]);
      await repo.save(draft());
      expect(await repo.list('alice'), hasLength(1));
    },
  );
  test(
    'draft quota allows edits but requires deletion before another capture',
    () async {
      for (var i = 0; i < 20; i++) {
        await repo.save(draft(id: 'draft-$i'));
      }
      await expectLater(repo.save(draft(id: 'overflow')), throwsStateError);
      await repo.save(draft(id: 'draft-0', warmth: .9));
      expect(
        (await repo.list(
          'alice',
        )).firstWhere((d) => d.id == 'draft-0').adjustments.warmth,
        .9,
      );
      await repo.delete('alice', 'draft-1');
      await repo.save(draft(id: 'replacement'));
      expect(await repo.list('alice'), hasLength(20));
    },
  );
  test('clear removes only the signed-in account and streams update', () async {
    final saved = Completer<void>();
    final cleared = Completer<void>();
    var clearing = false;
    final sub = repo.watch('alice').listen((items) {
      if (items.length == 1 && !saved.isCompleted) saved.complete();
      if (clearing && items.isEmpty && !cleared.isCompleted) cleared.complete();
    });
    await repo.save(draft());
    await saved.future.timeout(const Duration(seconds: 5));
    owner = 'bob';
    await repo.save(draft(uid: 'bob', id: 'second'));
    await repo.clear('bob');
    owner = 'alice';
    expect(await repo.list('alice'), hasLength(1));
    clearing = true;
    await repo.clear('alice');
    await cleared.future.timeout(const Duration(seconds: 5));
    await sub.cancel();
  });
}
