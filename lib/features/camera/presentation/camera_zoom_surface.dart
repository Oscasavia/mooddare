import 'dart:async';
import 'package:flutter/material.dart';

/// Only pointers that start on the preview participate. Shutter holds, lens
/// swipes and adjustment sliders keep their own gestures above this surface.
class CameraZoomSurface extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final double minZoom, maxZoom, initialZoom;
  final Future<double> Function(double ratio) onZoom;

  const CameraZoomSurface({
    super.key,
    required this.child,
    required this.onZoom,
    this.enabled = true,
    this.minZoom = 1,
    this.maxZoom = 1,
    this.initialZoom = 1,
  });

  @override
  State<CameraZoomSurface> createState() => _CameraZoomSurfaceState();
}

class _CameraZoomSurfaceState extends State<CameraZoomSurface> {
  final _pointers = <int, Offset>{};
  late double _zoom, _applied;
  double? _distance, _pending;
  bool _sending = false, _showZoom = false;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    _zoom = _applied = widget.initialZoom.clamp(widget.minZoom, widget.maxZoom);
  }

  @override
  void didUpdateWidget(CameraZoomSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      _pointers.clear();
      _distance = _pending = null;
      _showZoom = false;
      _hide?.cancel();
    }
  }

  double? get _span => _pointers.length == 2
      ? (_pointers.values.first - _pointers.values.last).distance
      : null;

  void _down(PointerDownEvent event) {
    if (!widget.enabled) return;
    _pointers[event.pointer] = event.localPosition;
    _distance = _span;
  }

  void _move(PointerMoveEvent event) {
    if (!widget.enabled || !_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.localPosition;
    final before = _distance, after = _span;
    _distance = after;
    if (before == null ||
        after == null ||
        before < 8 ||
        after < 8 ||
        widget.maxZoom <= widget.minZoom) {
      return;
    }
    final ratio = (_zoom * after / before).clamp(
      widget.minZoom,
      widget.maxZoom,
    );
    if (!ratio.isFinite || (ratio - _zoom).abs() < .001) return;
    _hide?.cancel();
    setState(() {
      _zoom = ratio;
      _showZoom = true;
    });
    _pending = ratio;
    unawaited(_drain());
  }

  // Coalesce quick movements rather than queueing dozens of stale camera calls.
  // Each surface belongs to one camera session and is disposed on a switch.
  Future<void> _drain() async {
    if (_sending) return;
    _sending = true;
    try {
      while (mounted && widget.enabled && _pending != null) {
        final ratio = _pending!;
        _pending = null;
        try {
          final applied = await widget.onZoom(ratio);
          if (!mounted) return;
          if (applied.isFinite) {
            _applied = applied.clamp(widget.minZoom, widget.maxZoom);
          }
          if (_pending == null) setState(() => _zoom = _applied);
        } catch (_) {
          // Camera interruptions must not interrupt capture or leave an
          // unhandled async error. A later pinch can retry on this session.
          if (!mounted) return;
          _pending = null;
          setState(() => _zoom = _applied);
        }
      }
    } finally {
      _sending = false;
    }
  }

  void _up(PointerEvent event) {
    _pointers.remove(event.pointer);
    _distance = _span;
    if (_pointers.length < 2) {
      _hide?.cancel();
      _hide = Timer(const Duration(milliseconds: 800), () {
        if (mounted) setState(() => _showZoom = false);
      });
    }
  }

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    key: const ValueKey('camera_zoom_surface'),
    behavior: HitTestBehavior.opaque,
    onPointerDown: _down,
    onPointerMove: _move,
    onPointerUp: _up,
    onPointerCancel: _up,
    child: Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: AnimatedOpacity(
                opacity: _showZoom ? 1 : 0,
                duration: const Duration(milliseconds: 150),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    '${_zoom.toStringAsFixed(1)}×',
                    key: const ValueKey('camera_zoom_label'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
