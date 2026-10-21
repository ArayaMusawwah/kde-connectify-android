# Linksy for Android → desktop handoff

The phone side's answer to `docs/protocol.md` in linksy-desktop. It says what the Android app
does, what it needs from the desktop, and what it **can't** build, so the desktop doesn't
offer those features to Android phones.

- App: `app.linksy.mg` (since 0.1.8; 0.1.x up to 0.1.7 was `app.linksy`), Flutter + the
  real `linksy-core` through flutter_rust_bridge. Repo: LinkSy-mg/linksy-mobile.
- Core pinned at `c7d9e72` (desktop 0.5.2). Builds for arm64-v8a, armeabi-v7a, x86_64.
- Releases: LinkSy-mg/linksy-releases (`/releases/latest/download/linksy.apk`).
- Distributed as a sideloaded APK, not through the Play Store. That shapes everything in
  §3: Android's fraud protection blocks installing sideloaded apps that declare certain
  permissions, with no way for the user to skip it (v0.1.3 hit this).

## 1. What the phone does (protocol as in `docs/protocol.md`)

| Feature | Phone side | Notes for the desktop |
|---|---|---|
| Discovery, presence, pairing (code, address, QR link) | Done | QR: any camera app opens `linksy://pair…`; the in-app scanner is Camera2 + ZXing |
| Files both ways, accept/decline, cancel | Done | Incoming offers also show as a notification with **Accept / Decline** when the app isn't on screen |
| Received files | Moved to **Downloads/Linksy** (Android 10+) | Folder offers keep their shape: `Downloads/Linksy/Photos/a.jpg` |
| Clipboard, ping, rename | Done | Incoming clipboard is put on the phone's clipboard at once |
| Open on PC (`open_url`) | Done both ways | Share sheet: a link opens on the computer; other text goes as `clipboard`; files are sent |
| Battery (`battery`) | Done | Sent on connect, when the computer is found nearby, at ±5 points and on plug/unplug |
| Ring / Find (`ring`, `ring_stop`) | Done both ways | Alarm stream at full volume, "Found it" screen, 30 s max |
| Media: the computer's players on the phone | Done | Phone sends `media_watch {on}` while the computer's page is open, shows each player with play/pause/next/previous (`media_command`) |
| Calls (`call_state`) | Done | From Android's audio mode (no phone permission), so WhatsApp/VoIP calls count too. **`contact` is never sent** |
| Lock when away (`heartbeat_watch` / `heartbeat`) | Done | Heartbeats come from the core's runtime; a `connectedDevice` foreground service + partial wake lock keep them going with the screen off (tested in forced Doze). Only while the app process lives: send `heartbeat_watch` again on every connect |
| Photo auto-import (`import: true`) | Done | Per computer, off by default. Source is **a folder the user picks** (usually DCIM/Camera), not the whole gallery. Sends folders named `YYYY-MM` (so files land in `Pictures/<phone>/YYYY-MM/…`), ≤ 40 files / ~300 MB per offer, only photos taken after it was turned on. A declined import is shown as "turned off on the computer" |
| Files sidebar (`fs`, §4.9) | Done | `/` is **one folder the user picked** (Android's folder picker), not shared storage. Android refuses Download and the storage root there. Until a folder is chosen and the switch is on, the phone answers `fs_error` "This phone doesn't share its files…" |
| Touchpad / keyboard / slides (`input`) | Done | `pointer_by`, `button`, `scroll`, `text`, `key` (BackSpace, Return, Left/Right, F5, Escape). Volume keys change slides |
| Phone shares its screen (`screen`) | Done | Always the **entire screen** (Android 14+ otherwise preselects "a single app" and the bars come out black) |
| Phone as webcam (`camera`) | Done | Back camera, 1280×720 at 30 fps; **front/back switch** mid-session from the phone (same stream; a keyframe with SPS/PPS follows the switch) |
| Phone as second display (`display`) | Done | Decodes whole access units (AUD / first-slice boundaries), so any slicing works |
| **Phone watches the computer's screen** (`screen`, and `control` with touch) | **New** | The phone *requests* `screen` or `control`. Touch in `control`: one finger = absolute `pointer` + left button held, two fingers = `scroll`. Uses the same receiver as `display` |
| Remote control *of the phone* (`control` asked by the computer) | Not possible | Answered with `decline_unsupported` at once; see §3 |
| Push notifications | Done | Firebase project `linksy-mg`, topic `all`. Nothing for the desktop to do |

The phone keeps running in the background only when a computer watches heartbeats, or when
the user turns on "Keep running in the background". Otherwise most things work while the
app is open.

## 2. What the phone needs from the desktop

1. **Second display at the phone's shape** (`docs/protocol.md` §7, still open). The phone
   letterboxes a 1920×1080 monitor on a ~20:9 screen. Proposal: the phone sends its
   landscape size when it accepts a `display` session:
   `{"type":"session_accept","width":2400,"height":1080}` (optional fields; older
   desktops ignore them). Core: `node.respond_session(request, accept, Some((w, h)))` or a
   `Session::size`. Desktop: create the virtual monitor at that aspect, scaled to at most
   1080 px high. The phone is ready to send it once the core has the field.
2. **Capabilities, so the desktop hides what a phone can't do.** Today the desktop finds
   out by trial: `sms_*` requests get no answer (the 15 s timeout), `control` gets
   `decline_unsupported`, notification and phone-media features simply never arrive.
   Proposal: an optional list in the handshake / `DeviceInfo`, for example
   `"features":["files","clipboard","open_url","battery","ring","media_remote",
   "call_state","heartbeat","import","fs","input","screen","camera","display","watch"]`.
   The desktop then greys out or hides Messages, notification mirroring, phone media,
   and "Control phone" for this app (see §3). Until then, please treat Android phones
   as not having those (`DeviceInfo.os == "android"`).
3. **Clipboard images and files** (planned on both sides). Proposal: an offer flag like
   `import`, `"clipboard": true`, one file ≤ 10 MiB, which the receiver puts on its
   clipboard instead of saving (images as image data, other files as a file
   reference). The phone side is small once the core has it.
4. **Automatic clipboard sync**, desktop → phone. Android lets an app read the clipboard
   only while it's on screen (Android 10+), so the phone can't watch its own clipboard.
   It can apply what arrives, at any time. Proposal: `clipboard_watch {on}` (like
   `media_watch`): while on, the desktop sends `clipboard` whenever its clipboard
   changes. Phone → desktop stays on demand (button, share sheet).
5. **`heartbeat_watch` on every connect.** The phone forgets watches when Android kills
   the app. The desktop already sends it when the phone connects; please keep that.
6. **`fs` labels.** The phone's `/` is a folder the user chose (often "Documents"), not
   the whole phone. Wording like "Linksy on Pixel (Documents)" would match. A small
   `fs_info` answer with the folder's name is easy to add on the phone if you want it.

## 3. What the phone can't build (please don't offer these for Android)

| Feature | Why not |
|---|---|
| **Texting from the computer** (`sms_list_threads`, `sms_list_messages`, `sms_send`, `sms_message`) | Needs READ_SMS / RECEIVE_SMS / SEND_SMS. Android's fraud protection blocks installing sideloaded apps that declare SMS permissions; Play also restricts them to default SMS apps |
| **Phone notifications on the computer**, reply, actions, dismiss (`notification_*`) | Needs a NotificationListenerService (`BIND_NOTIFICATION_LISTENER_SERVICE`), on the same install-block list, and "restricted settings" blocks enabling it for sideloaded apps |
| **The phone's own music on the computer** (`media_state` from the phone, `media_command` to it) | `MediaSessionManager.getActiveSessions` requires notification-listener access (see above) |
| **Controlling the phone from the computer** (`control` requested by the computer) | Injecting touch needs an AccessibilityService, also on the install-block list (it's what blocked v0.1.3/0.1.4). Answered with `decline_unsupported` |
| **Caller's name in `call_state`** | Would need READ_CONTACTS plus call permissions; the phone reads only the audio mode, which has no number. `contact` is always absent |
| **Browsing the whole phone** in the Files sidebar | Needs MANAGE_EXTERNAL_STORAGE ("All files access"), an alarming special permission for a sideloaded app; Android's picker won't grant Download or the root. Only one chosen folder is shared |
| **Watching the phone's clipboard** (auto sync phone → computer) | Android 10+ only lets the app on screen read the clipboard |
| **Everything with Linksy fully closed** | Without the foreground service (lock when away, or "Keep running in the background"), Android stops the app; transfers and requests then wait for the app |

If Linksy ever ships through the Play Store, the notification, media and control rows
become possible again, but each needs a Play policy declaration, and SMS only for a
default SMS app.

## 4. Not done yet on the phone (possible, just not built)

- Bluetooth LE presence (planned on both sides; needs the nearby-devices runtime
  permission, which is allowed).
- NsdManager discovery fallback for networks that drop multicast (mDNS from the core
  works on the networks tested; pairing by QR or address covers the rest).

## Changelog

- **2026-10-21** — First version: phone status up to 0.1.8+ (watching the computer's
  screen, camera switch, Accept/Decline notifications, Downloads), requests to the
  desktop (§2), and what Android won't allow (§3).
