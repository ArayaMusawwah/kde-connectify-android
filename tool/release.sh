#!/bin/zsh
# Builds and publishes a release from this machine: a universal APK (the
# default download), one APK per ABI, and a GitHub Release whose notes come
# from the version's section of CHANGELOG.md. Symbols for the obfuscated build
# stay in dist/. Finally the APKs (never code) go to the public download repo
# via tool/publish_public.sh.
#
#   tool/release.sh            # version from pubspec.yaml, tags vX.Y.Z
#
# Needs: android/key.properties (release key), gh signed in, a clean tree
# with the release commit already made.
set -euo pipefail
cd "$(dirname "$0")/.."

V=$(sed -n 's/^version: \([0-9.]*\)+.*/\1/p' pubspec.yaml)
TAG="v$V"
NAME="linksy"
[ -n "$(git status --porcelain)" ] && { echo "working tree not clean"; exit 1; }
[ -f android/key.properties ] || { echo "android/key.properties missing (release key)"; exit 1; }
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && { echo "$TAG already exists"; exit 1; }

echo "== $TAG: checks"
flutter pub get >/dev/null
flutter analyze
flutter test

echo "== $TAG: building"
OUT=build/app/outputs/flutter-apk
DIST="dist/$TAG"; rm -rf "$DIST"; mkdir -p "$DIST"
flutter build apk --release --obfuscate --split-debug-info=build/symbols
cp "$OUT/app-release.apk" "$DIST/$NAME-$V.apk"
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/symbols
cp "$OUT/app-arm64-v8a-release.apk"   "$DIST/$NAME-$V-arm64.apk"
cp "$OUT/app-armeabi-v7a-release.apk" "$DIST/$NAME-$V-armv7.apk"
cp "$OUT/app-x86_64-release.apk"      "$DIST/$NAME-$V-x86_64.apk"
tar -czf "$DIST/$NAME-$V-symbols.tar.gz" -C build symbols
ls -la "$DIST"

awk -v v="$V" '
  /^## \[/ { if (found) exit; if (index($0, "## [" v "]") == 1) { found = 1; next } }
  found { print }
' CHANGELOG.md > "$DIST/notes.md"
[ -s "$DIST/notes.md" ] || echo "_No changelog entry for $V._" > "$DIST/notes.md"

echo "== $TAG: tagging and publishing"
git tag "$TAG"
git push origin main "$TAG"
gh release create "$TAG" --title "Linksy $TAG" --notes-file "$DIST/notes.md" \
  "$DIST/$NAME-$V.apk" "$DIST/$NAME-$V-arm64.apk" "$DIST/$NAME-$V-armv7.apk" "$DIST/$NAME-$V-x86_64.apk"
gh release view "$TAG" --json url --jq .url

tool/publish_public.sh "$TAG"
