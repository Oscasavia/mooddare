import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// A thin visual track with a full-size touch target. Seeks are serialized so a
/// slow player cannot finish an older gesture after a newer one.
class VideoSeekBar extends StatefulWidget {
  final VideoPlayerController controller;
  final ValueChanged<bool> onScrubbingChanged;
  final VoidCallback onSeekError;
  const VideoSeekBar({
    super.key,
    required this.controller,
    required this.onScrubbingChanged,
    required this.onSeekError,
  });
  @override
  State<VideoSeekBar> createState() => _VideoSeekBarState();
}

class _VideoSeekBarState extends State<VideoSeekBar> {
  double? _drag;
  Duration? _pending;
  bool _seeking = false, _gesture = false;

  void _start(double value) {
    _gesture = true;
    setState(() => _drag = value);
    widget.onScrubbingChanged(true);
  }

  Future<void> _finish(double value) async {
    _gesture = false;
    _pending = Duration(milliseconds: value.round());
    if (_seeking) return;
    _seeking = true;
    while (mounted && _pending != null) {
      final target = _pending!;
      _pending = null;
      try {
        await widget.controller.seekTo(target);
      } catch (_) {
        if (mounted) widget.onSeekError();
      }
    }
    _seeking = false;
    if (mounted && !_gesture) {
      setState(() => _drag = null);
      widget.onScrubbingChanged(false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: widget.controller,
        builder: (context, value, _) {
          final duration = value.duration.inMilliseconds.toDouble();
          if (!value.isInitialized || value.hasError || duration <= 0) {
            return const SizedBox.shrink();
          }
          return Semantics(
            label: 'Video progress',
            child: SizedBox(
              height: 48,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  activeTrackColor: Colors.white.withValues(alpha: .85),
                  inactiveTrackColor: Colors.white.withValues(alpha: .24),
                  thumbColor: Colors.white,
                  overlayShape: SliderComponentShape.noOverlay,
                  thumbShape: RoundSliderThumbShape(
                    enabledThumbRadius: _drag == null ? 2 : 5,
                  ),
                ),
                child: Slider(
                  key: const ValueKey('video_progress'),
                  min: 0,
                  max: duration,
                  value: (_drag ?? value.position.inMilliseconds.toDouble())
                      .clamp(0, duration),
                  semanticFormatterCallback: (position) =>
                      '${(position / duration * 100).round()} percent',
                  onChangeStart: _start,
                  onChanged: (position) => setState(() => _drag = position),
                  onChangeEnd: _finish,
                ),
              ),
            ),
          );
        },
      );
}
