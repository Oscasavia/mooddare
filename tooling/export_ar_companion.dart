// Run: flutter test tooling/export_ar_companion.dart
// This atlas is drawn from the same vector contours as the app mascot.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/branding/mood_wink.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('export companion atlas from shared mascot contours', () async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (var i = 0; i < 2; i++) {
      canvas.save();
      canvas.translate(i * 256.0 + 12, 12);
      canvas.scale(2.32);
      final silhouette = Path();
      for (final c in MoodWinkGeometry.face) {
        if (c.isEmpty) {
          silhouette.close();
        } else if (c.length == 2) {
          silhouette.moveTo(c[0], c[1]);
        } else {
          silhouette.cubicTo(c[0], c[1], c[2], c[3], c[4], c[5]);
        }
      }
      canvas.drawPath(silhouette, Paint()..color = const Color(0xFF21192F));
      canvas.drawPath(
        MoodWinkGeometry.path(
          1,
          expression: i == 0
              ? MoodWinkExpression.wink
              : MoodWinkExpression.talking,
        ),
        Paint()..color = const Color(0xFFC5B4FF),
      );
      canvas.restore();
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(512, 256);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(
      'android/app/src/main/res/drawable-nodpi/ar_mood_companion.png',
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
    picture.dispose();
  });
}
