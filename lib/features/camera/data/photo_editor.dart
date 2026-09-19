import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../domain/photo_processing.dart';

class PhotoEditor {
  static const _channel = MethodChannel('mooddare/beauty');
  final Directory directory;
  final Uint8List original;
  final Uint8List smooth;
  final bool faceDetected;
  final String? notice;

  PhotoEditor._(
    this.directory,
    this.original,
    this.smooth,
    this.faceDetected,
    this.notice,
  );

  static Future<PhotoEditor> open(File file) async {
    final directory = await (await getTemporaryDirectory()).createTemp(
      'mooddare-edit-',
    );
    try {
      final original = await compute(normalizePhoto, await file.readAsBytes());
      final normalized = File('${directory.path}/original.jpg');
      await normalized.writeAsBytes(original);
      Map<String, dynamic>? face;
      String? notice;
      try {
        final result = await _channel.invokeMapMethod<String, dynamic>(
          'detectFace',
          {'path': normalized.path},
        );
        face = result;
        if (face == null) {
          notice =
              'No front-facing face found. Try a well-lit selfie for smoothing.';
        }
      } on PlatformException {
        notice =
            'Face detection is unavailable. You can still adjust light and warmth.';
      } on MissingPluginException {
        notice =
            'Smoothing is available on Android. You can still adjust light and warmth.';
      }
      final smooth = await compute(smoothPhoto, {
        'bytes': original,
        'face': face,
      });
      return PhotoEditor._(directory, original, smooth, face != null, notice);
    } catch (_) {
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  Future<Uint8List> render(PhotoAdjustments settings) => compute(renderPhoto, {
    'original': original,
    'smooth': smooth,
    'settings': settings,
  });

  Future<File> export(Uint8List bytes) async {
    final file = File('${directory.path}/edited.jpg');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> dispose() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
