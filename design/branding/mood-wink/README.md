# Mood Wink

Selected by the app owner on 2026-09-22 from concept A in
`../icon-concepts-v2/comparison.png`. The final artwork is a clean vector
reconstruction of that concept: an asymmetric friendly face with a wink and
curved smile. It uses MoodDare lavender (#C5B4FF) and ink (#0D0E14).

The canonical vector contours are in `lib/core/branding/mood_wink.dart`.
`app-icon.png` is the 1024px opaque icon preview; the transparent SVG export is
`assets/branding/mood-wink.svg`. No extra runtime package is needed for the mark.

To regenerate platform artwork from those contours, run from the repo root:

```sh
flutter test tooling/export_brand_assets.dart
```

This writes Android density-specific legacy icons, adaptive foregrounds and
monochrome artwork, native launch resources, and the complete iOS AppIcon and
LaunchImage catalogs. Android adaptive artwork stays within the central safe
circle. iOS launcher PNGs are opaque RGB, with no baked-in corner rounding.
Native launch screens use a still open-eyed lavender face on ink; Flutter then
closes and reopens one eye over 900ms. The splash shows only the animated icon;
the accessible startup label remains available to screen readers.
Flutter uses the full-window center, matching the native artwork, rather than
centering inside SafeArea. Unequal status/navigation insets previously shifted
the face downward during the native-to-Flutter handoff. The 900ms wink timeline
and 128px mark size are unchanged; inset regression tests lock in alignment.

The wink runs once per fresh app startup while Firebase initializes. It does not
loop during a slow initialization or replay when returning from the background.
Reduced-motion and accessible-navigation settings show a still wink with no
animation delay. Initialization errors retain a retry action. Authentication
and saved sessions still use the existing AuthGate.

Regression tests in `test/branded_startup_test.dart` cover timing, failure and
retry, initialization races, reduced motion, disposal, resizing, eye-only
deformation, adaptive mask safety, and iOS icon sizes/opacity.

## In-app personality

Discover uses a 26px open-eyed mark when inactive and the lavender wink when
selected. The navigation label remains visible and accessible. Login and signup
share a compact 64px wink above the 128px wordmark. These are static accents;
only startup animates.

Find people uses the wink to invite a first search and a thinking expression
for no matches: an upward glance, raised eyebrow, and small slanted mouth.
The `x_x` expression with a flat mouth is reserved for errors. The shared
`AppEmptyState.error` displays it for full-page startup, session, feed, profile,
and blocked-account loading errors; Find people also uses it for search and
blocked-account loading failures. Existing explanations and recovery actions
remain available. Loading and populated results do not display either face.
`AppEmptyState.illustration`
allows other screens to opt into branded artwork without replacing useful
status icons everywhere. Keyboard/large-text layouts, search transitions and
geometry are covered in `test/brand_personality_test.dart` and the existing
entry/search suites.

The empty Moments feed, profile grid, and followers/following lists now use an
open-eyed smile. This uses the original eyes and smile contours, with the same
outline and lavender color. Empty comments use a gently opened smiling mouth;
the outline and eyes stay identical. Filtered feed/connection lists use Thinking
when there are no matches. These illustrations remain static and yield to real
content immediately. Error and loading states remain distinct.

The login/signup divider sits between the email/password submit button and
Google sign-in. Account-switch links remain below Google. See
[personality opportunities](personality-opportunities.md) for implemented and
proposed placements elsewhere.
