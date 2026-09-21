import 'package:mooddare/features/feed/data/repositories/post_repository.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/features/camera/data/video_editor.dart';
import 'package:mooddare/features/camera/presentation/video_adjustments_panel.dart';
import 'package:mooddare/features/feed/presentation/screens/preview_screen.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'support/moments_fakes.dart';

class VideoPosts implements PostRepository {
  File? uploaded;
  List<int>? bytes;
  String? mood;
  @override
  Future<void> createPost({
    required String dareText,
    required File mediaFile,
    required String mediaType,
    String? postId,
    String? moodId,
    String? moodName,
  }) async {
    uploaded = mediaFile;
    bytes = await mediaFile.readAsBytes();
    mood = moodName;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late File original;
  late VideoEditor editor;
  final exports = <Map<dynamic, dynamic>>[];
  bool fail = false;
  setUp(() async {
    exports.clear();
    fail = false;
    temp = await Directory.systemTemp.createTemp('video-test-');
    original = await File('${temp.path}/original.mp4').writeAsBytes([1, 2, 3]);
    editor = VideoEditor(original, 10000);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => temp.path,
    );
    messenger.setMockMethodCallHandler(VideoEditor.channel, (call) async {
      final args = call.arguments as Map;
      exports.add(args);
      if (fail) throw PlatformException(code: 'export');
      await File(args['output'] as String).writeAsBytes([4, 5]);
      return args['output'];
    });
  });
  tearDown(() async {
    await editor.dispose();
    await temp.delete(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(VideoEditor.channel, null);
  });
  test(
    'unmodified returns original; every edited export includes trim and audio removal; cache and reset preserve original',
    () async {
      expect(
        await editor.export(const VideoEdits(startMs: 0, endMs: 10000)),
        original,
      );
      final edited = await editor.export(
        const VideoEdits(startMs: 1200, endMs: 5300, muted: true),
      );
      expect(edited.path, isNot(original.path));
      expect(exports.single['muted'], true);
      expect(exports.single['startMs'], 1200);
      expect(exports.single['endMs'], 5300);
      expect(
        await editor.export(
          const VideoEdits(startMs: 1200, endMs: 5300, muted: true),
        ),
        edited,
      );
      expect(exports.length, 1);
      final sound = await editor.export(
        const VideoEdits(startMs: 1200, endMs: 5300),
      );
      expect(exports.last['muted'], false);
      expect(await edited.exists(), false);
      expect(await sound.exists(), true);
      expect(
        await editor.export(const VideoEdits(startMs: 0, endMs: 10000)),
        original,
      );
      await editor.dispose();
      expect(await sound.exists(), false);
      expect(await original.readAsBytes(), [1, 2, 3]);
    },
  );
  test(
    'invalid ranges and native failures never silently return unedited media; retry works',
    () async {
      for (final edit in [
        const VideoEdits(startMs: -1, endMs: 1),
        const VideoEdits(startMs: 5, endMs: 5),
        const VideoEdits(startMs: 0, endMs: 10001),
      ]) {
        await expectLater(editor.export(edit), throwsFormatException);
      }
      fail = true;
      await expectLater(
        editor.export(const VideoEdits(startMs: 0, endMs: 10000, muted: true)),
        throwsA(isA<PlatformException>()),
      );
      expect(await original.exists(), true);
      fail = false;
      expect(
        await (await editor.export(
          const VideoEdits(startMs: 0, endMs: 10000, muted: true),
        )).length(),
        greaterThan(0),
      );
    },
  );
  testWidgets(
    'trim controls preserve mute, reject empty ranges, reset, and disable while exporting',
    (tester) async {
      var edit = const VideoEdits(startMs: 0, endMs: 10000);
      bool enabled = true, done = false;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, set) {
                update = set;
                return VideoAdjustmentsPanel(
                  edits: edit,
                  durationMs: 10000,
                  enabled: enabled,
                  onChanged: (value) => set(() => edit = value),
                  onDone: () => done = true,
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Remove audio'));
      await tester.pump();
      expect(edit.muted, true);
      tester.widget<RangeSlider>(find.byType(RangeSlider)).onChanged!(
        const RangeValues(2000, 8000),
      );
      await tester.pump();
      expect(edit.startMs, 2000);
      expect(edit.muted, true);
      tester.widget<RangeSlider>(find.byType(RangeSlider)).onChanged!(
        const RangeValues(2000, 2100),
      );
      await tester.pump();
      expect(edit.endMs, 8000);
      update(() => enabled = false);
      await tester.pump();
      expect(
        tester.widget<RangeSlider>(find.byType(RangeSlider)).onChanged,
        isNull,
      );
      update(() => enabled = true);
      await tester.pump();
      await tester.tap(find.text('Reset'));
      await tester.pump();
      expect(edit.startMs, 0);
      expect(edit.endMs, 10000);
      expect(edit.muted, false);
      await tester.tap(find.byTooltip('Done editing video'));
      expect(done, true);
    },
  );
  testWidgets(
    'review controls float without changing frame; muting updates preview and share exports edited file',
    (tester) async {
      final platform = MemoryVideo();
      VideoPlayerPlatform.instance = platform;
      Map? share;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/share'),
            (call) async {
              share = call.arguments as Map;
              return 'success';
            },
          );
      await tester.pumpWidget(
        MaterialApp(
          home: PreviewScreen(
            mediaFile: original,
            mediaType: 'video',
            dareText: 'Test video',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final frame = tester.getRect(find.byKey(const ValueKey('video_1')));
      await tester.tap(find.byTooltip('Edit video'));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(const ValueKey('video_1'))), frame);
      await tester.tap(find.byTooltip('Remove audio'));
      await tester.pumpAndSettle();
      expect(platform.volumes[1], 0);
      tester.widget<RangeSlider>(find.byType(RangeSlider)).onChanged!(
        const RangeValues(1000, 6000),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Done editing video'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        tester
            .widget<PopupMenuButton<String>>(
              find.byType(PopupMenuButton<String>),
            )
            .onSelected!('share');
        for (var i = 0; i < 50 && share == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pumpAndSettle();
      expect(exports.single['muted'], true);
      expect(exports.single['startMs'], 1000);
      expect(exports.single['endMs'], 6000);
      expect((share!['paths'] as List).single, exports.single['output']);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'save and post use the same muted trimmed bytes and retain mood metadata',
    (tester) async {
      VideoPlayerPlatform.instance = MemoryVideo();
      final repo = VideoPosts();
      List<int>? saved;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('gal'), (call) async {
            if (call.method == 'hasAccess' || call.method == 'requestAccess') {
              return true;
            }
            saved = await File(
              (call.arguments as Map)['path'] as String,
            ).readAsBytes();
            return null;
          });
      await tester.pumpWidget(
        MaterialApp(
          home: PreviewScreen(
            mediaFile: original,
            mediaType: 'video',
            dareText: 'Test',
            moodId: 'happy',
            moodName: 'Happy',
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit video'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove audio'));
      await tester.pump();
      tester.widget<RangeSlider>(find.byType(RangeSlider)).onChanged!(
        const RangeValues(1000, 6000),
      );
      await tester.pump();
      await tester.runAsync(() async {
        tester
            .widget<PopupMenuButton<String>>(
              find.byType(PopupMenuButton<String>),
            )
            .onSelected!('save');
        for (var i = 0; i < 50 && saved == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pumpAndSettle();
      expect(saved, [4, 5]);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Post dare'));
        for (var i = 0; i < 50 && repo.bytes == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pumpAndSettle();
      expect(repo.bytes, saved);
      expect(repo.uploaded!.path, exports.single['output']);
      expect(repo.mood, 'Happy');
      expect(exports.single['muted'], true);
      expect(exports.single['startMs'], 1000);
      expect(exports.single['endMs'], 6000);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
