import '../../../camera/data/video_editor.dart';
import '../../../camera/presentation/video_adjustments_panel.dart';
import 'package:mooddare/core/widgets/share_icon.dart';
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
import '../../../camera/presentation/photo_adjustments_panel.dart';
import '../../../camera/presentation/photo_review_frame.dart';
import '../../data/repositories/post_repository.dart';

class PreviewScreen extends StatefulWidget {
  final File mediaFile;
  final String mediaType;
  final String dareText;
  final String? moodId, moodName;
  final String? liveLens;
  final PostRepository? repository;
  const PreviewScreen({
    super.key,
    required this.mediaFile,
    required this.mediaType,
    required this.dareText,
    this.liveLens,
    this.repository,
    this.moodId,
    this.moodName,
  });
  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen>
    with WidgetsBindingObserver {
  final _postId = const Uuid().v4();
  VideoPlayerController? _video;
  PhotoEditor? _editor;
  VideoEditor? _videoEditor;
  VideoEdits? _videoEdits;
  bool _seekingTrim = false;
  bool _showVideoEdits = false;
  Uint8List? _rendered;
  PhotoAdjustments _settings = const PhotoAdjustments();
  bool _loading = true, _busy = false, _rendering = false, _original = false;
  String? _error;
  int _revision = 0;
  bool _processing = false;
  bool _showAdjustments = false;
  bool get _hasEdits =>
      _settings.smoothing != 0 ||
      _settings.brightness != 0 ||
      _settings.warmth != 0;
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
        _videoEditor = VideoEditor(
          widget.mediaFile,
          video.value.duration.inMilliseconds,
        );
        _videoEdits = VideoEdits(
          startMs: 0,
          endMs: video.value.duration.inMilliseconds,
        );
        video.addListener(_loopTrim);
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
      _original = false;
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
          : await _videoEditor!.export(_videoEdits!);
      if (action == 'post') {
        await (widget.repository ?? PostRepository()).createPost(
          dareText: widget.dareText,
          moodId: widget.moodId,
          moodName: widget.moodName,
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
    _video?.removeListener(_loopTrim);
    unawaited(_video?.dispose());
    unawaited(_videoEditor?.dispose());
    unawaited(_editor?.dispose());
    super.dispose();
  }

  void _loopTrim() {
    final video = _video;
    final edits = _videoEdits;
    if (video == null ||
        edits == null ||
        _seekingTrim ||
        !video.value.isPlaying) {
      return;
    }
    final position = video.value.position.inMilliseconds;
    if (position < edits.startMs || position >= edits.endMs) {
      _seekingTrim = true;
      video
          .seekTo(Duration(milliseconds: edits.startMs))
          .whenComplete(() => _seekingTrim = false);
    }
  }

  void _editVideo(VideoEdits edits) {
    setState(() => _videoEdits = edits);
    _video?.setVolume(edits.muted ? 0 : 1);
    _video?.seekTo(Duration(milliseconds: edits.startMs));
  }

  void _reset() {
    setState(() => _error = null);
    _adjust(const PhotoAdjustments());
  }

  void _showDare() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Text(
            widget.dareText,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
      ),
    );
  }

  Widget _media() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          semanticsLabel: 'Preparing your capture',
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.refresh, size: 32, color: Colors.white60),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              if (_editor != null)
                TextButton(
                  onPressed: _busy ? null : _reset,
                  child: const Text('Reset adjustments'),
                )
              else
                TextButton(
                  onPressed: () => Navigator.maybePop(context),
                  child: const Text('Retake'),
                ),
            ],
          ),
        ),
      );
    }
    if (_isPhoto) {
      return PhotoReviewFrame(
        photo: Image.memory(
          _original ? _editor!.original : _rendered!,
          key: const ValueKey('capture_preview'),
          fit: BoxFit.contain,
          gaplessPlayback: true,
        ),
        controls: _showAdjustments
            ? PhotoAdjustmentsPanel(
                settings: _settings,
                faceDetected: _editor!.faceDetected,
                notice: _editor!.notice,
                enabled: !_busy,
                onChanged: _adjust,
                onReset: _reset,
              )
            : null,
      );
    }
    final video = _video;
    if (video == null || !video.value.isInitialized) return const SizedBox();
    return Center(
      child: AspectRatio(
        aspectRatio: video.value.aspectRatio,
        child: ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: video,
          builder: (context, value, _) => Semantics(
            button: true,
            label: value.isPlaying ? 'Pause video' : 'Play video',
            child: GestureDetector(
              onTap: () => value.isPlaying ? video.pause() : video.play(),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  VideoPlayer(video),
                  if (!value.isPlaying)
                    const Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Icon(Icons.play_arrow_rounded, size: 40),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: VideoProgressIndicator(
                      video,
                      allowScrubbing: true,
                      colors: VideoProgressColors(
                        playedColor: Theme.of(context).colorScheme.primary,
                        backgroundColor: Colors.white24,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final blocked = _loading || _busy || _rendering || _error != null;
    final canAdjust = _isPhoto && _editor != null;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          leading: BackButton(
            onPressed: _busy ? null : () => Navigator.maybePop(context),
          ),
          title: Text(
            _isPhoto ? 'Make it yours' : 'Your moment',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          actions: [
            PopupMenuButton<String>(
              tooltip: 'Save or share',
              enabled: !blocked,
              onSelected: _useMedia,
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'save',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.download_outlined),
                    title: Text('Save to photos'),
                  ),
                ),
                PopupMenuItem(
                  value: 'share',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: ShareIcon(),
                    title: Text('Share capture'),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _media(),
                        if (canAdjust && _hasEdits && _error == null)
                          Positioned(
                            top: 12,
                            right: 12,
                            child: FilledButton.tonalIcon(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.black54,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(48, 44),
                              ),
                              onPressed: _busy
                                  ? null
                                  : () =>
                                        setState(() => _original = !_original),
                              icon: const Icon(Icons.compare_arrows, size: 18),
                              label: Text(
                                _original
                                    ? (widget.liveLens == null
                                          ? 'Original'
                                          : 'Captured')
                                    : 'Compare',
                              ),
                            ),
                          ),
                        if (_showVideoEdits && _videoEdits != null)
                          Positioned(
                            left: 8,
                            right: 8,
                            bottom: 8,
                            child: VideoAdjustmentsPanel(
                              edits: _videoEdits!,
                              durationMs: _videoEditor!.durationMs,
                              thumbnails: _videoEditor!.thumbnails(),
                              enabled: !_busy,
                              onChanged: _editVideo,
                              onDone: () =>
                                  setState(() => _showVideoEdits = false),
                            ),
                          ),
                        if (_rendering || _busy)
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
              // Keep the media visible even on short screens or with large text.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .42,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: _busy ? null : _showDare,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white60,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.bolt_rounded, size: 16),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                widget.dareText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: Colors.white60),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.chevron_right, size: 16),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          if (!_isPhoto && !_loading && _error == null) ...[
                            IconButton.filledTonal(
                              tooltip: 'Edit video',
                              onPressed: _busy
                                  ? null
                                  : () => setState(
                                      () => _showVideoEdits = !_showVideoEdits,
                                    ),
                              icon: const Icon(Icons.tune),
                            ),
                            const SizedBox(width: 12),
                          ],
                          if (canAdjust) ...[
                            IconButton.filledTonal(
                              tooltip: _showAdjustments
                                  ? 'Done adjusting'
                                  : 'Adjust photo',
                              isSelected: _showAdjustments,
                              style: IconButton.styleFrom(
                                splashFactory: NoSplash.splashFactory,
                                highlightColor: Colors.transparent,
                                minimumSize: const Size(56, 52),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: _busy
                                  ? null
                                  : () => setState(
                                      () =>
                                          _showAdjustments = !_showAdjustments,
                                    ),
                              icon: const Icon(Icons.tune),
                              selectedIcon: const Icon(Icons.check),
                            ),
                            const SizedBox(width: 12),
                          ],
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
                              label: Text(_busy ? 'Please wait…' : 'Post dare'),
                            ),
                          ),
                        ],
                      ),
                    ],
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
