import 'dart:io';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/features/feed/data/repositories/post_repository.dart';
import 'package:mooddare/features/feed/presentation/widgets/dare_proof_card.dart';
import 'package:mooddare/models/post_model.dart';
import 'support/moments_fakes.dart';

class DownloadPosts extends MemoryPosts {
  DownloadPosts(super.posts);
  int downloads = 0;
  bool fail = false;
  @override
  Future<void> downloadPost(PostModel post) async {
    downloads++;
    if (fail) throw StateError('Denied');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'gallery downloads preserve the stored bytes, clean temporary files, and stop before downloading when permission denied',
    () async {
      final temp = await Directory.systemTemp.createTemp('downloads-test-');
      final storage = MockFirebaseStorage();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final saved = <List<int>>[];
      final files = <File>[];
      bool allowed = true, failDownload = false;
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => temp.path,
      );
      messenger.setMockMethodCallHandler(const MethodChannel('gal'), (
        call,
      ) async {
        if (call.method == 'hasAccess' || call.method == 'requestAccess') {
          return allowed;
        }
        saved.add(
          await File((call.arguments as Map)['path'] as String).readAsBytes(),
        );
        return null;
      });
      final repo = PostRepository(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(),
        storage: storage,
        downloadFile: (ref, file) async {
          files.add(file);
          if (failDownload) throw StateError('Network interrupted');
          await file.writeAsBytes((await ref.getData())!);
        },
      );
      try {
        for (final type in ['image', 'video']) {
          final bytes = Uint8List.fromList([1, 9, type.length]);
          final ref = storage.ref('posts/other/$type');
          await ref.putData(
            bytes,
            SettableMetadata(
              contentType: type == 'video' ? 'video/mp4' : 'image/jpeg',
            ),
          );
          final post = moment(
            type,
            type: type,
            url: await ref.getDownloadURL(),
          );
          await repo.downloadPost(post);
          expect(saved.last, bytes);
          expect(await files.last.exists(), false);
        }
        allowed = false;
        await expectLater(
          repo.downloadPost(moment('denied')),
          throwsStateError,
        );
        expect(files.length, 2);
        allowed = true;
        failDownload = true;
        final ref = storage.ref('posts/other/video');
        await expectLater(
          repo.downloadPost(
            moment('video', type: 'video', url: await ref.getDownloadURL()),
          ),
          throwsStateError,
        );
        expect(await temp.list().toList(), isEmpty);
      } finally {
        messenger.setMockMethodCallHandler(const MethodChannel('gal'), null);
        await temp.delete(recursive: true);
      }
    },
  );
  for (final fullscreen in [false, true]) {
    testWidgets(
      'download is first on ${fullscreen ? 'viewer' : 'feed'} menu; errors can retry; mood is visible',
      (tester) async {
        final post = moment('download', moodId: 'happy', moodName: 'Happy');
        final repo = DownloadPosts([post]);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DareProofCard(
                post: post,
                repository: repo,
                isFullScreen: fullscreen,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('moment_mood')), findsOneWidget);
        Future<void> download() async {
          await tester.tap(find.byTooltip('Moment options'));
          await tester.pumpAndSettle();
          final options = tester
              .widgetList<PopupMenuItem<String>>(
                find.byType(PopupMenuItem<String>),
              )
              .toList();
          expect(options.first.value, 'download');
          await tester.tap(find.text('Download moment'));
          await tester.pumpAndSettle();
        }

        repo.fail = true;
        await download();
        expect(
          find.textContaining('Could not save this moment'),
          findsOneWidget,
        );
        repo.fail = false;
        await download();
        expect(repo.downloads, 2);
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(find.text('Saved to your device.'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
