#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

export ANDROID_NDK_HOME=${ANDROID_NDK_HOME:-$HOME/Android/Sdk/ndk/28.2.13676358}

echo "== 1. Compiling Rust bridge for arm64-v8a..."
(cd rust && cargo ndk -t arm64-v8a -P 24 -o ../android/app/src/main/jniLibs build --release)

echo "== 2. Building Flutter Release APK..."
flutter build apk --target-platform android-arm64 --release

# Ensure friendly named APK is copied into flutter-apk directory
V=$(sed -n 's/^version: \([0-9.]*\)+.*/\1/p' pubspec.yaml)
NAMED_APK="build/app/outputs/flutter-apk/kde-connectify-v$V-arm64.apk"
if [ -f "build/app/outputs/apk/release/kde-connectify-v$V.apk" ]; then
    cp "build/app/outputs/apk/release/kde-connectify-v$V.apk" "$NAMED_APK"
elif [ -f "build/app/outputs/flutter-apk/app-release.apk" ]; then
    cp "build/app/outputs/flutter-apk/app-release.apk" "$NAMED_APK"
fi

echo ""
echo "== SUCCESS! Generated APK files:"
ls -lh "$NAMED_APK"
