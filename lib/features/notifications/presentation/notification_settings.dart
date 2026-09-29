import 'package:flutter/material.dart';
import 'package:mooddare/features/settings/data/settings_repository.dart';
import '../data/notification_repository.dart';
import '../data/push_service.dart';

class NotificationSettingsScreen extends StatefulWidget {
  final NotificationRepository? repository;
  final SettingsRepository? settings;
  const NotificationSettingsScreen({super.key, this.repository, this.settings});
  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  late final _repo = widget.repository ?? NotificationRepository();
  late Stream<Map<String, bool>> _prefs = _repo.preferences();
  bool _busy = false;
  String? _status;
  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(
          () => _status =
              'Could not update notifications. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Notification settings')),
    body: StreamBuilder<Map<String, bool>>(
      stream: _prefs,
      builder: (context, s) {
        if (s.hasError) {
          return Center(
            child: TextButton(
              onPressed: () => setState(() => _prefs = _repo.preferences()),
              child: const Text('Could not load settings. Retry'),
            ),
          );
        }
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            Text(
              'Your activity, your way',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Choose what appears in your inbox and phone alerts. Changes apply to new activity.',
              style: TextStyle(color: Colors.white60, height: 1.4),
            ),
            const SizedBox(height: 20),
            for (final entry in const {
              'follows': 'New followers',
              'likes': 'Likes on moments and comments',
              'comments': 'Comments and replies',
              'dares': 'Dares from friends',
            }.entries)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(entry.value),
                value: s.data![entry.key] ?? true,
                onChanged: _busy
                    ? null
                    : (v) => _run(() => _repo.setPreference(entry.key, v)),
              ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Phone alerts'),
              subtitle: const Text(
                'Your in-app inbox stays available when alerts are off.',
              ),
              value: s.data!['push'] ?? true,
              onChanged: _busy
                  ? null
                  : (v) => _run(() => _repo.setPreference('push', v)),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                      final service = PushService.instance;
                      if (service == null) throw StateError('Push unavailable');
                      final granted = await service.enable();
                      if (granted) await _repo.setPreference('push', true);
                      if (mounted) {
                        setState(
                          () => _status = granted
                              ? 'Phone alerts are enabled on this device.'
                              : 'Alerts are off in phone settings. You can still use your inbox.',
                        );
                      }
                    }),
              icon: const Icon(Icons.notifications_active_outlined),
              label: const Text('Enable on this device'),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _run(
                      () => (widget.settings ?? SettingsRepository())
                          .notificationSettings(),
                    ),
              child: const Text('Open phone settings'),
            ),
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_status!, textAlign: TextAlign.center),
              ),
          ],
        );
      },
    ),
  );
}
