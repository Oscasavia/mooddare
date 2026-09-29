# MoodDare's dare writing guide

Reviewed September 29, 2026. The source of truth is `content/dares.json`:
12 dares for each of the 12 free moods and two holiday cards, and 10 for each
of the 15 locked Daring/Epic cards: 318 original prompts across 29 collections.
Premium cards remain locked previews until subscriptions are implemented.

## Writing rules

- Use short, common English words and concrete instructions. Aim for one simple
  activity, then a clear photo or video outcome. Maximum 45 words / 260 characters.
- No profanity, insults, sexual requests, humiliation, pressure or harmful stunts.
- Match the mood without assuming how a person should feel. Sad can mean comfort
  and small choices, not forced happiness. Energetic can mean gentle morning
  movement, not strenuous exercise. Creative and playful dares need not claim
  any health benefit.
- Let people adapt or skip activities. Use comfortable movement, seated options
  and easy alternatives. Never require breath holding, forced breathing,
  extreme food, dangerous locations, driving, fire, pain or intense exercise.
- Do not ask users to film strangers, expose addresses, private messages or
  personal struggles. Other people's participation needs their permission.
  Avoid tasks that require purchases or contacting someone unsafe.
- Photos and videos up to **30 seconds** are the capture options. Use short clips
  (usually 5–15 seconds). Longer real-world activities happen **off camera**,
  followed by a photo/result or short reflection. Do not ask for three-minute
  recordings, collages, editing features or upload formats the app lacks.
- No promises to cure, treat or reliably change a mood. Do not diagnose users or
  describe MoodDare as therapy. Breathing and movement should never be forced;
  stop or choose something else if uncomfortable.

## Research and limits

The wellbeing categories draw on public guidance, not clinical validation of
these individual prompts or the app. They are small, optional activities that
may support wellbeing. People respond differently.

- [NHS: five steps to mental wellbeing](https://www.nhs.uk/mental-health/self-help/guides-tools-and-activities/five-steps-to-mental-wellbeing/)
  supports the broad themes of connection, activity, learning, kindness and
  attention to the present. Those themes inform Grateful, Curious, Calm and
  gentle movement prompts; they do not establish an effect for any one dare.
- [NHS: breathing exercises for stress](https://www.nhs.uk/mental-health/self-help/guides-tools-and-activities/breathing-exercises-for-stress/)
  describes gentle, comfortable breathing without forcing it. Its full exercise
  recommends at least five minutes. Our five-breath prompt is a brief original
  adaptation, **not** that full protocol or a proven treatment dose. Recording
  happens afterward, so users need not perform breathing for an audience.
- [NHS: being active for mental health](https://www.nhs.uk/every-mind-matters/mental-wellbeing-tips/be-active-for-your-mental-health/)
  informs easy, manageable movement rather than demanding workouts.
- [WHO: Doing What Matters in Times of Stress](https://www.who.int/publications/i/item/9789240003927)
  informs attention to nearby sights/sounds, kindness and making room for
  feelings. Our original prompts are not a replacement for the WHO programme.
- [NCCIH: relaxation techniques](https://www.nccih.nih.gov/health/relaxation-techniques-what-you-need-to-know)
  notes that relaxation is not comfortable or helpful for everyone. Optional
  activities and stopping if uncomfortable matter; these are not medical care.

Keep these distinctions when writing marketing copy. A friend's helpful
experience is encouraging feedback, not evidence of a guaranteed health benefit.

## Review, tests and publication

1. Edit the reviewed JSON. Keep existing mood names, tiers, IDs and locks.
2. Review every prompt for plain English, accessibility, privacy, mood fit and
   capture mechanics. Automated checks cannot judge all these qualities.
3. Run `python3 tooling/dares/catalog.py --generate`, then
   `dart format lib/features/dares/domain/curated_dares.dart`.
4. Run `python3 -m unittest discover -s tooling/dares -p '*_test.py'`,
   `node --test tooling/dares/publish.test.cjs`, and the Flutter catalog tests.
   CI checks source/bundle parity, minimum counts, offline availability and
   locked previews. Rules tests reject client edits to the catalog.
5. Run `node tooling/dares/publish.cjs` to review the live change plan.
   `node tooling/dares/publish.cjs --apply` uses the authenticated Firebase CLI
   account to update only existing remote `dareList` arrays in one atomic commit.
   It takes a temporary backup and requires the versions read to still match.
   It refuses unexpected membership, tiers or missing concurrency versions.
6. Rebuild the app for local fallback/holiday changes. Remote mood updates are
   available when the catalog is next loaded. Existing open screens may retain
   their old selection until reopened.

The keyword, length and duration checks are regression guardrails, not a complete
profanity filter, clinical safety review or English reading-level assessment.
The duration check deliberately flags all explicit times over 30 seconds for
review, including off-camera tasks; this collection uses untimed/count-based
activities instead. Future exceptions need deliberate review, not bypassing CI.

Previously posted moments, saved dares and sent dares retain their original text.
Do not rewrite historical content or the active weekly community dare: its exact
prompt is used for participation credit. Weekly prompts have a separate publisher.
