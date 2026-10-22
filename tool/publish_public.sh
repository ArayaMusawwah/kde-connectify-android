#!/bin/zsh
# Publishes a built release to the public download repo,
# LinkSy-mg/linksy-releases: the APKs and the release notes, never the
# code or the symbols. The app repo stays private.
# Asset names carry the version (linksy-0.2.1.apk, -arm64, -armv7), so a downloaded file
# says which it is; the release is titled "Mobile release" (desktop ones say "Desktop
# release"). The website always links the newest, whatever its version:
#
#   https://linksy.diary.mg/download/android        (every phone)
#   https://linksy.diary.mg/download/android-arm64  (64-bit, smaller)
#   https://linksy.diary.mg/download/android-armv7  (32-bit, smaller)
#
#   tool/publish_public.sh v0.1.0      # run by tool/release.sh; by hand to republish
set -euo pipefail
cd "$(dirname "$0")/.."

TAG=${1:?usage: tool/publish_public.sh vX.Y.Z}
V=${TAG#v}
NAME=linksy
REPO=LinkSy-mg/linksy-releases
DIST="dist/$TAG"
OUT="$DIST/public"

for f in "$NAME-$V.apk" "$NAME-$V-arm64.apk" "$NAME-$V-armv7.apk" notes.md; do
  [ -f "$DIST/$f" ] || { echo "$DIST/$f missing: build the release first"; exit 1; }
done

rm -rf "$OUT"; mkdir -p "$OUT"
cp "$DIST/$NAME-$V.apk" "$DIST/$NAME-$V-arm64.apk" "$DIST/$NAME-$V-armv7.apk" "$OUT/"
{
  cat "$DIST/notes.md"
  print '\n### SHA-256\n```'
  (cd "$OUT" && shasum -a 256 *.apk)
  print '```'
} > "$OUT/notes.md"

echo "== $TAG: publishing to $REPO"
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  gh release upload "$TAG" --repo "$REPO" --clobber "$OUT"/*.apk
  gh release edit "$TAG" --repo "$REPO" --notes-file "$OUT/notes.md"
else
  gh release create "$TAG" --repo "$REPO" --target main --latest \
    --title "Mobile release · Linksy $V for Android" --notes-file "$OUT/notes.md" "$OUT"/*.apk
fi
gh release view "$TAG" --repo "$REPO" --json url --jq .url
