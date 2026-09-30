import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/branding/mood_wink.dart';
import '../../models/mood_model.dart';

// Explicitly opt in for design reviews. Even an opted-in release/profile build
// cannot expose this prototype. This flag never grants a paid entitlement.
const membershipPreviewEnabled =
    kDebugMode && bool.fromEnvironment('MOODDARE_MEMBERSHIP_PREVIEW');

class MembershipConcept {
  final String heading, description;
  final List<String> benefits;
  const MembershipConcept(this.heading, this.description, this.benefits);

  static const plans = {
    MoodTier.basic: MembershipConcept(
      'Good moments start here.',
      'The everyday MoodDare experience, free to enjoy.',
      [
        'Everyday moods and seasonal dares',
        'The weekly community dare',
        'Today’s camera lenses, including Golden Hour',
        'My look, saved dares and your community',
      ],
    ),
    MoodTier.daring: MembershipConcept(
      'A little more adventure.',
      'Fresh ideas for the days you want to try something different.',
      [
        'Everything in Free',
        'All Daring mood collections',
        'Regular additions to Daring dares',
        'A future collection of exclusive beauty looks',
      ],
    ),
    MoodTier.epic: MembershipConcept(
      'Make it unmistakably you.',
      'More ways to play, create and bring your personality to a moment.',
      [
        'Everything in Daring',
        'All Epic mood collections',
        'Regular additions to Epic dares',
        'Future playful AR lens collections',
        'Future profile color collections',
      ],
    ),
  };
}

/// Presentation only: no purchases, storage, networking or entitlement writes.
class MembershipPreviewScreen extends StatefulWidget {
  final MoodTier initialTier;
  const MembershipPreviewScreen({
    super.key,
    this.initialTier = MoodTier.daring,
  });

  @override
  State<MembershipPreviewScreen> createState() =>
      _MembershipPreviewScreenState();
}

class _MembershipPreviewScreenState extends State<MembershipPreviewScreen> {
  late MoodTier _tier = widget.initialTier;
  bool _yearly = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final plan = MembershipConcept.plans[_tier]!;
    final paid = _tier != MoodTier.basic;
    final tint = switch (_tier) {
      MoodTier.basic => const Color(0xFFB2D8C2),
      MoodTier.daring => accent,
      MoodTier.epic => const Color(0xFFF2C4AA),
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Membership preview')),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: MoodWink(size: 64)),
                  const SizedBox(height: 20),
                  Text(
                    'More ways to be you.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.8,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'A first look at Free, Daring and Epic.\nPaid memberships are not available yet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      for (final tier in MoodTier.values)
                        ChoiceChip(
                          key: ValueKey('membership_${tier.name}'),
                          label: Text(tier.label),
                          selected: _tier == tier,
                          showCheckmark: false,
                          onSelected: (_) => setState(() => _tier = tier),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    key: const ValueKey('membership_details'),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: tint.withValues(alpha: .09),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_tier.label} · ${paid ? 'Planned' : 'Available now'}',
                          style: TextStyle(
                            color: tint,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          plan.heading,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          plan.description,
                          style: const TextStyle(
                            color: Colors.white70,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 20),
                        for (final benefit in plan.benefits)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Icon(
                                    paid
                                        ? Icons.add_rounded
                                        : Icons.check_rounded,
                                    size: 20,
                                    color: tint,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    benefit,
                                    style: const TextStyle(height: 1.4),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (paid) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              for (final yearly in [false, true])
                                ChoiceChip(
                                  key: ValueKey(
                                    yearly
                                        ? 'membership_yearly'
                                        : 'membership_monthly',
                                  ),
                                  label: Text(yearly ? 'Yearly' : 'Monthly'),
                                  selected: _yearly == yearly,
                                  showCheckmark: false,
                                  onSelected: (_) =>
                                      setState(() => _yearly = yearly),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _yearly
                                ? 'One payment per year · Pricing to come'
                                : 'One payment per month · Pricing to come',
                            key: const ValueKey('membership_billing_copy'),
                            style: TextStyle(color: tint, height: 1.5),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Planned as a renewing membership. Final prices and renewal terms will be shown before any purchase.',
                            style: TextStyle(
                              color: Colors.white60,
                              height: 1.5,
                            ),
                          ),
                        ] else
                          Text(
                            'No subscription needed.',
                            style: TextStyle(color: tint),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'At a glance',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Compare what’s included. Paid additions are planned.',
                    style: TextStyle(color: Colors.white60, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  for (final comparison in const [
                    ('Everyday moods & seasonal dares', 'Free · Daring · Epic'),
                    (
                      'Community, saved dares & weekly dare',
                      'Free · Daring · Epic',
                    ),
                    ('Current lenses & My look', 'Free · Daring · Epic'),
                    (
                      'Daring moods & new beauty looks',
                      'Planned for Daring · Epic',
                    ),
                    ('Epic moods, new AR & profile colors', 'Planned for Epic'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            comparison.$1,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            comparison.$2,
                            style: TextStyle(color: accent, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'New looks. Same little you.',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'We’re exploring new beauty looks for Daring and playful AR collections for Epic. Today’s lenses, including Golden Hour, would stay free.',
                    style: TextStyle(color: Colors.white70, height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Design preview only. Benefits may change. Nothing on this screen starts a subscription or unlocks paid content.',
                    style: TextStyle(color: Colors.white60, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => Navigator.maybePop(context),
                    child: const Text('Back to MoodDare'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
