import 'package:flutter/material.dart';
import '../branding/mood_wink.dart';
import 'app_empty_state.dart';
import 'mooddare_wordmark.dart';

/// A single short wink concurrent with initialization, never a looping loader.
/// Authentication remains the responsibility of [child].
class BrandedStartup extends StatefulWidget {
  final Future<void> Function() initialize;
  final Widget child;
  const BrandedStartup({
    super.key,
    required this.initialize,
    required this.child,
  });

  @override
  State<BrandedStartup> createState() => _BrandedStartupState();
}

class _BrandedStartupState extends State<BrandedStartup>
    with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late Future<void> _ready;
  bool _started = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _ready = Future<void>.sync(widget.initialize)..ignore();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    if (_reduceMotion) {
      _animation.value = 1;
    } else if (!_started) {
      _animation.forward();
    }
    _started = true;
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  void _retry() {
    setState(() {
      _ready = Future<void>.sync(widget.initialize)..ignore();
      if (!_reduceMotion) _animation.forward(from: 0);
    });
  }

  double get _wink {
    if (_reduceMotion) return 1;
    final t = _animation.value;
    if (t < .2 || t > .8) return 0;
    if (t < .4) return Curves.easeInOut.transform((t - .2) / .2);
    if (t < .55) return 1;
    return 1 - Curves.easeInOut.transform((t - .55) / .25);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _ready,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.done &&
          snapshot.hasError) {
        return Scaffold(
          body: AppEmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Let’s try that again',
            message:
                'MoodDare could not start. Check your connection and try again.',
            actionLabel: 'Retry',
            onAction: _retry,
          ),
        );
      }
      return AnimatedBuilder(
        animation: _animation,
        builder: (context, _) {
          final initialized = snapshot.connectionState == ConnectionState.done;
          if (initialized && _animation.isCompleted) return widget.child;
          return Scaffold(
            body: SafeArea(
              child: Semantics(
                label: 'Starting MoodDare',
                child: ExcludeSemantics(
                  child: LayoutBuilder(
                    builder: (context, constraints) => Stack(
                      alignment: Alignment.center,
                      children: [
                        Center(child: MoodWink(wink: _wink)),
                        Positioned(
                          top: constraints.maxHeight / 2 + 86,
                          child: const MoodDareWordmark(width: 160),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
