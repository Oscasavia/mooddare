# MoodDare

A Flutter app for mood-based challenges, a photo beauty studio, and shared moments.

## Run locally

Tested with Flutter 3.32.8 / Dart 3.8.1 and Java 17. Android's face detector is bundled in the app; it needs no API key or beauty SDK subscription.

```sh
flutter config --jdk-dir="/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home"
flutter pub get
flutter run
```

Use your own Java 17 path on other machines. Flutter may otherwise choose Android Studio's incompatible Java 25 runtime. Firebase client configuration is already present for the existing MoodDare project. Enable the desired sign-in providers and configure Android SHA fingerprints in Firebase for Google sign-in. Firebase services may have their own billing requirements; free photo processing does not change Firebase's pricing.

If the debugger connection hangs on the splash screen on this Mac, the verified fallback is `flutter run -d sdk --no-hot --no-resident`. It installs and opens the app without a hot-reload session. The standalone debug APK also launches normally.

## Camera and photo studio

Choose Discover → mood → Capture your moment → Photo. After capture, the studio offers smoothing, light, warmth, reset, and an original/edited toggle. Smoothing starts at zero. The strongest usable front-facing face is processed; eyes, mouth and nose are protected with a feathered mask. If no suitable face is found, smoothing is disabled and color adjustments remain available.

The implementation combines **free on-device ML Kit face detection on Android** with our own edge-preserving pixel processing in a Dart isolate. ML Kit is a Google SDK, not an open-source beauty engine. No camera frames are uploaded for processing. Photos are normalized upright and limited to a 1600-pixel longest edge to bound memory and processing cost. Save, share and post use the same edited JPEG.

On Android, tap **✨ beside the shutter** to open **Live beauty**. Swipe the lens carousel: Original, Soft, Glow, Wide eyes, Sculpt, and Studio (a combined look). Strength controls the amount; Compare shows the original. Eye enlargement, lower-face slimming, smoothing and color adjustments run continuously. Original is selected initially. Face effects pause when no suitable face is tracked; global color adjustments remain active.

Live photos are captured from the same GPU-rendered frame as the preview, including selfie mirroring, then enter the existing save/share/post studio. The live look is baked into the capture: the studio's **Captured** comparison restores that capture, not the pre-lens camera frame. Live capture uses preview resolution (960 × 1280 on the tested emulator), not the full sensor resolution. This first live implementation is designed for portrait use.

The live engine uses native CameraX upright RGBA frames, bundled ML Kit landmarks and OpenGL ES shaders. It drops old frames instead of building a processing backlog, checks for stale tracking, and keeps all frame pixels on Android; Flutter receives a texture and small status updates. It does not require a paid SDK or cloud face processing. The approximately 29.5 fps measured on the emulator is not a physical-device performance guarantee; test latency and thermal behavior on actual phones.

Choose **Video** inside Live beauty to record the selected lens with microphone audio, for up to 30 seconds. You can change lenses and strength while recording. The MP4 contains the same GPU effects and selfie mirroring as the preview and uses the existing playback/save/share/post flow. Recording stops when the app loses focus; returning to the camera opens the completed clip for review while the app process remains alive. An interrupted clip that is too short to encode may be discarded.

Live video targets H.264 at 4 Mbps with mono AAC audio at 96 kbps. Dimensions preserve the camera aspect ratio, capped at a 720-pixel short edge and 1280-pixel long edge (720 × 960 for the tested portrait stream). The encoder targets 30 fps; actual frame delivery depends on the phone. Native duration/file limits bound recordings. The standard camera also remains available for video without live effects.

iOS currently supports photo color adjustments and normal capture; face smoothing and live lenses need native iOS implementation and validation. Virtual makeup, AR masks/stickers and full face-mesh tracking are future work.

## Verification

```sh
flutter analyze
flutter test
flutter test integration_test -d <android-emulator-id>
flutter build apk --debug --target-platform android-arm64
npm ci --ignore-scripts --prefix tooling/rules-tests
firebase emulators:exec --project demo-mooddare --only firestore,storage 'npm --prefix tooling/rules-tests test'
```

The Android integration tests use a public-domain U.S. Navy portrait of Grace Hopper (James S. Davis; TensorFlow test crop). They cover detection, GPU pixel effects, no-face bypass, orientation/mirroring, export, editor UI, continuous frames, camera switching, capture/retake and rapid background/resume without posting to Firebase. Video tests check encoded effects against a GPU still, H.264/AAC tracks and duration, playback, the 30-second limit and interrupted-clip recovery. Run these on a test emulator: Flutter's integration runner may uninstall the app afterward. Allow camera and microphone access when Android prompts. The test fixture is not part of the normal app bundle, and native fixture/track-inspection entry points are disabled in release builds.

## Structure

- `lib/features/camera`: photo processing, lens presets, live camera UI and platform-channel adapters.
- `lib/features/feed`: capture, preview, posting, playback, likes, blocking and reports.
- `lib/features/auth`, `user`, `profile`: account flow and profile management.
- `lib/features/dares`: discovery and local starter dares if the remote catalog is empty or unavailable.
- `android/.../BeautyPlugin.kt`: bundled native face detector.
- `android/.../LiveBeautyPlugin.kt`, `LiveBeautyRenderer.kt` and `LiveBeautyRecorder.kt`: native live camera, landmark tracking, GPU lens rendering/capture and MP4 recording with audio.
- `firestore.rules`, `storage.rules`, `firestore.indexes.json`: versioned backend access policy, not automatically deployed.
- `docs/RELEASE.md`: required migration and release work.

Feed queries are bounded to 60 posts. Profile grids show the latest 60. The feed hides moments after 24 hours; the profile retains them until deleted. No fake followers, premium checkout or notification controls are shown.

## Build cache troubleshooting

Do not sync `build/`, `.dart_tool/`, or `android/.gradle/` through a cloud drive. This checkout contained old duplicate generated files (`… 2.json`, `… 3.class`) that caused D8 errors and stalled Gradle reads. Prefer a local development directory outside a synced Desktop folder.

For this Mac, the generated `build` folder was relocated to a temporary local cache and replaced with an ignored symlink. It is not committed. Temporary caches may be removed by macOS; if the target no longer exists, recreate it or remove the symlink and run `flutter clean` / `flutter pub get`. A fresh Git clone uses a normal build directory.

## Release status

This is a tested Android development build, not a store-ready release. Read [the release checklist](docs/RELEASE.md) before publishing, especially database migration, deployment, signing, moderation and device testing.
