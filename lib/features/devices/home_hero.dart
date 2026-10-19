import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app/linksy_controller.dart';
import '../../core/models.dart';
import '../../ui/components.dart';
import '../../ui/orbit.dart';
import '../../ui/sig.dart';
import '../settings/settings_screen.dart';

/// The top of home: what's going on in one line, the orbit, and the counts.
class HomeHero extends StatelessWidget {
  const HomeHero({
    super.key,
    required this.controller,
    required this.onDevice,
    required this.onPair,
  });

  final LinksyController controller;
  final ValueChanged<DeviceView> onDevice;
  final ValueChanged<DeviceView> onPair;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    final c = controller;
    final name = c.settings?.name ?? c.node.info.name;
    final paired = c.paired;
    final linked = paired.where((d) => d.connected).toList();
    final near = paired.where((d) => d.nearby && !d.connected).toList();
    final away = paired.length - linked.length - near.length;
    const radius = BorderRadius.vertical(bottom: Radius.circular(40));

    return ClipRRect(
      borderRadius: radius,
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: s.hero),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _Backdrop(deep: s.heroBottom)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Wordmark(onBlue: true),
                      const Spacer(),
                      RoundButton(
                        icon: Ph.gearSix,
                        tooltip: 'Settings',
                        onDark: true,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SettingsScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Text(
                    _headline(paired, linked, near),
                    style: sora(
                      29,
                      weight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Transform.translate(
                        offset: const Offset(-5, 0),
                        child: const PulseDot(color: Sig.cyanLight, size: 7),
                      ),
                      Expanded(
                        child: Text(
                          '$name is visible on this Wi-Fi',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                    ],
                  ),
                  OrbitView(
                    devices: [...paired, ...c.unpaired],
                    onDevice: onDevice,
                    onPair: onPair,
                    height: 300,
                  ),
                  if (paired.isNotEmpty)
                    _Counts(
                      linked: linked.length,
                      near: near.length,
                      away: away,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// What matters most right now, in a few words.
  static String _headline(
    List<DeviceView> paired,
    List<DeviceView> linked,
    List<DeviceView> near,
  ) {
    if (paired.isEmpty) return 'Looking for\nyour devices';
    if (linked.length == 1) return 'Linked to\n${linked.single.device.name}';
    if (linked.length > 1) return 'Linked to\n${linked.length} devices';
    if (near.length == 1) return '${near.single.device.name}\nis nearby';
    if (near.length > 1) return '${near.length} devices\nare nearby';
    return 'Your devices\nare away';
  }
}

/// Linked · Nearby · Away on a glass panel.
class _Counts extends StatelessWidget {
  const _Counts({required this.linked, required this.near, required this.away});

  final int linked;
  final int near;
  final int away;

  @override
  Widget build(BuildContext context) {
    Widget cell(int n, String label, Color color) => Expanded(
      child: Column(
        children: [
          Text(
            '$n',
            style: sora(24, weight: FontWeight.w700, color: color),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
    Widget divider() => Container(
      width: 1,
      height: 30,
      color: Colors.white.withValues(alpha: 0.16),
    );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Row(
        children: [
          cell(linked, 'Linked', Sig.cyanLight),
          divider(),
          cell(near, 'Nearby', Colors.white),
          divider(),
          cell(away, 'Away', Colors.white.withValues(alpha: 0.55)),
        ],
      ),
    );
  }
}

/// Light blooming from two corners, for depth.
class _Backdrop extends CustomPainter {
  const _Backdrop({required this.deep});

  final Color deep;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    void bloom(Offset c, double r, Color color) => canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.radial(c, r, [
          color,
          color.withValues(alpha: 0),
        ]),
    );
    bloom(
      Offset(w * 0.95, h * 0.05),
      w * 0.75,
      Sig.cyanLight.withValues(alpha: 0.28),
    );
    bloom(Offset(w * 0.0, h * 0.95), w * 0.9, deep.withValues(alpha: 0.65));
  }

  @override
  bool shouldRepaint(_Backdrop old) => old.deep != deep;
}
