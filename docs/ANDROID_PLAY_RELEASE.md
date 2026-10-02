# Android Play release preparation

The store package is `com.mooddare.app`, version 1.0.0 build 3. Development builds retain `com.example.mooddare`; native Kotlin namespace remains unchanged. These install side by side. A store installation starts with its own local data and requires sign-in; signing into an existing account restores its server profile and content. Do not uninstall the development app to test the release.

Release Firebase registration: `1:1010705723283:android:c08f77f47d452ca3270266`. Its public configuration is in `android/app/src/release/google-services.json`. Dart selects the matching Firebase options in release mode. The release upload SHA-1/SHA-256 certificates are registered in Firebase, including its Android OAuth client. Debug/profile builds retain their original registration. Membership previews remain unavailable in release.

## Signing and backups

A new, private MoodDare RSA upload key was created locally, separate from Wimbli:

- `android/signing/mooddare-upload.jks`
- `android/key.properties` (contains the passwords; permissions 0600)

Both are excluded from Git. Back up **both files together** to private encrypted storage before relying on this build. Do not email, commit, or upload them to the website. The public certificate at `docs/release/mooddare-upload-certificate.pem` is safe to share with Play Console. Never regenerate the key for subsequent builds or fall back to debug signing. Release tasks fail if signing configuration is missing.

Public upload SHA-256: `D9:32:7F:DA:F9:CC:B6:C1:CB:5E:0C:4B:20:3E:E5:E9:D4:37:1F:FA:23:5D:EB:27:04:9A:22:94:4C:68:2E:42`.

## Rebuild and verify

Run Flutter build and integration-test commands sequentially. They regenerate the same native plugin registrant; overlapping test/release builds can insert the test-only plugin into release compilation.

```sh
flutter build appbundle --release
flutter build apk --release --split-per-abi
python3 tooling/check_android_native.py build/app/outputs/bundle/release/app-release.aab
python3 tooling/check_android_native.py build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

Use Android build-tools `apksigner verify --verbose --print-certs` to check the APK signer and `zipalign -c -P 16 4` to check APK packaging. Use `aapt2 dump badging` to confirm `com.mooddare.app`, version code 3, minimum SDK 24 and target SDK 36. The `.aab` is for Play Console; the ARM64 `.apk` is for direct installation on the Samsungs. The corrected build 3 AAB is in the ignored `releases/android/1.0.0+3/` folder. Previously generated build 2 APKs remain in `releases/android/1.0.0+2/`.

The build targets Android 16 / API 36 and requires Android 7.0 / API 24 or later. Build 3 raises the minimum from API 23 to 24 to meet Google Play automatic protection requirements; Android 6 devices are no longer supported. Face mesh is updated from 16.0.0-beta1 to beta3 for 16 KB LOAD alignment. The static checker also exposes upstream RELRO-boundary advisories; do not interpret passing LOAD/ZIP checks as exhaustive native compatibility certification. Keep physical-device tests and a 16 KB emulator camera regression in release qualification. The Android 16 large-screen compatibility property preserves the existing portrait experience; complete a landscape/foldable audit and remove that temporary opt-out before targeting API 37.

Verification on October 2, 2026: the ARM64 APK passed v1/v2/v3 signature verification with the new certificate, 16 KB ZIP alignment, package/version/target checks, installation and cold launch on the 16 KB Android emulator. All twelve 64-bit libraries in the AAB passed LOAD alignment; five upstream RELRO advisories remain recorded by the checker. The face-mesh regression passed both scenarios with `bionic.linker.16kb.app_compat.enabled=false` and `pm.16kb.app_compat.disabled=true` on the emulator; both properties were restored afterward. No Samsung system settings were changed. The x86_64 and ARMv7 artifacts were built but not exercised on matching hardware.

Build 3 follow-up: rebuilt the signed AAB after the Play upload rejected API 23. Verified its packaged protobuf manifest reports `com.mooddare.app`, version code 3, minimum SDK 24 and target SDK 36; verified the existing upload certificate and all twelve 64-bit native LOAD alignments. This configuration-only update did not rerun the Dart suite or device walkthrough.

## Remaining Play Console steps

Create/select the Play Console app and use an internal testing release first. Enable Play App Signing. Its **app-signing certificate differs from this upload certificate**: add Play's SHA-1/SHA-256 to this Firebase Android app, download the refreshed public configuration, and add Play's SHA-256 to `website/assetlinks.json` for verified shared-post links. Test Google sign-in, notifications, posting, camera output, account deletion and deep links on the actual Play-delivered build before production rollout.

Complete the store listing and declarations using the app's real behavior, including private recommendation activity, uploaded media, account information and moderation/reporting. Privacy policy: `https://mooddare.web.app/privacy.html`. Store download links on the website stay placeholders until the listing is available. This preparation does not submit or publish an app to Google Play.

References: [Flutter Android release guide](https://docs.flutter.dev/deployment/android), [Play target API requirements](https://support.google.com/googleplay/android-developer/answer/11926878), [16 KB native guidance](https://developer.android.com/guide/practices/page-sizes), [Android 16 large-screen behavior](https://developer.android.com/about/versions/16/behavior-changes-16).
