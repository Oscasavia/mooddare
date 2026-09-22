#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
work=/private/tmp/mooddare-promo
out=design/promo/mooddare-first-look
mkdir -p "$work/swift-cache"
python3 tooling/promo/audio.py --narration "$out/voiceover.json"
node tooling/promo/render.mjs
swiftc -module-cache-path "$work/swift-cache" tooling/promo/encode.swift -o "$work/encode"
swiftc -module-cache-path "$work/swift-cache" tooling/promo/inspect.swift -o "$work/inspect"
"$work/encode" "$work/landscape" "$out/mooddare-promo-landscape-v2.mp4" 1920 1080 30 "$work/audio/promo-mix.wav"
"$work/encode" "$work/portrait" "$out/mooddare-promo-vertical-v2.mp4" 1080 1920 30 "$work/audio/promo-mix.wav"
"$work/inspect" "$out/mooddare-promo-landscape-v2.mp4"
"$work/inspect" "$out/mooddare-promo-vertical-v2.mp4"
