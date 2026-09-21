import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class VideoEdits {
  final int startMs, endMs;
  final bool muted;
  const VideoEdits({
    required this.startMs,
    required this.endMs,
    this.muted = false,
  });
  void validate(int durationMs) {
    if (startMs < 0 || endMs <= startMs || endMs > durationMs) {
      throw const FormatException('Choose a valid video range.');
    }
  }

  bool sameAs(VideoEdits other) =>
      startMs == other.startMs && endMs == other.endMs && muted == other.muted;
}

class VideoEditor {
  static const channel = MethodChannel('mooddare/video_edit');
  final File original;
  final int durationMs;
  Directory? _directory;
  VideoEdits? _cachedEdits;
  File? _cached;
  bool _exporting = false;
  VideoEditor(this.original, this.durationMs);

  Future<File> export(VideoEdits edits) async {
    edits.validate(durationMs);
    if (_exporting) throw StateError('An export is already in progress.');
    if (!edits.muted && edits.startMs == 0 && edits.endMs == durationMs) {
      return original;
    }
    if (_cachedEdits?.sameAs(edits) == true && await _cached!.exists()) {
      return _cached!;
    }
    _exporting = true;
    try {
      _directory ??= await (await getTemporaryDirectory()).createTemp(
        'video-edit-',
      );
      final output = File(
        '${_directory!.path}/${DateTime.now().microsecondsSinceEpoch}.mp4',
      );
      try {
        await channel.invokeMethod<String>('export', {
          'input': original.path,
          'output': output.path,
          'startMs': edits.startMs,
          'endMs': edits.endMs,
          'muted': edits.muted,
        });
        if (!await output.exists() || await output.length() == 0) {
          throw StateError('The video export is empty.');
        }
      } catch (_) {
        if (await output.exists()) await output.delete();
        rethrow;
      }
      if (_cached != null && await _cached!.exists()) await _cached!.delete();
      _cached = output;
      _cachedEdits = edits;
      return output;
    } finally {
      _exporting = false;
    }
  }

  Future<void> dispose() async {
    if (_directory != null && await _directory!.exists()) {
      await _directory!.delete(recursive: true);
    }
  }
}
