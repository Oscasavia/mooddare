import 'package:flutter/material.dart';
import '../widgets/welcome_artwork.dart';
import 'login_screen.dart';
import 'signup_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'MOODDARE',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 48),
                const WelcomeArtwork(),
                const SizedBox(height: 32),
                const Text(
                  'A little dare.\nA great story.',
                  style: TextStyle(
                    fontSize: 42,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.5,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Pick your mood. Try something new.\nShare the moments that make you, you.',
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.6,
                    color: Colors.white60,
                  ),
                ),
                const SizedBox(height: 32),
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
            ),
          ),
        ),
      ),
    ),
  );
}
