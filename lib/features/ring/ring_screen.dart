import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/scope.dart';
import '../../core/models.dart';
import '../../ui/components.dart';
import '../../ui/l10n.dart';
import '../../ui/sig.dart';

/// "Find my phone": full screen while it rings, one big "Found it". Closes by
/// itself when the computer stops it or after 30 seconds.
class RingScreen extends StatefulWidget {
  const RingScreen({super.key, required this.from});

  final DeviceInfo from;

  @override
  State<RingScreen> createState() => _RingScreenState();
}

class _RingScreenState extends State<RingScreen> {
  bool _closed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Stopped elsewhere: the controller isn't ringing anymore.
    if (LinksyScope.of(context).ringingFrom == null && !_closed) {
      _closed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
  }

  void _found() {
    LinksyScope.read(context).stopRinging();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) LinksyScope.read(context).stopRinging();
    },
    child: AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayFor(Brightness.dark),
      child: Scaffold(
        backgroundColor: Sig.blue,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
            child: Column(
              children: [
                const Spacer(),
                Container(
                  width: 132,
                  height: 132,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Sig.deep,
                  ),
                  child: const Icon(
                    PhFill.bellRinging,
                    color: Colors.white,
                    size: 64,
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  context.l10n.ringTitle,
                  textAlign: TextAlign.center,
                  style: sora(34, weight: FontWeight.w700, color: Colors.white),
                ),
                const SizedBox(height: 10),
                Text(
                  context.l10n.ringLookingFor(widget.from.name),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    height: 1.4,
                  ),
                ),
                const Spacer(),
                Pressable(
                  onTap: _found,
                  semanticLabel: context.l10n.ringFoundIt,
                  child: Container(
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      context.l10n.ringFoundIt,
                      style: sora(19, weight: FontWeight.w700, color: Sig.deep),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
