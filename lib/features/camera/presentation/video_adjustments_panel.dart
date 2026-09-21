import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../data/video_editor.dart';

class VideoAdjustmentsPanel extends StatelessWidget {
  final VideoEdits edits;
  final int durationMs;
  final ValueChanged<VideoEdits> onChanged;
  final VoidCallback onDone;
  final bool enabled;
  const VideoAdjustmentsPanel({
    super.key,
    required this.edits,
    required this.durationMs,
    required this.onChanged,
    required this.onDone,
    this.enabled = true,
  });
  static String time(int ms) =>
      '${ms ~/ 60000}:${((ms ~/ 1000) % 60).toString().padLeft(2, '0')}.${(ms % 1000) ~/ 100}';
  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xE6101014),
    borderRadius: BorderRadius.circular(20),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Trim & sound',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: edits.muted ? 'Unmute original audio' : 'Remove audio',
                onPressed: !enabled
                    ? null
                    : () => onChanged(
                        VideoEdits(
                          startMs: edits.startMs,
                          endMs: edits.endMs,
                          muted: !edits.muted,
                        ),
                      ),
                icon: Icon(
                  edits.muted
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                ),
              ),
              IconButton(
                tooltip: 'Done editing video',
                onPressed: enabled ? onDone : null,
                icon: const Icon(Icons.check),
              ),
            ],
          ),
          RangeSlider(
            key: const ValueKey('video_trim_range'),
            min: 0,
            max: math.max(1, durationMs).toDouble(),
            values: RangeValues(
              edits.startMs.toDouble(),
              edits.endMs.toDouble(),
            ),
            labels: RangeLabels(time(edits.startMs), time(edits.endMs)),
            onChanged: !enabled || durationMs <= 0
                ? null
                : (range) {
                    if (range.end - range.start < math.min(500, durationMs)) {
                      return;
                    }
                    onChanged(
                      VideoEdits(
                        startMs: range.start.round(),
                        endMs: range.end.round(),
                        muted: edits.muted,
                      ),
                    );
                  },
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${time(edits.startMs)} – ${time(edits.endMs)}',
                  semanticsLabel:
                      'Selected clip from ${time(edits.startMs)} to ${time(edits.endMs)}',
                ),
              ),
              TextButton(
                onPressed: !enabled
                    ? null
                    : () => onChanged(
                        VideoEdits(startMs: 0, endMs: durationMs, muted: false),
                      ),
                child: const Text('Reset'),
              ),
            ],
          ),
          if (edits.muted)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'This moment will be saved without sound',
                style: TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ),
        ],
      ),
    ),
  );
}
