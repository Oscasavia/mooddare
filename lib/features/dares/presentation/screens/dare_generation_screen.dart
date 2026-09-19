import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mooddare/models/mood_model.dart';
import 'package:mooddare/features/feed/presentation/screens/camera_screen.dart';

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
  @override
  void initState() {
    super.initState();
    if (widget.mood.dareList.isNotEmpty) {
      _index = Random().nextInt(widget.mood.dareList.length);
    }
  }

  void _shuffle() {
    if (widget.mood.dareList.length < 2) return;
    HapticFeedback.selectionClick();
    setState(
      () => _index =
          (_index + 1 + Random().nextInt(widget.mood.dareList.length - 1)) %
          widget.mood.dareList.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dare = widget.mood.dareList.isEmpty
        ? 'More dares are on their way.'
        : widget.mood.dareList[_index];
    return Scaffold(
      appBar: AppBar(title: Text('${widget.mood.icon} ${widget.mood.name}')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              const Text(
                'YOUR NEXT LITTLE ADVENTURE',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 2,
                  color: Colors.white54,
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: widget.mood.color.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: Center(
                    child: SingleChildScrollView(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: Text(
                          dare,
                          key: ValueKey(dare),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 28,
                            height: 1.35,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: widget.mood.dareList.length > 1 ? _shuffle : null,
                icon: const Icon(Icons.shuffle),
                label: const Text('Try another dare'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: widget.mood.dareList.isEmpty
                    ? null
                    : () async {
                        final posted = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CameraScreen(dareText: dare),
                          ),
                        );
                        if (context.mounted && posted == true) {
                          Navigator.pop(context);
                        }
                      },
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Capture your moment'),
              ),
              const SizedBox(height: 16),
              const Text(
                'Make it your own. Sharing is always optional.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.white54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
