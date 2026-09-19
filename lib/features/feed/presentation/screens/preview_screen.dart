import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:uuid/uuid.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import '../../../camera/data/photo_editor.dart';
import '../../../camera/domain/photo_processing.dart';
import '../../data/repositories/post_repository.dart';

class PreviewScreen extends StatefulWidget {
  final File mediaFile;
  final String mediaType;
  final String dareText;
  const PreviewScreen({
    super.key,
    required this.mediaFile,
    required this.mediaType,
    required this.dareText,
  });
  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen>
    with WidgetsBindingObserver {
  final _postId = const Uuid().v4();
  VideoPlayerController? _video;
  PhotoEditor? _editor;
  Uint8List? _rendered;
  PhotoAdjustments _settings = const PhotoAdjustments();
  bool _loading = true, _busy = false, _rendering = false, _original = false;
  String? _error;
  int _revision = 0;
  bool _processing = false;
  Timer? _debounce;
  bool get _isPhoto => widget.mediaType == 'image';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_isPhoto) {
        final editor = await PhotoEditor.open(widget.mediaFile);
        if (!mounted) {
          await editor.dispose();
          return;
        }
        _editor = editor;
        _rendered = editor.original;
      } else {
        final video = VideoPlayerController.file(widget.mediaFile);
        _video = video;
        await video.initialize();
        if (!mounted) return;
        await video.setLooping(true);
        await video.play();
      }
    } catch (_) {
      if (mounted) _error = 'Could not open this capture. Please retake it.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _adjust(PhotoAdjustments settings) {
    _debounce?.cancel();
    setState(() {
      _settings = settings;
      _rendering = true;
      _revision++;
    });
    _debounce = Timer(const Duration(milliseconds: 250), _render);
  }

  Future<void> _render() async {
    if (_processing || !mounted) return;
    _processing = true;
    final revision = _revision;
    try {
      final bytes = await _editor!.render(_settings);
      if (mounted && revision == _revision) setState(() => _rendered = bytes);
    } catch (_) {
      if (mounted && revision == _revision) {
        _message('Could not apply these adjustments. Try again.');
        setState(
          () => _error =
              'Could not render this photo. Reset adjustments to retry.',
        );
      }
    } finally {
      _processing = false;
      if (mounted && revision == _revision) setState(() => _rendering = false);
      if (mounted && revision != _revision) {
        _debounce?.cancel();
        unawaited(_render());
      }
    }
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _useMedia(String action) async {
    if (_busy || _loading || _rendering || _error != null) return;
    setState(() => _busy = true);
    try {
      final file = _isPhoto
          ? await _editor!.export(_rendered!)
          : widget.mediaFile;
      if (action == 'post') {
        await PostRepository().createPost(
          dareText: widget.dareText,
          mediaFile: file,
          mediaType: widget.mediaType,
          postId: _postId,
        );
        if (mounted) {
          _message('Your dare is live!');
          Navigator.of(context).pop(true);
        }
      } else if (action == 'save') {
        if (!await Gal.hasAccess()) {
          if (!await Gal.requestAccess()) {
            throw StateError('Gallery permission denied');
          }
        }
        if (_isPhoto) {
          await Gal.putImage(file.path);
        } else {
          await Gal.putVideo(file.path);
        }
        _message('Saved to your photos');
      } else {
        if (!mounted) return;
        final box = context.findRenderObject() as RenderBox?;
        await Share.shareXFiles(
          [XFile(file.path)],
          text: '${widget.dareText} #MoodDare',
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        );
      }
    } catch (_) {
      _message(
        action == 'post'
            ? 'Could not post. Check your connection and try again.'
            : action == 'save'
            ? 'Could not save. Check photo permissions in Settings.'
            : 'Could not share. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _video?.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _revision++;
    unawaited(_video?.dispose());
    unawaited(_editor?.dispose());
    super.dispose();
  }

  Widget _slider(
    String label,
    double value,
    ValueChanged<double>? onChanged, {
    double min = 0,
  }) => Row(
    children: [
      SizedBox(
        width: 68,
        child: Text(label, style: Theme.of(context).textTheme.bodySmall),
      ),
      Expanded(
        child: Slider(
          value: value,
          min: min,
          max: 1,
          onChanged: _busy ? null : onChanged,
        ),
      ),
      SizedBox(
        width: 34,
        child: Text(
          '${(value * 100).round()}',
          textAlign: TextAlign.end,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final blocked = _loading || _busy || _rendering || _error != null;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isPhoto ? 'Make it yours' : 'Your moment'),
          actions: [
            if (_isPhoto && _editor != null)
              TextButton(
                onPressed: _busy
                    ? null
                    : () {
                        setState(() => _error = null);
                        _adjust(const PhotoAdjustments());
                      },
                child: const Text('Reset'),
              ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      color: Colors.black,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (_loading)
                            const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(),
                                  SizedBox(height: 16),
                                  Text('Preparing your capture…'),
                                ],
                              ),
                            )
                          else if (_error != null)
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          else if (_isPhoto)
                            Image.memory(
                              _original ? _editor!.original : _rendered!,
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                            )
                          else if (_video?.value.isInitialized ?? false)
                            Center(
                              child: AspectRatio(
                                aspectRatio: _video!.value.aspectRatio,
                                child: GestureDetector(
                                  onTap: () => setState(() {
                                    _video!.value.isPlaying
                                        ? _video!.pause()
                                        : _video!.play();
                                  }),
                                  child: VideoPlayer(_video!),
                                ),
                              ),
                            ),
                          if (_isPhoto && _editor != null && _error == null)
                            Positioned(
                              top: 12,
                              right: 12,
                              child: FilledButton.tonalIcon(
                                onPressed: () =>
                                    setState(() => _original = !_original),
                                icon: const Icon(
                                  Icons.compare_arrows,
                                  size: 18,
                                ),
                                label: Text(_original ? 'Original' : 'Edited'),
                              ),
                            ),
                          if (_rendering)
                            const Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: LinearProgressIndicator(),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Flexible(
                flex: 0,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .42,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isPhoto && _editor != null) ...[
                          Row(
                            children: [
                              const Icon(Icons.auto_awesome, size: 18),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Photo studio',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                              Text(
                                'On your device',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: Colors.white54),
                              ),
                            ],
                          ),
                          if (_editor!.notice != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                _editor!.notice!,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: Colors.white60),
                              ),
                            ),
                          _slider(
                            'Smooth',
                            _settings.smoothing,
                            _editor!.faceDetected
                                ? (v) =>
                                      _adjust(_settings.copyWith(smoothing: v))
                                : null,
                          ),
                          _slider(
                            'Light',
                            _settings.brightness,
                            (v) => _adjust(_settings.copyWith(brightness: v)),
                            min: -1,
                          ),
                          _slider(
                            'Warmth',
                            _settings.warmth,
                            (v) => _adjust(_settings.copyWith(warmth: v)),
                            min: -1,
                          ),
                        ],
                        Text(
                          widget.dareText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: Colors.white70),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            IconButton.filledTonal(
                              tooltip: 'Save to photos',
                              onPressed: blocked
                                  ? null
                                  : () => _useMedia('save'),
                              icon: const Icon(Icons.download_outlined),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              tooltip: 'Share capture',
                              onPressed: blocked
                                  ? null
                                  : () => _useMedia('share'),
                              icon: const Icon(Icons.ios_share),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: blocked
                                    ? null
                                    : () => _useMedia('post'),
                                icon: _busy
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.arrow_upward, size: 20),
                                label: const Text('Post dare'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
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
