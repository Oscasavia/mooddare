# MoodDare identity concept v1

Created 2026-09-22 using the built-in image_gen tool (not CLI/API fallback).

A rounded lowercase wordmark paired with an asymmetric two-arch m and diagonal notch. Palette direction follows the app: lavender #C5B4FF, ink #0D0E14, warm white #FAF8FF. Generated PNG colors are approximate; these are concept raster assets, not exact-color vector masters.

- identity-board.png: wordmark, icon treatments and a dark splash-screen preview.
- app-icon.png: standalone square icon artwork with opaque lavender background.
- wordmark-dark.png: standalone lavender lettering with opaque dark background.

The user approved the wordmark; its original source is now copied to `assets/branding/mooddare-wordmark.png` for Moments and Welcome. The shared Flutter widget renders it in uniform brand lavender with its dark background removed at paint time. The app-icon concept needs further design work and is not wired into launcher or splash resources. Before icon integration, prepare consistent vector masters, exact colors, platform-specific launcher masks and splash exports, and inspect at actual icon sizes. Transparent wordmark generations were discarded because of visible edge artifacts.

The artwork was generated for this project, but worldwide uniqueness, trademark availability and non-infringement have not been established. The name and symbol both need clearance; a custom visual design alone does not clear the name. See [USPTO clearance-search guidance](https://www.uspto.gov/trademarks/search/comprehensive-clearance-search-similar-trademarks).

## Prompts

### Initial identity board

Use case: logo-brand.
Create a polished original brand identity concept board for the social photo/video dare app "mooddare". Its personality is expressive, warm, playful, confident, grown-up, quietly distinctive.
Design a custom-drawn lowercase wordmark spelling EXACTLY "mooddare" (m o o d d a r e), with excellent legibility and optical kerning. Rounded substantial geometric letterforms with broad open counters, a custom asymmetric m, subtly angled cuts on selected terminals, rounded single-storey a, and slightly animated paired o letters. It must feel like drawn lettering rather than simply typed stock font. Avoid cursive.
Develop ONE matching standalone symbol: a bold, very simple sculptural lowercase m made from a continuous soft ribbon with two unequal rounded arches, one shoulder rising slightly higher, and one distinctive short diagonal cut. It should suggest an expressive change of mood and a little leap forward; recognizable silhouette at 24px. No thin linework or tiny detail. Deliberately design an original silhouette, do not reference or imitate existing company logos.
Palette precisely inspired by existing app: lavender #C5B4FF, deep ink #0D0E14, muted plum #403750, warm white #FAF8FF. Flat colors, no gradients.
Presentation: elegant landscape identity board with generous whitespace, three cohesive areas. Upper-left large dark-ink wordmark on warm white with matching lavender symbol beside it. Lower-left a lavender square app icon with generous safe margin and deep-ink symbol, plus small monochrome symbol demonstrations. Right third a tall dark-ink splash-screen rectangle with small centered lavender symbol above lavender "mooddare" wordmark. Use the EXACT same symbol and lettering consistently throughout, flat front-facing artwork not perspective mockups. Board should look like a considered boutique design studio identity presentation. Main wordmark is the hero.
Only text is "mooddare". No slogans, no watermarks, no labels, no trademark or copyright symbols. No camera, lens aperture, ghost, fire/flame, hearts, lightning bolt, generic sparkle, speech bubble, infinity loop, familiar social media icon, photorealism, textures, bevels, glow, drop shadows or 3D. Crisp vector-like graphic edges, but deliver a raster concept image.

### Board refinement (reference: initial board)

Use case: logo-brand. Edit the supplied mooddare identity board. Preserve the exact m symbol silhouette, diagonal notch, and exact lowercase wordmark spelling and letter shapes. Make a single targeted presentation correction: the LEFT TWO THIRDS MUST HAVE A SOLID OPAQUE WARM-WHITE #FAF8FF background so the dark wordmark and dark symbols are plainly visible. Keep ONLY the right splash panel solid dark #0D0E14 with lavender wordmark and symbol. Remove ALL glows, gradients, haze, texture and shadows everywhere. ALL shapes and backgrounds are solid flat colors with crisp edges. Large upper left wordmark is solid deep ink #0D0E14, its symbol lavender #C5B4FF. Bottom left app icon is a flat lavender rounded square with solid dark m symbol. Smaller marks demonstrate dark and lavender versions on the WHITE background. Preserve airy layout. No new text or elements. This is a legible flat graphic design presentation, not a luminous render.

### Standalone icon (reference: refined board)

Use case: logo-brand. Create one standalone square app-icon artwork using the m SYMBOL shown in the supplied mooddare concept board as the design reference. Preserve the asymmetrical two-arch silhouette and diagonal cut in its lower right arm. One large solid deep-ink #0D0E14 m symbol centered on an entirely flat solid lavender #C5B4FF square background that fills the whole image edge to edge. Symbol occupies approximately 58 percent of canvas width and is optically centered, with generous safe margins for circle and rounded-square launcher masks. Do not draw rounded outer corners, because the operating system will mask the square. Flat, sharp, clean geometric artwork. No wordmark, text, typography, gradient, glow, texture, haze, shadows, white edging, lighting or presentation board. EXACTLY ONE SIMPLE ICON. Output 1024 square if possible.

### Standalone wordmark (reference: refined board)

Use case: logo-brand. Create one standalone horizontal wordmark. Use the supplied concept board only as a visual reference for its EXACT lowercase mooddare lettering. Redraw the lettering cleanly with crisp smooth edges, no extraction artifacts. Exact text "mooddare" (m o o d d a r e), rounded bold geometric custom lettering matching the reference, single-storey a, subtly angled tops of d ascenders, optical letterspacing with a little breathing room between every letter. Solid lavender #C5B4FF letters on a perfectly solid opaque deep-ink #0D0E14 background. NO transparency. No gradients, glow, texture, white edging, outline, shadow, icon, symbol, labels or other elements. Wide horizontal canvas, lettering centered, fills about 85% of width with even clear margins. A refined wordmark asset that can sit on the app's dark splash background.
