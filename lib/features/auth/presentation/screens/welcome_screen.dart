import 'package:flutter/material.dart';
import 'package:mooddare/core/widgets/mooddare_wordmark.dart';
import '../widgets/welcome_artwork.dart';
import 'login_screen.dart';
import 'signup_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  Widget _brand(double width) => Align(
    alignment: Alignment.centerLeft,
    child: MoodDareWordmark(width: width),
  );

  Widget _intro(BuildContext context, {required bool compact}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'A little dare.\nA great story.',
        style: TextStyle(
          fontSize: compact ? 36 : 42,
          height: 1.1,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.5,
        ),
      ),
      const SizedBox(height: 16),
      const Text(
        'Pick your mood. Take a dare.\nMake a moment worth sharing.',
        style: TextStyle(fontSize: 16, height: 1.6, color: Colors.white60),
      ),
      const SizedBox(height: 28),
      FilledButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SignupScreen()),
        ),
        child: const Text('Find your next dare'),
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        ),
        child: const Text('I already have an account'),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          final compact = constraints.maxWidth < 380;
          return Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(wide ? 40 : 28),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: wide ? 1000 : 480),
                child: wide
                    ? Row(
                        children: [
                          const Expanded(child: WelcomeArtwork()),
                          const SizedBox(width: 40),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _brand(180),
                                const SizedBox(height: 40),
                                _intro(context, compact: false),
                              ],
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _brand(compact ? 160 : 180),
                          const SizedBox(height: 24),
                          const WelcomeArtwork(),
                          const SizedBox(height: 24),
                          _intro(context, compact: compact),
                        ],
                      ),
              ),
            ),
          );
        },
      ),
    ),
  );
}
