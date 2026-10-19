import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/scope.dart';
import '../../core/invite.dart';
import '../../core/linksy_node.dart';
import '../../core/models.dart';
import '../../ui/components.dart';
import '../../ui/sig.dart';
import 'scan_screen.dart';

/// "Add a device": the QR scanner first, pairing by address as the fallback.
Future<void> showAddDevice(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  builder: (sheet) {
    final s = Sig.of(sheet);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add a device', style: sora(24, color: s.ink)),
            const SizedBox(height: 6),
            Text(
              'On the other device, open Linksy and choose “Pair with QR '
              'Code”.',
              style: TextStyle(color: s.muted, fontSize: 14.5, height: 1.4),
            ),
            const SizedBox(height: 22),
            _Option(
              icon: PhBold.scan,
              title: 'Scan QR code',
              caption: 'Fastest. Nothing to type.',
              primary: true,
              onTap: () {
                Navigator.of(sheet).pop();
                scanAndPair(context);
              },
            ),
            const SizedBox(height: 10),
            _Option(
              icon: Ph.network,
              title: 'Pair by address',
              caption: 'When the other device can’t be found.',
              onTap: () {
                Navigator.of(sheet).pop();
                pairByAddress(context);
              },
            ),
          ],
        ),
      ),
    );
  },
);

class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.title,
    required this.caption,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String title;
  final String caption;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    final fg = primary ? Colors.white : s.ink;
    final content = Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: primary
                ? Colors.white.withValues(alpha: 0.16)
                : Sig.blue.withValues(alpha: 0.1),
          ),
          child: Icon(icon, color: primary ? Colors.white : Sig.blue),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: sora(17, color: fg)),
              Text(
                caption,
                style: TextStyle(
                  fontSize: 13,
                  color: primary
                      ? Colors.white.withValues(alpha: 0.75)
                      : s.muted,
                ),
              ),
            ],
          ),
        ),
        Icon(Ph.caretRight, color: primary ? Colors.white70 : s.faint),
      ],
    );
    if (!primary) {
      return SigCard(onTap: onTap, color: s.bg, child: content);
    }
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: Sig.sendGradient,
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        child: content,
      ),
    );
  }
}

/// Scanning is the user's consent: no code is shown unless the desktop falls
/// back to the code flow (expired or reused token), which arrives as a normal
/// pairing request.
Future<void> scanAndPair(BuildContext context) async {
  final c = LinksyScope.read(context);
  final uri = await Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) => const ScanScreen(),
      fullscreenDialog: true,
    ),
  );
  final invite = uri == null ? null : Invite.tryParse(uri);
  if (invite == null || !context.mounted) return;
  final name = invite.name.isEmpty ? shortDeviceId(invite.id) : invite.name;
  showMessage(context, 'Pairing with $name…');
  await report(context, c.pairWithInvite(uri!));
}

Future<void> pairByAddress(BuildContext context) async {
  final c = LinksyScope.read(context);
  final address = await showDialog<String>(
    context: context,
    builder: (_) => const _AddressDialog(),
  );
  if (address == null || address.isEmpty || !context.mounted) return;
  await report(context, c.pairAddress(address));
}

class _AddressDialog extends StatefulWidget {
  const _AddressDialog();

  @override
  State<_AddressDialog> createState() => _AddressDialogState();
}

class _AddressDialogState extends State<_AddressDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_text.text.trim());

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(
              child: IconCircle(icon: Ph.network, color: Sig.blue, size: 56),
            ),
            const SizedBox(height: 16),
            Text(
              'Pair by address',
              textAlign: TextAlign.center,
              style: sora(21, color: s.ink),
            ),
            const SizedBox(height: 6),
            Text(
              'It’s in Linksy’s Preferences on the other device.',
              textAlign: TextAlign.center,
              style: TextStyle(color: s.muted),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _text,
              autofocus: true,
              style: sora(18, weight: FontWeight.w500, color: s.ink),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F.:\[\]]')),
              ],
              decoration: const InputDecoration(hintText: '192.168.1.20'),
              onSubmitted: (_) => _submit(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 20),
              child: Text(
                'Port $defaultPort unless you add another.',
                style: TextStyle(fontSize: 12.5, color: s.faint),
              ),
            ),
            SigButton(label: 'Pair', expand: true, onTap: _submit),
            SigButton(
              label: 'Cancel',
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

/// Both screens show the same code; both users confirm (§4.3, §4.4).
class PairingDialog extends StatelessWidget {
  const PairingDialog({super.key, required this.request});

  final PairingRequest request;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    final name = request.device.name;
    final digits = request.code.padLeft(6, '0');
    final me = LinksyScope.read(context).node.info;
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 28, 22, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Handshake(me: me, other: request.device),
            const SizedBox(height: 20),
            Text(
              request.incoming ? '$name wants to pair' : 'Pair with $name',
              textAlign: TextAlign.center,
              style: sora(21, color: s.ink),
            ),
            const SizedBox(height: 6),
            Text(
              'Both screens should show this code.',
              textAlign: TextAlign.center,
              style: TextStyle(color: s.muted),
            ),
            const SizedBox(height: 22),
            Semantics(
              label: 'Code ${formatPairingCode(digits)}',
              excludeSemantics: true,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 6; i++) ...[
                    if (i == 3)
                      Container(
                        width: 10,
                        height: 3,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          color: s.line,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      )
                    else if (i != 0)
                      const SizedBox(width: 6),
                    _Digit(digits[i]),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 26),
            SigButton(
              label: 'Codes match',
              icon: PhBold.check,
              expand: true,
              onTap: () => _answer(context, true),
            ),
            SigButton(
              label: 'Decline',
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
    Navigator.of(context).pop();
    await c.respond(request.request, accept: accept);
  }
}

/// This phone and the other device, joined by the mark's two arcs.
class _Handshake extends StatelessWidget {
  const _Handshake({required this.me, required this.other});

  final DeviceInfo me;
  final DeviceInfo other;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 64,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: Sig.sendGradient,
          ),
          child: const Icon(Ph.deviceMobile, color: Colors.white, size: 26),
        ),
        const SizedBox(
          width: 70,
          height: 40,
          child: CustomPaint(painter: _Arcs()),
        ),
        Orb(device: other, size: 56),
      ],
    ),
  );
}

class _Arcs extends CustomPainter {
  const _Arcs();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    for (final (r, color, start) in [
      (14.0, Sig.blue, pi),
      (9.0, Sig.cyan, 0.0),
    ]) {
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round;
      final dx = start == 0 ? 8.0 : -8.0;
      canvas.drawArc(
        Rect.fromCircle(center: c + Offset(dx, 0), radius: r),
        start - pi / 3.2,
        pi / 1.6,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_Arcs old) => false;
}

class _Digit extends StatelessWidget {
  const _Digit(this.digit);

  final String digit;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    return Container(
      width: 36,
      height: 50,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Sig.blue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Text(
        digit,
        style: sora(
          26,
          weight: FontWeight.w700,
          color: s.ink,
        ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      ),
    );
  }
}
