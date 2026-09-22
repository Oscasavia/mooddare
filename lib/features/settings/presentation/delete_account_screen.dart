import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mooddare/core/user_message.dart';
import 'package:mooddare/features/auth/presentation/auth_gate.dart';
import '../data/settings_repository.dart';
import 'package:mooddare/features/auth/data/welcome_history.dart';

class DeleteAccountScreen extends StatefulWidget {
  final SettingsRepository repository;
  final WidgetBuilder? signedOutBuilder;
  final WelcomeHistory? welcomeHistory;
  const DeleteAccountScreen({
    super.key,
    required this.repository,
    this.signedOutBuilder,
    this.welcomeHistory,
  });
  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _confirmation = TextEditingController();
  final _password = TextEditingController();
  late final String? _accountId;
  @override
  void initState() {
    super.initState();
    _accountId = widget.repository.account.id;
  }

  bool _busy = false, _verify = false;
  String? _error;
  bool get _confirmed => _confirmation.text.trim() == 'DELETE';

  Future<void> _delete({bool google = false}) async {
    if (_busy || !_confirmed) return;
    if (_accountId != widget.repository.account.id) {
      setState(
        () => _error =
            'Your signed-in account changed. Reopen this screen to continue.',
      );
      return;
    }
    if (_verify &&
        !google &&
        widget.repository.account.password &&
        _password.text.isEmpty) {
      setState(() => _error = 'Enter your current password.');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_verify) {
        final verified = await widget.repository.reauthenticateForDeletion(
          password: !google && widget.repository.account.password
              ? _password.text
              : null,
        );
        if (!verified) {
          if (mounted) {
            setState(
              () => _error =
                  'Verification cancelled. Your account has not been deleted.',
            );
          }
          return;
        }
        _password.clear();
      }
      await widget.repository.deleteAccount();
      // A local preference failure must not report an already deleted account
      // as a failed deletion or encourage retrying the destructive operation.
      final history = widget.welcomeHistory ?? WelcomeHistory.instance;
      try {
        await history.resetAfterDeletion();
      } catch (_) {}
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder:
                widget.signedOutBuilder ??
                (_) => AuthGate(welcomeHistory: history, showWelcome: true),
          ),
          (_) => false,
        );
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        setState(() {
          if (error.code == 'requires-recent-login') {
            _verify = true;
            _error =
                'Please verify that this is your account to finish deleting it.';
          } else if (error.code == 'user-mismatch') {
            _error = 'Choose the Google account you use for MoodDare.';
          } else {
            _error = userMessage(error);
          }
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = userMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _confirmation.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.repository.account;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Delete account'),
          automaticallyImplyLeading: !_busy,
        ),
        body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Say goodbye to MoodDare?',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Deleting your account removes your profile, posts, uploaded media, post likes, comments and connections. This cannot be undone.',
                ),
                const SizedBox(height: 24),
                TextField(
                  key: const ValueKey('delete_confirmation'),
                  controller: _confirmation,
                  enabled: !_busy,
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: (_) => setState(() {}),
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: const InputDecoration(
                    labelText: 'Type DELETE to confirm',
                  ),
                ),
                if (_verify && account.password) ...[
                  const SizedBox(height: 20),
                  TextField(
                    key: const ValueKey('delete_password'),
                    controller: _password,
                    enabled: !_busy,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    decoration: const InputDecoration(
                      labelText: 'Current password',
                    ),
                    onSubmitted: (_) => _delete(),
                  ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                FilledButton(
                  key: const ValueKey('confirm_delete_account'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  ),
                  onPressed: _busy || !_confirmed
                      ? null
                      : () => _delete(
                          google: !account.password && account.google,
                        ),
                  child: Text(
                    _busy
                        ? 'Finishing up…'
                        : _verify
                        ? account.password
                              ? 'Verify and delete account'
                              : 'Verify with Google and delete'
                        : 'Delete account',
                  ),
                ),
                if (_verify && account.password && account.google)
                  TextButton(
                    onPressed: _busy || !_confirmed
                        ? null
                        : () => _delete(google: true),
                    child: const Text('Verify with Google instead'),
                  ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Text(
                      'Finishing up. Please keep the app open.',
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Keep my account'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
