import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/invite.dart';
import '../../ui/components.dart';
import '../../ui/sig.dart';

/// Full-screen camera that pops with the first valid Linksy invite link.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _scanner = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _done = false;
  bool _wrongCode = false;
  bool _torch = false;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final code in capture.barcodes) {
      final value = code.rawValue;
      if (value == null) continue;
      if (Invite.tryParse(value) != null) {
        _done = true;
        Navigator.of(context).pop(value);
        return;
      }
      if (!_wrongCode) setState(() => _wrongCode = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    const window = 264.0;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        leadingWidth: 72,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Center(
            child: RoundButton(
              icon: Ph.x,
              tooltip: 'Close',
              onDark: true,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
        ),
        actions: [
          RoundButton(
            icon: _torch ? PhFill.flashlight : Ph.flashlight,
            tooltip: 'Flashlight',
            onDark: true,
            onTap: () {
              _scanner.toggleTorch();
              setState(() => _torch = !_torch);
            },
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _scanner,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _CameraError(error),
          ),
          const CustomPaint(painter: _Viewfinder(window)),
          Align(
            alignment: const Alignment(0, -0.62),
            child: Text(
              'Scan the code',
              style: sora(26, weight: FontWeight.w700, color: Colors.white),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 0,
            child: SafeArea(
              minimum: const EdgeInsets.only(bottom: 24),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Container(
                  key: ValueKey(_wrongCode),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: _wrongCode
                        ? Sig.of(context).red
                        : Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(Radii.lg),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _wrongCode ? Ph.warningCircle : Ph.desktop,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          _wrongCode
                              ? 'That’s not a Linksy code. On your computer, '
                                    'open Linksy → Pair with QR Code.'
                              : 'On your computer, open Linksy and choose '
                                    '“Pair with QR Code”.',
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.35,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dims everything but a rounded window, with bright corners.
class _Viewfinder extends CustomPainter {
  const _Viewfinder(this.window);

  final double window;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: window,
      height: window,
    );
    final hole = RRect.fromRectAndRadius(rect, const Radius.circular(32));
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(hole),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );

    final corner = Paint()
      ..color = Sig.cyan
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    const r = 32.0;
    const arm = 28.0;
    final l = rect.left, t = rect.top, rt = rect.right, b = rect.bottom;
    // Each corner: a straight run, the rounded corner, another run.
    final corners = Path()
      ..moveTo(l, t + r + arm)
      ..lineTo(l, t + r)
      ..arcToPoint(Offset(l + r, t), radius: const Radius.circular(r))
      ..lineTo(l + r + arm, t)
      ..moveTo(rt - r - arm, t)
      ..lineTo(rt - r, t)
      ..arcToPoint(Offset(rt, t + r), radius: const Radius.circular(r))
      ..lineTo(rt, t + r + arm)
      ..moveTo(rt, b - r - arm)
      ..lineTo(rt, b - r)
      ..arcToPoint(Offset(rt - r, b), radius: const Radius.circular(r))
      ..lineTo(rt - r - arm, b)
      ..moveTo(l + r + arm, b)
      ..lineTo(l + r, b)
      ..arcToPoint(Offset(l, b - r), radius: const Radius.circular(r))
      ..lineTo(l, b - r - arm);
    canvas.drawPath(corners, corner);
  }

  @override
  bool shouldRepaint(_Viewfinder old) => old.window != window;
}

class _CameraError extends StatelessWidget {
  const _CameraError(this.error);

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Ph.cameraSlash, color: Colors.white70, size: 48),
            const SizedBox(height: 16),
            Text(
              denied
                  ? 'Linksy needs the camera to scan the pairing code. '
                        'Allow it in the system settings, or pair by address.'
                  : 'The camera isn’t available.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
