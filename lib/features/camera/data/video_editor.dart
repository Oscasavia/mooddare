import 'dart:io';
import 'package:video_thumbnail/video_thumbnail.dart';
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
  bool _exporting = false, _disposed = false;
  Future<List<Uint8List?>>? _thumbnails;

  // Extract small frames sequentially and reuse them for the review session.
  // Preview failure must never prevent trimming or exporting the original file.
  Future<List<Uint8List?>> thumbnails() => _thumbnails ??= _loadThumbnails();

  Future<List<Uint8List?>> _loadThumbnails() async {
    final frames = List<Uint8List?>.filled(8, null);
    if (durationMs <= 0) return frames;
    for (var i = 0; i < frames.length && !_disposed; i++) {
      try {
        frames[i] = await VideoThumbnail.thumbnailData(
          video: original.path,
          imageFormat: ImageFormat.JPEG,
          maxHeight: 96,
          timeMs: ((durationMs - 1) * i / (frames.length - 1)).round(),
          quality: 65,
        );
      } catch (_) {
        // Keep a neutral frame placeholder for unsupported or unreadable media.
      }
    }
    return frames;
  }

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
    _disposed = true;
    if (_directory != null && await _directory!.exists()) {
      await _directory!.delete(recursive: true);
    }
  }
}
