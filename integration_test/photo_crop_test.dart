import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/features/camera/presentation/photo_crop_screen.dart';
import 'package:mooddare/features/feed/presentation/screens/preview_screen.dart';
import 'package:mooddare/features/feed/data/repositories/post_repository.dart';

class _CapturePost implements PostRepository {
  img.Image? image;
  @override
  Future<void> createPost({
    required String dareText,
    required File mediaFile,
    required String mediaType,
    String? postId,
    String? moodId,
    String? moodName,
  }) async {
    image = img.decodeImage(await mediaFile.readAsBytes());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> waitFor(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (done()) return;
  }
  fail('Photo operation timed out.');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'captured photo crops, resets and exports through the real editor on device',
    (tester) async {
      final directory = await (await getTemporaryDirectory()).createTemp(
        'crop-device-',
      );
      final source = img.Image(width: 800, height: 1200);
      img.fill(source, color: img.ColorRgb8(90, 110, 150));
      final file = await File(
        '${directory.path}/capture.jpg',
      ).writeAsBytes(img.encodeJpg(source));
      final repo = _CapturePost();
      final navigator = GlobalKey<NavigatorState>();
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(),
            navigatorKey: navigator,
            home: const Scaffold(body: SizedBox()),
          ),
        );
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => PreviewScreen(
              mediaFile: file,
              mediaType: 'image',
              dareText: 'Find a new perspective.',
              repository: repo,
            ),
          ),
        );
        await tester.pump();
        await waitFor(
          tester,
          () => find
              .byKey(const ValueKey('capture_preview'))
              .evaluate()
              .isNotEmpty,
        );
        await tester.tap(find.byTooltip('Crop photo'));
        await waitFor(
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
        final square = tester.getRect(selection);
        expect(square.width, closeTo(square.height, 1));
        await tester.drag(selection, const Offset(0, 20));
        await tester.pump();
        expect(tester.getRect(selection).top, greaterThan(square.top));
        await tester.tap(find.text('Done'));
        await waitFor(
          tester,
          () =>
              find.byType(PhotoCropScreen).evaluate().isEmpty &&
              find.byType(LinearProgressIndicator).evaluate().isEmpty,
        );
        await tester.tap(find.byTooltip('Crop photo'));
        await waitFor(
          tester,
          () => find
              .byKey(const ValueKey('crop_selection'))
              .evaluate()
              .isNotEmpty,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reset crop'));
        await tester.pump();
        final full = tester.getRect(selection);
        expect(full.width / full.height, closeTo(2 / 3, .001));
        await tester.ensureVisible(find.text('Square'));
        await tester.tap(find.text('Square'));
        await tester.tap(find.text('Done'));
        await waitFor(
          tester,
          () =>
              find.byType(PhotoCropScreen).evaluate().isEmpty &&
              find.byType(LinearProgressIndicator).evaluate().isEmpty,
        );
        await tester.tap(find.text('Post dare'));
        await waitFor(tester, () => repo.image != null);
        expect(repo.image!.width, 800);
        expect(repo.image!.height, 800);
        expect(img.decodeImage(await file.readAsBytes())!.height, 1200);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        await tester.pumpAndSettle();
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}
