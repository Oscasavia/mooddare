# Beauty camera motion and performance checks

This is a hands-on acceptance checklist, not a claim that every device or face has passed. Android's live beauty pipeline is the scope. Automated fixtures protect rendering and capture behavior; they cannot establish aesthetic quality across people, lighting, glasses or sustained device heat.

## Repeatable phone session

Use the ordinary app build, installed in place. Never run Flutter integration tests on a personal phone: the runner may uninstall the app. Keep test photos/clips local and discard them after review; posting is unnecessary.

1. Preview Original for 15 seconds. Select Golden Hour at the default strength and preview for 30 seconds.
2. Blink, smile, speak, open/close the mouth, and gently turn/tilt the head. Check that lips follow the mouth without tinting teeth, eyes do not stretch while blinking, and the face edge does not trail. Strong turns intentionally fade effects out; returning should reacquire smoothly.
3. Repeat with Wide eyes, Sculpt, and My look (one control at a time). Briefly leave the frame, cover part of the face, then return. Effects must disappear on loss and must not jump to a bystander while the tracked face remains visible.
4. Take a photo while smiling, then record a locked 30-second clip while talking. Review lip color, shape, audio sync, orientation and framing. Compare to preview. Retake, switch cameras, try flash and pinch zoom, and background/resume.
5. Repeat several clips over a five-minute session. Note stutter, unusual warmth, audio drift and whether the end of the session is worse than the beginning. A brief debug session is not a battery benchmark.
6. Repeat under daylight, warm indoor light and dim light, with/without glasses where applicable, and with volunteers covering a range of skin tones. Include a second physical Android phone with less powerful hardware. Record what was actually tested and leave unavailable combinations pending.

## Debug timing summaries

Debug builds emit `MoodDareCameraPerf` every approximately five seconds of rendered camera frames. Summaries contain frame throughput, mean/max processing time, frames over 33.3 ms, face/mesh-visible counts, latest detector latency, cumulative detector completions, and recording/tracking flags. They contain no images, face coordinates, account information or uploads. Release builds do not collect these summaries.

`averageFrameMs` measures the render-thread processing path (including submission/swap waits), not pure GPU execution time or camera-to-display latency. FPS reflects delivered analysis/render frames, not the display refresh rate. Windows spanning a mode switch mix both modes; wait for a full settled window before comparing. Fixture recording gaps can also affect its throughput window. Emulator figures are functional diagnostics, not phone performance results.

Read only this tag while the user runs the check:

```sh
adb -s DEVICE_SERIAL logcat -d -s MoodDareCameraPerf:I '*:S'
```

Original, compare, and zero-strength lenses should stop detector completions after any in-flight task finishes. Selecting an active face effect should resume detection. A missing face in the camera view is not itself a detection failure.

## Regression commands

```sh
flutter test --coverage
python3 tooling/check_coverage.py
flutter analyze
cd android
./gradlew :app:testDebugUnitTest -Ptarget-platform=android-arm64
cd ..
flutter test integration_test/camera_tracking_work_test.dart integration_test/live_video_test.dart integration_test/mesh_shape_test.dart integration_test/photo_makeup_regression_test.dart -d emulator-5554 --reporter expanded
```

Build the ordinary APK again after emulator integration tests before installing it on a personal phone.

## Acceptance record

Record the build, phone/OS, lenses/strength, lighting/glasses, session length, observed alignment/stutter, and any timing summaries. Do not record identifying photos or face coordinates here. Multi-phone, skin-tone, glasses, low-light and sustained-heat acceptance remain pending until hands-on results are recorded.

### Samsung sample — 2026-09-29, build de5f1e0

Installed in place on the connected Samsung SM-F976U1. Camera timing summaries from 15:57–16:00 showed approximately 29.1–29.9 fps across preview and recording windows. Original's initial three windows had zero detector completions. The first active-effect recording windows showed 29.7–29.9 fps, mean processing times of 8.8–9.7 ms, maxima of 28.0–32.3 ms, and face/mesh visibility on all frames in those windows. Later sampled recording windows remained near 30 fps. No sampled window reported processing frames exceeding 33.3 ms.

These are short debug-build observations, not a before/after benchmark, a battery claim or verification of an entire recording. Lens names, ambient lighting, glasses and skin tones are not logged; The user reported a significant visual improvement, with occasional lipstick lag during faster head movements, and approved proceeding to AR. Fast-motion lip latency remains an open refinement. Multi-phone and longer thermal testing remain open.
