// Run: flutter test tooling/export_brand_assets.dart
// Rasterizes our vector geometry directly; never reads or edits concept PNGs.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/core/branding/mood_wink.dart';

String pathData(double wink) => [
  for (final contour in [
    MoodWinkGeometry.face,
    MoodWinkGeometry.leftEye,
    MoodWinkGeometry.rightEye(wink),
    MoodWinkGeometry.smile,
  ])
    for (final command in contour)
      command.isEmpty
          ? 'Z'
          : '${command.length == 2 ? 'M' : 'C'}${command.join(' ')}',
].join(' ');

void write(String path, String contents) {
  final file = File(path)..parent.createSync(recursive: true);
  file.writeAsStringSync(
    contents.replaceAll(RegExp(r'[ \t]+$', multiLine: true), ''),
  );
}

Future<void> png(String path, int size, {bool launcher = true}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  if (launcher) {
    canvas.drawColor(AppTheme.accent, BlendMode.src);
    canvas.translate(size * .14, size * .14);
    canvas.scale(.72);
  }
  MoodWinkPainter(
    wink: launcher ? 1 : 0,
    color: launcher ? AppTheme.background : AppTheme.accent,
  ).paint(canvas, Size.square(size.toDouble()));
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final raster = img.Image.fromBytes(
    width: size,
    height: size,
    bytes: rgba.buffer,
    bytesOffset: rgba.offsetInBytes,
    numChannels: 4,
  );
  final file = File(path)..parent.createSync(recursive: true);
  // iOS App Store icons must have no alpha channel. Launch images need alpha.
  file.writeAsBytesSync(
    img.encodePng(launcher ? raster.convert(numChannels: 3) : raster),
  );
  image.dispose();
  picture.dispose();
}

String vector({
  required String color,
  double wink = 1,
  int viewport = 108,
  double scale = MoodWinkGeometry.adaptiveScale,
  double offset = MoodWinkGeometry.adaptiveOffset,
  int? size,
}) =>
    '''<?xml version="1.0" encoding="utf-8"?>
<!-- Generated from MoodWinkGeometry by tooling/export_brand_assets.dart. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="${size ?? viewport}dp" android:height="${size ?? viewport}dp"
    android:viewportWidth="$viewport" android:viewportHeight="$viewport">
    <group android:scaleX="$scale" android:scaleY="$scale"
        android:translateX="$offset" android:translateY="$offset">
        <path android:fillColor="$color" android:fillType="evenOdd"
            android:pathData="${pathData(wink)}" />
    </group>
</vector>
''';

void main() {
  testWidgets('export consistent Mood Wink launcher and launch resources', (
    tester,
  ) async {
    await tester.runAsync(() async {
      const res = 'android/app/src/main/res';
      for (final entry in {
        'mdpi': 48,
        'hdpi': 72,
        'xhdpi': 96,
        'xxhdpi': 144,
        'xxxhdpi': 192,
      }.entries) {
        await png('$res/mipmap-${entry.key}/ic_launcher.png', entry.value);
      }
      final catalog =
          jsonDecode(
                File(
                  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json',
                ).readAsStringSync(),
              )
              as Map;
      final written = <String>{};
      for (final entry in catalog['images'] as List) {
        final name = entry['filename'] as String;
        if (!written.add(name)) continue;
        final points = double.parse((entry['size'] as String).split('x').first);
        final scale = int.parse((entry['scale'] as String).replaceAll('x', ''));
        await png(
          'ios/Runner/Assets.xcassets/AppIcon.appiconset/$name',
          (points * scale).round(),
        );
      }
      for (var scale = 1; scale <= 3; scale++) {
        final suffix = scale == 1 ? '' : '@${scale}x';
        await png(
          'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage$suffix.png',
          128 * scale,
          launcher: false,
        );
      }
      await png('design/branding/mood-wink/app-icon.png', 1024);
      write(
        'assets/branding/mood-wink.svg',
        '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><path fill="#0D0E14" fill-rule="evenodd" d="${pathData(1)}"/></svg>
''',
      );
      write(
        '$res/drawable/ic_launcher_foreground.xml',
        vector(color: '#0D0E14'),
      );
      write(
        '$res/drawable/ic_launcher_monochrome.xml',
        vector(color: '#FFFFFF'),
      );
      write(
        '$res/drawable/mood_wink_splash.xml',
        vector(
          color: '#C5B4FF',
          wink: 0,
          viewport: 288,
          scale: 1.28,
          offset: 80,
        ),
      );
      // PNG also supports even-odd cutouts on Android 6 (API 23).
      for (final entry in {
        'mdpi': 1,
        'hdpi': 1.5,
        'xhdpi': 2,
        'xxhdpi': 3,
        'xxxhdpi': 4,
      }.entries) {
        await png(
          '$res/drawable-${entry.key}/mood_wink_launch.png',
          (128 * entry.value).round(),
          launcher: false,
        );
      }
      for (final api in [26, 33]) {
        write(
          '$res/mipmap-anydpi-v$api/ic_launcher.xml',
          '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/brand_lavender" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
    ${api == 33 ? '<monochrome android:drawable="@drawable/ic_launcher_monochrome" />' : ''}
</adaptive-icon>
''',
        );
      }
      write(
        '$res/values/brand_colors.xml',
        '''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="brand_lavender">#C5B4FF</color>
    <color name="brand_ink">#0D0E14</color>
</resources>
''',
      );
      for (final folder in ['drawable', 'drawable-v21']) {
        write(
          '$res/$folder/launch_background.xml',
          '''<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="@color/brand_ink" />
    <item><bitmap android:gravity="center" android:src="@drawable/mood_wink_launch" /></item>
</layer-list>
''',
        );
      }
      for (final folder in [
        'values',
        'values-night',
        'values-v31',
        'values-night-v31',
      ]) {
        final modern = folder.endsWith('v31');
        write(
          '$res/$folder/styles.xml',
          '''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="LaunchTheme" parent="@android:style/Theme.Black.NoTitleBar">
        <item name="android:windowBackground">@drawable/launch_background</item>
        <item name="android:windowLightStatusBar">false</item>
        ${modern ? '<item name="android:windowSplashScreenBackground">@color/brand_ink</item>\n        <item name="android:windowSplashScreenAnimatedIcon">@drawable/mood_wink_splash</item>\n        <item name="android:windowSplashScreenIconBackgroundColor">@android:color/transparent</item>' : ''}
    </style>
    <style name="NormalTheme" parent="@android:style/Theme.Black.NoTitleBar">
        <item name="android:windowBackground">@color/brand_ink</item>
    </style>
</resources>
''',
        );
      }
    });
  });
}
