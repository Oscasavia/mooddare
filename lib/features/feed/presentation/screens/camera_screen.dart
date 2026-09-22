import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'preview_screen.dart';
import '../../../camera/presentation/live_beauty_screen.dart';
import '../../../camera/presentation/capture_timer.dart';
import '../../../camera/presentation/camera_zoom_surface.dart';

class CameraScreen extends StatelessWidget {
  final String dareText;
  final String? moodId, moodName;
  const CameraScreen({
    super.key,
    required this.dareText,
    this.moodId,
    this.moodName,
  });
  @override
  Widget build(BuildContext context) => Platform.isAndroid
      ? LiveBeautyScreen(dareText: dareText, moodId: moodId, moodName: moodName)
      : BasicCameraScreen(
          dareText: dareText,
          moodId: moodId,
          moodName: moodName,
        );
}

/// Fallback for platforms that do not yet implement native live lenses.
class BasicCameraScreen extends StatefulWidget {
  final String dareText;
  final String? moodId, moodName;
  const BasicCameraScreen({
    super.key,
    required this.dareText,
    this.moodId,
    this.moodName,
  });
  @override
  State<BasicCameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<BasicCameraScreen>
    with WidgetsBindingObserver {
  CameraController? _camera;
  List<CameraDescription> _cameras = [];
  int _index = 0;
  double _minZoom = 1, _maxZoom = 1;
  bool _busy = false;
  bool _initializing = false;
  bool _videoMode = false;
  bool _recording = false;
  bool _inPreview = false;
  bool _appActive = true;
  String? _error;
  Timer? _timer;
  final _countdown = CaptureCountdown();
  int _timerSeconds = 0;
  int _seconds = 0;
  int _generation = 0;
  Future<void> _releasing = Future<void>.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _countdown.addListener(_countdownChanged);
    _initialize();
  }

  void _countdownChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _initialize() async {
    if (!mounted || !_appActive || _inPreview || _initializing) return;
    _initializing = true;
    final generation = ++_generation;
    setState(() => _error = null);
    CameraController? candidate;
    try {
      await _releaseCamera();
      if (!mounted || generation != _generation || !_appActive || _inPreview) {
        return;
      }
      if (_cameras.isEmpty) {
        _cameras = await availableCameras();
        if (_cameras.isEmpty) throw StateError('No camera found.');
        final front = _cameras.indexWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
        );
        _index = front < 0 ? 0 : front;
      }
      candidate = CameraController(
        _cameras[_index],
        ResolutionPreset.high,
        enableAudio: _videoMode,
      );
      await candidate.initialize();
      await candidate.lockCaptureOrientation(DeviceOrientation.portraitUp);
      var minZoom = 1.0, maxZoom = 1.0;
      try {
        minZoom = await candidate.getMinZoomLevel();
        maxZoom = await candidate.getMaxZoomLevel();
      } on CameraException {
        // A camera without zoom support should still be usable for capture.
      }
      if (!mounted || generation != _generation || !_appActive || _inPreview) {
        await candidate.dispose();
        return;
      }
      setState(() {
        _camera = candidate;
        _minZoom = minZoom;
        _maxZoom = maxZoom;
      });
    } catch (error) {
      await candidate?.dispose();
      if (mounted && generation == _generation) {
        setState(
          () =>
              _error = error is CameraException && error.code.contains('Access')
              ? 'Camera access is needed. Allow it in your phone settings, then try again.'
              : 'Could not open the camera. Close other camera apps and try again.',
        );
      }
    } finally {
      _initializing = false;
      if (mounted && generation != _generation && _appActive && !_inPreview) {
        unawaited(_initialize());
      }
    }
  }

  Future<double> Function(double) _zoomCamera(CameraController camera) =>
      (ratio) async {
        if (camera != _camera || !_appActive || _inPreview) {
          throw StateError('Camera session has ended');
        }
        await camera.setZoomLevel(ratio);
        return ratio;
      };

  Future<void> _releaseCamera() {
    final camera = _camera;
    if (camera == null) return _releasing;
    setState(() => _camera = null);
    // Remove CameraPreview before disposing the controller it listens to.
    // A subsequent initialization must also wait for this release to finish.
    return _releasing = () async {
      await WidgetsBinding.instance.endOfFrame;
      await camera.dispose();
    }();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (!_appActive) {
      ++_generation;
      _countdown.cancel();
      _timer?.cancel();
      _recording = false;
      unawaited(_releaseCamera());
    } else {
      _initialize();
    }
  }

  Future<void> _capture() async {
    final camera = _camera;
    if (_busy || !_appActive || camera == null || !camera.value.isInitialized) {
      return;
    }
    setState(() => _busy = true);
    HapticFeedback.lightImpact();
    try {
      if (!_recording) {
        final completed = await _countdown.start(
          _timerSeconds,
          canContinue: () =>
              mounted &&
              _appActive &&
              camera == _camera &&
              camera.value.isInitialized,
        );
        if (!completed || !mounted || !_appActive || camera != _camera) return;
      }
      if (_videoMode && !_recording) {
        await camera.startVideoRecording();
        if (!mounted || camera != _camera) return;
        setState(() {
          _recording = true;
          _seconds = 0;
        });
        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted) return;
          setState(() => _seconds++);
          if (_seconds >= 30) _capture();
        });
        return;
      }
      final file = _videoMode
          ? await camera.stopVideoRecording()
          : await camera.takePicture();
      _timer?.cancel();
      _recording = false;
      if (!mounted || camera != _camera) return;
      _inPreview = true;
      await _releaseCamera();
      if (!mounted) return;
      final posted = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => PreviewScreen(
            mediaFile: File(file.path),
            mediaType: _videoMode ? 'video' : 'image',
            dareText: widget.dareText,
            moodId: widget.moodId,
            moodName: widget.moodName,
          ),
        ),
      );
      _inPreview = false;
      if (!mounted) return;
      if (posted == true) {
        Navigator.of(context).pop(true);
        return;
      }
      await _initialize();
    } catch (_) {
      _timer?.cancel();
      _recording = false;
      _inPreview = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Capture failed. Please try again.')),
        );
        await _initialize();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _flip() async {
    if (_cameras.length < 2 || _busy || _recording) return;
    setState(() => _busy = true);
    _index = (_index + 1) % _cameras.length;
    await _initialize();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _openLiveBeauty() async {
    if (_busy || _recording) return;
    setState(() => _busy = true);
    _inPreview = true;
    try {
      await _releaseCamera();
      if (!mounted) return;
      final posted = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => LiveBeautyScreen(
            dareText: widget.dareText,
            moodId: widget.moodId,
            moodName: widget.moodName,
          ),
        ),
      );
      _inPreview = false;
      if (!mounted) return;
      if (posted == true) {
        Navigator.of(context).pop(true);
        return;
      }
      await _initialize();
    } finally {
      _inPreview = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _flash() async {
    final camera = _camera;
    if (camera == null || _busy || _recording) return;
    try {
      await camera.setFlashMode(
        camera.value.flashMode == FlashMode.off
            ? FlashMode.auto
            : FlashMode.off,
      );
      if (mounted) setState(() {});
    } on CameraException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Flash is not available on this camera.'),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    ++_generation;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _countdown.removeListener(_countdownChanged);
    _countdown.dispose();
    unawaited(_camera?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _camera?.value.isInitialized ?? false;
    return PopScope(
      canPop: !_recording && !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _countdown.running) _countdown.cancel();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Close camera',
                      onPressed: _countdown.running
                          ? _countdown.cancel
                          : _recording || _busy
                          ? null
                          : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                    const Expanded(
                      child: Text(
                        'Capture the moment',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Toggle flash',
                      onPressed: ready && !_recording && !_busy ? _flash : null,
                      icon: Icon(
                        _camera?.value.flashMode == FlashMode.auto
                            ? Icons.flash_auto
                            : Icons.flash_off,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Container(
                      color: const Color(0xFF18181F),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (ready)
                            CameraZoomSurface(
                              key: ObjectKey(_camera),
                              enabled: _appActive && !_busy && !_inPreview,
                              minZoom: _minZoom,
                              maxZoom: _maxZoom,
                              onZoom: _zoomCamera(_camera!),
                              child: Center(child: CameraPreview(_camera!)),
                            )
                          else if (_error == null)
                            const Center(child: CircularProgressIndicator())
                          else
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.all(28),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.no_photography_outlined,
                                      size: 40,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(_error!, textAlign: TextAlign.center),
                                    const SizedBox(height: 16),
                                    FilledButton(
                                      onPressed: _initialize,
                                      child: const Text('Try again'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          Positioned(
                            left: 16,
                            right: 16,
                            top: 16,
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Text(
                                widget.dareText,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: CaptureTimerButton(
                              seconds: _timerSeconds,
                              enabled: ready && !_busy && !_recording,
                              onChanged: (value) {
                                if (_busy || _recording) return;
                                setState(() => _timerSeconds = value);
                              },
                            ),
                          ),
                          if (_countdown.remaining != null)
                            CaptureCountdownOverlay(
                              remaining: _countdown.remaining!,
                              onCancel: _countdown.cancel,
                            ),
                          if (_recording)
                            Positioned(
                              bottom: 16,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: Chip(
                                  avatar: const Icon(
                                    Icons.circle,
                                    color: Colors.redAccent,
                                    size: 12,
                                  ),
                                  label: Text(
                                    '00:${_seconds.toString().padLeft(2, '0')} / 00:30',
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.camera_alt_outlined),
                    label: Text('Photo'),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.videocam_outlined),
                    label: Text('Video'),
                  ),
                ],
                selected: {_videoMode},
                onSelectionChanged: _recording || _busy
                    ? null
                    : (value) async {
                        setState(() {
                          _videoMode = value.first;
                          _busy = true;
                        });
                        await _initialize();
                        if (mounted) setState(() => _busy = false);
                      },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 16,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (Platform.isAndroid)
                      IconButton(
                        tooltip: 'Live beauty lenses',
                        onPressed: ready && !_busy && !_recording
                            ? _openLiveBeauty
                            : null,
                        icon: const Icon(Icons.auto_awesome),
                      )
                    else
                      const SizedBox(width: 48),
                    Semantics(
                      button: true,
                      label: _recording
                          ? 'Stop recording'
                          : (_videoMode ? 'Record video' : 'Take photo'),
                      child: GestureDetector(
                        onTap: ready && !_busy ? _capture : null,
                        child: Container(
                          width: 76,
                          height: 76,
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: ready ? Colors.white : Colors.white24,
                              width: 3,
                            ),
                          ),
                          child: _busy
                              ? const CircularProgressIndicator()
                              : AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  margin: EdgeInsets.all(_recording ? 16 : 0),
                                  decoration: BoxDecoration(
                                    color: _videoMode
                                        ? Colors.redAccent
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(
                                      _recording ? 8 : 40,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Switch camera',
                      onPressed: ready && !_recording && !_busy ? _flip : null,
                      icon: const Icon(Icons.flip_camera_ios_outlined),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  _videoMode
                      ? 'Record up to 30 seconds · Original video'
                      : (Platform.isAndroid
                            ? 'Tap ✨ for live beauty lenses'
                            : 'Fine-tune your photo with beauty controls after capture'),
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.white60),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
