import 'package:flutter/material.dart';
import 'package:mooddare/core/widgets/mooddare_wordmark.dart';
import 'package:mooddare/core/widgets/legal_notice.dart';
import '../widgets/welcome_artwork.dart';
import '../widgets/welcome_arrow.dart';
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
    ],
  );

  Widget _actions(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FilledButton(
        key: const ValueKey('welcome_get_started'),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SignupScreen()),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              SizedBox(width: 42),
              Expanded(child: Text('Get started', textAlign: TextAlign.center)),
              SizedBox(width: 12),
              WelcomeArrow(),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
      Center(
        child: TextButton(
          style: TextButton.styleFrom(
            splashFactory: NoSplash.splashFactory,
            overlayColor: Colors.transparent,
          ),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          ),
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(
                  text: 'Already a member? ',
                  style: TextStyle(
                    color: Colors.white60,
                    fontWeight: FontWeight.normal,
                  ),
                ),
                TextSpan(
                  text: 'Sign in',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
      const SizedBox(height: 8),
      const LegalNotice(),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          final compact = constraints.maxWidth < 380;
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  wide ? 40 : 28,
                  28,
                  wide ? 40 : 28,
                  16,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: wide ? 1000 : 480,
                        ),
                        child: wide
                            ? Row(
                                children: [
                                  const Expanded(child: WelcomeArtwork()),
                                  const SizedBox(width: 40),
                                  Expanded(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
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
                                mainAxisSize: MainAxisSize.min,
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
                    Padding(
                      padding: const EdgeInsets.only(top: 28),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: _actions(context),
                      ),
                    ),
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
