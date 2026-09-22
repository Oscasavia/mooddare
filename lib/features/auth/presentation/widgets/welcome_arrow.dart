import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Two small nudges on arrival, then rests so the welcome page stays calm.
class WelcomeArrow extends StatefulWidget {
  const WelcomeArrow({super.key});
  @override
  State<WelcomeArrow> createState() => _WelcomeArrowState();
}

class _WelcomeArrowState extends State<WelcomeArrow>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.of(context);
    if (media.disableAnimations || media.accessibleNavigation) {
      _controller.value = 1;
    } else if (!_controller.isAnimating && _controller.value == 0) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: 30,
      height: 24,
      child: AnimatedBuilder(
        animation: _controller,
        child: const Icon(Icons.arrow_forward_rounded, size: 22),
        builder: (context, child) => Transform.translate(
          offset: Offset(
            5.0 * math.pow(math.sin(_controller.value * math.pi * 2), 2),
            0,
          ),
          child: child,
        ),
      ),
    ),
  );
}
