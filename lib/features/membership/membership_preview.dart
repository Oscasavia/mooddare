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
  late final _pages = PageController(
    initialPage: _tier.index,
    viewportFraction: .9,
  );
  bool _yearly = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _select(MoodTier tier) {
    _pages.animateToPage(
      tier.index,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _options() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, updateSheet) {
          final tint = _tierColor(_tier);
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(child: MoodWink(size: 52, color: tint)),
                  const SizedBox(height: 16),
                  Text(
                    '${_tier.label}, your way.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Choose a rhythm to preview.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white60),
                  ),
                  const SizedBox(height: 24),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final stack =
                          constraints.maxWidth < 300 ||
                          MediaQuery.textScalerOf(context).scale(1) > 1.4;
                      final choices = [
                        for (final yearly in [false, true])
                          _DurationCard(
                            yearly: yearly,
                            selected: _yearly == yearly,
                            tint: tint,
                            onTap: () {
                              setState(() => _yearly = yearly);
                              updateSheet(() {});
                            },
                          ),
                      ];
                      return stack
                          ? Column(
                              children: [
                                choices.first,
                                const SizedBox(height: 12),
                                choices.last,
                              ],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: choices.first),
                                const SizedBox(width: 12),
                                Expanded(child: choices.last),
                              ],
                            );
                    },
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _yearly
                        ? 'One payment per year · Pricing to come'
                        : 'One payment per month · Pricing to come',
                    key: const ValueKey('membership_billing_copy'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: tint, height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Preview only. Memberships are not available to buy. Final prices and renewal terms will be shown before any purchase.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white60, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Keep exploring'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paid = _tier != MoodTier.basic;
    final tint = _tierColor(_tier);
    return Scaffold(
      appBar: AppBar(title: const Text('Membership preview')),
      bottomNavigationBar: Material(
        color: theme.scaffoldBackgroundColor,
        elevation: 12,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  paid
                      ? '${_tier.label} · Coming soon'
                      : 'Free · Available now',
                  style: TextStyle(color: tint),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const ValueKey('membership_action'),
                    onPressed: paid
                        ? _options
                        : () => Navigator.maybePop(context),
                    style: FilledButton.styleFrom(backgroundColor: tint),
                    child: Text(
                      paid ? 'View plan options' : 'Back to MoodDare',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 154 * MediaQuery.textScalerOf(context).scale(1),
                    child: PageView.builder(
                      key: const ValueKey('membership_carousel'),
                      controller: _pages,
                      itemCount: MoodTier.values.length,
                      onPageChanged: (index) =>
                          setState(() => _tier = MoodTier.values[index]),
                      itemBuilder: (context, index) {
                        final tier = MoodTier.values[index];
                        final color = _tierColor(tier);
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(28),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  color.withValues(alpha: .28),
                                  color.withValues(alpha: .07),
                                ],
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'mooddare',
                                        style: TextStyle(
                                          color: color,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        tier.label,
                                        style: theme.textTheme.headlineLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: -1,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (MediaQuery.textScalerOf(context).scale(1) <=
                                    1.4) ...[
                                  const SizedBox(width: 12),
                                  MoodWink(size: 52, color: color),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    children: [
                      for (final tier in MoodTier.values)
                        ChoiceChip(
                          key: ValueKey('membership_${tier.name}'),
                          label: Text(tier.label),
                          selected: _tier == tier,
                          showCheckmark: false,
                          onSelected: (_) => _select(tier),
                        ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          MembershipConcept.plans[_tier]!.heading,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          paid
                              ? '${_tier == MoodTier.epic ? 'Everything in Daring' : 'Everything in Free'}, with more room to play.'
                              : 'No subscription needed.',
                          style: const TextStyle(
                            color: Colors.white70,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Compare below. Paid additions are planned.',
                          style: TextStyle(color: Colors.white60, height: 1.4),
                        ),
                        const SizedBox(height: 24),
                        _BenefitGroup(
                          title: 'Find your next dare',
                          tier: _tier,
                          benefits: const [
                            (
                              'Everyday & seasonal moods',
                              'Available in every plan',
                              MoodTier.basic,
                            ),
                            (
                              'Daring mood collections',
                              'New Daring dares added regularly',
                              MoodTier.daring,
                            ),
                            (
                              'Epic mood collections',
                              'New Epic dares added regularly',
                              MoodTier.epic,
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        _BenefitGroup(
                          title: 'Make it your look',
                          tier: _tier,
                          benefits: const [
                            (
                              'Current lenses & My look',
                              'Including Golden Hour and today’s AR lenses',
                              MoodTier.basic,
                            ),
                            (
                              'New beauty collections',
                              'Exclusive looks planned for Daring and Epic',
                              MoodTier.daring,
                            ),
                            (
                              'New playful AR & profile colors',
                              'Extra creative collections planned for Epic',
                              MoodTier.epic,
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        _BenefitGroup(
                          title: 'Better together',
                          tier: _tier,
                          benefits: const [
                            (
                              'Your community',
                              'Posting, comments, follows and saved dares',
                              MoodTier.basic,
                            ),
                            (
                              'The weekly community dare',
                              'One shared challenge, open to everyone',
                              MoodTier.basic,
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Your current features stay free. This is a design preview: benefits may change, and nothing here starts a subscription or unlocks paid content.',
                          style: TextStyle(color: Colors.white60, height: 1.5),
                        ),
                      ],
                    ),
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

Color _tierColor(MoodTier tier) => switch (tier) {
  MoodTier.basic => const Color(0xFFB2D8C2),
  MoodTier.daring => const Color(0xFFC5B4FF),
  MoodTier.epic => const Color(0xFFF2C4AA),
};

class _BenefitGroup extends StatelessWidget {
  final String title;
  final MoodTier tier;
  final List<(String, String, MoodTier)> benefits;
  const _BenefitGroup({
    required this.title,
    required this.tier,
    required this.benefits,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          children: [
            for (final benefit in benefits)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        tier.index >= benefit.$3.index
                            ? Icons.check_rounded
                            : Icons.lock_outline_rounded,
                        color: tier.index >= benefit.$3.index
                            ? _tierColor(tier)
                            : Colors.white38,
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            benefit.$1,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            benefit.$2,
                            style: const TextStyle(
                              color: Colors.white60,
                              height: 1.4,
                            ),
                          ),
                          if (benefit.$3 != MoodTier.basic) ...[
                            const SizedBox(height: 4),
                            Text(
                              tier.index >= benefit.$3.index
                                  ? 'Included in this planned tier'
                                  : 'Starts with ${benefit.$3.label} · Planned',
                              style: TextStyle(
                                color: _tierColor(benefit.$3),
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

class _DurationCard extends StatelessWidget {
  final bool yearly, selected;
  final Color tint;
  final VoidCallback onTap;
  const _DurationCard({
    required this.yearly,
    required this.selected,
    required this.tint,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: Material(
      color: selected
          ? tint.withValues(alpha: .16)
          : Colors.white.withValues(alpha: .04),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        key: ValueKey(yearly ? 'membership_yearly' : 'membership_monthly'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      yearly ? 'Yearly' : 'Monthly',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    size: 20,
                    color: tint,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'Pricing to come',
                style: TextStyle(color: Colors.white70, height: 1.4),
              ),
              const SizedBox(height: 6),
              Text(
                yearly ? 'Billed once a year' : 'Billed once a month',
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class MembershipPreviewBanner extends StatelessWidget {
  const MembershipPreviewBanner({super.key});
  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFF282238),
    borderRadius: BorderRadius.circular(24),
    child: InkWell(
      key: const ValueKey('profile_membership_banner'),
      borderRadius: BorderRadius.circular(24),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => const MembershipPreviewScreen(),
        ),
      ),
      child: const Padding(
        padding: EdgeInsets.all(18),
        child: Row(
          children: [
            MoodWink(size: 44),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'A little more MoodDare',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'Explore Daring & Epic · Preview',
                    style: TextStyle(color: Colors.white70, height: 1.4),
                  ),
                ],
              ),
            ),
            SizedBox(width: 8),
            Icon(Icons.arrow_forward_rounded, size: 20),
          ],
        ),
      ),
    ),
  );
}
