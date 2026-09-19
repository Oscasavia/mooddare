import 'package:flutter/material.dart';
import 'package:mooddare/features/auth/presentation/screens/signup_screen.dart';

class SignInPromptCard extends StatelessWidget {
  const SignInPromptCard({super.key});
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.all(20),
    child: ListTile(
      contentPadding: const EdgeInsets.all(16),
      leading: const Icon(Icons.bookmark_border),
      title: const Text('Keep your moments'),
      subtitle: const Text(
        'Create an account to keep this guest profile across devices.',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SignupScreen()),
      ),
    ),
  );
}
