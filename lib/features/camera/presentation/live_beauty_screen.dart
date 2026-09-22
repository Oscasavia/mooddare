import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../feed/presentation/screens/preview_screen.dart';
import '../domain/beauty_lens.dart';
import 'capture_shutter.dart';
import 'camera_zoom_surface.dart';
import 'capture_timer.dart';
import 'custom_beauty_panel.dart';

enum _CameraFrame {
  story('9:16', 9 / 16),
  photo('3:4', 3 / 4),
  full('Full', null);

  final String label;
  final double? aspect;
  const _CameraFrame(this.label, this.aspect);
}

class LiveBeautyScreen extends StatefulWidget {
  final String dareText;
  final String? moodId, moodName;
  const LiveBeautyScreen({
    super.key,
    required this.dareText,
    this.moodId,
    this.moodName,
  });

  @override
  State<LiveBeautyScreen> createState() => _LiveBeautyScreenState();
}

class _LiveBeautyScreenState extends State<LiveBeautyScreen>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('mooddare/live_beauty');
  static final _initialPage = 500 * BeautyLens.all.length;
  final _carousel = PageController(
    initialPage: _initialPage,
    viewportFraction: .23,
  );
  Future<void> _operations = Future<void>.value();
  Timer? _poll, _lookDebounce;
  final _countdown = CaptureCountdown();
  int _timerSeconds = 0;
  int? _texture;
  int _generation = 0, _selected = 0;
  double _strength = .65, _aspect = .75;
  double _minZoom = 1, _maxZoom = 1, _initialZoom = 1;
  CustomBeautyLook _customLook = const CustomBeautyLook();
  BeautyAdjustment _customAdjustment = BeautyAdjustment.smooth;
  bool get _isCustom => BeautyLens.all[_selected] == BeautyLens.custom;
  bool get _needsMesh {
    if (_isCustom) return _customLook.eyes > 0 || _customLook.face > 0;
    final lens = BeautyLens.all[_selected];
    return _strength > 0 &&
        (lens.makeup > 0 || lens.eyeSize > 0 || lens.faceSlim > 0);
  }

  bool _ready = false, _face = false, _geometry = false, _front = true;
  bool _busy = false, _comparing = false, _active = true, _inPreview = false;
  bool _recording = false, _showAdjustments = false;
  bool _askedForCamera = false;
  bool _flash = false, _hasFlash = false, _screenFlash = false;
  _CameraFrame _framing = _CameraFrame.story;
  double _viewportAspect = .5625;
  int _recordingMillis = 0;
  String? _lastRecordingError;
  File? _interruptedClip;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _countdown.addListener(_countdownChanged);
    _start();
  }

  void _countdownChanged() {
    if (mounted) setState(() {});
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _operations.then((_) => operation());
    _operations = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  Future<void> _start() async {
    if (!mounted || !_active || _inPreview) return;
    if (_interruptedClip != null) {
      final file = _interruptedClip!;
      _interruptedClip = null;
      await _review(file, 'video');
      return;
    }
    final generation = ++_generation;
    _poll?.cancel();
    setState(() {
      _ready = false;
      _texture = null;
      _error = null;
      _face = false;
      _geometry = false;
      _recording = false;
      _recordingMillis = 0;
    });
    try {
      final value = await _enqueue(() async {
        await _channel.invokeMethod<void>('stop');
        if (!mounted || generation != _generation) return null;
        if (_interruptedClip == null) {
          final pending = await _channel.invokeMethod<String>(
            'takePendingVideo',
          );
          if (pending != null) {
            final file = File(pending);
            if (!mounted) {
              if (await file.exists()) await file.delete();
              return null;
            }
            // Retain ownership if another lifecycle event supersedes this start.
            _interruptedClip = file;
          }
        }
        if (_interruptedClip != null) {
          return <String, dynamic>{'pendingVideo': true};
        }
        if (generation != _generation) return null;
        final prompt = !_askedForCamera;
        _askedForCamera = true;
        final allowed =
            await _channel.invokeMethod<bool>('requestCamera', {
              'prompt': prompt,
            }) ??
            false;
        if (!mounted || generation != _generation) return null;
        if (!allowed) {
          throw PlatformException(
            code: 'permission',
            message: 'Allow camera access in phone settings, then try again.',
          );
        }
        return _channel.invokeMapMethod<String, dynamic>('start', {
          'front': _front,
        });
      });
      if (!mounted || generation != _generation) return;
      if (value?['pendingVideo'] != null) {
        final file = _interruptedClip!;
        _interruptedClip = null;
        await _review(file, 'video');
        return;
      }
      await _sendLook();
      if (!mounted || generation != _generation) return;
      setState(() {
        _texture = (value!['textureId'] as num).toInt();
        _minZoom = (value['minZoom'] as num?)?.toDouble() ?? 1;
        _maxZoom = (value['maxZoom'] as num?)?.toDouble() ?? 1;
        _initialZoom = (value['zoom'] as num?)?.toDouble() ?? 1;
      });
      var polling = false;
      var waitingTicks = 0;
      _poll = Timer.periodic(const Duration(milliseconds: 250), (_) async {
        if (polling || !mounted || generation != _generation) return;
        polling = true;
        try {
          final state = await _channel.invokeMapMethod<String, dynamic>(
            'status',
          );
          if (!mounted || generation != _generation || state == null) return;
          final w = (state['width'] as num?)?.toDouble() ?? 0;
          final h = (state['height'] as num?)?.toDouble() ?? 0;
          setState(() {
            _ready = state['ready'] == true;
            _face = state['faceDetected'] == true;
            _geometry = state['geometryDetected'] == true;
            _hasFlash = state['hasFlash'] == true;
            _recording = state['recording'] == true;
            _recordingMillis = (state['recordingMillis'] as num?)?.toInt() ?? 0;
            if (w > 0 && h > 0) _aspect = w / h;
            _error = state['error'] as String?;
            if (!_ready && ++waitingTicks > 60 && _error == null) {
              _error =
                  'The camera is taking too long to start. Please try again.';
            }
          });
          final recordingError = state['recordingError'] as String?;
          if (recordingError != null && recordingError != _lastRecordingError) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(recordingError)));
          }
          _lastRecordingError = recordingError;
          if (state['videoReady'] == true && !_busy && _active && !_inPreview) {
            unawaited(_finishVideo());
          }
        } on PlatformException {
          if (mounted && generation == _generation) {
            setState(() => _error = 'Camera disconnected. Please try again.');
          }
        } finally {
          polling = false;
        }
      });
    } on PlatformException catch (error) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = error.message ?? 'Could not start the live camera.',
        );
      }
    }
  }

  Future<void> _stop() async {
    _countdown.cancel();
    ++_generation;
    _poll?.cancel();
    _lookDebounce?.cancel();
    Future<void>? removed;
    if (mounted) {
      setState(() {
        _texture = null;
        _ready = false;
        _recording = false;
        _screenFlash = false;
      });
      removed = WidgetsBinding.instance.endOfFrame;
    }
    // Queue immediately, even if the app is paused and the next frame must
    // wait for resume. A later start must never overtake this stop.
    await _enqueue(() async {
      await removed;
      await _channel.invokeMethod<void>('stop');
    });
  }

  Future<double> Function(double) _zoomCamera(int texture) => (ratio) async {
    if (_texture != texture || !_active || _inPreview) {
      throw StateError('Camera session has ended');
    }
    return await _channel.invokeMethod<double>('setZoom', {
          'ratio': ratio,
          'textureId': texture,
        }) ??
        ratio;
  };

  Future<void> _sendLook() => _channel.invokeMethod<void>('setLook', {
    ...(_isCustom
        ? _customLook.settings(original: _comparing)
        : BeautyLens.all[_selected].settings(_strength, original: _comparing)),
    'aspectRatio': _viewportAspect,
  });

  void _adjust() {
    _lookDebounce?.cancel();
    _lookDebounce = Timer(const Duration(milliseconds: 30), () async {
      if (!mounted || !_active || _inPreview || _texture == null) return;
      try {
        await _sendLook();
      } on PlatformException catch (error) {
        if (mounted && _active && _texture != null && error.code != 'closed') {
          setState(
            () => _error = 'Could not apply this lens. Please try again.',
          );
        }
      }
    });
  }

  Future<void> _capture() async {
    if (!_ready || _busy || !_active || _recording || _error != null) return;
    final generation = _generation;
    final useFlash = _flash && (_front || _hasFlash);
    setState(() => _busy = true);
    HapticFeedback.lightImpact();
    File? captured;
    try {
      final completed = await _countdown.start(
        _timerSeconds,
        canContinue: () =>
            mounted &&
            _active &&
            _ready &&
            _error == null &&
            generation == _generation,
      );
      if (!completed || !mounted || !_active || generation != _generation) {
        return;
      }
      _lookDebounce?.cancel();
      await _sendLook();
      try {
        if (useFlash) {
          if (_front && mounted) {
            setState(() => _screenFlash = true);
            await WidgetsBinding.instance.endOfFrame;
          }
          if (!mounted || !_active || generation != _generation) return;
          await _channel.invokeMethod<void>('setCaptureLight', {
            'enabled': true,
          });
          // Let exposure settle and fresh illuminated frames reach the GPU.
          await Future<void>.delayed(const Duration(milliseconds: 650));
        }
        if (!mounted || !_active || generation != _generation) return;
        captured = File(
          (await _channel.invokeMethod<String>('capture', {
            'flash': useFlash,
          }))!,
        );
      } finally {
        if (useFlash) {
          try {
            await _channel.invokeMethod<void>('setCaptureLight', {
              'enabled': false,
            });
          } on PlatformException {
            // Native pause/close and the timeout independently restore the light.
          }
          if (mounted) setState(() => _screenFlash = false);
        }
      }
      if (!mounted || !_active) return;
      await _review(captured, 'image');
      captured = null;
    } on PlatformException catch (error) {
      _inPreview = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message ?? 'Could not take this photo.'),
          ),
        );
        await _start();
      }
    } finally {
      if (captured != null && await captured.exists()) await captured.delete();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review(File file, String type) async {
    if (!mounted) {
      if (await file.exists()) await file.delete();
      return;
    }
    if (!_active && type == 'video') {
      _interruptedClip = file;
      return;
    }
    _inPreview = true;
    setState(() => _busy = true);
    try {
      await _stop();
      if (!mounted) return;
      final posted = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => PreviewScreen(
            mediaFile: file,
            mediaType: type,
            dareText: widget.dareText,
            moodId: widget.moodId,
            moodName: widget.moodName,
            liveLens: _comparing ? 'Original' : BeautyLens.all[_selected].name,
          ),
        ),
      );
      _inPreview = false;
      if (!mounted) return;
      if (posted == true) {
        Navigator.of(context).pop(true);
        return;
      }
      await _start();
    } finally {
      _inPreview = false;
      if (await file.exists()) await file.delete();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _beginVideo(bool Function() stillHeld) async {
    if (!_ready || _busy || !_active || _error != null) return false;
    final generation = _generation;
    setState(() {
      _busy = true;
      _showAdjustments = false;
    });
    try {
      final allowed =
          await _channel.invokeMethod<bool>('requestMicrophone') ?? false;
      if (!mounted) return false;
      if (!allowed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Allow microphone access in phone settings to record video.',
            ),
          ),
        );
        return false;
      }
      // Permission dialogs release the finger and interrupt the camera. Never
      // start recording automatically after the dialog has been dismissed.
      if (generation != _generation || !_active || !stillHeld()) return false;
      final completed = await _countdown.start(
        _timerSeconds,
        canContinue: () =>
            mounted &&
            _active &&
            _ready &&
            _error == null &&
            generation == _generation &&
            stillHeld(),
      );
      if (!completed ||
          !mounted ||
          !_active ||
          generation != _generation ||
          !stillHeld()) {
        return false;
      }
      _lookDebounce?.cancel();
      await _sendLook();
      if (!stillHeld() || generation != _generation) return false;
      await _channel.invokeMethod<void>('startRecording');
      if (mounted && _active) {
        setState(() {
          _recording = true;
          _recordingMillis = 0;
        });
      }
      return true;
    } on PlatformException catch (error) {
      if (mounted && _active) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message ?? 'Could not start recording.'),
          ),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finishVideo() async {
    if (!mounted || _busy) return;
    setState(() => _busy = true);
    try {
      final path = await _channel.invokeMethod<String>('stopRecording');
      if (mounted) setState(() => _recording = false);
      if (path != null) await _review(File(path), 'video');
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() => _recording = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message ?? 'Could not finish this video.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _flip() async {
    if (_busy || _recording) return;
    setState(() {
      _busy = true;
      _front = !_front;
    });
    await _stop();
    await _start();
    if (mounted) setState(() => _busy = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (!_active) {
      unawaited(_stop());
    } else if (!_inPreview) {
      unawaited(_start());
    }
  }

  @override
  void dispose() {
    ++_generation;
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _lookDebounce?.cancel();
    _countdown.removeListener(_countdownChanged);
    _countdown.dispose();
    _carousel.dispose();
    final abandoned = _interruptedClip;
    if (abandoned != null) {
      unawaited(abandoned.delete().catchError((_) => abandoned));
    }
    unawaited(_enqueue(() => _channel.invokeMethod<void>('stop')));
    super.dispose();
  }

  static const _lensIcons = [
    null, // Original is a plain branded circle.
    Icons.blur_on_rounded,
    Icons.wb_sunny_outlined,
    Icons.visibility_outlined,
    Icons.face_retouching_natural,
    Icons.auto_awesome,
    Icons.local_florist_outlined,
    Icons.tune_rounded,
  ];
  static const _lensColors = [
    <Color>[], // Original uses the translucent theme accent below.
    [Color(0xFFF0C9C2), Color(0xFFAD7593)],
    [Color(0xFFFFE2AA), Color(0xFFE99773)],
    [Color(0xFFB6DCEE), Color(0xFF697FBD)],
    [Color(0xFFCDC3F1), Color(0xFF8774B3)],
    [Color(0xFFF2CEEA), Color(0xFFA583CB)],
    [Color(0xFFFFB8C8), Color(0xFFC4597C)],
    [Color(0xFFA9E5D8), Color(0xFF548EAA)],
  ];

  Widget _lensDisc(int index) {
    if (index == 0) {
      return DecoratedBox(
        key: const ValueKey('original_lens_disc'),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .25),
        ),
        child: const SizedBox.expand(),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _lensColors[index],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: .4)),
      ),
      child: Icon(_lensIcons[index], color: Colors.white, size: 28),
    );
  }

  void _chooseLens(int index) {
    if (_busy || _recording || index < 0) {
      return;
    }
    _carousel.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _floatingButton(
    String tooltip,
    IconData icon,
    VoidCallback? action, {
    bool selected = false,
  }) => IconButton(
    tooltip: tooltip,
    onPressed: action,
    style: IconButton.styleFrom(
      backgroundColor: selected ? Colors.white : Colors.black38,
      foregroundColor: selected ? Colors.black : Colors.white,
      disabledBackgroundColor: Colors.black12,
      disabledForegroundColor: Colors.white38,
    ),
    icon: Icon(icon, size: 24),
  );

  void _showDare() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your dare', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Text(
                widget.dareText,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final frameAspect = _framing.aspect ?? viewport.aspectRatio;
    if (_viewportAspect != frameAspect && !_recording) {
      _viewportAspect = frameAspect;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _ready) _adjust();
      });
    }
    final enabled = _ready && !_busy && _error == null && _active;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: PopScope(
        canPop: !_busy && !_recording,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _countdown.running) _countdown.cancel();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              if (_texture != null)
                Align(
                  alignment: Alignment.center,
                  child: AspectRatio(
                    key: const ValueKey('camera_frame'),
                    aspectRatio: _viewportAspect,
                    child: CameraZoomSurface(
                      key: ValueKey(_texture),
                      enabled: _ready && _active && !_inPreview && !_busy,
                      minZoom: _minZoom,
                      maxZoom: _maxZoom,
                      initialZoom: _initialZoom,
                      onZoom: _zoomCamera(_texture!),
                      child: ClipRect(
                        child: SizedBox.expand(
                          child: FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: _aspect * 1000,
                              height: 1000,
                              child: Texture(textureId: _texture!),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0, .23, .6, 1],
                      colors: [
                        Colors.black54,
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black54,
                      ],
                    ),
                  ),
                ),
              ),
              if (!_ready && _error == null)
                const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              if (_error != null)
                Center(
                  child: Container(
                    margin: const EdgeInsets.all(32),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.no_photography_outlined, size: 32),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  _askedForCamera = false;
                                  _start();
                                },
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _floatingButton(
                          'Close camera',
                          Icons.close,
                          _countdown.running
                              ? _countdown.cancel
                              : _busy || _recording
                              ? null
                              : () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Center(
                              heightFactor: 1,
                              child: _recording
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFDA3655),
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                      child: Text(
                                        '● 00:${(_recordingMillis ~/ 1000).clamp(0, 30).toString().padLeft(2, '0')} / 00:30',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    )
                                  : TextButton(
                                      onPressed: _busy ? null : _showDare,
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.white,
                                        backgroundColor: Colors.black26,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                        ),
                                      ),
                                      child: Text(
                                        widget.dareText,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _floatingButton(
                              'Switch camera',
                              Icons.flip_camera_ios_outlined,
                              enabled && !_recording ? _flip : null,
                            ),
                            if (!_recording) ...[
                              const SizedBox(height: 8),
                              PopupMenuButton<_CameraFrame>(
                                key: const ValueKey('camera_ratio'),
                                tooltip: 'Change frame',
                                enabled: enabled,
                                initialValue: _framing,
                                onSelected: (value) {
                                  if (_busy || _recording) return;
                                  setState(() => _framing = value);
                                },
                                itemBuilder: (_) => _CameraFrame.values
                                    .map(
                                      (value) => CheckedPopupMenuItem(
                                        value: value,
                                        checked: value == _framing,
                                        child: Text(value.label),
                                      ),
                                    )
                                    .toList(),
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  alignment: Alignment.center,
                                  decoration: const BoxDecoration(
                                    color: Colors.black38,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    _framing.label,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: enabled
                                          ? Colors.white
                                          : Colors.white38,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              _floatingButton(
                                !_front && !_hasFlash
                                    ? 'Flash unavailable'
                                    : _front
                                    ? (_flash
                                          ? 'Screen flash on'
                                          : 'Screen flash off')
                                    : (_flash
                                          ? 'Photo flash on'
                                          : 'Photo flash off'),
                                _flash && (_front || _hasFlash)
                                    ? Icons.flash_on_rounded
                                    : Icons.flash_off_rounded,
                                enabled && (_front || _hasFlash)
                                    ? () => setState(() => _flash = !_flash)
                                    : null,
                                selected: _flash && (_front || _hasFlash),
                              ),
                              const SizedBox(height: 8),
                              CaptureTimerButton(
                                seconds: _timerSeconds,
                                enabled: enabled,
                                onChanged: (value) {
                                  if (!enabled || _recording) return;
                                  setState(() => _timerSeconds = value);
                                },
                              ),
                              const SizedBox(height: 8),
                              _floatingButton(
                                'Adjust lens',
                                Icons.tune_rounded,
                                enabled && _selected != 0
                                    ? () => setState(
                                        () => _showAdjustments =
                                            !_showAdjustments,
                                      )
                                    : null,
                                selected: _showAdjustments,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_showAdjustments && !_recording)
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 232,
                  left: 24,
                  right: 76,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .65),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: _isCustom
                        ? CustomBeautyPanel(
                            look: _customLook,
                            selected: _customAdjustment,
                            enabled: enabled,
                            comparing: _comparing,
                            onSelect: (value) =>
                                setState(() => _customAdjustment = value),
                            onChanged: (value) {
                              setState(
                                () => _customLook = _customLook.withAmount(
                                  _customAdjustment,
                                  value,
                                ),
                              );
                              _adjust();
                            },
                            onReset: () {
                              setState(() {
                                _customLook = const CustomBeautyLook();
                                _comparing = false;
                              });
                              _adjust();
                            },
                            onCompare: () {
                              setState(() => _comparing = !_comparing);
                              _adjust();
                            },
                          )
                        : Row(
                            children: [
                              Text(
                                '${(_strength * 100).round()}%',
                                style: const TextStyle(fontSize: 12),
                              ),
                              Expanded(
                                child: Slider(
                                  value: _strength,
                                  label: '${(_strength * 100).round()}%',
                                  semanticFormatterCallback: (value) =>
                                      'Lens strength ${(value * 100).round()} percent',
                                  onChanged: enabled && !_comparing
                                      ? (value) {
                                          setState(() => _strength = value);
                                          _adjust();
                                        }
                                      : null,
                                ),
                              ),
                              _floatingButton(
                                _comparing ? 'Show lens' : 'Compare original',
                                Icons.compare_rounded,
                                enabled
                                    ? () {
                                        setState(
                                          () => _comparing = !_comparing,
                                        );
                                        _adjust();
                                      }
                                    : null,
                                selected: _comparing,
                              ),
                            ],
                          ),
                  ),
                ),
              Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 208,
                      child: Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          if (!_recording && !_busy)
                            Positioned(
                              bottom: 126,
                              left: 0,
                              right: 0,
                              child: IgnorePointer(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _comparing
                                          ? 'Original'
                                          : BeautyLens.all[_selected].name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                        shadows: [
                                          Shadow(
                                            color: Colors.black87,
                                            blurRadius: 8,
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (_selected != 0 &&
                                        _ready &&
                                        !_comparing &&
                                        (!_face || (_needsMesh && !_geometry)))
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          !_face
                                              ? 'Find your face'
                                              : BeautyLens
                                                        .all[_selected]
                                                        .makeup >
                                                    0
                                              ? 'Face the camera for makeup'
                                              : 'Face the camera for shaping',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.white70,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          Positioned(
                            bottom: 24,
                            left: 0,
                            right: 0,
                            height: 84,
                            child: IgnorePointer(
                              ignoring: _busy || _recording,
                              child: AnimatedOpacity(
                                opacity: _recording ? 0 : 1,
                                duration: const Duration(milliseconds: 150),
                                child: PageView.builder(
                                  controller: _carousel,
                                  onPageChanged: (index) {
                                    setState(() {
                                      _selected = index % BeautyLens.all.length;
                                      _comparing = false;
                                      if (_selected == 0) {
                                        _showAdjustments = false;
                                      } else if (_isCustom) {
                                        _showAdjustments = true;
                                      }
                                    });
                                    _adjust();
                                    HapticFeedback.selectionClick();
                                  },
                                  itemBuilder: (context, index) {
                                    final lens = index % BeautyLens.all.length;
                                    return Center(
                                      child: Semantics(
                                        label:
                                            '${BeautyLens.all[lens].name} lens',
                                        button: true,
                                        selected: lens == _selected,
                                        child: GestureDetector(
                                          onTap: () => _chooseLens(index),
                                          child: AnimatedScale(
                                            scale: lens == _selected ? 1 : .8,
                                            duration: const Duration(
                                              milliseconds: 150,
                                            ),
                                            child: SizedBox(
                                              width: 64,
                                              height: 64,
                                              child: _lensDisc(lens),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                          // Only the shutter/lock have hit regions; the wheel remains scrollable beside them.
                          CaptureShutter(
                            timedVideo: _timerSeconds > 0,
                            enabled: enabled,
                            recording: _recording,
                            active: _active,
                            elapsedMillis: _recordingMillis,
                            lens: _lensDisc(_selected),
                            onPhoto: _capture,
                            onStart: _beginVideo,
                            onStop: _finishVideo,
                            onSwipeLens: (delta) => _chooseLens(
                              (_carousel.page ?? _initialPage).round() + delta,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (_countdown.remaining != null)
                CaptureCountdownOverlay(
                  remaining: _countdown.remaining!,
                  onCancel: _countdown.cancel,
                ),
              if (_screenFlash)
                const Positioned.fill(
                  child: AbsorbPointer(
                    child: ColoredBox(
                      key: ValueKey('screen_flash'),
                      // Slight transparency keeps the camera texture consuming frames.
                      color: Color(0xF5FFFFFF),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
