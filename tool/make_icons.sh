#!/usr/bin/env bash
# Renders the Android launcher icons from the brand mark in assets/brand/.
# Needs rsvg-convert (brew install librsvg). Rerun after the mark changes.
set -euo pipefail
cd "$(dirname "$0")/.."

res=android/app/src/main/res
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Adaptive icon layers are 108dp with the mark inside the 66dp safe zone,
# so the 100-unit mark gets 32 units of padding on each side.
mark=$(grep -E '<(circle|path)' assets/brand/linksy-mark--signal.svg)
cat > "$tmp/fg.svg" <<SVG
<svg xmlns="http://www.w3.org/2000/svg" viewBox="-32 -32 164 164">
  <style>.a{fill:#2563FF}.b{fill:#22C3E6}.sa{fill:none;stroke:#2563FF}.sb{fill:none;stroke:#22C3E6}</style>
  $mark
</svg>
SVG
# Themed icons (Android 13+): one color, the system tints it.
sed 's/#2563FF/#000000/g; s/#22C3E6/#000000/g' "$tmp/fg.svg" > "$tmp/mono.svg"
# Legacy icon (Android 7): the mark on a white circle.
cat > "$tmp/legacy.svg" <<SVG
<svg xmlns="http://www.w3.org/2000/svg" viewBox="-16 -16 132 132">
  <style>.a{fill:#2563FF}.b{fill:#22C3E6}.sa{fill:none;stroke:#2563FF}.sb{fill:none;stroke:#22C3E6}</style>
  <circle cx="50" cy="50" r="66" fill="#FFFFFF"/>
  $mark
</svg>
SVG

for pair in mdpi:1 hdpi:1.5 xhdpi:2 xxhdpi:3 xxxhdpi:4; do
  d=${pair%%:*}; s=${pair##*:}
  out=$res/mipmap-$d
  mkdir -p "$out"
  layer=$(awk "BEGIN{print int(108*$s)}")
  legacy=$(awk "BEGIN{print int(48*$s)}")
  rsvg-convert -w "$layer" -h "$layer" "$tmp/fg.svg" -o "$out/ic_launcher_foreground.png"
  rsvg-convert -w "$layer" -h "$layer" "$tmp/mono.svg" -o "$out/ic_launcher_monochrome.png"
  rsvg-convert -w "$legacy" -h "$legacy" "$tmp/legacy.svg" -o "$out/ic_launcher.png"
done

mkdir -p "$res/mipmap-anydpi-v26" "$res/values"
cat > "$res/mipmap-anydpi-v26/ic_launcher.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>
</adaptive-icon>
XML
cat > "$res/values/ic_launcher_background.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#FFFFFF</color>
</resources>
XML
echo "Icons written to $res"
