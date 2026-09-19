import 'package:flutter/material.dart';
import 'package:mooddare/core/user_message.dart';
import 'package:mooddare/core/validation.dart';
import 'package:mooddare/features/user/data/repositories/user_repository.dart';
import '../../data/repositories/auth_repository.dart';

class UsernameScreen extends StatefulWidget {
  final bool isGuest;
  const UsernameScreen({super.key, required this.isGuest});
  @override
  State<UsernameScreen> createState() => _UsernameScreenState();
}

class _UsernameScreenState extends State<UsernameScreen> {
  final _controller = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;
  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await UserRepository().saveProfile(username: _controller.text);
    } catch (e) {
      if (mounted) setState(() => _error = userMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.alternate_email, size: 52),
                  const SizedBox(height: 24),
                  const Text(
                    'Make a name\nfor yourself.',
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Choose a username people can find you by.',
                    style: TextStyle(color: Colors.white60),
                  ),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: _controller,
                    enabled: !_busy,
                    validator: validateUsername,
                    maxLength: 20,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      prefixText: '@',
                    ),
                    onFieldSubmitted: (_) => _save(),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: Text(_busy ? 'Saving…' : 'Let’s go'),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            try {
                              await AuthRepository().signOut();
                            } catch (e) {
                              if (mounted) {
                                setState(() => _error = userMessage(e));
                              }
                            }
                          },
                    child: const Text('Use a different account'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
