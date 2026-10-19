# Linksy for Android

Your devices, connected. The phone app for [Linksy](https://github.com/LinkSy-mg/linksy-desktop):
share files, clipboard text and pings with your own devices directly over the local
network, with no account, cloud or server.

The product, the wire protocol and the feature status are in
[`docs/protocol.md`](https://github.com/LinkSy-mg/linksy-desktop/blob/main/docs/protocol.md) in
linksy-desktop. Read it before changing anything that talks to other devices.

## Status

The app runs on **linksy-core itself** (Rust, from linksy-desktop) through
flutter_rust_bridge, so it speaks the desktop's exact protocol. Tested against a node on
the same network: pairing by invite link and by 6-digit code, files both ways (resume
and BLAKE3 checks are the core's), clipboard and pings both ways, and screen, camera,
remote control and second-display sessions (streams checked for profile, SPS/PPS before
keyframes, size, frame rate and rotation; input checked both ways).

| Done | To do |
|---|---|
| linksy-core on the phone: discovery (mDNS, with a Wi-Fi multicast lock while open), pairing, transfers | Foreground service while a transfer or prompt is open (now: only while the app is on screen) |
| Device list with presence, nearby unpaired devices | Share sheet entry point ("Share → Linksy") |
| Device page: Send files, Clipboard, Ping, activity as a timeline | Notifications with Accept / Decline actions |
| Pairing: in-app QR scanner, `linksy://pair` links from any camera app, by address, 6-digit code | Send from `content://` URIs without copying (needs a core API, docs/protocol.md §7) |
| Incoming files prompt, live progress / speed / time left, cancel, open received files | Save received files into MediaStore Downloads (now: app folder, `Android/data/app.linksy/files/Received`) |
| Settings: name, auto-accept, stay connected | NsdManager discovery fallback for phones that filter multicast |
| History kept on the phone (500 entries, clipboard text never on disk) | Watching the desktop's screen on the phone; front/back camera switch |
| Sharing this phone's screen ("View Screen", exact shape, follows rotation) and camera ("Use as Webcam"), in a foreground service with a Stop notification | Second display at the phone's own size (the desktop sends 1920×1080 for now) |
| Remote control (`control`) through an accessibility service the user turns on once; declined as unsupported until then | |
| Second display (`display`): the desktop's virtual monitor full screen in landscape, touch as mouse, two-finger scroll | |
| Signal design, light and dark, edge-to-edge, predictive back, reduced motion respected | |

`flutter run --dart-define=LINKSY_DEMO=true` runs on `DemoNode` (made-up devices) for UI
work; Settings → Demo then triggers what another device would. Widget tests use it too.

## Releases

Downloads are public at
[LinkSy-mg/linksy-releases](https://github.com/LinkSy-mg/linksy-releases/releases/latest)
(APKs and notes only; this repo stays private). To release:

1. Add the version's section to `CHANGELOG.md` (user-facing: it becomes the public
   release notes) and bump `version: X.Y.Z+N` in `pubspec.yaml`.
2. Commit as `chore(release): vX.Y.Z`.
3. Run `tool/release.sh`: it checks, builds the universal APK and one per ABI, tags,
   publishes the release here, then `tool/publish_public.sh` puts the APKs on the public
   repo under unversioned names (`…/releases/latest/download/linksy.apk`).

The release key lives outside the repo in `~/Axel/linksy-mobile-keys/`;
`android/key.properties` (ignored) points to it.

## Run

```sh
flutter pub get
flutter run
flutter analyze && flutter test
```

Android only for now (application id `app.linksy`). iOS comes later.

## Layout

| Path | What it is |
|---|---|
| `lib/core/` | Node interface (`linksy_node.dart`, mirrors `linksy_core::Node`), models and events, invite parsing, `DemoNode` |
| `lib/app/` | `LinksyController` (devices, settings, activity), history store, app shell that shows prompts |
| `lib/features/` | Screens: devices, device page, pairing, incoming transfer, settings |
| `lib/ui/` | The Signal design system: tokens and theme (`sig.dart`), components, icons, formatting |
| `assets/brand/` | The "Sender" mark and the app icon from linksy-desktop, with inline colors |
| `tool/make_icons.sh` | Renders the launcher icons (adaptive + themed) from the mark |

## Design

Linksy has its own look, "Signal", rather than stock Material:

- **Flat, and only the brand's colors.** No gradients, shadows or glows. Blue
  `#2563FF` is the sender, cyan `#22C3E6` the receiver (from the mark): outgoing things
  are blue, incoming things cyan. Device headers are solid blue (deep `#1438B8` in dark
  mode) with the mark in white and light cyan `#9FE6F5`. Devices are flat blue, deep or
  cyan. Red only for failed or declined.
- **The real logo.** `assets/brand/` holds the mark and the desktop app icon with inline
  colors (flutter_svg ignores the `<style>` classes in linksy-desktop's SVGs). The
  launcher icon is rendered from the same design by `tool/make_icons.sh`.
- **Type.** Sora for names, titles and numbers; Inter for everything else. Both bundled
  in `assets/fonts/` (OFL).
- **Icons.** Phosphor (MIT), vendored as fonts in `assets/fonts/phosphor/` with the
  icons in use declared in `lib/ui/icons.dart` (the `phosphor_flutter` package doesn't
  build on current Flutter).
- **Shapes.** Solid cards (no borders, no shadows), pill buttons, pressables that shrink
  instead of rippling.
- **Home stays simple.** A plain header (logo, name, settings) and the device list. No
  decorative hero.

## The Rust bridge

Per `docs/protocol.md` §3 the protocol is **not** reimplemented in Dart (QUIC, mutual TLS with
self-signed certificates, the TLS exporter behind the pairing code). Instead:

- `rust/` is a thin crate over `linksy_core::Node` (a git dependency pinned to a
  linksy-desktop commit). Values cross as JSON in the core's own serde shapes; errors as
  kinds (`unreachable`, `declined`…) that `lib/core/rust_node.dart` words with the
  device's name.
- `lib/src/rust/` and `rust/src/frb_generated.rs` are generated by
  `flutter_rust_bridge_codegen generate` (committed, so Dart builds without Rust).
- `lib/core/rust_node.dart` implements the app's `LinksyNode` on the bindings.
- `MainActivity.kt` holds a `WifiManager.MulticastLock` from `onStart` to `onStop`,
  gives Dart the phone's name, forwards `linksy://pair` links, and asks for screen
  capture and camera consent.
- Screen and camera sharing (`android/…/media/`): `ShareService` (foreground, types
  `mediaProjection|camera`) feeds MediaProjection or Camera2 into a hardware H.264
  encoder (Constrained Baseline, Annex-B, keyframe every 2 s, SPS/PPS before each,
  screen at its exact shape within 1920×1080 at ≤ 30 fps, restarted on rotation; camera
  1280×720 at 30 fps). Video and input cross through JNI (`rust/src/sessions.rs`, one
  task per session owning its streams), not through Dart.
- Remote control: `ControlService` (an accessibility service the user enables once)
  plays `control` input with `ControlInput`: left button + pointer moves = one stroke
  (tap or drag), wheel = swipe, Escape/right click = Back, Home/Super = Home, text into
  the focused field. Off: requests are declined with `decline_unsupported`.
- Second display: `DisplayReceiver` decodes the desktop's stream into a Flutter texture
  (`TextureRegistry.SurfaceProducer`); `DisplayScreen` sends touches back as framed
  `pointer`/`button`/`scroll` messages.

Build the native libraries before `flutter run` or a release (release.sh does it):

```sh
tool/build_rust.sh
```

It needs `rustup` (Homebrew's keg: `/opt/homebrew/opt/rustup/bin`), the targets
`aarch64-linux-android armv7-linux-androideabi x86_64-linux-android`, `cargo-ndk`,
`flutter_rust_bridge_codegen` 2.13.0, NDK 28.2 and SSH access to linksy-desktop. To move
to a newer core, change the `rev` in `rust/Cargo.toml` and rebuild.

Core logs go to logcat under the tag `linksy`.
