import 'package:flutter/material.dart';
import '../data/settings_repository.dart';

const mooddareFaq = <(String, String)>[
  (
    'How do I capture a moment?',
    'Pick a mood and a dare, then open the camera. Tap the shutter for a photo. Hold it to record video; slide toward the lock to keep recording hands-free. Tap stop to finish.',
  ),
  (
    'How do lenses and photo edits work?',
    'Choose a lens from the camera wheel and adjust its strength. On Make it yours, fine-tune smoothness, light and warmth before posting. Processing happens on your device. Live face lenses are currently available on Android.',
  ),
  (
    'Why did a moment leave my feed?',
    'Moments stay in the feed for 24 hours. Your own dares remain available from your profile until you delete them.',
  ),
  (
    'How do I edit or delete a comment?',
    'Open comments and use the menu beside your comment. You can edit or delete your own comments. Post owners can also delete comments on their posts. Hold a post’s heart to see who liked it.',
  ),
  (
    'Why can’t I post?',
    'Check your connection and that you are signed in. Keep the app open while uploading. If it still fails, contact us with what happened and your app version. Never send your password.',
  ),
  (
    'Why don’t I receive notifications?',
    'Push notifications are not available yet. Notification settings opens your phone’s controls for MoodDare; enabling them does not turn on alerts that the app does not yet send.',
  ),
  (
    'Can I unlock Daring and Epic?',
    'Premium mood packs are coming soon. Locked previews do not make a purchase or start a subscription.',
  ),
  (
    'How do I block or report someone?',
    'Open the menu on their moment to report it or block the author. Manage blocked accounts in Settings. Blocking hides their posts and comments from your feed.',
  ),
  (
    'Who can see my moments?',
    'Posted moments are visible to other signed-in members. Anyone with a shared media link can also view that media. Only post content you are comfortable sharing.',
  ),
  (
    'What happens when I delete my account?',
    'Account deletion removes your profile, posts, uploaded media, post likes and comments. It cannot be undone. You may need to sign in again first. Keep the app open until it finishes; contact support if it fails.',
  ),
];

class HelpScreen extends StatelessWidget {
  final SettingsRepository repository;
  const HelpScreen({super.key, required this.repository});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Help & FAQ')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'A little help, whenever you need it.',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 20),
        for (final item in mooddareFaq)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              margin: EdgeInsets.zero,
              child: ExpansionTile(
                shape: const RoundedRectangleBorder(side: BorderSide.none),
                collapsedShape: const RoundedRectangleBorder(
                  side: BorderSide.none,
                ),
                title: Text(item.$1),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [Text(item.$2)],
              ),
            ),
          ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ContactScreen(repository: repository),
            ),
          ),
          icon: const Icon(Icons.mail_outline),
          label: const Text('Still need help? Contact us'),
        ),
        const SizedBox(height: 20),
      ],
    ),
  );
}

class ContactScreen extends StatefulWidget {
  final SettingsRepository repository;
  const ContactScreen({super.key, required this.repository});
  @override
  State<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends State<ContactScreen> {
  final _message = TextEditingController();
  late final _version = widget.repository.version().catchError(
    (_) => 'Unknown',
  );
  String _topic = 'Help with the app';
  bool _busy = false;
  String? _status;
  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _contact({bool copy = false}) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final body =
          '${_message.text.trim()}\n\nMoodDare ${await _version}\nTopic: $_topic';
      if (copy) {
        await widget.repository.copy(
          'To: ${SettingsRepository.supportEmail}\nSubject: MoodDare — $_topic\n\n$body',
        );
      } else {
        final query = {'subject': 'MoodDare — $_topic', 'body': body}.entries
            .map(
              (e) =>
                  '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
            )
            .join('&');
        await widget.repository.openUrl(
          Uri(
            scheme: 'mailto',
            path: SettingsRepository.supportEmail,
            query: query,
          ),
        );
      }
      if (mounted) {
        setState(
          () => _status = copy
              ? 'Support draft copied.'
              : 'Your email app opened. Review the draft and send it when you’re ready.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _status = copy
              ? 'Could not copy the draft. Your message is still here; email it to ${SettingsRepository.supportEmail}.'
              : 'Could not open your email app. Copy the draft and email it to ${SettingsRepository.supportEmail}.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Contact us')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'We’re listening.',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        const SelectableText(SettingsRepository.supportEmail),
        const SizedBox(height: 8),
        const Text(
          'Tell us what happened or share an idea. Please don’t include passwords or sensitive information.',
        ),
        const SizedBox(height: 24),
        DropdownButtonFormField<String>(
          value: _topic,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Topic'),
          items: const [
            'Help with the app',
            'Report a bug',
            'Share an idea',
            'Account & data',
          ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
          onChanged: _busy ? null : (v) => setState(() => _topic = v!),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _message,
          enabled: !_busy,
          minLines: 5,
          maxLines: 10,
          maxLength: 2000,
          decoration: const InputDecoration(
            labelText: 'Your message',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 16),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Semantics(liveRegion: true, child: Text(_status!)),
          ),
        FilledButton.icon(
          onPressed: _busy ? null : () => _contact(),
          icon: const Icon(Icons.mail_outline),
          label: const Text('Open email draft'),
        ),
        TextButton.icon(
          onPressed: _busy ? null : () => _contact(copy: true),
          icon: const Icon(Icons.copy_outlined),
          label: const Text('Copy support draft'),
        ),
      ],
    ),
  );
}

class NotificationsScreen extends StatefulWidget {
  final SettingsRepository repository;
  const NotificationsScreen({super.key, required this.repository});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _busy = false;
  String? _error;
  Future<void> _open() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.notificationSettings();
    } catch (e) {
      if (mounted) {
        setState(
          () => _error =
              'Could not open notification settings. Open your phone’s Settings, then Apps → MoodDare → Notifications.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Notifications')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.notifications_none_rounded, size: 48),
        const SizedBox(height: 24),
        Text(
          'Stay in the moment',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        const Text(
          'Push notifications are coming later. MoodDare does not send like, comment or dare alerts yet.',
        ),
        const SizedBox(height: 12),
        const Text(
          'You can review MoodDare’s notification permissions in your phone settings. Available controls depend on your phone.',
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _busy ? null : _open,
          icon: const Icon(Icons.open_in_new),
          label: const Text('Open phone settings'),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(_error!),
          ),
      ],
    ),
  );
}
