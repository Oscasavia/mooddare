import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mooddare/core/branding/mood_wink.dart';
import 'package:mooddare/core/widgets/app_empty_state.dart';
import 'package:mooddare/features/dares/data/repositories/weekly_dare_repository.dart';
import 'package:mooddare/features/feed/presentation/screens/camera_screen.dart';
import '../data/notification_repository.dart';

/// Opens the announced week, never silently replaces an old notification with a
/// different prompt. Rechecks availability at capture time and on app resume.
class WeeklyDareNotificationScreen extends StatefulWidget {
  final String weekId;
  final NotificationRepository repository;
  final DateTime Function()? now;
  final Widget Function(WeeklyDare)? cameraBuilder;
  const WeeklyDareNotificationScreen({
    super.key,
    required this.weekId,
    required this.repository,
    this.now,
    this.cameraBuilder,
  });
  @override
  State<WeeklyDareNotificationScreen> createState() =>
      _WeeklyDareNotificationScreenState();
}

class _WeeklyDareNotificationScreenState
    extends State<WeeklyDareNotificationScreen>
    with WidgetsBindingObserver {
  late Stream<WeeklyDare?> _week = widget.repository.watchWeekly(widget.weekId);
  DateTime get _now => (widget.now ?? DateTime.now)();
  Timer? _timer;
  bool _opening = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _join(WeeklyDare dare) async {
    if (_opening) return;
    if (!dare.isActive(_now)) {
      setState(() {});
      return;
    }
    setState(() => _opening = true);
    try {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) =>
              widget.cameraBuilder?.call(dare) ??
              CameraScreen(
                dareText: dare.prompt.text,
                moodId: dare.prompt.moodId,
                moodName: dare.prompt.moodName,
                weeklyDareId: dare.id,
              ),
        ),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Community dare')),
    body: StreamBuilder<WeeklyDare?>(
      stream: _week,
      builder: (context, s) {
        if (s.hasError) {
          return AppEmptyState.error(
            title: 'Couldn’t load this dare',
            message: 'Check your connection and try again.',
            actionLabel: 'Retry',
            onAction: () => setState(
              () => _week = widget.repository.watchWeekly(widget.weekId),
            ),
          );
        }
        if (s.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final dare = s.data;
        if (dare == null || !dare.isActive(_now)) {
          return const AppEmptyState(
            illustration: MoodWink(size: 80),
            title: 'This weekly dare is no longer active',
            message: 'Find the current community dare on Discover.',
          );
        }
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 20),
            const Center(child: MoodWink(size: 88)),
            const SizedBox(height: 28),
            Text(
              'This week · ${dare.prompt.moodName}',
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: 12),
            Text(
              dare.title,
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            Text(
              dare.prompt.text,
              style: const TextStyle(fontSize: 18, height: 1.5),
            ),
            const SizedBox(height: 12),
            const Text(
              'One dare. Everyone’s own take.',
              style: TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _opening ? null : () => _join(dare),
              child: const Text('Join this week'),
            ),
            const SizedBox(height: 16),
            const Text(
              'Post before the week ends to reach your milestones. Resets Monday, UTC.',
              style: TextStyle(color: Colors.white54, height: 1.4),
              textAlign: TextAlign.center,
            ),
          ],
        );
      },
    ),
  );
}
