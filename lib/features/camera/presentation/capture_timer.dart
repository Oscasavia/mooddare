import 'dart:async';
import 'package:flutter/material.dart';

/// A cancellable delay. Cancellation always releases the awaiting capture.
class CaptureCountdown extends ChangeNotifier {
  Timer? _timer;
  Completer<bool>? _result;
  int? remaining;
  bool get running => _result != null;

  Future<bool> start(int seconds, {required bool Function() canContinue}) {
    if (running) return Future.value(false);
    if (!canContinue()) return Future.value(false);
    if (seconds <= 0) return Future.value(true);
    final result = _result = Completer<bool>();
    remaining = seconds;
    notifyListeners();
    // Check held gestures promptly, but only rebuild once per displayed second.
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!canContinue()) {
        cancel();
        return;
      }
      final next = ((seconds * 10 - timer.tick) / 10).ceil();
      if (next <= 0) {
        _finish(true);
      } else if (next != remaining) {
        remaining = next;
        notifyListeners();
      }
    });
    return result.future;
  }

  void cancel() => _finish(false);

  void _finish(bool completed, {bool notify = true}) {
    _timer?.cancel();
    _timer = null;
    final result = _result;
    _result = null;
    remaining = null;
    if (result != null) {
      result.complete(completed);
      if (notify) notifyListeners();
    }
  }

  @override
  void dispose() {
    _finish(false, notify: false);
    super.dispose();
  }
}

class CaptureTimerButton extends StatelessWidget {
  final int seconds;
  final bool enabled;
  final ValueChanged<int> onChanged;
  const CaptureTimerButton({
    super.key,
    required this.seconds,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => PopupMenuButton<int>(
    key: const ValueKey('camera_timer'),
    tooltip: seconds == 0 ? 'Timer off' : 'Timer: $seconds seconds',
    enabled: enabled,
    initialValue: seconds,
    onSelected: onChanged,
    itemBuilder: (_) => [
      for (final delay in [0, 3, 10])
        CheckedPopupMenuItem(
          value: delay,
          checked: seconds == delay,
          child: Text(delay == 0 ? 'Off' : '$delay seconds'),
        ),
    ],
    child: Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: seconds == 0 ? Colors.black38 : Colors.white,
      ),
      child: Center(
        child: Icon(
          seconds == 3
              ? Icons.timer_3_outlined
              : seconds == 10
              ? Icons.timer_10_outlined
              : Icons.timer_outlined,
          size: 24,
          color: !enabled
              ? Colors.white38
              : seconds == 0
              ? Colors.white
              : Colors.black,
        ),
      ),
    ),
  );
}

class CaptureCountdownOverlay extends StatelessWidget {
  final int remaining;
  final VoidCallback onCancel;
  const CaptureCountdownOverlay({
    super.key,
    required this.remaining,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          liveRegion: true,
          label: 'Capture in $remaining',
          child: ExcludeSemantics(
            child: Text(
              '$remaining',
              key: const ValueKey('capture_countdown'),
              style: const TextStyle(
                fontSize: 88,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                shadows: [Shadow(color: Colors.black54, blurRadius: 18)],
              ),
            ),
          ),
        ),
        TextButton(
          onPressed: onCancel,
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: Colors.black54,
          ),
          child: const Text('Cancel timer'),
        ),
      ],
    ),
  );
}
