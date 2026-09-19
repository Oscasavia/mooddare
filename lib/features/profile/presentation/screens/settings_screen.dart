import 'package:flutter/material.dart';
import 'blocked_accounts_screen.dart';
import 'package:mooddare/core/user_message.dart';
import 'package:mooddare/features/auth/data/repositories/auth_repository.dart';
import 'package:mooddare/features/auth/presentation/auth_gate.dart';
import '../../data/account_repository.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;
  Future<void> _accountAction({bool delete = false}) async {
    if (_busy) return;
    if (delete) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete your account?'),
          content: const Text(
            'Your profile, posts, uploaded media and likes will be removed. This cannot be undone. You may need to sign in again first.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete account'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      if (delete) {
        await AccountRepository().deleteAccount();
      } else {
        await AuthRepository().signOut();
      }
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthGate()),
          (_) => false,
        );
      }
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
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'YOUR ACCOUNT',
            style: TextStyle(
              letterSpacing: 2,
              fontSize: 11,
              color: Colors.white54,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Sign out'),
                  onTap: _busy ? null : () => _accountAction(),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.block),
                  title: const Text('Blocked accounts'),
                  onTap: _busy
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const BlockedAccountsScreen(),
                          ),
                        ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Delete account'),
                  subtitle: const Text('Permanently remove your data'),
                  onTap: _busy ? null : () => _accountAction(delete: true),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            'ABOUT MOODDARE',
            style: TextStyle(
              letterSpacing: 2,
              fontSize: 11,
              color: Colors.white54,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('How your photos are processed'),
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Your photos, your choice'),
                      content: const Text(
                        'Photo adjustments and face detection run on your device. Photos are uploaded to Firebase only when you choose Post dare. Shared moments are visible to other signed-in members. Anyone with a shared media link can also view that media. You can delete your posts or your account in the app.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Got it'),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('About & licenses'),
                  onTap: () => showAboutDialog(
                    context: context,
                    applicationName: 'MoodDare',
                    applicationVersion: '1.0.0',
                    children: [
                      const Text(
                        'Small challenges. Real moments. Made for your everyday adventures.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Finishing up. Please keep the app open.'),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
