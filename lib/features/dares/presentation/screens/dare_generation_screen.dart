import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mooddare/models/mood_model.dart';
import 'package:mooddare/features/feed/presentation/screens/camera_screen.dart';
import '../widgets/mood_preview.dart';

class DareDisplayScreen extends StatefulWidget {
  final MoodModel mood;
  final bool isProofRequired;
  const DareDisplayScreen({
    super.key,
    required this.mood,
    required this.isProofRequired,
  });
  @override
  State<DareDisplayScreen> createState() => _DareDisplayScreenState();
}

class _DareDisplayScreenState extends State<DareDisplayScreen> {
  int _index = 0;
  bool _openingCamera = false;
  @override
  void initState() {
    super.initState();
    if (widget.mood.dareList.isNotEmpty) {
      _index = Random().nextInt(widget.mood.dareList.length);
    }
  }

  void _shuffle() {
    if (_openingCamera ||
        !widget.mood.isAvailable ||
        widget.mood.dareList.length < 2) {
      return;
    }
    HapticFeedback.selectionClick();
    setState(
      () => _index =
          (_index + 1 + Random().nextInt(widget.mood.dareList.length - 1)) %
          widget.mood.dareList.length,
    );
  }

  Future<void> _capture(String dare) async {
    if (_openingCamera || !widget.mood.isAvailable) return;
    setState(() => _openingCamera = true);
    try {
      final posted = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => CameraScreen(dareText: dare)),
      );
      if (mounted && posted == true) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _openingCamera = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mood = widget.mood;
    if (mood.isPremium || mood.isLocked) {
      return Scaffold(
        appBar: AppBar(),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: MoodPreviewContent(mood: mood),
          ),
        ),
      );
    }
    final hasDares = mood.dareList.isNotEmpty;
    final dare = hasDares
        ? mood.dareList[_index]
        : 'More dares are on their way.';
    final accent = Color.lerp(mood.color, Colors.white, .2)!;
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -.75),
            radius: 1.25,
            colors: [
              mood.color.withValues(alpha: .18),
              const Color(0xFF0D0E14),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .05),
                            shape: BoxShape.circle,
                          ),
                          child: const BackButton(),
                        ),
                        const Expanded(
                          child: Text(
                            'Your mood',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        key: const ValueKey('mood_dare_scroll'),
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 28),
                              Center(
                                child: ExcludeSemantics(
                                  child: Container(
                                    width: 88,
                                    height: 88,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(30),
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          mood.color.withValues(alpha: .22),
                                          mood.color.withValues(alpha: .06),
                                        ],
                                      ),
                                    ),
                                    child: Text(
                                      mood.icon,
                                      style: const TextStyle(fontSize: 44),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                mood.name,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: accent,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -.6,
                                ),
                              ),
                              const SizedBox(height: 28),
                              Container(
                                key: const ValueKey('mood_dare_card'),
                                padding: const EdgeInsets.fromLTRB(
                                  24,
                                  12,
                                  24,
                                  28,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: .045),
                                  borderRadius: BorderRadius.circular(28),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        const Expanded(
                                          child: Text(
                                            'Your dare',
                                            style: TextStyle(
                                              color: Colors.white60,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Try another dare',
                                          onPressed:
                                              mood.dareList.length > 1 &&
                                                  !_openingCamera
                                              ? _shuffle
                                              : null,
                                          style: IconButton.styleFrom(
                                            foregroundColor: accent,
                                            splashFactory:
                                                NoSplash.splashFactory,
                                            highlightColor: Colors.transparent,
                                          ),
                                          icon: const Icon(
                                            Icons.shuffle_rounded,
                                            size: 21,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        minHeight: 140,
                                      ),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: AnimatedSwitcher(
                                          duration:
                                              MediaQuery.disableAnimationsOf(
                                                context,
                                              )
                                              ? Duration.zero
                                              : const Duration(
                                                  milliseconds: 220,
                                                ),
                                          transitionBuilder:
                                              (child, animation) =>
                                                  FadeTransition(
                                                    opacity: animation,
                                                    child: SlideTransition(
                                                      position: Tween<Offset>(
                                                        begin: const Offset(
                                                          0,
                                                          .04,
                                                        ),
                                                        end: Offset.zero,
                                                      ).animate(animation),
                                                      child: child,
                                                    ),
                                                  ),
                                          child: Semantics(
                                            key: ValueKey(dare),
                                            liveRegion: true,
                                            child: Text(
                                              dare,
                                              style: TextStyle(
                                                fontSize:
                                                    constraints.maxWidth < 360
                                                    ? 26
                                                    : 30,
                                                height: 1.25,
                                                fontWeight: FontWeight.w600,
                                                letterSpacing: -.6,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 28),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton(
                          key: const ValueKey('mood_open_camera'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(48, 56),
                            backgroundColor: accent,
                            foregroundColor: const Color(0xFF15121C),
                          ),
                          onPressed: hasDares && !_openingCamera
                              ? () => _capture(dare)
                              : null,
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.camera_alt_outlined, size: 22),
                              SizedBox(width: 10),
                              Flexible(
                                child: Text(
                                  'Open camera',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Sharing is optional.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
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
}
