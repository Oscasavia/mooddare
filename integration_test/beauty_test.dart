import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import 'package:mooddare/features/camera/data/photo_editor.dart';
import 'package:mooddare/features/camera/domain/photo_processing.dart';
import 'package:mooddare/features/feed/presentation/screens/preview_screen.dart';
import 'package:mooddare/core/app_theme.dart';
import 'face_fixture.dart';
import 'package:mooddare/features/feed/presentation/screens/camera_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native face detection, smoothing and export work together offline',
    (tester) async {
      final file = File(
        '${(await getTemporaryDirectory()).path}/beauty-test.jpg',
      );
      await file.writeAsBytes(base64Decode(faceFixtureBase64));
      final editor = await PhotoEditor.open(file);
      try {
        expect(editor.faceDetected, isTrue, reason: editor.notice);
        final bytes = await editor.render(
          const PhotoAdjustments(smoothing: .75, warmth: .2),
        );
        final output = await editor.export(bytes);
        expect(await output.readAsBytes(), bytes);
        final decoded = img.decodeJpg(bytes)!;
        expect(decoded.width, greaterThan(100));
        expect(bytes, isNot(editor.original));
        // Preview uses the same processing service as save/share/post.
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(),
            home: PreviewScreen(
              mediaFile: file,
              mediaType: 'image',
              dareText: 'Capture a new perspective.',
            ),
          ),
        );
        for (
          var i = 0;
          i < 60 && find.text('Photo studio').evaluate().isEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 500));
        }
        expect(find.text('Photo studio'), findsOneWidget);
        expect(find.text('Smooth'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Edited'));
        await tester.pump();
        expect(find.text('Original'), findsOneWidget);
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        await tester.pump();
      } finally {
        await editor.dispose();
        await file.delete();
      }
    },
  );
  testWidgets('camera can capture a photo, open the studio and retake', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: const CameraScreen(dareText: 'A camera test moment.'),
      ),
    );
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }
    expect(
      find.text(
        'Could not open the camera. Close other camera apps and try again.',
      ),
      findsNothing,
    );
    await tester.tap(find.bySemanticsLabel('Take photo'));
    for (
      var i = 0;
      i < 80 && find.text('Photo studio').evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.text('Photo studio'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Capture the moment'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(seconds: 1));
  });
}
