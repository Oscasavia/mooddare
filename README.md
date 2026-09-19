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

## Moments

The Moments header uses **mooddare** branding. Photos and videos fill their rounded feed cards with a centered crop, preserving proportions. A single tap on the media or caption opens the same full-screen viewer used by profile dares; that viewer contains the full image/video without the feed crop. Tap a video in the viewer to pause or resume. Double-tapping media still likes the post, and action buttons and vertical feed swipes retain their own behavior.

The feed video pauses before its viewer opens, the outgoing viewer pauses as it closes, and the active feed video resumes on return. Manually paused viewer videos stay paused after interruptions. Hiding a moment from the viewer closes it and removes the card from the current feed session.

Comments open in a keyboard-aware bottom sheet from either surface. Signed-in users can post up to 500 characters, retry failed sends with the same comment ID, and delete their own comments; post owners can also remove comments on their posts. The panel streams the latest 100 comments and hides blocked authors. Videos pause while commenting or sharing. Sharing opens the native chooser with the dare and media URL.

Videos start muted on each app launch. The mute button changes a session-wide preference shared by subsequent videos and profile/full-screen viewers. The feed's filter button selects a mood with a server-side query; new posts retain mood ID/name through capture and review. Older posts without this metadata remain under All moods. Back refreshes the current filter and returns to the first card; a second Back within two seconds exits. Opening a sheet or interacting with the feed cancels the exit countdown.


## Mood collections

Discover has a searchable mood grid with All, Free, Daring, Epic and Seasonal filters. Daring and Epic are locked premium previews. Tapping a premium mood shows **Coming soon**, including for legacy premium documents marked unlocked. Subscriptions, checkout and paid access are not implemented. Free moods still open the selected-dare screen and camera.

Christmas and New Year start the Seasonal collection with three free themed dares each. These are available year-round for now; there is no automatic holiday calendar. A mood's optional `season` metadata is separate from its tier, so future holidays can have free or premium moods. The optional Firestore `tier` field accepts `basic`/`free`, `daring`, or `epic`; older `gold`/`diamond` aliases and legacy `pack` values remain supported. Remote entries take precedence over local defaults by ID or normalized name. Empty, failed or timed-out catalogs keep local free moods available; Retry refreshes without clearing search or the selected collection. This does not write or seed Firestore.

The grid keeps two columns on regular and narrow phones, including at enlarged text sizes; wider layouts can show more. Cards and filter pills use filled surfaces without outline strokes. Inputs use a different fill when focused.

The app requests portrait-up before its first Flutter frame, and Android/iOS launch configuration also allows portrait only. iPad full-screen mode is enabled for orientation locking. The OS may still override orientation on large displays or multi-window configurations; responsive layout checks remain necessary, especially when upgrading the Android target SDK. iOS device behavior has not been validated.

Premium previews are presentation only, not a paid-content security boundary. See [release gates](docs/RELEASE.md) before adding subscriptions or publishing paid dares.

## Camera and photo studio

Choose Discover → mood → Open camera. The selected mood has its own color treatment and a focused dare card; tap the shuffle icon for another dare. Long dares scroll while the camera action stays visible. Android opens directly into the live-lens camera with floating controls. Framing starts at **9:16**; tap the ratio button beneath camera flip to choose **3:4** or **Full** (the screen shape). Tap the shutter for a photo. After capture, the review screen gives the photo most of the space. Tap the sliders button to open Adjust, swipe the circular icon wheel (or tap a neighboring icon) to choose Smooth, Light or Warmth, and use the slider below it. The wheel wraps in both directions, shows the selected effect name above it, and preserves each adjustment when switching. Controls float over a shaded lower part of the photo; opening them never changes the photo framing or rounded corners. Effect icons have no tap splash. Reset is inside Adjust; Compare appears after an edit. Save and Share are in the top-right menu, and Post dare is the primary action. Smoothing starts at zero. The strongest usable front-facing face is processed; eyes, mouth and nose are protected with a feathered mask. If no suitable face is found, smoothing is disabled and color adjustments remain available.

The implementation combines **free on-device ML Kit face detection on Android** with our own edge-preserving pixel processing in a Dart isolate. ML Kit is a Google SDK, not an open-source beauty engine. No camera frames are uploaded for processing. Photos are normalized upright and limited to a 1600-pixel longest edge to bound memory and processing cost. Save, share and post use the same edited JPEG.

For photos, the lightning button toggles flash (off by default). Selfies use a brief bright screen; the rear camera briefly uses its LED light when available. Exposure gets a short settling period before capture. Brightness and the light are restored after capture, on interruption, and by a native timeout. Photo flash does not apply to video.

On Android, swipe the lens wheel around the shutter: Original, Soft, Glow, Wide eyes, Sculpt, and Studio (a combined look). The wheel wraps in both directions. Select a beauty lens and tap **Adjust lens** (the sliders icon) to reveal strength and original-comparison controls. Tap the compact dare at the top to read it in full. Eye enlargement, lower-face slimming, smoothing and color adjustments run continuously. Original is selected initially. Face effects pause when no suitable face is tracked; global color adjustments remain active.

Live photos are captured from the same GPU-rendered frame as the preview, including selfie mirroring, then enter the existing save/share/post studio. The live look is baked into the capture: the studio's **Captured** comparison restores that capture, not the pre-lens camera frame. The viewfinder sits in the vertical and horizontal center of the screen. The preview uses a centered crop at the selected ratio; saved photos use that same framing. Dark space outside the viewfinder is not included in the capture. The 3:4 option preserves the full view of a 3:4 camera stream, while taller ratios crop the sides. Capture uses pixels from the preview stream (960 × 1280 before cropping on the tested emulator), not the full sensor resolution. This first live implementation is designed for portrait use.

The live engine uses native CameraX upright RGBA frames, bundled ML Kit landmarks and OpenGL ES shaders. It drops old frames instead of building a processing backlog, checks for stale tracking, and keeps all frame pixels on Android; Flutter receives a texture and small status updates. It does not require a paid SDK or cloud face processing. The approximately 29.5 fps measured on the emulator is not a physical-device performance guarantee; test latency and thermal behavior on actual phones.

**Hold the shutter** to record with lens effects and microphone audio; **release** to finish. While holding, **slide up to the lock** to keep recording hands-free, then **tap the shutter** to stop. The native 30-second limit still applies. Lenses are chosen before recording, and extra controls hide during capture. Screen-reader users can invoke the shutter’s “Record hands-free video” action. A first-time permission dialog cancels the hold; hold again after granting microphone access. The MP4 contains the same GPU effects and selfie mirroring as the preview and uses the existing playback/save/share/post flow. Recording stops when the app loses focus; returning to the camera opens the completed clip for review while the app process remains alive. An interrupted clip that is too short to encode may be discarded.

Live video targets H.264 at 4 Mbps with mono AAC audio at 96 kbps. Dimensions follow the selected preview ratio, capped at a 720-pixel short edge and 1280-pixel long edge. Choose framing before recording; the ratio is fixed during a clip. The encoder targets 30 fps; actual frame delivery depends on the phone. Native duration/file limits bound recordings. Select Original in the lens wheel for unfiltered capture. iOS retains the standard camera with its existing photo/video modes.

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

The Android integration tests use a public-domain U.S. Navy portrait of Grace Hopper (James S. Davis; TensorFlow test crop). They cover detection, GPU pixel effects, no-face bypass, orientation/mirroring, export, editor UI, continuous frames, camera switching, capture/retake and rapid background/resume without posting to Firebase. Widget tests cover tap/hold/lock, pointer cancellation, release during recorder startup and switching between 9:16, 3:4 and Full on narrow/foldable layouts with enlarged text. Photo review tests cover opening/closing adjustments, rendered edits, comparison, reset and the export menu. Video tests check playback controls and encoded effects against a GPU still, H.264/AAC tracks and duration, playback, the 30-second limit and interrupted-clip recovery. Run these on a test emulator: Flutter's integration runner may uninstall the app afterward. Allow camera and microphone access when Android prompts. The test fixture is not part of the normal app bundle, and native fixture/track-inspection entry points are disabled in release builds.

The mood regression suite covers legacy tier parsing, malformed catalog data, duplicate handling, source timeouts, offline fallback/retry, collection/search combinations, locked previews, direct premium-route guards and narrow/foldable layouts with enlarged text. The Android mood integration test follows an offline catalog through a premium preview, seasonal dare, live capture, floating photo controls and return navigation. It never posts or modifies Firebase. Unit/widget tests run in the existing GitHub workflow on pushes and pull requests; native integration tests currently run locally on a disposable Android emulator.

Moments widget tests cover branding, photo fit, single/double taps, caption/action handling, vertical swiping, hiding, three video shapes, playback handoff, interruption, disposal, comments and retry/delete permissions, native share calls, mood filters, double-Back timing, shared mute state, keyboard insets and large-text layouts. A dedicated Android test records a real clip, decodes a local photo fixture and follows both through feed/detail navigation. Its repository and photo response are test fixtures; video playback uses the native player with a local file. It does not post to Firebase or exercise live Storage streaming.

## Structure

- `lib/features/camera`: photo processing, lens presets, live camera UI and platform-channel adapters.
- `lib/features/feed`: capture, preview, posting, playback, comments, mood filters, likes, blocking and reports.
- `lib/features/auth`, `user`, `profile`: account flow and profile management.
- `lib/features/dares`: discovery and local starter dares if the remote catalog is empty or unavailable.
- `android/.../BeautyPlugin.kt`: bundled native face detector.
- `android/.../LiveBeautyPlugin.kt`, `LiveBeautyRenderer.kt` and `LiveBeautyRecorder.kt`: native live camera, landmark tracking, GPU lens rendering/capture and MP4 recording with audio.
- `firestore.rules`, `storage.rules`, `firestore.indexes.json`: full target policy and indexes. `firestore.compat.rules` / `firebase.compat.json` contain the current, explicitly deployed post/comment rollout; profile migration is still required before using the full policy. See `docs/RELEASE.md`.
- `docs/RELEASE.md`: required migration and release work.

Feed queries are bounded to 60 posts. Profile grids show the latest 60. The feed hides moments after 24 hours; the profile retains them until deleted. No fake followers, premium checkout or notification controls are shown.

## Build cache troubleshooting

Do not sync `build/`, `.dart_tool/`, or `android/.gradle/` through a cloud drive. This checkout contained old duplicate generated files (`… 2.json`, `… 3.class`) that caused D8 errors and stalled Gradle reads. Prefer a local development directory outside a synced Desktop folder.

For this Mac, the generated `build` folder was relocated to a temporary local cache and replaced with an ignored symlink. It is not committed. Temporary caches may be removed by macOS; if the target no longer exists, recreate it or remove the symlink and run `flutter clean` / `flutter pub get`. A fresh Git clone uses a normal build directory.

## Release status

This is a tested Android development build, not a store-ready release. Read [the release checklist](docs/RELEASE.md) before publishing, especially database migration, deployment, signing, moderation and device testing.
