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
closes and reopens one eye over 900ms, with the approved wordmark below it.

The wink runs once per fresh app startup while Firebase initializes. It does not
loop during a slow initialization or replay when returning from the background.
Reduced-motion and accessible-navigation settings show a still wink with no
animation delay. Initialization errors retain a retry action. Authentication
and saved sessions still use the existing AuthGate.

Regression tests in `test/branded_startup_test.dart` cover timing, failure and
retry, initialization races, reduced motion, disposal, resizing, eye-only
deformation, adaptive mask safety, and iOS icon sizes/opacity.
