import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';

/// Owns a press across asynchronous permission/recorder startup and release.
/// Recording itself remains owned by the camera so lifecycle/limits still apply.
class CaptureShutter extends StatefulWidget {
  final bool enabled, recording, active;
  final int elapsedMillis;
  final Widget lens;
  final Future<void> Function() onPhoto, onStop;
  final Future<bool> Function(bool Function() stillHeld) onStart;
  final ValueChanged<int> onSwipeLens;

  const CaptureShutter({
    super.key,
    required this.enabled,
    required this.recording,
    required this.active,
    required this.elapsedMillis,
    required this.lens,
    required this.onPhoto,
    required this.onStart,
    required this.onStop,
    required this.onSwipeLens,
  });

  @override
  State<CaptureShutter> createState() => _CaptureShutterState();
}

class _CaptureShutterState extends State<CaptureShutter> {
  bool _held = false, _locked = false, _starting = false;
  bool _ownsRecording = false, _stopping = false;
  double _drag = 0;

  @override
  void didUpdateWidget(CaptureShutter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active ||
        (oldWidget.recording && !widget.recording && !_starting)) {
      _held = false;
      _locked = false;
      _ownsRecording = false;
    }
  }

  Future<void> _start({bool handsFree = false}) async {
    if (!widget.enabled || _starting || widget.recording || _stopping) return;
    setState(() {
      _held = !handsFree;
      _locked = handsFree;
      _starting = true;
    });
    HapticFeedback.mediumImpact();
    final started = await widget.onStart(
      () => mounted && widget.active && (_held || _locked),
    );
    if (!mounted) {
      if (started) await widget.onStop();
      return;
    }
    setState(() {
      _starting = false;
      _ownsRecording = started;
      if (!started) {
        _held = false;
        _locked = false;
      }
    });
    // Finger-up can happen before MediaRecorder.start() returns.
    if (started && !_held && !_locked) {
      await _stop();
    }
  }

  Future<void> _stop() async {
    if (_stopping) return;
    setState(() {
      _stopping = true;
      _held = false;
      _locked = false;
    });
    await widget.onStop();
    if (mounted) {
      setState(() {
        _stopping = false;
        _ownsRecording = false;
      });
    }
  }

  void _release() {
    if (!_held) return;
    setState(() => _held = false);
    if (!_locked && _ownsRecording) unawaited(_stop());
  }

  void _move(LongPressMoveUpdateDetails details) {
    final offset = details.localOffsetFromOrigin;
    if (_held && !_locked && offset.dy <= -90 && offset.dx.abs() < 64) {
      setState(() => _locked = true);
      HapticFeedback.selectionClick();
    }
  }

  void _tap() {
    if (widget.recording || _ownsRecording) {
      unawaited(_stop());
    } else if (widget.enabled && !_starting && !_stopping) {
      unawaited(widget.onPhoto());
    }
  }

  @override
  Widget build(BuildContext context) {
    final recording = widget.recording || _ownsRecording;
    final holding = _held || _starting;
    return SizedBox(
      width: 200,
      height: 208,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (holding || (recording && _locked)) ...[
            Positioned(
              top: 0,
              child: AnimatedContainer(
                key: const ValueKey('recording_lock'),
                duration: const Duration(milliseconds: 160),
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _locked ? Colors.white : Colors.black45,
                  border: Border.all(color: Colors.white54),
                ),
                child: Icon(
                  _locked ? Icons.lock : Icons.lock_open_rounded,
                  color: _locked ? Colors.black : Colors.white,
                  size: 22,
                ),
              ),
            ),
            if (!_locked)
              const Positioned(
                top: 52,
                child: Icon(
                  Icons.keyboard_arrow_up_rounded,
                  color: Colors.white70,
                ),
              ),
          ],
          Positioned(
            key: const ValueKey('shutter_position'),
            bottom: 24,
            child: Semantics(
              button: true,
              enabled: widget.enabled || recording,
              label: recording ? 'Stop recording' : 'Capture photo',
              hint: recording
                  ? 'Tap to finish video'
                  : 'Tap for photo. Hold for video. Slide up to lock.',
              onTap: _tap,
              onLongPress: () => unawaited(_start(handsFree: true)),
              customSemanticsActions: {
                const CustomSemanticsAction(
                  label: 'Record hands-free video',
                ): () =>
                    unawaited(_start(handsFree: true)),
              },
              child: ExcludeSemantics(
                child: GestureDetector(
                  key: const ValueKey('capture_shutter'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _tap,
                  onLongPressStart: (_) => unawaited(_start()),
                  onLongPressMoveUpdate: _move,
                  onLongPressEnd: (_) => _release(),
                  onLongPressCancel: _release,
                  onHorizontalDragStart: (_) => _drag = 0,
                  onHorizontalDragUpdate: (details) =>
                      _drag += details.delta.dx,
                  onHorizontalDragEnd: (_) {
                    if (widget.enabled && !recording && _drag.abs() > 18) {
                      widget.onSwipeLens(_drag < 0 ? 1 : -1);
                    }
                  },
                  child: AnimatedScale(
                    scale: holding && !_locked ? 1.1 : 1,
                    duration: const Duration(milliseconds: 140),
                    child: SizedBox(
                      width: 84,
                      height: 84,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CircularProgressIndicator(
                            value: recording
                                ? (widget.elapsedMillis / 30000).clamp(0, 1)
                                : 1,
                            strokeWidth: 4,
                            color: recording
                                ? const Color(0xFFFF526E)
                                : Colors.white,
                            backgroundColor: Colors.white38,
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: recording
                                    ? const Color(0xFFFF526E)
                                    : Colors.black26,
                              ),
                              child: _starting || _stopping
                                  ? const Padding(
                                      padding: EdgeInsets.all(21),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : (recording
                                        ? Center(
                                            child: Container(
                                              width: _locked ? 26 : 38,
                                              height: _locked ? 26 : 38,
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      _locked ? 7 : 30,
                                                    ),
                                              ),
                                            ),
                                          )
                                        : Opacity(
                                            opacity: widget.enabled ? 1 : .35,
                                            child: widget.lens,
                                          )),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            key: const ValueKey('shutter_hint'),
            bottom: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Text(
                recording || holding
                    ? (_locked ? 'Tap to stop' : 'Slide up to lock')
                    : 'Tap photo · hold video',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
