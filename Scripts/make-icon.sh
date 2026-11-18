#!/usr/bin/env bash
# Author: Simon-Pierre Boucher — contact@spboucher.ai
# File: Scripts/make-icon.sh
# Description: Renders Resources/icon/SPWallet.svg into the asset catalog's AppIcon set (all macOS sizes).
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="Resources/icon/SPWallet.svg"; OUT="Resources/Assets.xcassets/AppIcon.appiconset"
command -v rsvg-convert >/dev/null || { echo "rsvg-convert is required (brew install librsvg)"; exit 1; }
mkdir -p "$OUT"
for s in 16 32 64 128 256 512 1024; do rsvg-convert -w $s -h $s "$SRC" -o "$OUT/icon_$s.png"; done
cat > "$OUT/Contents.json" <<'JSON'
{
  "images" : [
    { "idiom" : "mac", "scale" : "1x", "size" : "16x16",   "filename" : "icon_16.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "16x16",   "filename" : "icon_32.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "32x32",   "filename" : "icon_32.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "32x32",   "filename" : "icon_64.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "128x128", "filename" : "icon_128.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "128x128", "filename" : "icon_256.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "256x256", "filename" : "icon_256.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "256x256", "filename" : "icon_512.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "512x512", "filename" : "icon_512.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "512x512", "filename" : "icon_1024.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
echo "icon rendered: $(ls "$OUT"/*.png | wc -l | tr -d ' ') PNG files"
