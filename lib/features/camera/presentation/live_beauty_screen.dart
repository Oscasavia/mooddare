import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../feed/presentation/screens/preview_screen.dart';
import '../domain/beauty_lens.dart';

class LiveBeautyScreen extends StatefulWidget {
  final String dareText;
  const LiveBeautyScreen({super.key, required this.dareText});

  @override
  State<LiveBeautyScreen> createState() => _LiveBeautyScreenState();
}

class _LiveBeautyScreenState extends State<LiveBeautyScreen>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('mooddare/live_beauty');
  final _carousel = PageController(viewportFraction: .23);
  Future<void> _operations = Future<void>.value();
  Timer? _poll, _lookDebounce;
  int? _texture;
  int _generation = 0, _selected = 0;
  double _strength = .65, _aspect = .75;
  bool _ready = false, _face = false, _front = true;
  bool _busy = false, _comparing = false, _active = true, _inPreview = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
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
    final generation = ++_generation;
    _poll?.cancel();
    setState(() {
      _ready = false;
      _texture = null;
      _error = null;
      _face = false;
    });
    try {
      final value = await _enqueue(() async {
        await _channel.invokeMethod<void>('stop');
        return _channel.invokeMapMethod<String, dynamic>('start', {
          'front': _front,
        });
      });
      if (!mounted || generation != _generation) return;
      await _sendLook();
      if (!mounted || generation != _generation) return;
      setState(() => _texture = (value!['textureId'] as num).toInt());
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
            if (w > 0 && h > 0) _aspect = w / h;
            _error = state['error'] as String?;
            if (!_ready && ++waitingTicks > 60 && _error == null) {
              _error =
                  'The camera is taking too long to start. Please try again.';
            }
          });
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
    ++_generation;
    _poll?.cancel();
    _lookDebounce?.cancel();
    Future<void>? removed;
    if (mounted) {
      setState(() {
        _texture = null;
        _ready = false;
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

  Future<void> _sendLook() => _channel.invokeMethod<void>(
    'setLook',
    BeautyLens.all[_selected].settings(_strength, original: _comparing),
  );

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
    if (!_ready || _busy) return;
    setState(() => _busy = true);
    HapticFeedback.lightImpact();
    File? captured;
    try {
      _lookDebounce?.cancel();
      await _sendLook();
      captured = File((await _channel.invokeMethod<String>('capture'))!);
      if (!mounted || !_active) return;
      _inPreview = true;
      await _stop();
      if (!mounted) return;
      final posted = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => PreviewScreen(
            mediaFile: captured!,
            mediaType: 'image',
            dareText: widget.dareText,
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

  Future<void> _flip() async {
    if (_busy) return;
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
    _carousel.dispose();
    unawaited(_enqueue(() => _channel.invokeMethod<void>('stop')));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Close live camera',
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                  const Expanded(
                    child: Text(
                      'Live beauty',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Switch live camera',
                    onPressed: _busy ? null : _flip,
                    icon: const Icon(Icons.flip_camera_ios_outlined),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: ColoredBox(
                    color: const Color(0xFF18181F),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_texture != null)
                          Center(
                            child: AspectRatio(
                              aspectRatio: _aspect,
                              child: Texture(textureId: _texture!),
                            ),
                          ),
                        if (!_ready && _error == null)
                          const Center(child: CircularProgressIndicator()),
                        if (_error != null)
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.no_photography_outlined,
                                    size: 36,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(_error!, textAlign: TextAlign.center),
                                  const SizedBox(height: 12),
                                  FilledButton(
                                    onPressed: _busy ? null : _start,
                                    child: const Text('Try again'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (_ready)
                          Positioned(
                            top: 12,
                            left: 12,
                            right: 12,
                            child: Row(
                              children: [
                                Flexible(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      child: Text(
                                        _selected == 0 || _comparing
                                            ? 'Original'
                                            : (_face
                                                  ? 'Face tracked'
                                                  : 'Face the camera · find good light'),
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton.filledTonal(
                                  tooltip: _comparing
                                      ? 'Show lens'
                                      : 'Compare original',
                                  onPressed: _busy
                                      ? null
                                      : () {
                                          setState(
                                            () => _comparing = !_comparing,
                                          );
                                          _adjust();
                                        },
                                  icon: Icon(
                                    _comparing
                                        ? Icons.auto_awesome
                                        : Icons.compare,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (_ready)
                          Positioned(
                            bottom: 12,
                            left: 16,
                            right: 16,
                            child: Text(
                              widget.dareText,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                shadows: [
                                  Shadow(blurRadius: 5, color: Colors.black),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 88,
              child: PageView.builder(
                controller: _carousel,
                itemCount: BeautyLens.all.length,
                physics: _busy ? const NeverScrollableScrollPhysics() : null,
                onPageChanged: (index) {
                  setState(() {
                    _selected = index;
                    _comparing = false;
                  });
                  _adjust();
                  HapticFeedback.selectionClick();
                },
                itemBuilder: (context, index) => Semantics(
                  label: '${BeautyLens.all[index].name} lens',
                  selected: index == _selected,
                  button: true,
                  child: GestureDetector(
                    onTap: _busy
                        ? null
                        : () => _carousel.animateToPage(
                            index,
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOut,
                          ),
                    child: Column(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFF655298).withValues(
                                  alpha: index == _selected ? 1 : .4,
                                ),
                                const Color(0xFF293A50),
                              ],
                            ),
                            border: Border.all(
                              color: index == _selected
                                  ? const Color(0xFFC6B4FF)
                                  : Colors.white24,
                              width: index == _selected ? 3 : 1,
                            ),
                          ),
                          child: Icon(
                            [
                              Icons.block,
                              Icons.blur_on,
                              Icons.wb_sunny_outlined,
                              Icons.visibility_outlined,
                              Icons.face_retouching_natural,
                              Icons.auto_awesome,
                            ][index],
                            size: 26,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          BeautyLens.all[index].name,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 11,
                            color: index == _selected
                                ? Colors.white
                                : Colors.white60,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  const Text('Strength', style: TextStyle(fontSize: 12)),
                  Expanded(
                    child: Slider(
                      value: _strength,
                      label: '${(_strength * 100).round()}%',
                      onChanged: _selected == 0 || _busy || _comparing
                          ? null
                          : (value) {
                              setState(() => _strength = value);
                              _adjust();
                            },
                    ),
                  ),
                  SizedBox(
                    width: 35,
                    child: Text(
                      '${(_strength * 100).round()}%',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: IconButton.filled(
                tooltip: 'Capture live photo',
                onPressed: _ready && !_busy && _error == null ? _capture : null,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  fixedSize: const Size(72, 72),
                ),
                icon: _busy
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(),
                      )
                    : const Icon(Icons.camera_alt_outlined, size: 32),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Live photo · swipe to choose a lens',
                style: TextStyle(fontSize: 12, color: Colors.white60),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
