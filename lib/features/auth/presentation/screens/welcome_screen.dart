import 'package:flutter/material.dart';
import 'package:mooddare/core/user_message.dart';
import '../../data/repositories/auth_repository.dart';
import 'login_screen.dart';
import 'signup_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _busy = false;
  Future<void> _guest() async {
    setState(() => _busy = true);
    try {
      await AuthRepository().signInAnonymously();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
                Container(
                  height: 190,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(36),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF302547), Color(0xFF1C2936)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Center(
                    child: Wrap(
                      spacing: 24,
                      children: [
                        Text('✨', style: TextStyle(fontSize: 48)),
                        Text('📸', style: TextStyle(fontSize: 64)),
                        Text('⚡', style: TextStyle(fontSize: 48)),
                      ],
                    ),
                  ),
                ),
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
                  onPressed: _busy
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SignupScreen(),
                          ),
                        ),
                  child: const Text('Find your next dare'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const LoginScreen(),
                          ),
                        ),
                  child: const Text('I already have an account'),
                ),
                TextButton(
                  onPressed: _busy ? null : _guest,
                  child: Text(_busy ? 'Getting ready…' : 'Explore as a guest'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
