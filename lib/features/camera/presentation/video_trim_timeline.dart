import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';

/// The platform slider keeps its drag, keyboard and screen-reader behavior;
/// only its track and handles are painted as a video selection window.
class VideoTrimTimeline extends StatelessWidget {
  final RangeValues values;
  final double durationMs;
  final ValueChanged<RangeValues>? onChanged;
  final RangeLabels labels;
  final Future<List<Uint8List?>>? thumbnails;
  final int? positionMs;
  final ValueChanged<int>? onSeek;
  const VideoTrimTimeline({
    super.key,
    required this.values,
    required this.durationMs,
    required this.onChanged,
    required this.labels,
    this.thumbnails,
    this.positionMs,
    this.onSeek,
  });

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: RepaintBoundary(
      child: SizedBox(
        key: const ValueKey('video_trim_timeline'),
        height: 84,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final trackWidth = math.max(0.0, constraints.maxWidth - 48);
            final duration = math.max(1.0, durationMs);
            final position = ((positionMs ?? 0) / duration).clamp(0.0, 1.0);
            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  left: 24,
                  right: 24,
                  top: 10,
                  bottom: 10,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: ExcludeSemantics(
                      child: FutureBuilder<List<Uint8List?>>(
                        future: thumbnails,
                        builder: (context, snapshot) => Row(
                          children: List.generate(8, (index) {
                            final frames = snapshot.data;
                            final bytes =
                                frames != null && index < frames.length
                                ? frames[index]
                                : null;
                            const placeholder = ColoredBox(
                              color: Color(0xFF303039),
                              child: Center(
                                child: Icon(
                                  Icons.movie_outlined,
                                  size: 18,
                                  color: Colors.white24,
                                ),
                              ),
                            );
                            return Expanded(
                              child: SizedBox.expand(
                                child: bytes == null
                                    ? placeholder
                                    : Image.memory(
                                        bytes,
                                        key: ValueKey('trim_frame_$index'),
                                        fit: BoxFit.cover,
                                        gaplessPlayback: true,
                                        errorBuilder: (_, _, _) => placeholder,
                                      ),
                              ),
                            );
                          }),
                        ),
                      ),
                    ),
                  ),
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    rangeTrackShape: const _FilmstripTrack(),
                    rangeThumbShape: const _TrimHandle(),
                    overlayColor: Colors.transparent,
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 24,
                    ),
                    activeTrackColor: Theme.of(context).colorScheme.primary,
                    disabledActiveTrackColor: Colors.white38,
                    showValueIndicator: ShowValueIndicator.never,
                    minThumbSeparation: 0,
                  ),
                  child: RangeSlider(
                    key: const ValueKey('video_trim_range'),
                    min: 0,
                    max: math.max(1, durationMs),
                    values: values,
                    labels: labels,
                    onChanged: onChanged,
                    semanticFormatterCallback: (value) =>
                        '${(value / 1000).toStringAsFixed(1)} seconds',
                  ),
                ),
                if (positionMs != null)
                  Positioned(
                    left: 24 + position * trackWidth - 1.5,
                    top: 6,
                    bottom: 6,
                    child: IgnorePointer(
                      child: ExcludeSemantics(
                        child: Container(
                          key: const ValueKey('video_trim_playhead'),
                          width: 3,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: const [
                              BoxShadow(color: Colors.black54, blurRadius: 3),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (onSeek != null && durationMs > 0 && trackWidth > 0)
                  _seekRegions(trackWidth, duration),
              ],
            );
          },
        ),
      ),
    ),
  );

  int _boundedTime(double value) =>
      value.round().clamp(0, math.max(0, durationMs.ceil() - 1));

  Widget _seekRegions(double trackWidth, double duration) {
    final start = 24 + values.start / duration * trackWidth;
    final end = 24 + values.end / duration * trackWidth;
    final right = trackWidth + 24;
    final zones = [
      (24.0, (start - 24).clamp(24.0, right)),
      ((start + 24).clamp(24.0, right), (end - 24).clamp(24.0, right)),
      ((end + 24).clamp(24.0, right), right),
    ];
    final current = _boundedTime((positionMs ?? 0).toDouble());
    final next = _boundedTime(current + 1000);
    final previous = _boundedTime(current - 1000);
    String time(int ms) => '${(ms / 1000).toStringAsFixed(1)} seconds';
    return Positioned.fill(
      child: Semantics(
        container: true,
        label: 'Video preview position',
        value: time(current),
        increasedValue: time(next),
        decreasedValue: time(previous),
        onIncrease: next == current ? null : () => onSeek!(next),
        onDecrease: previous == current ? null : () => onSeek!(previous),
        child: Stack(
          children: [
            // Reserve 48px around each handle for trimming. Other frame taps seek.
            for (final zone in zones)
              if (zone.$2 > zone.$1)
                Positioned(
                  left: zone.$1,
                  width: zone.$2 - zone.$1,
                  top: 10,
                  bottom: 10,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    excludeFromSemantics: true,
                    onTapUp: (details) => onSeek!(
                      _boundedTime(
                        (details.localPosition.dx + zone.$1 - 24) /
                            trackWidth *
                            duration,
                      ),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _FilmstripTrack extends RangeSliderTrackShape {
  const _FilmstripTrack();
  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) => Rect.fromLTWH(
    offset.dx + 24,
    offset.dy + (parentBox.size.height - 64) / 2,
    math.max(0, parentBox.size.width - 48),
    64,
  );

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset startThumbCenter,
    required Offset endThumbCenter,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
    );
    final left = math.min(startThumbCenter.dx, endThumbCenter.dx);
    final right = math.max(startThumbCenter.dx, endThumbCenter.dx);
    final canvas = context.canvas;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)));
    final shade = Paint()..color = Colors.black.withValues(alpha: .65);
    canvas.drawRect(
      Rect.fromLTRB(rect.left, rect.top, left, rect.bottom),
      shade,
    );
    canvas.drawRect(
      Rect.fromLTRB(right, rect.top, rect.right, rect.bottom),
      shade,
    );
    canvas.restore();
    final selected = Paint()
      ..color = (isEnabled
          ? sliderTheme.activeTrackColor
          : sliderTheme.disabledActiveTrackColor)!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(left, rect.top + 1.5, right, rect.bottom - 1.5),
        const Radius.circular(6),
      ),
      selected,
    );
  }
}

class _TrimHandle extends RangeSliderThumbShape {
  const _TrimHandle();
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(24, 64);
  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    bool isDiscrete = false,
    bool isEnabled = false,
    bool isOnTop = false,
    TextDirection textDirection = TextDirection.ltr,
    required SliderThemeData sliderTheme,
    Thumb thumb = Thumb.start,
    bool isPressed = false,
  }) {
    final canvas = context.canvas;
    final handle = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: 18, height: 64),
      const Radius.circular(7),
    );
    canvas.drawShadow(Path()..addRRect(handle), Colors.black54, 3, true);
    canvas.drawRRect(
      handle,
      Paint()..color = isEnabled ? Colors.white : Colors.grey.shade500,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: 3, height: 20),
        const Radius.circular(2),
      ),
      Paint()
        ..color = isPressed
            ? sliderTheme.activeTrackColor!
            : const Color(0xFF44414F),
    );
  }
}
