# MoodDare first-look promo

A 22-second brand introduction: **A little dare. A great story.**

Deliverables (rendered locally):
- `mooddare-promo-landscape-v2.mp4` — 1920×1080, 30 fps, website/presentation format.
- `mooddare-promo-vertical-v2.mp4` — 1080×1920, 30 fps, social format.
- `captions.srt` — timed voiceover transcript.
- `review.html` — local player for both versions.

The five-scene plan and voiceover script are in `storyboard.json`. The animation
uses the actual app's Discover and Creative dare screenshots from `website/assets`.
These were exported with bundled examples, not private user posts. Phone screens
are animated screenshots, not a live screen recording. The keepsake card is brand
artwork rather than a claim about an app screen.

Mood-wink's contours are extracted directly from `MoodWinkGeometry` in the app;
the right eye morphs between the same open/winking shapes without replacing the
face. The approved transparent wordmark is reused unchanged. No generated logo,
stock footage, paid lens, external voice API or stock music is used.

Current narration: the user's downloaded TTSMaker MP3. The source stays local
(`voiceover-source.mp3`, ignored by Git), with its SHA-256 fingerprint and eight
sentence cuts in `voiceover.json`. Four-millisecond edge fades prevent clicks;
pitch and speech speed are unchanged. New pauses align the speech with the scenes,
including separate beats for “MoodDare,” “A little dare,” and “A great story.”
The source was checked with local speech recognition; no audio was uploaded.

The original macOS Samantha first cut remains available in the unversioned MP4s.
To recreate that voice mix, run `python3 tooling/promo/audio.py` without the
`--narration` argument. Music and sonic winks are original, locally synthesized
notes; they duck underneath the narration.
The ending says “Coming soon” because public store links are still placeholders.

## Rebuild on this Mac

Requirements: Node 22+, Google Chrome, Python 3, Xcode command-line tools, and
macOS `say` / `afconvert` with Samantha available. No package installation required.

```sh
zsh tooling/promo/build.sh
```

Frames and audio intermediates stay under `/private/tmp/mooddare-promo`.
Final videos are ignored by Git to avoid committing large review exports before
approval. Export checks decode all 660 frames in each MP4, verify dimensions,
frame rate, duration, audio tracks and audible samples, and extract stills for
visual review. No app or public website changes are needed to watch these files.
