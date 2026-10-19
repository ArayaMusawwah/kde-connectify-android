#!/bin/zsh
# Publishes a built release to the public download repo,
# LinkSy-mg/linksy-releases: the APKs and the release notes, never the
# code or the symbols. The app repo stays private.
# Asset names carry no version, so these links always serve the newest release:
#
#   https://github.com/LinkSy-mg/linksy-releases/releases/latest/download/linksy.apk        (every phone)
#   https://github.com/LinkSy-mg/linksy-releases/releases/latest/download/linksy-arm64.apk  (64-bit, smaller)
#   https://github.com/LinkSy-mg/linksy-releases/releases/latest/download/linksy-armv7.apk  (32-bit, smaller)
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
cp "$DIST/$NAME-$V.apk"       "$OUT/$NAME.apk"
cp "$DIST/$NAME-$V-arm64.apk" "$OUT/$NAME-arm64.apk"
cp "$DIST/$NAME-$V-armv7.apk" "$OUT/$NAME-armv7.apk"
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
    --title "Linksy $V" --notes-file "$OUT/notes.md" "$OUT"/*.apk
fi
gh release view "$TAG" --repo "$REPO" --json url --jq .url
