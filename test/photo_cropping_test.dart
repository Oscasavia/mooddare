import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/features/camera/domain/photo_crop.dart';
import 'package:mooddare/features/camera/domain/photo_processing.dart';
import 'package:mooddare/features/camera/presentation/photo_crop_screen.dart';
import 'package:mooddare/features/camera/presentation/photo_adjustments_panel.dart';
import 'package:mooddare/features/feed/presentation/screens/preview_screen.dart';
import 'package:mooddare/features/feed/data/repositories/post_repository.dart';

class _Posts implements PostRepository {
  Uint8List? bytes;
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
    bytes = await mediaFile.readAsBytes();
    mood = moodName;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Uint8List fixture() {
  final image = img.Image(width: 120, height: 80);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      image.setPixelRgb(x, y, x < 60 ? 160 : 60, 90, 70);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

Future<void> ready(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 150; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 30));
    if (condition()) return;
  }
  fail('Photo operation did not finish.');
}

Uint8List preview(WidgetTester tester) =>
    (tester.widget<Image>(find.byKey(const ValueKey('capture_preview'))).image
            as MemoryImage)
        .bytes;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'crop extracts the selected pixels and reset preserves the complete bytes',
    () {
      final bytes = fixture();
      final result = img.decodeJpg(
        cropPhoto({'bytes': bytes, 'crop': const Rect.fromLTWH(.5, 0, .5, 1)}),
      )!;
      expect(result.width, 60);
      expect(result.height, 80);
      expect(result.getPixel(25, 30).r, closeTo(60, 3));
      expect(cropPhoto({'bytes': bytes, 'crop': fullPhotoCrop}), same(bytes));
      final single = img.decodeJpg(
        cropPhoto({
          'bytes': bytes,
          'crop': const Rect.fromLTWH(.9999, .9999, .0001, .0001),
        }),
      )!;
      expect(single.width, 1);
      expect(single.height, 1);
    },
  );
  test('invalid crops fail instead of silently exporting the original', () {
    for (final crop in [
      Rect.zero,
      const Rect.fromLTWH(-.1, 0, 1, 1),
      const Rect.fromLTWH(0, 0, 2, 1),
      const Rect.fromLTWH(double.nan, 0, 1, 1),
    ]) {
      expect(
        () => cropPhoto({'bytes': fixture(), 'crop': crop}),
        throwsFormatException,
      );
    }
    expect(
      () => cropPhoto({
        'bytes': Uint8List(0),
        'crop': const Rect.fromLTWH(0, 0, .5, .5),
      }),
      throwsFormatException,
    );
  });
  test('preset ratios, moves and all corner drags remain within the image', () {
    for (final imageRatio in [0.5, 1.0, 1.5, 2.0]) {
      for (final ratio in [1.0, 3 / 4, 9 / 16, imageRatio]) {
        final crop = cropForRatio(fullPhotoCrop, imageRatio, ratio);
        expect(crop.width * imageRatio / crop.height, closeTo(ratio, 1e-9));
        for (var corner = 0; corner < 4; corner++) {
          for (final delta in [
            const Offset(2, -2),
            const Offset(-2, 2),
            const Offset(.1, .1),
          ]) {
            final resized = resizePhotoCrop(
              crop,
              delta,
              corner,
              ratio / imageRatio,
            );
            expect(resized.left, greaterThanOrEqualTo(-1e-9));
            expect(resized.top, greaterThanOrEqualTo(-1e-9));
            expect(resized.right, lessThanOrEqualTo(1 + 1e-9));
            expect(resized.bottom, lessThanOrEqualTo(1 + 1e-9));
            expect(
              resized.width / resized.height,
              closeTo(ratio / imageRatio, 1e-8),
            );
          }
        }
      }
    }
    const crop = Rect.fromLTWH(.2, .3, .4, .5);
    expect(movePhotoCrop(crop, const Offset(3, -3)).left, closeTo(.6, 1e-9));
    expect(cropForRatio(crop, 1.5, null), crop);
    expect(
      resizePhotoCrop(crop, const Offset(.1, .1), 2, null).height,
      closeTo(.6, 1e-9),
    );
  });

  for (final size in [const Size(320, 640), const Size(768, 1024)]) {
    testWidgets(
      'crop controls allow presets, movement, resize, reset and cancel at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Rect? result;
        var returned = false;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await Navigator.push<Rect>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MediaQuery(
                          data: MediaQuery.of(
                            context,
                          ).copyWith(textScaler: const TextScaler.linear(1.5)),
                          child: PhotoCropScreen(photo: fixture()),
                        ),
                      ),
                    );
                    returned = true;
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await ready(
          tester,
          () => find
              .byKey(const ValueKey('crop_selection'))
              .evaluate()
              .isNotEmpty,
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Square'));
        await tester.tap(find.text('Square'));
        await tester.pump();
        final selection = find.byKey(const ValueKey('crop_selection'));
        var bounds = tester.getRect(selection);
        expect(bounds.width, closeTo(bounds.height, .01));
        await tester.drag(selection, const Offset(15, 0));
        await tester.pump();
        expect(tester.getRect(selection).left, greaterThan(bounds.left));
        await tester.ensureVisible(find.text('Free'));
        await tester.tap(find.text('Free'));
        await tester.drag(
          find.byKey(const ValueKey('crop_handle_2')),
          const Offset(-30, -20),
        );
        await tester.pump();
        expect(tester.getRect(selection).width, lessThan(bounds.width));
        await tester.tap(find.text('Reset crop'));
        await tester.pump();
        bounds = tester.getRect(selection);
        expect(bounds.width / bounds.height, closeTo(1.5, .001));
        await tester.ensureVisible(find.text('Square'));
        await tester.tap(find.text('Square'));
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(returned, true);
        expect(result!.width * 1.5 / result!.height, closeTo(1, .001));
        returned = false;
        await tester.tap(find.text('Open'));
        await ready(
          tester,
          () => find
              .byKey(const ValueKey('crop_selection'))
              .evaluate()
              .isNotEmpty,
        );
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(returned, true);
        expect(result, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'crop retains adjustments; cancel and reset are reversible; save/share/post use cropped bytes',
    (tester) async {
      final temp = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('photo-crop-test-'),
      ))!;
      final original = (await tester.runAsync(
        () => File('${temp.path}/capture.png').writeAsBytes(fixture()),
      ))!;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      Uint8List? saved, shared;
      final repo = _Posts();
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => temp.path,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('mooddare/beauty'),
        (_) async => null,
      );
      messenger.setMockMethodCallHandler(const MethodChannel('gal'), (
        call,
      ) async {
        if (call.method == 'hasAccess' || call.method == 'requestAccess') {
          return true;
        }
        saved = await File(
          (call.arguments as Map)['path'] as String,
        ).readAsBytes();
        return null;
      });
      messenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/share'),
        (call) async {
          shared = await File(
            ((call.arguments as Map)['paths'] as List).single as String,
          ).readAsBytes();
          return 'success';
        },
      );
      addTearDown(() async {
        for (final name in [
          'plugins.flutter.io/path_provider',
          'mooddare/beauty',
          'gal',
          'dev.fluttercommunity.plus/share',
        ]) {
          messenger.setMockMethodCallHandler(MethodChannel(name), null);
        }
        if (await temp.exists()) await temp.delete(recursive: true);
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          home: PreviewScreen(
            mediaFile: original,
            mediaType: 'image',
            dareText: 'Test dare',
            moodName: 'Creative',
            repository: repo,
          ),
        ),
      );
      await ready(
        tester,
        () =>
            find.byKey(const ValueKey('capture_preview')).evaluate().isNotEmpty,
      );
      await tester.tap(find.byTooltip('Adjust photo'));
      await tester.pumpAndSettle();
      tester
          .widget<PhotoAdjustmentsPanel>(find.byType(PhotoAdjustmentsPanel))
          .onChanged(const PhotoAdjustments(brightness: .5, warmth: .8));
      await tester.pump(const Duration(milliseconds: 300));
      await ready(
        tester,
        () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
      );
      final adjusted = preview(tester);
      Future<void> openCrop() async {
        await tester.tap(find.byTooltip('Crop photo'));
        await ready(
          tester,
          () => find
              .byKey(const ValueKey('crop_selection'))
              .evaluate()
              .isNotEmpty,
        );
        await tester.pumpAndSettle();
      }

      Future<void> done() async {
        await tester.tap(find.text('Done'));
        await ready(
          tester,
          () =>
              find.byType(PhotoCropScreen).evaluate().isEmpty &&
              find.byType(LinearProgressIndicator).evaluate().isEmpty,
        );
        await tester.pumpAndSettle();
      }

      await openCrop();
      await tester.ensureVisible(find.text('Square'));
      await tester.tap(find.text('Square'));
      await done();
      final cropped = preview(tester);
      expect(img.decodeJpg(cropped)!.width, 80);
      expect(img.decodeJpg(cropped)!.height, 80);
      expect(
        img.decodeJpg(cropped)!.getPixel(40, 40).r,
        closeTo(img.decodeJpg(adjusted)!.getPixel(60, 40).r, 5),
      );
      await openCrop();
      await tester.tap(find.text('Reset crop'));
      await tester.pageBack();
      await ready(
        tester,
        () =>
            find.byType(PhotoCropScreen).evaluate().isEmpty &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty,
      );
      expect(preview(tester), cropped);
      await openCrop();
      await tester.tap(find.text('Reset crop'));
      await done();
      expect(preview(tester), adjusted);
      await openCrop();
      await tester.ensureVisible(find.text('Square'));
      await tester.tap(find.text('Square'));
      await done();
      await tester.tap(find.text('Compare'));
      await tester.pump();
      expect(img.decodeJpg(preview(tester))!.width, 80);
      final menu = tester.widget<PopupMenuButton<String>>(
        find.byType(PopupMenuButton<String>),
      );
      menu.onSelected!('save');
      await ready(
        tester,
        () =>
            saved != null &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty,
      );
      menu.onSelected!('share');
      await ready(
        tester,
        () =>
            shared != null &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty,
      );
      expect(saved, cropped);
      expect(shared, cropped);
      ScaffoldMessenger.of(
        tester.element(find.byType(PreviewScreen)),
      ).removeCurrentSnackBar();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Post dare'));
      await ready(tester, () => repo.bytes != null);
      expect(repo.bytes, cropped);
      expect(repo.mood, 'Creative');
      expect(await tester.runAsync(original.readAsBytes), fixture());
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
    },
  );
}
