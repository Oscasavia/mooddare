import 'package:flutter/material.dart';
import 'package:mooddare/core/branding/mood_wink.dart';
import 'package:mooddare/core/widgets/mooddare_wordmark.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('About MoodDare')),
    body: SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
            children: [
              const Center(child: MoodWink(size: 96)),
              const SizedBox(height: 20),
              const Center(child: MoodDareWordmark(width: 160)),
              const SizedBox(height: 32),
              Text(
                'A little dare.\nA great story.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.8,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'MoodDare turns the way you feel into something worth doing. '
                'Pick a mood, try a dare, and share a little piece of your day.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, height: 1.6),
              ),
              const SizedBox(height: 28),
              const Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Make it yours',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Capture a photo or video, find a look you love, and let your personality show.',
                        style: TextStyle(color: Colors.white70, height: 1.6),
                      ),
                      SizedBox(height: 24),
                      Text(
                        'Find your people',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Discover everyday adventures, cheer someone on, and turn a comment into a conversation.',
                        style: TextStyle(color: Colors.white70, height: 1.6),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Stay curious. Be kind. Dare a little.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
