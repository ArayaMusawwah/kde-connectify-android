import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/platform.dart';
import '../../core/models.dart';
import '../../ui/components.dart';
import '../../ui/sig.dart';

/// What Linksy asks Android for, why, and a button that brings up Android's
/// own dialog (or, for remote control, its settings page). Re-reads when the
/// user comes back from Android's settings.
Future<void> showPermissions(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _PermissionsSheet(),
    );

/// Once, on a first launch on a real phone.
Future<void> showPermissionsOnce(BuildContext context) async {
  if (await LinksyPlatform.permissions() == null) return;
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('permissions_shown') ?? false) return;
  await prefs.setBool('permissions_shown', true);
  if (context.mounted) await showPermissions(context);
}

class _PermissionsSheet extends StatefulWidget {
  const _PermissionsSheet();

  @override
  State<_PermissionsSheet> createState() => _PermissionsSheetState();
}

class _PermissionsSheetState extends State<_PermissionsSheet>
    with WidgetsBindingObserver {
  ({bool notifications, bool camera, bool control})? _state;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _read();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _read();
  }

  Future<void> _read() async {
    final state = await LinksyPlatform.permissions();
    if (mounted) setState(() => _state = state);
  }

  Future<void> _request(String name) async {
    await LinksyPlatform.requestPermission(name);
    await _read();
  }

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    final state = _state;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Permissions', style: sora(24, color: s.ink)),
            const SizedBox(height: 6),
            Text(
              'Linksy asks only for what it needs, and you can change any of '
              'these later in Settings.',
              style: TextStyle(color: s.muted, height: 1.4),
            ),
            const SizedBox(height: 20),
            _Permission(
              icon: Ph.bellRinging,
              title: 'Notifications',
              why:
                  'Shows when a computer sees your screen or uses your camera, '
                  'with a button to stop it.',
              allowed: state?.notifications,
              action: 'Allow',
              onTap: () => _request('notifications'),
            ),
            const SizedBox(height: 10),
            _Permission(
              icon: Ph.videoCamera,
              title: 'Camera',
              why:
                  'Scans the pairing QR code, and lets a computer use this '
                  'phone as a webcam when you allow it.',
              allowed: state?.camera,
              action: 'Allow',
              onTap: () => _request('camera'),
            ),
            const SizedBox(height: 10),
            _Permission(
              icon: Ph.cursorClick,
              title: 'Remote control',
              why:
                  'Lets a computer you allow tap, swipe and type on this phone '
                  'while it watches the screen. Android has no pop-up for '
                  'this: turn on “Linksy remote control” on the next screen.',
              allowed: state?.control,
              action: 'Open settings',
              onTap: LinksyPlatform.openAccessibilitySettings,
            ),
            const SizedBox(height: 20),
            SigButton(
              label: 'Done',
              kind: SigButtonKind.secondary,
              expand: true,
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

class _Permission extends StatelessWidget {
  const _Permission({
    required this.icon,
    required this.title,
    required this.why,
    required this.allowed,
    required this.action,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String why;
  final bool? allowed;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    return SigCard(
      color: s.bg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconCircle(icon: icon, color: Sig.blue, size: 42),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: sora(16, color: s.ink)),
                const SizedBox(height: 4),
                Text(
                  why,
                  style: TextStyle(fontSize: 13, color: s.muted, height: 1.4),
                ),
                const SizedBox(height: 12),
                if (allowed == true)
                  Row(
                    children: [
                      const Icon(PhBold.check, size: 16, color: Sig.blue),
                      const SizedBox(width: 6),
                      Text(
                        'Allowed',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: s.ink,
                        ),
                      ),
                    ],
                  )
                else
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SigButton(
                      label: action,
                      height: 40,
                      onTap: allowed == null ? null : onTap,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A computer asked to control this phone while remote control is off: the
/// request was declined as unsupported; this says how to turn it on.
class ControlSetupDialog extends StatelessWidget {
  const ControlSetupDialog({super.key, required this.from});

  final DeviceInfo from;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(
              child: IconCircle(
                icon: Ph.cursorClick,
                color: Sig.blue,
                size: 64,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '${from.name} wants to control this phone',
              textAlign: TextAlign.center,
              style: sora(21, color: s.ink, height: 1.2),
            ),
            const SizedBox(height: 8),
            Text(
              'Turn on “Linksy remote control” first: Android lets you do it '
              'only in its settings. Then ask again from ${from.name}.',
              textAlign: TextAlign.center,
              style: TextStyle(color: s.muted, height: 1.4),
            ),
            const SizedBox(height: 24),
            SigButton(
              label: 'Open settings',
              expand: true,
              onTap: () {
                Navigator.of(context).pop();
                LinksyPlatform.openAccessibilitySettings();
              },
            ),
            SigButton(
              label: 'Not now',
              kind: SigButtonKind.quiet,
              expand: true,
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
