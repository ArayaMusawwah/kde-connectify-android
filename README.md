# Linksy for Android

Your devices, connected. The phone app for [Linksy](https://github.com/LinkSy-mg/linksy-desktop):
share files, clipboard text and pings with your own devices directly over the local
network, with no account, cloud or server.

The product, the wire protocol and the feature status are in
[`docs/protocol.md`](https://github.com/LinkSy-mg/linksy-desktop/blob/main/docs/protocol.md) in
linksy-desktop. Read it before changing anything that talks to other devices.

## Status

The UI runs on **`DemoNode`**, a simulated node with made-up devices, until the Rust
core is bridged in. Settings → Demo triggers the flows that start on the other device
(incoming files, pairing request, clipboard).

| Done | To do |
|---|---|
| Device list with presence, nearby unpaired devices | Rust bridge to `linksy-core` (below) |
| Device page: Send Files, Send Clipboard, Ping, activity by day | Foreground service while a transfer or prompt is open |
| Pairing: QR scan (`linksy://pair` invites), by address, 6-digit code dialog | Share sheet entry point ("Share → Linksy") |
| Incoming files prompt, live progress / speed / time left, cancel | Notifications with Accept / Decline actions |
| Settings: name, auto-accept, stay connected | Save received files into MediaStore Downloads |
| History kept on the phone (500 entries, clipboard text never on disk) | Screen mirroring, Sidecar, phone as webcam (§4.8) |
| Open received files from the timeline | |
| Signal design: orbit home, device timelines, light and dark, edge-to-edge, predictive back, reduced motion respected | |

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
| `lib/ui/` | The Signal design system: tokens and theme (`sig.dart`), components, the orbit, icons, formatting |
| `assets/brand/` | The "Sender" mark and the app icon from linksy-desktop, with inline colors |
| `tool/make_icons.sh` | Renders the launcher icons (adaptive + themed) from the mark |

## Design

Linksy has its own look, "Signal", rather than stock Material:

- **Only the brand's colors.** Blue `#2563FF` is the sender, cyan `#22C3E6` the
  receiver (from the mark): outgoing things are blue, incoming things cyan. Heroes use
  the app icon's tile gradient (`#3B78FF` → `#1A45C8`, deep `#1438B8` in dark mode) with
  the mark in white and light cyan `#9FE6F5`. Devices are blue, deep or cyan. Red only
  for failed or declined.
- **The real logo.** `assets/brand/` holds the mark and the desktop app icon with inline
  colors (flutter_svg ignores the `<style>` classes in linksy-desktop's SVGs). The
  launcher icon is rendered from the same design by `tool/make_icons.sh`.
- **Type.** Sora for names, titles and numbers; Inter for everything else. Both bundled
  in `assets/fonts/` (OFL).
- **Icons.** Phosphor (MIT), vendored as fonts in `assets/fonts/phosphor/` with the
  icons in use declared in `lib/ui/icons.dart` (the `phosphor_flutter` package doesn't
  build on current Flutter).
- **Shapes.** Solid cards with soft shadows (no borders), pill buttons, pressables that shrink instead of rippling.
- **The orbit.** Home shows this phone at the center and each device on an orbit by how
  close it is: connected (with a live beam), nearby, away. Unpaired devices are dashed.

## Next: the Rust bridge

Per `docs/protocol.md` §3, the protocol is **not** reimplemented in Dart (QUIC, mutual TLS with
self-signed certificates, TLS exporter for the pairing code). The plan:

1. Install Rust (`rustup`), the Android targets
   (`aarch64-linux-android armv7-linux-androideabi x86_64-linux-android`), `cargo-ndk`,
   an Android NDK, and `flutter_rust_bridge_codegen`.
2. Add a thin bridge crate in `rust/` that depends on `linksy-core` from
   `LinkSy-mg/linksy-desktop` and exposes the `Node` API and its event stream.
3. Implement `LinksyNode` on top of the generated bindings and swap it in for `DemoNode`
   in `lib/main.dart`. Store identity and settings in the app's private files dir.
4. Discovery through `NsdManager` (`_linksy._udp.`) with `node.device_found` /
   `device_lost` if raw multicast is unreliable, and a `MulticastLock` while in use.
