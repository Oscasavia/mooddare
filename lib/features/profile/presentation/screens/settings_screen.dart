import 'package:mooddare/core/widgets/share_icon.dart';
import 'package:flutter/material.dart';
import 'package:mooddare/core/user_message.dart';
import 'package:mooddare/features/auth/presentation/auth_gate.dart';
import 'package:mooddare/features/settings/data/settings_repository.dart';
import 'package:mooddare/features/settings/presentation/password_screen.dart';
import 'package:mooddare/features/settings/presentation/help_screen.dart';
import 'blocked_accounts_screen.dart';
import 'package:mooddare/features/settings/presentation/delete_account_screen.dart';
import 'edit_profile_screen.dart';

class SettingsScreen extends StatefulWidget {
  final SettingsRepository? repository;
  final WidgetBuilder? signedOutBuilder;
  const SettingsScreen({super.key, this.repository, this.signedOutBuilder});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _repo = widget.repository ?? SettingsRepository();
  late final _version = _repo.version().catchError(
    (_) => 'Version unavailable',
  );
  bool _busy = false, _confirming = false;
  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  void _open(Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  Future<void> _password() async {
    final account = _repo.account;
    if (account.password) {
      final changed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => PasswordScreen(repository: _repo)),
      );
      if (changed == true) _message('Password updated.');
    } else {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            account.guest
                ? 'You’re browsing as a guest'
                : 'Your sign-in provider manages this',
          ),
          content: Text(
            account.guest
                ? 'Guest accounts do not have a password. Create an account from your profile to keep access to your moments.'
                : 'You use ${account.google ? 'Google' : 'another provider'} to sign in. Change your password with that provider.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Got it'),
            ),
            if (account.google)
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  try {
                    await _repo.openUrl(
                      Uri.parse('https://myaccount.google.com/security'),
                    );
                  } catch (_) {
                    _message(
                      'Could not open Google. Visit myaccount.google.com to manage your password.',
                    );
                  }
                },
                child: const Text('Google account'),
              ),
          ],
        ),
      );
    }
  }

  Future<void> _accountAction({bool delete = false}) async {
    if (_busy || _confirming) return;
    if (delete) {
      _open(
        DeleteAccountScreen(
          repository: _repo,
          signedOutBuilder: widget.signedOutBuilder,
        ),
      );
      return;
    }
    _confirming = true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out of MoodDare?'),
        content: Text(
          _repo.account.guest
              ? 'This guest account has no sign-in method. Signing out can lose access to its moments. Create an account from your profile first if you want to keep them.'
              : 'You can sign back in whenever you’re ready.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    _confirming = false;
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _repo.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: widget.signedOutBuilder ?? (_) => const AuthGate(),
          ),
          (_) => false,
        );
      }
    } catch (e) {
      _message(userMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(BuildContext buttonContext) async {
    if (_busy) return;
    final box = buttonContext.findRenderObject() as RenderBox;
    try {
      await _repo.shareApp(box.localToGlobal(Offset.zero) & box.size);
    } catch (_) {
      _message('Could not open sharing. Please try again.');
    }
  }

  Widget _section(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 10),
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: Colors.white60),
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    ),
  );
  Widget _tile(
    String title,
    IconData icon,
    VoidCallback onTap, {
    String? subtitle,
    bool danger = false,
  }) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
    leading: icon == Icons.ios_share_rounded
        ? ShareIcon(color: Theme.of(context).colorScheme.primary)
        : Icon(
            icon,
            color: danger
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.primary,
          ),
    title: Text(
      title,
      style: danger
          ? TextStyle(color: Theme.of(context).colorScheme.error)
          : null,
    ),
    subtitle: subtitle == null ? null : Text(subtitle),
    trailing: const Icon(
      Icons.chevron_right_rounded,
      size: 20,
      color: Colors.white38,
    ),
    onTap: _busy ? null : onTap,
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your space. Your way.',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _repo.account.guest
                            ? 'Make yourself at home.'
                            : _repo.account.email ?? 'Make yourself at home.',
                        style: const TextStyle(color: Colors.white60),
                      ),
                    ],
                  ),
                ),
                _section('Account', [
                  _tile(
                    'Edit profile',
                    Icons.person_outline_rounded,
                    () => _open(const EditProfileScreen()),
                    subtitle: 'Photo, username and bio',
                  ),
                  _tile(
                    'Change password',
                    Icons.lock_outline_rounded,
                    _password,
                    subtitle: _repo.account.password
                        ? 'Keep your account secure'
                        : 'Manage your sign-in method',
                  ),
                ]),
                _section('Preferences & privacy', [
                  _tile(
                    'Notifications',
                    Icons.notifications_none_rounded,
                    () => _open(NotificationsScreen(repository: _repo)),
                  ),
                  _tile(
                    'Blocked accounts',
                    Icons.block_outlined,
                    () => _open(const BlockedAccountsScreen()),
                  ),
                  _tile(
                    'Your photos & data',
                    Icons.privacy_tip_outlined,
                    () => showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Your photos, your choice'),
                        content: const SingleChildScrollView(
                          child: Text(
                            'Photo adjustments and face detection run on your device. Photos are uploaded to Firebase only when you choose Post dare. Shared moments are visible to other signed-in members. Anyone with a shared media link can also view that media. You can delete your posts or your account in the app.',
                          ),
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
                ]),
                _section('Here to help', [
                  _tile(
                    'Help & FAQ',
                    Icons.help_outline_rounded,
                    () => _open(HelpScreen(repository: _repo)),
                    subtitle: 'Quick answers and useful tips',
                  ),
                  _tile(
                    'Contact us',
                    Icons.mail_outline_rounded,
                    () => _open(ContactScreen(repository: _repo)),
                    subtitle: 'Get help, report a bug or share an idea',
                  ),
                ]),
                _section('About MoodDare', [
                  Builder(
                    builder: (context) => _tile(
                      'Share MoodDare',
                      Icons.ios_share_rounded,
                      () => _share(context),
                      subtitle:
                          Uri.tryParse(
                                SettingsRepository.appUrl,
                              )?.host.endsWith('.example') ==
                              true
                          ? 'Preview link · download coming soon'
                          : 'Invite someone to try a dare',
                    ),
                  ),
                  FutureBuilder<String>(
                    future: _version,
                    builder: (context, version) => _tile(
                      'About & licenses',
                      Icons.info_outline_rounded,
                      () => showAboutDialog(
                        context: context,
                        applicationName: 'MoodDare',
                        applicationVersion: version.data ?? 'Loading version…',
                        children: [
                          const Text(
                            'Small challenges. Real moments. Made for your everyday adventures.',
                          ),
                        ],
                      ),
                      subtitle: version.data,
                    ),
                  ),
                ]),
                _section('Account actions', [
                  _tile(
                    'Sign out',
                    Icons.logout_rounded,
                    () => _accountAction(),
                  ),
                  _tile(
                    'Delete account',
                    Icons.delete_outline_rounded,
                    () => _accountAction(delete: true),
                    subtitle: 'Permanently remove your account',
                    danger: true,
                  ),
                ]),
              ],
            ),
            if (_busy)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Material(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      children: [
                        LinearProgressIndicator(),
                        SizedBox(height: 8),
                        Text('Finishing up. Please keep the app open.'),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
