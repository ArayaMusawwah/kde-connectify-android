# Changelog

All notable changes to Linksy for Android. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versions follow [SemVer](https://semver.org/).

## [Unreleased]

### Added
- **Remote**: use the phone as your computer's touchpad and keyboard, or as a presentation remote (big Next/Back buttons, and the volume keys change slides).
- **Media controls**: what plays on your computer shows on its page, with play/pause and skip.
- **Lock when you walk away**: when your computer asks for it, the phone keeps telling it you're near, even with the screen off, so it locks when you leave.
- **Pause music during calls**: your computers pause while a call rings or goes on, and resume after. No phone permission needed.
- **Back up photos**: new photos from the folder you choose go to a computer's Pictures folder, per computer.
- **Browse the phone from your computer**: share one folder you choose; it shows up in the computer's Files app.
- Keep Linksy running in the background (optional), so files, backups and calls keep working with the app closed.

### Not included
- Texting from the computer and showing the phone's notifications or music there: Android blocks apps installed from outside the Play Store from asking for those permissions.

## [0.1.6] - 2026-10-20

### Added
- **Open on PC**: share a link from any app to Linksy and it opens in your computer's browser. Shared text goes to its clipboard, and shared files are sent.
- Links your computer sends open on the phone with a tap.
- **Find my phone**: your computer can make the phone ring loudly, even on silent, until you tap "Found it" (or for 30 seconds).
- **Find my computer**: a button on each computer's page makes it ring.
- Your computer shows the phone's battery level and warns you when it runs low.

### Fixed
- **Second display stays black** on some phones (realme and others): the phone now decodes whole frames, whatever way the computer slices them.

## [0.1.5] - 2026-10-19

### Fixed
- **Installs again.** Android blocked installing 0.1.3 and 0.1.4 with no way to continue: phones block apps from outside the Play Store that ask to control the phone through Accessibility. Linksy no longer asks for that.
- Linksy no longer asks for access to your photos, videos, music or storage. Sending uses Android's own file picker, and received files open without any extra permission.
- The phone could appear twice to your computer after Android restarted the app's screen.

### Changed
- **Smaller and lighter**: about a third smaller to download (9.6 MB on most phones), with no Google services or background reporting inside. QR codes are read on the phone itself.

### Removed
- Controlling the phone from your computer. Your computer now hears that this phone can't do it.

## [0.1.4] - 2026-10-19

### Fixed
- The permissions guide now shows on first launch as intended (in 0.1.3 it only opened from Settings → Permissions).

## [0.1.3] - 2026-10-19

### Added
- **Control your phone from your computer**: when your computer asks to control this phone, you can let it tap, swipe and type while it shows your screen. Turn on “Linksy remote control” once in Android's Accessibility settings; Linksy takes you there.
- **Use your phone as a second display**: when your computer asks, the phone shows one of its screens full screen in landscape. Touch to click and drag, scroll with two fingers, go back to stop.
- **Permissions, explained up front**: on first launch (and any time in Settings → Permissions), Linksy shows what it needs and why, and brings up Android's own prompt for each. If you said no before, it opens Linksy's app settings so you can still turn it on.

### Changed
- **A flat look**: solid colors, no gradients or shadows.
- Your computer now hears “this phone can't do that yet” instead of “declined” when it asks for something the phone doesn't support.

### Fixed
- **No more black bars** around your shared screen: the video keeps your screen's exact shape, and follows when you turn the phone.

## [0.1.2] - 2026-10-19

### Added
- **Share your screen**: “View Screen” in Linksy on your computer now works. Your phone asks first, then Android asks you to confirm (choose “Entire screen” to show everything). Your screen keeps showing on the computer while you use other apps.
- **Use your phone as a webcam**: “Use as Webcam” on your computer turns this phone's back camera into a camera every app on the computer can use. Hold the phone sideways for a wide picture.
- While sharing, a banner in Linksy and a notification show what's shared and with whom, with a **Stop** button. Stopping on either the phone or the computer ends it for both.
- Each share appears in the device's timeline.

### Known limits
- Controlling your phone from the computer and using it as a second display aren't available yet; those requests are declined.
- The webcam always uses the back camera for now.

## [0.1.1] - 2026-10-19

Linksy for Android **now works with your real devices**: it runs the same engine as Linksy on your computer, so they find each other on your Wi-Fi and share directly.

### Added
- **Pair for real**: scan the QR code from “Add Device” in Linksy on your computer, or open it with your phone's camera app, and the phone pairs straight away. Pairing by address with the 6-digit code works too.
- **Share both ways**: send files, your clipboard and pings to your computer, and receive them from it. Received files are saved in Linksy's folder on the phone (Android/data/app.linksy/files/Received) and open from the timeline.
- Files sent automatically from your devices (“Accept from my devices”) now show up in the timeline too.
- This phone is named after your phone the first time you open Linksy; change it in Settings.

### Fixed
- A forgotten device no longer stays in the list until something else happens.

### Known limits
- Keep Linksy open while sharing: transfers in the background come in a later release.
- Screen sharing and the phone-as-webcam requests from your computer are declined for now.

## [0.1.0] - 2026-10-19

First preview of Linksy for Android. **This preview runs on simulated devices**: it shows the app's design and flows, but it can't reach Linksy on your computer yet. Connecting to real devices comes in a following release.

### Added
- **Your devices** at a glance: which ones are nearby, connected or away, what you last shared with each, and a one-tap send button.
- **Device pages**: send files, send your clipboard or ping, and see everything shared with that device as a timeline, by day.
- **Pairing**: scan the QR code Linksy shows on your computer, pair by address, or confirm a 6-digit code on both screens.
- **Incoming files**: see who's sending what before you accept, follow progress, speed and time left, and open received files from the timeline.
- **Settings**: name this phone, accept files from your devices without asking, and stay connected for faster sharing.
- Light and dark themes, in Linksy's own colors.
