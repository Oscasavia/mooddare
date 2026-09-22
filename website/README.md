# MoodDare landing page

A standalone static marketing site. No framework, package installation, tracking,
cookies, signup forms or live Firebase data. The Flutter `web/` directory remains
separate. This website does not change the Android/iOS app.

The visual direction uses spacious product presentation, restrained typography,
warm ivory and muted lavender. Mood Wink carries the personality; decorative
sparkles and starbursts are omitted. The mood sampler changes its tone alongside
the selected dare, and the screenshot viewer and FAQ keep their original behavior.

## Preview

From this directory, run `npm start`, then open http://127.0.0.1:4173.
Set `PORT` if needed. Node 22 or later is required.

## Release placeholders

Edit `config.js` to supply final HTTPS Android/iOS download URLs and a direct
promo video URL. Until then, downloads are visibly disabled and the film says
“Coming soon.” Supplying a video creates a native player with controls, without
autoplay or background download. Add captions before publishing a spoken video.
The supplied video URL should point to a browser-compatible media file, not a
YouTube page. The configured domain and real store availability should also be
reflected in the page's FAQ, availability copy and social metadata at launch.

## Screenshots and policy pages

`tooling/export_website_assets.dart` renders the actual Flutter screens, using
only built-in moods. No real profile, email, photo or post is included. The wordmark
and mascot come from the approved app artwork. Roboto is loaded from the Flutter
SDK when rendering; the website itself uses system fonts and makes no font requests.
PNG screenshots are committed, so browsing the site needs no Flutter installation.

Regenerate from the repository root:

```sh
MOODDARE_FLUTTER_SDK=/path/to/flutter flutter test tooling/export_website_assets.dart
```

On macOS the renderer uses the system emoji font; on another OS, point
`MOODDARE_EMOJI_FONT` at a local compatible emoji font. Fonts are not copied to the
website. The exporter also generates `privacy.html` and `terms.html` from the app's
policy data. Regenerate after policy changes. Policies are still drafts; see
`docs/LEGAL_READINESS.md` before public launch. Hosting the website does not by
itself satisfy the outstanding moderation, operator disclosure or age-assurance work.

## Tests

Run `npm test`. The tests use Node's built-in test runner and a local Chrome or
Chromium executable (set `CHROME_BIN` if auto-detection is insufficient). They check
responsive layout, real images and links, placeholder behavior, mood interaction,
the screenshot dialog and its keyboard dismissal/focus restoration, FAQ expansion,
legal pages, reduced-motion support and future release URL handling. Browser
captures are written under ignored `test-results/website/` at the repo root.

## Publish when approved

The hosting config is isolated from the app's database/security deployment:

```sh
firebase deploy --project mooddare --config firebase.landing.json --only hosting
```

Run that from the repository root only when ready to publish. Confirm which
Firebase Hosting site/domain is intended before deploying: this command targets
the project's default site and replaces its current hosting release. No deployment
is performed by tests or GitHub Actions. After choosing the public domain, add an
absolute canonical URL and absolute `og:image` URL to `index.html`.
