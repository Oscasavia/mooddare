import 'package:flutter/material.dart';
import '../../../../models/mood_model.dart';

Future<void> showMoodPreview(BuildContext context, MoodModel mood) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: MoodPreviewContent(mood: mood),
        ),
      ),
    );

class MoodPreviewContent extends StatelessWidget {
  final MoodModel mood;
  const MoodPreviewContent({super.key, required this.mood});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ExcludeSemantics(
        child: Text(
          mood.icon,
          textAlign: TextAlign.center,
          textScaler: TextScaler.noScaling,
          style: const TextStyle(fontSize: 56),
        ),
      ),
      const SizedBox(height: 16),
      Text(
        mood.name,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      Text(
        mood.isPremium ? '${mood.tier.label} · Coming soon' : 'Coming soon',
        textAlign: TextAlign.center,
        style: TextStyle(color: Theme.of(context).colorScheme.primary),
      ),
      if (mood.description.isNotEmpty) ...[
        const SizedBox(height: 20),
        Text(
          mood.description,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, height: 1.5),
        ),
      ],
      const SizedBox(height: 16),
      Text(
        mood.isPremium
            ? 'We’re preparing this collection. Subscriptions aren’t available yet.'
            : 'This mood is being prepared. Check back for new dares.',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white60, height: 1.5),
      ),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: () => Navigator.maybePop(context),
        child: const Text('Back to moods'),
      ),
    ],
  );
}

Future<void> showMoodCollections(
  BuildContext context,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  constraints: BoxConstraints(
    maxHeight: MediaQuery.sizeOf(context).height * .85,
  ),
  builder: (context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'More ways to play',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          const Text(
            'Free moods are ready now. Daring and Epic are previews of future collections.',
            style: TextStyle(color: Colors.white70, height: 1.5),
          ),
          const SizedBox(height: 20),
          for (final tier in MoodTier.values)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(switch (tier) {
                MoodTier.basic => Icons.favorite_border,
                MoodTier.daring => Icons.local_fire_department_outlined,
                MoodTier.epic => Icons.auto_awesome_outlined,
              }),
              title: Text(tier.label),
              subtitle: Text(
                tier == MoodTier.basic
                    ? 'Everyday and seasonal dares · Available now'
                    : 'Coming soon',
              ),
            ),
          const SizedBox(height: 12),
          const Text(
            'Subscriptions aren’t available yet.',
            style: TextStyle(color: Colors.white54),
          ),
        ],
      ),
    ),
  ),
);
