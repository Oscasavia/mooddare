# Release checklist and audit

## Implemented

- Android on-device face detection with custom, face-masked photo smoothing; light/warmth controls; original comparison; shared JPEG export path for gallery/share/feed.
- Android live photo/video lens carousel: Original, Soft, Glow, Wide eyes, Sculpt and Studio, with strength/compare controls. Native CameraX/ML Kit/OpenGL pipeline applies smoothing, color, eye enlargement and face slimming to preview, photos and recorded MP4 video with microphone audio.
- Android opens directly into a camera with floating controls and a repeating lens wheel. The viewfinder is centered vertically and horizontally. Default 9:16 framing can be changed to 3:4 or Full; the viewfinder and saved photo/video share the chosen ratio. Tap for a photo, hold/release for video, slide up to lock, tap to stop. Strength/comparison controls appear on demand. Camera startup error/retry states, front camera default, lifecycle cleanup and the native 30-second limit remain.
- Capture review emphasizes the media and Post action. Photo adjustments float inside the photo’s rounded frame without resizing it, with a repeating icon wheel, selected-effect label, one slider at a time, reset and comparison. Effect icons and the adjustment toggle have no tap splash; Save/Share live in an overflow menu. Video review has accessible play/pause and scrubbing.
- Android live photo flash: manual off/on, white screen and temporary window brightness for selfies, brief CameraX torch illumination for rear cameras with an LED. Capture waits for exposure and new frames. Native timeout, pause/close and Dart cleanup restore lighting; video is unaffected.
- Selected-mood screen uses a mood-colored background, emoji badge and focused dare card, with a compact shuffle action and a fixed Open camera button. Long dares and enlarged text scroll without hiding the main action; duplicate camera launches are guarded.
- Material 3 dark theme, responsive auth/discovery/editor screens, real profile counts and milestones; removed fake social stats, subscriptions, notification switches and unused seed tools.
- Actual sign-out, Firebase auth errors, guest-to-account linking on signup, username reservations, avatar selection/cropping/upload and profile bio.
- Bounded feed queries, cached author/thumbnail futures, video pause on navigation/backgrounding, like transactions, post deletion confirmation, reporting and blocked accounts.
- Explicit post authorization, consistent media metadata, stable IDs for retrying posts, release Internet permission and no debug signing fallback for release.
- Local Firestore/Storage access-rule tests, image-processing tests, widget tests, Android integration test and GitHub CI configuration.

## Must happen before backend rule deployment

The live Firebase policy has not been inspected or changed. The new policy and username collection must be rolled out with the client.

1. Export/back up existing Firestore data. Audit current rules and enabled Auth/Storage services.
2. Migrate public `users/{uid}` documents: remove `email` and any other private fields (Firebase Auth remains the email source); populate `id`, `createdAt`, and lowercase `username_lower`; keep only fields allowed by `validProfile`. Resolve usernames that do not match the new 3–20 letters/numbers/underscore format.
3. Check ALL usernames case-insensitively for collisions, including legacy profiles without helper fields. Create matching `usernames/{lowercase}` documents with `{uid}` using trusted admin tooling. Resolve collisions manually before opening signups. Client compatibility queries are not a replacement for this migration.
4. Test a migrated staging copy, including old posts/avatar paths, signup, guest linking, profile rename, likes, block/unblock, account deletion and failed uploads.
5. Deploy reviewed Firestore rules, Storage rules and indexes to the intended project. There is no automatic production deployment in CI. Existing rules may deny new username/report/block operations until rollout.

Do not deploy the policy onto unmigrated profiles: old public email fields will otherwise remain readable, and profile updates may be rejected.

## Store and backend release gates

- Choose and register production Android/iOS bundle IDs. Android still uses `com.example.mooddare` to preserve the existing Firebase configuration. Replace Firebase config files together with any identifier changes.
- Supply `android/key.properties` and a private release keystore; both are ignored. Release no longer falls back to the debug key. Configure iOS signing and confirm the current Play/App Store SDK requirements before submission; this project has not been migrated to the newest Flutter/toolchain.
- Publish real privacy/terms/support information and complete store data disclosures. The in-app data explanation is not a full privacy policy.
- Arrange a moderation workflow for `reports` and an appropriate user-content policy. Blocking currently hides that author's feed posts for the blocking user; it is not a server-enforced access ban.
- Firebase media download URLs are bearer links: recipients can access shared files until those files/tokens are revoked. The 24-hour feed timer does not delete files or revoke URLs.
- Add trusted server cleanup for interrupted account deletions and orphaned uploads. Current account deletion cleans up from the client and keeps Auth until last, but is not atomic across Firebase services. Reauthenticate before deleting a non-guest account. Users should keep the app open and retry after an interruption. Server-side cleanup is needed for a reliable production deletion SLA.
- Add server-enforced abuse controls / App Check as appropriate. Current rules enforce ownership and field constraints, not posting-rate limits. Stats aggregate the user's posts client-side; move aggregates server-side and add pagination beyond 60 posts as usage grows. Likes still use a bounded array, not a scalable per-like collection.
- Measure Firebase usage and set budget alerts; the camera itself has no paid inference service, but Firebase Storage/Firestore/hosting remain separate services.

## Device acceptance testing

Local verification completed: Flutter analysis with no issues, 28 unit/widget tests, 9 Firebase emulator access-rule tests, and 6 Android emulator integration tests. The live tests cover real GPU pixel changes for eyes/jaw/smoothing, unmodified background, original bypass, no-face bypass, RGBA color order, upright/mirrored exports, matching centered photo/video crops, continuing frames, capture/retake, camera switching and rapid background/resume. Gesture/layout tests cover tap-versus-swipe, hold/release, slide-to-lock, slow recorder startup, cancellation, automatic-stop reset, ratio switching with matching viewfinder/export settings and enlarged text on narrow/foldable layouts. Video tests verify baked effects against the GPU still, H.264/AAC tracks with matching durations, playback, the 30-second cutoff, repeated recording and interrupted-clip recovery. The rules tests passed in the previous backend work; live-lens changes do not modify backend policy. These checks do not exercise store signing. The user separately confirmed physical-phone live photo lenses and, on the preceding build, posting, photo edits, video playback and audio. The user also confirmed filtered video on the physical phone before the camera UI redesign. The user confirmed the gesture/layout redesign on the physical phone. The user confirmed the centered camera, review redesign and icon wheel on the physical phone. The user confirmed the floating photo controls. The selected-mood redesign and flash still need physical-phone acceptance, including dark-room exposure, rear LED behavior, and restoring screen brightness after interruptions. The emulator verifies front-screen flash capture and cleanup but cannot establish real LED illumination quality.

Live camera measured about 29.5 fps at 960 × 1280 on the emulator. Physical-phone FPS, tracking latency, power consumption and thermal throttling remain acceptance checks. CameraX RGBA conversion/copy and downscaled face detection use CPU; the image effects run on the GPU. Frame queues are bounded. This is a portrait, single-face implementation with geometric landmarks, not a full face mesh or semantic skin segmentation. Test large head turns, lost/reacquired faces, overlapping faces, glasses, facial hair and movement. Live photos use the selected centered crop from the preview stream and preserve mirrored selfie appearance; test folded/unfolded layouts and orientation before extending landscape support. Live lens effects are baked into captured photos, so the later editor cannot recover a pre-lens original.

Automated Android tests prove integration, not aesthetic quality across users. Validate smoothing with consenting test users across skin tones, lighting, glasses, facial hair and movement before marketing it as a beauty feature. Face detection is limited to the largest front-facing face with usable landmarks; rotated/profile faces are skipped. The geometric mask is not a semantic skin segmentation model.

Check: capture/retake, camera flipping, permission denial/regrant, background/resume while recording, no-face handling, all slider combinations, processed gallery/share/upload equality, offline/retry, long text, large text sizes and screen readers. Record 30 seconds and verify audio/video sync. Test a low-end and a recent physical Android phone.

Live video uses the GPU output surface with MediaRecorder H.264/AAC encoding, capped at 720 pixels on the short edge and 1280 on the long edge, targeting 4 Mbps video and 96 kbps mono audio. Native limits stop at 30 seconds or 28 MiB. The app finalizes recordings when it loses focus and reviews interrupted clips on resume while the process survives; force-kill/crash recovery is not implemented. Phone acceptance must include audible speech/lip sync, incoming interruptions, microphone denial/regrant, tap/hold/release and slide-to-lock on real touch hardware, long-clip playback and uploading the filtered clip. Emulator track-duration checks do not prove physical-device lip sync.

No iOS build/device validation has been completed. Native iOS face detection and live beauty video processing are not implemented. Before iOS release, configure/test all permissions, Google sign-in, gallery sharing, account deletion and build/signing; verify minimum OS versions with the installed plugins.

## Source backup

A snapshot of the original source/configuration was saved locally at `/private/tmp/mooddare-before-refresh.tar.gz` before editing. It is not a durable backup or part of GitHub. The repository remote is `https://github.com/Oscasavia/mooddare.git`.
