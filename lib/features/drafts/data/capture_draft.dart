import 'dart:io';
import 'dart:ui';
import '../../camera/data/video_editor.dart';
import '../../camera/domain/photo_processing.dart';
import '../../camera/domain/photo_crop.dart';

class CaptureDraft {
  final String id, ownerId, mediaType, dareText;
  final String? moodId, moodName, weeklyDareId, liveLens;
  final File mediaFile;
  final PhotoAdjustments adjustments;
  final Rect crop;
  final VideoEdits? videoEdits;
  final DateTime updatedAt;
  const CaptureDraft({
    required this.id,
    required this.ownerId,
    required this.mediaType,
    required this.dareText,
    required this.mediaFile,
    required this.updatedAt,
    this.moodId,
    this.moodName,
    this.weeklyDareId,
    this.liveLens,
    this.adjustments = const PhotoAdjustments(),
    this.crop = fullPhotoCrop,
    this.videoEdits,
  });

  static bool validId(String id) =>
      RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(id);
  Map<String, Object?> toJson() => {
    'version': 1,
    'id': id,
    'ownerId': ownerId,
    'mediaType': mediaType,
    'dareText': dareText,
    'moodId': moodId,
    'moodName': moodName,
    'weeklyDareId': weeklyDareId,
    'liveLens': liveLens,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'adjustments': [
      adjustments.smoothing,
      adjustments.brightness,
      adjustments.warmth,
    ],
    'crop': [crop.left, crop.top, crop.right, crop.bottom],
    'videoEdits': videoEdits == null
        ? null
        : {
            'startMs': videoEdits!.startMs,
            'endMs': videoEdits!.endMs,
            'muted': videoEdits!.muted,
          },
  };
  factory CaptureDraft.fromJson(Map<String, dynamic> data, File file) {
    if (data['version'] != 1 ||
        data['id'] is! String ||
        !validId(data['id']) ||
        data['ownerId'] is! String ||
        !['image', 'video'].contains(data['mediaType']) ||
        data['dareText'] is! String ||
        (data['dareText'] as String).trim().isEmpty ||
        (data['dareText'] as String).length > 500) {
      throw const FormatException('Invalid draft.');
    }
    final a = (data['adjustments'] as List).cast<num>(),
        c = (data['crop'] as List).cast<num>();
    if (a.length != 3 ||
        a.any((n) => !n.isFinite) ||
        a[0] < 0 ||
        a[0] > 1 ||
        a[1].abs() > 1 ||
        a[2].abs() > 1 ||
        c.length != 4 ||
        c.any((n) => !n.isFinite || n < 0 || n > 1) ||
        c[0] >= c[2] ||
        c[1] >= c[3]) {
      throw const FormatException('Invalid draft edits.');
    }
    final v = data['videoEdits'] as Map?;
    final video = v == null
        ? null
        : VideoEdits(
            startMs: v['startMs'] as int,
            endMs: v['endMs'] as int,
            muted: v['muted'] as bool,
          );
    if (video != null && (video.startMs < 0 || video.endMs <= video.startMs)) {
      throw const FormatException('Invalid draft trim.');
    }
    return CaptureDraft(
      id: data['id'],
      ownerId: data['ownerId'],
      mediaType: data['mediaType'],
      dareText: data['dareText'],
      mediaFile: file,
      updatedAt: DateTime.parse(data['updatedAt'] as String),
      moodId: data['moodId'] as String?,
      moodName: data['moodName'] as String?,
      weeklyDareId: data['weeklyDareId'] as String?,
      liveLens: data['liveLens'] as String?,
      adjustments: PhotoAdjustments(
        smoothing: a[0].toDouble(),
        brightness: a[1].toDouble(),
        warmth: a[2].toDouble(),
      ),
      crop: Rect.fromLTRB(
        c[0].toDouble(),
        c[1].toDouble(),
        c[2].toDouble(),
        c[3].toDouble(),
      ),
      videoEdits: video,
    );
  }
}
