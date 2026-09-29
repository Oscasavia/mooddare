import 'dart:async';
import '../../data/weekly_dare_preferences.dart';
import 'package:flutter/material.dart';
import 'package:mooddare/core/branding/mood_wink.dart';
import 'package:mooddare/features/feed/presentation/screens/camera_screen.dart';
import '../../data/repositories/weekly_dare_repository.dart';

class WeeklyDareCard extends StatefulWidget {
  final WeeklyDareRepository? repository;
  final WeeklyDarePreferences? preferences;
  final DateTime Function()? now;
  final Widget Function(WeeklyDare)? cameraBuilder;
  const WeeklyDareCard({
    super.key,
    this.repository,
    this.preferences,
    this.now,
    this.cameraBuilder,
  });
  @override
  State<WeeklyDareCard> createState() => _WeeklyDareCardState();
}

class _WeeklyDareCardState extends State<WeeklyDareCard>
    with WidgetsBindingObserver {
  late final WeeklyDareRepository _repository;
  late Stream<WeeklyDare?> _challenge;
  late DateTime _now;
  late String _week;
  Timer? _timer;
  bool _opening = false;
  bool _preferencesReady = false;
  String? _collapsedWeek;
  late final _preferences =
      widget.preferences ?? WeeklyDarePreferences.instance;
  DateTime get now => (widget.now ?? DateTime.now)().toUtc();
  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? WeeklyDareRepository();
    _load();
    _restorePreference();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
  }

  Future<void> _restorePreference() async {
    String? week;
    try {
      week = await _preferences.load();
    } catch (_) {
      // A missing/unreadable local preference must not block the weekly dare.
    }
    if (mounted) {
      setState(() {
        _collapsedWeek = week;
        _preferencesReady = true;
      });
    }
  }

  Future<void> _toggle(WeeklyDare dare) async {
    FocusScope.of(context).unfocus();
    setState(() => _collapsedWeek = _collapsedWeek == dare.id ? null : dare.id);
    try {
      await _preferences.save(_collapsedWeek);
    } catch (_) {
      // The choice still applies for this visit if local storage is unavailable.
    }
  }

  void _load() {
    _now = now;
    _week = WeeklyDare.weekId(_now);
    _challenge = _repository.watch(_now);
  }

  void _tick() {
    if (!mounted) return;
    setState(() {
      _now = now;
      if (_week != WeeklyDare.weekId(_now)) _load();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _tick();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _join(WeeklyDare dare) async {
    FocusScope.of(context).unfocus();
    if (!dare.isActive(now)) {
      setState(_load);
      return;
    }
    setState(() => _opening = true);
    try {
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
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
      if (mounted) {
        setState(() {
          _opening = false;
          _load();
        });
      }
    }
  }

  String _remaining(WeeklyDare dare) {
    final remaining = dare.endsAt.difference(_now);
    if (remaining.inDays >= 1) return '${remaining.inDays}d left';
    if (remaining.inHours >= 1) return '${remaining.inHours}h left';
    return '${remaining.inMinutes.clamp(1, 59)}m left';
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<WeeklyDare?>(
    stream: _challenge,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Weekly dare couldn’t load.'),
              TextButton(
                onPressed: () => setState(_load),
                child: const Text('Retry'),
              ),
            ],
          ),
        );
      }
      final dare = snapshot.data;
      if (!_preferencesReady || dare == null || !dare.isActive(_now)) {
        return const SizedBox.shrink();
      }
      final collapsed = _collapsedWeek == dare.id;
      return Container(
        key: const ValueKey('weekly_dare_card'),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 20),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF35264F), Color(0xFF211C2E)],
          ),
        ),
        child: AnimatedSize(
          duration: MediaQuery.of(context).disableAnimations
              ? Duration.zero
              : const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          curve: Curves.easeInOut,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Material(
                type: MaterialType.transparency,
                child: Semantics(
                  button: true,
                  value: collapsed ? 'Collapsed' : 'Expanded',
                  child: Tooltip(
                    message: collapsed
                        ? 'Expand weekly dare'
                        : 'Collapse weekly dare',
                    child: InkWell(
                      key: const ValueKey('weekly_dare_header'),
                      onTap: () => _toggle(dare),
                      borderRadius: BorderRadius.circular(12),
                      splashFactory: NoSplash.splashFactory,
                      highlightColor: Colors.transparent,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Wrap(
                                  spacing: 12,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    const Text(
                                      'This week’s dare',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFFD2BBFA),
                                      ),
                                    ),
                                    if (!collapsed)
                                      Text(
                                        _remaining(dare),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.white60,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                collapsed
                                    ? Icons.keyboard_arrow_down_rounded
                                    : Icons.keyboard_arrow_up_rounded,
                                color: const Color(0xFFD2BBFA),
                                size: 24,
                              ),
                            ],
                          ),
                          SizedBox(height: collapsed ? 8 : 16),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      dare.title,
                                      style: TextStyle(
                                        fontSize: collapsed ? 20 : 24,
                                        fontWeight: FontWeight.w700,
                                        height: 1.15,
                                      ),
                                    ),
                                    if (!collapsed) ...[
                                      const SizedBox(height: 7),
                                      Text(
                                        'This week · ${dare.prompt.moodName}',
                                        style: const TextStyle(
                                          color: Color(0xFFD2BBFA),
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (!collapsed) ...[
                                const SizedBox(width: 12),
                                const ExcludeSemantics(
                                  child: MoodWink(size: 54),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (!collapsed) ...[
                const SizedBox(height: 16),
                Text(
                  dare.prompt.text,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.45,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'One dare. Everyone’s own take.',
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                ),
                const SizedBox(height: 18),
                _WeeklyParticipation(
                  key: ValueKey(dare.id),
                  repository: _repository,
                  dare: dare,
                  onJoin: _opening ? null : () => _join(dare),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Post before the week ends to reach your milestones. Resets Monday, UTC.',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class _WeeklyParticipation extends StatefulWidget {
  final WeeklyDareRepository repository;
  final WeeklyDare dare;
  final VoidCallback? onJoin;
  const _WeeklyParticipation({
    super.key,
    required this.repository,
    required this.dare,
    required this.onJoin,
  });
  @override
  State<_WeeklyParticipation> createState() => _WeeklyParticipationState();
}

class _WeeklyParticipationState extends State<_WeeklyParticipation> {
  late final _completed = widget.repository.completed(widget.dare.id);
  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(
    stream: _completed,
    builder: (context, snapshot) {
      final completed = snapshot.data == true;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (completed) ...[
            const Text(
              '✓ You joined this week',
              style: TextStyle(
                color: Color(0xFFD2BBFA),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (snapshot.hasError)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Your progress is unavailable right now.',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: widget.onJoin,
              child: Text(completed ? 'Make another moment' : 'Join this week'),
            ),
          ),
        ],
      );
    },
  );
}
