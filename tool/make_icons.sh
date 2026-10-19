#!/usr/bin/env bash
# Renders the Android launcher icons from the desktop app icon's design
# (assets/brand/app-icon.svg: the mark in white and light cyan on a blue tile).
# Needs rsvg-convert (brew install librsvg). Rerun after the brand changes.
set -euo pipefail
cd "$(dirname "$0")/.."

res=android/app/src/main/res
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mark=$(grep -E '<(circle|path)' assets/brand/mark-on-blue.svg)

# Adaptive icon layers are 108dp with the mark inside the 66dp safe zone,
# so the 100-unit mark gets 32 units of padding on each side.
cat > "$tmp/fg.svg" <<SVG
<svg xmlns="http://www.w3.org/2000/svg" viewBox="-32 -32 164 164">
  <g fill="none" stroke-linecap="round">$mark</g>
</svg>
SVG
# The tile's gradient, full bleed: the launcher applies its own shape.
cat > "$tmp/bg.svg" <<SVG
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 108 108">
  <defs><linearGradient id="t" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#3B78FF"/><stop offset="1" stop-color="#1A45C8"/>
  </linearGradient></defs>
  <rect width="108" height="108" fill="url(#t)"/>
</svg>
SVG
# Themed icons (Android 13+): one color, the system tints it.
sed 's/#FFFFFF/#000000/g; s/#9FE6F5/#000000/g' "$tmp/fg.svg" > "$tmp/mono.svg"

for pair in mdpi:1 hdpi:1.5 xhdpi:2 xxhdpi:3 xxxhdpi:4; do
  d=${pair%%:*}; s=${pair##*:}
  out=$res/mipmap-$d
  mkdir -p "$out"
  layer=$(awk "BEGIN{print int(108*$s)}")
  legacy=$(awk "BEGIN{print int(48*$s)}")
  rsvg-convert -w "$layer" -h "$layer" "$tmp/fg.svg" -o "$out/ic_launcher_foreground.png"
  rsvg-convert -w "$layer" -h "$layer" "$tmp/bg.svg" -o "$out/ic_launcher_background.png"
  rsvg-convert -w "$layer" -h "$layer" "$tmp/mono.svg" -o "$out/ic_launcher_monochrome.png"
  # Android 7: the app icon itself, tile and all.
  rsvg-convert -w "$legacy" -h "$legacy" assets/brand/app-icon.svg -o "$out/ic_launcher.png"
done

mkdir -p "$res/mipmap-anydpi-v26"
cat > "$res/mipmap-anydpi-v26/ic_launcher.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>
</adaptive-icon>
XML
rm -f "$res/values/ic_launcher_background.xml"
echo "Icons written to $res"
