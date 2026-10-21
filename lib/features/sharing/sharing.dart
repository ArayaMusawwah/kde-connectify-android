import 'package:flutter/material.dart';

import '../../app/linksy_controller.dart';
import '../../app/platform.dart';
import '../../app/scope.dart';
import '../../core/models.dart';
import '../../ui/components.dart';
import '../../ui/sig.dart';
import 'webcam_screen.dart';

/// "Studio Desktop wants to see your screen": Allow leads on to Android's own
/// prompt (screen capture or camera permission).
class SessionRequestDialog extends StatelessWidget {
  const SessionRequestDialog({super.key, required this.request});

  final SessionRequest request;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    final name = request.from.name;
    final (icon, title, detail) = switch (request.kind) {
      SessionKind.screen => (
        Ph.screencast,
        '$name wants to see your screen',
        'Everything on this phone’s screen shows on $name until you stop. '
            'Android asks you to confirm next.',
      ),
      SessionKind.control => (
        Ph.cursorClick,
        '$name wants to control your screen',
        '$name sees this phone’s screen and can tap, swipe and type on it '
            'until you stop. Android asks you to confirm next.',
      ),
      SessionKind.camera => (
        Ph.videoCamera,
        '$name wants to use your camera',
        '$name gets this phone’s camera as a webcam until you stop. '
            'Zoom, focus, light, lenses and rotation are in Linksy while it '
            'runs.',
      ),
      SessionKind.input => (
        Ph.mouseSimple,
        '$name wants to use this phone as a touchpad',
        'Unexpected: computers don’t ask this. Don’t allow it.',
      ),
      SessionKind.microphone => (
        Ph.microphone,
        '$name wants to use your microphone',
        '$name hears this phone’s microphone until you stop, as a '
            'microphone any of its apps can use. Android asks you to confirm '
            'next.',
      ),
      SessionKind.display => (
        Ph.monitor,
        '$name wants to use this screen as a second display',
        'This phone shows a screen of $name full screen. Touch it to click '
            'and drag; scroll with two fingers. Go back to stop.',
      ),
    };
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: IconCircle(icon: icon, color: Sig.blue, size: 64),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: sora(21, color: s.ink, height: 1.2),
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(color: s.muted, height: 1.4),
            ),
            const SizedBox(height: 24),
            SigButton(
              label: 'Allow',
              expand: true,
              onTap: () => _answer(context, true),
            ),
            SigButton(
              label: 'Don’t allow',
              kind: SigButtonKind.quiet,
              expand: true,
              onTap: () => _answer(context, false),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _answer(BuildContext context, bool accept) async {
    final c = LinksyScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    final error = await c.respondSession(request, accept: accept);
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
    }
  }
}

/// Live shares at the top of home, each with Stop.
class SharingBanners extends StatelessWidget {
  const SharingBanners({super.key, required this.controller, this.deviceId});

  final LinksyController controller;

  /// Only the shares with this device (its page), else all (home).
  final String? deviceId;

  @override
  Widget build(BuildContext context) {
    final shares = controller.sharing.values
        .where((s) => deviceId == null || s.peer.id == deviceId)
        .toList();
    if (shares.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        children: [
          for (final share in shares) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _Banner(share: share, controller: controller),
            ),
            if ((share.kind == SessionKind.screen ||
                    share.kind == SessionKind.control) &&
                controller.warnShareProtections)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ProtectionHint(controller: controller),
              ),
          ],
        ],
      ),
    );
  }
}

/// Android 15 hides parts of the screen from screen sharing; some phones
/// (realme, among others) black out the whole status bar and notification
/// shade. A developer option turns that off.
class _ProtectionHint extends StatelessWidget {
  const _ProtectionHint({required this.controller});

  final LinksyController controller;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    return SigCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Ph.warningCircle, color: Sig.blue, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Top bar or notifications black on the computer? Android’s '
                  'screen share protection hides them. Turn on “Disable screen '
                  'share protections” in Developer options, then share again.',
                  style: TextStyle(fontSize: 13, color: s.muted, height: 1.35),
                ),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: controller.dismissShareHint,
                child: const Text('Got it'),
              ),
              TextButton(
                onPressed: LinksyPlatform.developerOptions,
                child: const Text('Developer options'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.share, required this.controller});

  final SessionStarted share;
  final LinksyController controller;

  @override
  Widget build(BuildContext context) {
    final name = share.peer.name;
    final (icon, text) = switch (share.kind) {
      SessionKind.control => (
        Ph.cursorClick,
        '$name is controlling your screen',
      ),
      SessionKind.camera => (Ph.videoCamera, '$name is using your camera'),
      SessionKind.microphone => (
        Ph.microphone,
        '$name is using your microphone',
      ),
      _ => (Ph.screencast, 'Sharing your screen with $name'),
    };
    final banner = Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: Sig.blue,
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Row(
        children: [
          const PulseDot(color: Sig.cyanLight, size: 8),
          const SizedBox(width: 8),
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14.5,
                  ),
                ),
                if (share.kind == SessionKind.camera)
                  const Text(
                    'Tap for camera controls',
                    style: TextStyle(color: Colors.white70, fontSize: 12.5),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (share.kind == SessionKind.camera) ...[
            Tooltip(
              message: 'Switch camera',
              child: Pressable(
                onTap: () => controller.switchCamera(share.session),
                semanticLabel: 'Switch camera',
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Sig.deep,
                  ),
                  child: const Icon(
                    Ph.cameraRotate,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Pressable(
            onTap: () => controller.stopSharing(share.session),
            semanticLabel: 'Stop sharing',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(99),
              ),
              child: const Text(
                'Stop',
                style: TextStyle(color: Sig.deep, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
    // A webcam's banner opens its controls.
    if (share.kind != SessionKind.camera) return banner;
    return Pressable(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => WebcamScreen(share: share)),
      ),
      semanticLabel: 'Camera controls',
      child: banner,
    );
  }
}
