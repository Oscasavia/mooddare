import 'package:flutter/material.dart';
import 'package:mooddare/core/user_message.dart';
import '../data/settings_repository.dart';

class PasswordScreen extends StatefulWidget {
  final SettingsRepository repository;
  const PasswordScreen({super.key, required this.repository});
  @override
  State<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends State<PasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController(),
      _next = TextEditingController(),
      _confirm = TextEditingController();
  bool _busy = false, _visible = false, _resetSent = false;
  String? _error;
  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit({bool reset = false}) async {
    if (_busy || (!reset && !_form.currentState!.validate())) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (reset) {
        await widget.repository.resetPassword();
        if (mounted) setState(() => _resetSent = true);
      } else {
        await widget.repository.changePassword(_current.text, _next.text);
        if (mounted) Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = userMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Change password')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Keep your account yours.',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              'Confirm your current password to choose a new one for ${widget.repository.account.email ?? 'your account'}.',
            ),
            const SizedBox(height: 24),
            TextFormField(
              key: const ValueKey('current_password'),
              controller: _current,
              enabled: !_busy,
              obscureText: !_visible,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(labelText: 'Current password'),
              validator: (v) => v == null || v.isEmpty
                  ? 'Enter your current password.'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('new_password'),
              controller: _next,
              enabled: !_busy,
              obscureText: !_visible,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(
                labelText: 'New password',
                helperText: 'At least 8 characters',
                helperMaxLines: 2,
              ),
              validator: (v) => v == null || v.length < 8
                  ? 'Use at least 8 characters.'
                  : v == _current.text
                  ? 'Choose a different password.'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('confirm_password'),
              controller: _confirm,
              enabled: !_busy,
              obscureText: !_visible,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Confirm new password',
              ),
              validator: (v) =>
                  v != _next.text ? 'The passwords do not match.' : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show passwords'),
              value: _visible,
              onChanged: _busy ? null : (v) => setState(() => _visible = v),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            FilledButton(
              onPressed: _busy ? null : () => _submit(),
              child: Text(_busy ? 'Please wait…' : 'Save password'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _busy || _resetSent
                  ? null
                  : () => _submit(reset: true),
              child: const Text('Forgot your current password?'),
            ),
            if (_resetSent)
              const Text(
                'Password reset email sent. Check your inbox and spam folder.',
              ),
          ],
        ),
      ),
    ),
  );
}
