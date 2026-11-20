# KDE Connectify for Android

Your devices, connected. Companion Android mobile app for
[Project KDE Connectify](https://github.com/ArayaMusawwah/kde-connectify):
share files, clipboard text, pings, camera webcam, second display (sidecar),
microphone directly over local network or USB cable, no account, cloud or
server.

## Status

This is a fork of
[LinkSy-mg/linksy-mobile](https://github.com/LinkSy-mg/linksy-mobile), merged
with KDE Connectify-specific features:

- Android accessibility input/control overlay (pointer + keyboard)
- Home-screen command widgets synced from the computer
- PC file browsing with all-files access (`MANAGE_EXTERNAL_STORAGE`)
- Phone media sync (`MediaNotificationListener`)
- Dual/triple pairing scheme (`kdeconnectify://`, `connectify://`, `linksy://`)
- Application id `org.kde.connectify` and rebranded strings

## Key Features

- **Virtual Webcam**: Stream phone camera (1080p, 60fps, front/back switch, zoom) into PC PipeWire apps.
- **Second Display (Sidecar)**: Use phone tablet as low-latency touch-enabled monitor.
- **Virtual Microphone**: Low-latency PCM 48kHz audio directly into PC PipeWire.
- **Screen Mirror & Remote Desktop**: Real-time display mirroring, mouse/keyboard control.
- **USB Cable Mode (AOA)**: Zero Wi-Fi latency connection via plain USB cable (no developer options / ADB required).
- **Away Home**: Reach paired computers securely over internet via `iroh` P2P relay.
- **Wi-Fi Direct**: Ad-hoc 5GHz P2P group transfer files > 256 MB (~80 MB/s).
- **Remote Terminal**: Interactive shell on computer PIN authorization.
- **Shared Clipboard, Files & Notifications**: Fast local-first transfers, BLAKE3 checksums, resume support.

## For the desktop side

The C++ side lives in
[Project KDE Connectify](https://github.com/ArayaMusawwah/kde-connectify) under
`3rdparty/linksy-desktop`.

## Lean on purpose

See the upstream documentation for design rationale.

## The Rust bridge

`rust/` contains the flutter_rust_bridge wrapper around `linksy_core`.
