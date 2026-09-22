# MoodDare

A Flutter app for mood-based challenges, a photo beauty studio, and shared moments.

## Marketing website

The standalone landing page lives in [`website/`](website/README.md). Preview it
with `npm --prefix website start` and open http://127.0.0.1:4173. It includes real
app screenshots, an interactive mood sampler, FAQs, policy pages and the 22-second
MoodDare promo with narration and English captions. Desktop uses the landscape cut;
phones use the vertical cut. Store downloads remain placeholders until final HTTPS
URLs are set in `website/config.js`.
Run `npm --prefix website test` for the Chrome browser checks (Node 22+). The
separate `firebase.landing.json` prepares Hosting; nothing is deployed automatically.

## Run locally

Tested with Flutter 3.32.8 / Dart 3.8.1 and Java 17. Android's face detector is bundled in the app; it needs no API key or beauty SDK subscription.

```sh
flutter config --jdk-dir="/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home"
flutter pub get
flutter run
```

Use your own Java 17 path on other machines. Flutter may otherwise choose Android Studio's incompatible Java 25 runtime. Firebase client configuration is already present for the existing MoodDare project. Enable the desired sign-in providers and configure Android SHA fingerprints in Firebase for Google sign-in. Firebase services may have their own billing requirements; free photo processing does not change Firebase's pricing.

If the debugger connection hangs on the splash screen on this Mac, the verified fallback is `flutter run -d sdk --no-hot --no-resident`. It installs and opens the app without a hot-reload session. The standalone debug APK also launches normally.

## Welcome and account screens

Welcome shows Mood Wink, a centered Get started button with a subtle right arrow, a Sign in link, and local Terms of Use / Privacy Policy links. A device-local preference shows Welcome on the first entry, then routes returning signed-out users directly to Login—even after closing and reopening the app. Signed-in members still restore their session and mark the installation as returning. Login and Signup have no top-left back button; account-switch links, policy-page Back and system Back navigation remain available.

Successful account deletion resets the entry preference and opens Welcome. Cancelling, failing or merely verifying deletion does not reset it. Welcome remains stable while opening policies or resuming the current session; the next cold start goes to Login. Preference failures do not sign users out or report an already deleted account as a failed deletion. Android stores the flag in private preferences (excluded by the existing backup rules); iOS uses UserDefaults. No credentials or account identifiers are stored in this flag.

Guest access is retired: the auth gate clears persisted anonymous sessions before selecting the entry screen, with a retry screen if sign-out fails. Registered accounts keep their sessions. The Google buttons use the unmodified multicolor logo from [Google’s official branding assets](https://developers.google.com/identity/branding-guidelines) on a white button. Tests cover first entry, cold restarts, resumed screens, existing-member migration, sign-out, deletion retry/cancellation and policy navigation. Run the native preference test on a **test emulator**, not a personal phone: `flutter test integration_test/welcome_history_test.dart -d emulator-5554`.

Edit profile saves from the top-right toolbar. Save stays disabled while loading, choosing a photo or saving; failed/missing profile loads show Retry instead of a blank editable form. Validation, upload behavior and success navigation are preserved.

Profile details subscribe to saved changes, so the display name, username, bio and photo update without restarting or reopening the page. New avatar uploads use unique object URLs to avoid reusing a cached photo; the bottom navigation follows the same live profile document. Older avatar objects remain until account cleanup.

## Social profiles and video edits

Profiles show Moments, Followers and Following, with searchable people lists, follow/unfollow, blocking and an expandable profile picture. Reply threads expand under comments; replies support editing, likes and deletion. Each thread initially shows five replies, with more available on demand. Posts display their saved mood and offer Download in the overflow menu. The shared paper-plane icon points northeast, and tapping outside a text field dismisses focus on mobile.

In **Your moment**, Edit video opens floating **Trim & sound** controls. Start/end handles choose a clip; muting removes the audio track from the exported MP4. Posting, saving and sharing all use that same edited file, so a subsequent download preserves the trim and silence. Android uses Media3 Transformer 1.5.1, matching the player's Media3 version; iOS uses AVFoundation. Trimming does not use MP4 edit lists to hide excluded footage. Original captures remain unchanged for Reset.

GitHub Actions runs Flutter tests with coverage and enforces a 75% executable Dart line minimum using `python3 tooling/check_coverage.py`. Native export and camera behavior have separate Android integration tests; Firestore permissions have emulator tests for both rule sets.

## Settings

Settings groups account details, privacy/preferences, help and app information into borderless cards. Sign out and Delete account are the final two rows and both require confirmation; pending operations prevent repeated requests and Back navigation. Google provider cleanup failures no longer report a failed sign-out after the Firebase session has already ended.

Email/password accounts can change their password after reauthenticating with the current password, or explicitly request a reset email. Google accounts open Google account security instead. Guest accounts receive sign-in guidance. This follows [Firebase’s user-management flow](https://firebase.google.com/docs/auth/flutter/manage-users).

Help & FAQ explains capture, lenses, moments, comments, premium previews and privacy. Contact us prepares an email to `oscasavia@gmail.com` with a topic, the user's message and app version; it never sends automatically. A copyable draft is available if no email app can open. Share MoodDare opens the native share chooser and labels `https://mooddare.example` as a preview link with downloads coming soon. Replace these defaults at build time with `--dart-define=SUPPORT_EMAIL=...` and `--dart-define=APP_SHARE_URL=https://...` when public launch details are ready.

Notifications opens the app's OS settings. Push delivery, tokens, channels, server triggers and per-category preferences are not implemented; the screen explicitly states that alerts are coming later. About & licenses reads version/build from the installed application. Android and iOS platform handoffs use the small `mooddare/settings` channel.

## Moments

The Moments header uses **mooddare** branding. Photos and videos fill their rounded feed cards with a centered crop, preserving proportions. A single tap on the media or caption opens the same full-screen viewer used by profile dares; that viewer contains the full image/video without the feed crop. Tap a video in the viewer to pause or resume. Double-tapping media still likes the post, and action buttons and vertical feed swipes retain their own behavior.

The feed video pauses before its viewer opens, the outgoing viewer pauses as it closes, and the active feed video resumes on return. Manually paused viewer videos stay paused after interruptions. Hiding a moment from the viewer closes it and removes the card from the current feed session.

Comments open in a keyboard-aware bottom sheet from either surface. Signed-in users can post up to 500 characters, retry failed sends with the same comment ID, and delete their own comments; post owners can also remove comments on their posts. Authors can edit comments in place; edits retain likes and show an Edited label. Signed-in users can like/unlike individual comments. The panel streams the latest 100 comments and hides blocked authors. Comment avatars and usernames open profiles without losing the composer draft. The comment heart and count share one line below full-width text; menus sit at the far right of the author row. Dismiss the panel by dragging down or pressing Back. Videos pause while commenting, viewing likes or sharing. Sharing opens the native chooser with the dare and media URL.

The full-screen Back, mute and menu controls share one safe-area toolbar. Mute is a floating icon in both views. Avatar and username sit close together and both open the author’s profile. Long-press the post heart to see a fresh list of people who liked it. Profiles load as the list scrolls; blocked accounts are hidden and missing profiles are unavailable. Each available avatar and username opens that profile. Heart, comment and paper-plane share icons use the same size/color; filled hearts indicate liked items. Like/comment totals use lowercase compact notation (`1k`, `1.2k`, `10k`, `1m`), with full counts exposed to accessibility. Comment totals use an aggregate query over all comments, refreshed on open, after closing comments/returning from a viewer, and each minute while the card is active.

Videos start muted on each app launch. The mute button changes a session-wide preference shared by subsequent videos and profile/full-screen viewers. The feed's filter button opens a searchable mood list. Search matches mood names case-insensitively, trims whitespace, offers clear/empty states, and keeps All moods available. Typing only filters the choices locally; selecting a mood queries the feed server-side; new posts retain mood ID/name through capture and review. Older posts without this metadata remain under All moods. Back refreshes the current filter and returns to the first card; the next Back exits, even after waiting. Opening a sheet or completing a touch interaction with the feed resets this sequence. Android edge-back gestures do not reset it when the system cancels the app pointer.


## Mood collections

Discover has a searchable mood grid with All, Free, Daring, Epic and Seasonal filters. Daring and Epic are locked premium previews. Tapping a premium mood shows **Coming soon**, including for legacy premium documents marked unlocked. Subscriptions, checkout and paid access are not implemented. Free moods still open the selected-dare screen and camera.

Christmas and New Year start the Seasonal collection with three free themed dares each. These are available year-round for now; there is no automatic holiday calendar. A mood's optional `season` metadata is separate from its tier, so future holidays can have free or premium moods. The optional Firestore `tier` field accepts `basic`/`free`, `daring`, or `epic`; older `gold`/`diamond` aliases and legacy `pack` values remain supported. Remote entries take precedence over local defaults by ID or normalized name. Empty, failed or timed-out catalogs keep local free moods available; Retry refreshes without clearing search or the selected collection. This does not write or seed Firestore.

The grid keeps two columns on regular and narrow phones, including at enlarged text sizes; wider layouts can show more. Cards and filter pills use filled surfaces without outline strokes. Inputs use a different fill when focused.

The app requests portrait-up before its first Flutter frame, and Android/iOS launch configuration also allows portrait only. iPad full-screen mode is enabled for orientation locking. The OS may still override orientation on large displays or multi-window configurations; responsive layout checks remain necessary, especially when upgrading the Android target SDK. iOS device behavior has not been validated.

Premium previews are presentation only, not a paid-content security boundary. See [release gates](docs/RELEASE.md) before adding subscriptions or publishing paid dares.

## Camera and photo studio

On **Make it yours**, Crop photo opens an on-device crop editor with Free,
Original, Square, 3:4 and 9:16 framing. Drag the corners to resize or drag inside
to reposition. Done applies the selection; Back cancels. Reset crop restores the
entire capture without removing beauty adjustments. Reopening always uses the
full adjusted capture, avoiding cumulative cropping and JPEG recompression.
Cropping happens after beauty processing, so face masks and baked live lenses
stay aligned. Compare keeps the chosen crop; Save, Share and Post all export the
same cropped result. Run `flutter test test/photo_cropping_test.dart` and the
device check `flutter test integration_test/photo_crop_test.dart -d emulator-5554`.

Choose Discover → mood → Open camera. The selected mood has its own color treatment and a focused dare card; tap the shuffle icon for another dare. Long dares scroll while the camera action stays visible. Android opens directly into the live-lens camera with floating controls. Framing starts at **9:16**; tap the ratio button beneath camera flip to choose **3:4** or **Full** (the screen shape). Tap the shutter for a photo. After capture, the review screen gives the photo most of the space. Tap the sliders button to open Adjust, swipe the circular icon wheel (or tap a neighboring icon) to choose Smooth, Light or Warmth, and use the slider below it. The wheel wraps in both directions, shows the selected effect name above it, and preserves each adjustment when switching. Controls float over a shaded lower part of the photo; opening them never changes the photo framing or rounded corners. Effect icons have no tap splash. Reset is inside Adjust; Compare appears after an edit. Save and Share are in the top-right menu, and Post dare is the primary action. Smoothing starts at zero. The strongest usable front-facing face is processed; eyes, mouth and nose are protected with a feathered mask. If no suitable face is found, smoothing is disabled and color adjustments remain available.

The implementation combines **free on-device ML Kit face detection on Android** with our own edge-preserving pixel processing in a Dart isolate. ML Kit is a Google SDK, not an open-source beauty engine. No camera frames are uploaded for processing. Photos are normalized upright and limited to a 2048-pixel longest edge to bound memory and processing cost. Save, share and post use the same edited JPEG.

For photos, the lightning button toggles flash (off by default). Selfies use a brief bright screen; the rear camera briefly uses its LED light when available. Exposure gets a short settling period before capture. Brightness and the light are restored after capture, on interruption, and by a native timeout. Photo flash does not apply to video.

On Android, swipe the lens wheel around the shutter: Original, Soft, Glow, Wide eyes, Sculpt, Studio (a combined look), **Rosy** (lip tint and soft blush), and **My look**. The wheel wraps in both directions. Select a preset and tap **Adjust lens** (the sliders icon) to reveal strength and original-comparison controls. My look opens its adjustments automatically: choose Smooth, Eyes or Face and use the single slider to set each amount independently. Compare temporarily shows the original; Reset clears all three custom amounts. Custom amounts start at zero and remain available through preset switches, camera flips, capture/retake and recording during that camera session. They are not saved after leaving the camera. Controls float over the same viewfinder without changing framing and hide during recording. Photo and video both receive the chosen amounts.

Tap the compact dare at the top to read it in full. Eye enlargement, lower-face slimming, smoothing and color adjustments run continuously. Original is selected initially. Face effects pause when no suitable face is tracked; global color adjustments remain active.

Live tracking keeps the selected person while their tracking ID remains visible, even if another face becomes larger. Adaptive landmark filtering reduces small jitters while following larger movements more quickly; short interpolation spreads coordinate updates across preview frames. Effects fade in on acquisition and reduce toward the existing head-angle limits. Known face loss/missing landmarks disable them immediately; old detections fade out and expire after 260 ms. Smoothing retains some original texture and protects the eye/brow area, while eye enlargement and jaw slimming have gentler maximum displacement. Eye and jaw reshaping still use the stabilized geometric landmarks and existing frontal-pose limits.

Smoothing and makeup now use contours from a bundled [ML Kit face mesh model](https://developers.google.com/ml-kit/vision/face-mesh-detection/android). Mesh results are matched to the tracked face and stabilized alongside its landmarks. The contour mask excludes eyes, brows and lips from smoothing. Rosy adds a luminance-preserving rose lip tint and feathered cheek blush; the inner mouth is excluded to protect teeth. Strength adjusts the whole look, and Compare shows the original. Makeup pauses if a matching mesh is unavailable; smoothing falls back to its existing conservative mask. A short camera hint appears when Rosy needs a usable frontal face. Mesh inference runs for smoothing, makeup and face shaping; Original and color-only looks skip it. Preview, saved photos and videos use the same shader; photos re-detect their own mesh. Still detection tries the live analysis size, a padded crop of the face in the same exposure, then the original still if necessary. These bounded retries preserve the full-resolution output and never reuse preview coordinates. Eyes and Face now derive their guides from the same stabilized mesh: eye contours set the enlargement area and reduce strength on closed lids, while separate contour samples guide each side of the lower face. The guides rotate with the eye line and account for image aspect ratio before mirroring. Shaping pauses when the mesh is unavailable, and its hint clears when tracking recovers. Existing frontal-pose limits remain. This is contour-based rendering, not semantic skin segmentation or a 3D AR mask system. The bundled mesh SDK is currently beta and pinned to a specific version; processing stays on-device.

Live photos use a dedicated CameraX still exposure, bounded to a 2048-pixel longest edge, then apply the same GPU lens shader. The preview and still share a sensor viewport so framing and selfie mirroring match. Face landmarks are detected again on the captured exposure instead of reusing coordinates from an earlier preview frame. Actual resolution depends on the camera; devices unable to bind both camera streams fall back to preview capture. The studio retains the larger photo through editing, save, share and post.

The live look is baked into the capture: the studio's **Captured** comparison restores that capture, not the pre-lens camera frame. The viewfinder sits in the vertical and horizontal center of the screen. Saved photos use the selected centered crop; dark space outside the viewfinder is not included. The 3:4 option preserves the full view of the portrait sensor viewport, while taller ratios crop the sides. This live implementation is designed for portrait use.

The live engine uses native CameraX upright RGBA frames, bundled ML Kit landmarks and OpenGL ES shaders. It drops old frames instead of building a processing backlog, checks for stale tracking, and keeps all frame pixels on Android; Flutter receives a texture and small status updates. It does not require a paid SDK or cloud face processing. The approximately 29.5 fps measured on the emulator is not a physical-device performance guarantee; test latency and thermal behavior on actual phones.

**Hold the shutter** to record with lens effects and microphone audio; **release** to finish. While holding, **slide up to the lock** to keep recording hands-free, then **tap the shutter** to stop. The native 30-second limit still applies. Lenses are chosen before recording, and extra controls hide during capture. Screen-reader users can invoke the shutter’s “Record hands-free video” action. A first-time permission dialog cancels the hold; hold again after granting microphone access. The MP4 contains the same GPU effects and selfie mirroring as the preview and uses the existing playback/save/share/post flow. Recording stops when the app loses focus; returning to the camera opens the completed clip for review while the app process remains alive. An interrupted clip that is too short to encode may be discarded.

**Pinch the camera preview with two fingers** to zoom in or out before a photo or during video recording, including a held or locked recording. Zoom is applied by the camera, so saved photos and videos use the zoomed view; lens tracking continues on the resulting frames. A small zoom readout appears while pinching and fades afterward. Each front/rear camera supplies its own zoom limits (including zoom-out below 1× where supported); switching/reopening the camera resets zoom. Lens-wheel swipes, sliders and shutter gestures remain separate. The fallback camera supports the same pinch gesture. Run `flutter test integration_test/camera_zoom_test.dart -d emulator-5554` on a test emulator to verify saved-photo pixels, recorded video, fallback capture, bounds and stale-session rejection.

Live video targets H.264 at 4 Mbps with mono AAC audio at 96 kbps. Dimensions follow the selected preview ratio, capped at a 720-pixel short edge and 1280-pixel long edge. Choose framing before recording; the ratio is fixed during a clip. The encoder targets 30 fps; actual frame delivery depends on the phone. Native duration/file limits bound recordings. Select Original in the lens wheel for unfiltered capture. iOS retains the standard camera with its existing photo/video modes.

iOS currently supports photo color adjustments and normal capture; face smoothing and live lenses need native iOS implementation and validation. Android includes the first contour-based makeup look. Additional makeup styles, 3D AR masks/stickers and corresponding iOS support remain future work.

## Verification

```sh
flutter analyze
flutter test
flutter test integration_test -d <android-emulator-id>
flutter build apk --debug --target-platform android-arm64
cd android && ./gradlew :app:testDebugUnitTest -Ptarget-platform=android-arm64 && cd ..
npm ci --ignore-scripts --prefix tooling/rules-tests
firebase emulators:exec --project demo-mooddare --only firestore,storage 'npm --prefix tooling/rules-tests test'
```

The Android integration tests use a public-domain U.S. Navy portrait of Grace Hopper (James S. Davis; TensorFlow test crop). A generated fine-detail fixture also checks that larger stills retain source detail beyond an enlarged preview, preserve both crop ratios and selfie mirroring, and leave the preview texture intact. Front/rear sensor tests cover still capture and cancellation recovery. The portrait tests cover detection, GPU pixel effects, no-face bypass, orientation/mirroring, export, editor UI, continuous frames, camera switching, capture/retake and rapid background/resume without posting to Firebase. Widget tests cover tap/hold/lock, pointer cancellation, release during recorder startup and switching between 9:16, 3:4 and Full on narrow/foldable layouts with enlarged text. Photo review tests cover opening/closing adjustments, rendered edits, comparison, reset and the export menu. Video tests check playback controls and encoded effects against a GPU still, H.264/AAC tracks and duration, playback, the 30-second limit and interrupted-clip recovery. Run these on a test emulator: Flutter's integration runner may uninstall the app afterward. Allow camera and microphone access when Android prompts. The test fixture is not part of the normal app bundle, and native fixture/track-inspection entry points are disabled in release builds.

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
