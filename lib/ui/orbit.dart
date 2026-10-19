import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/models.dart';
import 'components.dart';
import 'sig.dart';

/// This phone at the center and every device on an orbit by how close it is:
/// connected on the inner one (with a live beam), nearby in the middle, away
/// on the outside. Unpaired devices nearby are dashed outlines with a plus.
class OrbitView extends StatefulWidget {
  const OrbitView({
    super.key,
    required this.devices,
    required this.onDevice,
    required this.onPair,
    this.height = 330,
  });

  final List<DeviceView> devices;
  final ValueChanged<DeviceView> onDevice;
  final ValueChanged<DeviceView> onPair;
  final double height;

  @override
  State<OrbitView> createState() => _OrbitViewState();
}

/// Orbit radius as a fraction of the panel's half-size.
const _orbits = [0.64, 0.84, 1.0];

int _orbitOf(DeviceView v) => !v.trusted
    ? 1
    : switch (v.presence) {
        Presence.connected => 0,
        Presence.nearby => 1,
        Presence.notNearby => 2,
      };

class _OrbitViewState extends State<OrbitView>
    with SingleTickerProviderStateMixin {
  late final _t = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    loopUnlessReduced(context, _t);
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final size = Size(box.maxWidth, widget.height);
      final center = Offset(size.width / 2, size.height / 2 + 6);
      final rx = size.width / 2 - 44;
      final ry = size.height / 2 - 40;

      // Spread each orbit's devices evenly, each orbit turned a little
      // differently so labels on neighbouring orbits don't stack.
      final byOrbit = <int, List<DeviceView>>{};
      for (final v in widget.devices) {
        byOrbit.putIfAbsent(_orbitOf(v), () => []).add(v);
      }
      // Inner orbits first; each device takes the free spot on its orbit
      // farthest from those already placed, starting from a preferred angle,
      // so names never pile up.
      final placed = <(DeviceView, Offset, int)>[];
      for (final orbit in byOrbit.keys.toList()..sort()) {
        final views = byOrbit[orbit]!
          ..sort((a, b) => a.device.id.compareTo(b.device.id));
        final f = _orbits[orbit];
        Offset at(double a) =>
            center + Offset(cos(a) * rx * f, sin(a) * ry * f);
        for (final v in views) {
          final preferred = [-0.3, -2.5, 2.3][orbit];
          var best = preferred;
          var bestScore = -1.0;
          for (var k = 0; k < 24; k++) {
            final a = preferred + k * pi / 12;
            final p = at(a);
            // Names hang below orbs: weigh vertical closeness double.
            // This phone at the center counts as taken too.
            final score = [center, for (final e in placed) e.$2]
                .map((q) {
                  final d = q - p;
                  return sqrt(d.dx * d.dx + 4 * d.dy * d.dy);
                })
                .reduce(min);
            if (score > bestScore + 1) {
              best = a;
              bestScore = score;
            }
          }
          placed.add((v, at(best), orbit));
        }
      }
      final linked = [
        for (final (v, p, _) in placed)
          if (v.trusted && v.connected) p,
      ];

      return SizedBox(
        width: size.width,
        height: size.height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _OrbitPainter(
                    t: _t,
                    center: center,
                    rx: rx,
                    ry: ry,
                    linked: linked,
                  ),
                ),
              ),
            ),
            Positioned(
              left: center.dx - 34,
              top: center.dy - 34,
              child: const _Me(),
            ),
            for (final (v, p, orbit) in placed)
              Positioned(
                left: p.dx - 50,
                top: p.dy - (orbit == 0 ? 30 : 26),
                width: 100,
                child: _Body(
                  view: v,
                  onTap: () =>
                      v.trusted ? widget.onDevice(v) : widget.onPair(v),
                  size: orbit == 0 ? 52 : 44,
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _Me extends StatelessWidget {
  const _Me();

  @override
  Widget build(BuildContext context) => Container(
    width: 68,
    height: 68,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white,
      boxShadow: [
        BoxShadow(
          color: Colors.white.withValues(alpha: 0.45),
          blurRadius: 32,
          spreadRadius: 2,
        ),
      ],
    ),
    child: const Center(child: LinksyMark(size: 40)),
  );
}

class _Body extends StatelessWidget {
  const _Body({required this.view, required this.onTap, required this.size});

  final DeviceView view;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final d = view.device;
    final away = view.trusted && view.presence == Presence.notNearby;
    return Pressable(
      onTap: onTap,
      scale: 0.9,
      semanticLabel: view.trusted
          ? '${d.name}, ${presenceLabel(view.presence)}'
          : 'Pair with ${d.name}',
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (view.trusted)
              Orb(
                device: d,
                size: size,
                presence: view.presence,
                glow: view.connected,
                onBlue: true,
              )
            else
              _Unpaired(size: size),
            const SizedBox(height: 6),
            Text(
              d.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: sora(
                12,
                weight: FontWeight.w600,
                color: Colors.white.withValues(alpha: away ? 0.45 : 0.95),
                spacing: 0,
              ),
            ),
            if (!view.trusted)
              Text(
                'Tap to pair',
                style: TextStyle(
                  fontFamily: Sig.body,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: Sig.cyanLight,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Unpaired extends StatelessWidget {
  const _Unpaired({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _DashedCircle(color: Colors.white.withValues(alpha: 0.85)),
    child: SizedBox.square(
      dimension: size,
      child: Icon(PhBold.plus, color: Colors.white, size: size * 0.4),
    ),
  );
}

class _DashedCircle extends CustomPainter {
  _DashedCircle({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final r = size.shortestSide / 2 - 1;
    const dashes = 16;
    for (var i = 0; i < dashes; i++) {
      final a = i * 2 * pi / dashes;
      canvas.drawArc(
        Rect.fromCircle(center: size.center(Offset.zero), radius: r),
        a,
        pi / dashes,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedCircle old) => old.color != color;
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter({
    required this.t,
    required this.center,
    required this.rx,
    required this.ry,
    required this.linked,
  }) : super(repaint: t);

  final Animation<double> t;
  final Offset center;
  final double rx;
  final double ry;

  /// Connected devices, which get a beam from this phone.
  final List<Offset> linked;

  @override
  void paint(Canvas canvas, Size size) {
    // A glow behind this phone.
    canvas.drawCircle(
      center,
      ry * 0.9,
      Paint()
        ..shader = ui.Gradient.radial(center, ry * 0.9, [
          Sig.cyanLight.withValues(alpha: 0.28),
          Sig.cyanLight.withValues(alpha: 0),
        ]),
    );

    // The orbits.
    for (var i = 0; i < _orbits.length; i++) {
      final f = _orbits[i];
      final rect = Rect.fromCenter(
        center: center,
        width: rx * 2 * f,
        height: ry * 2 * f,
      );
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.26 - i * 0.05);
      if (i < _orbits.length - 1) {
        canvas.drawOval(rect, paint);
      } else {
        const dashes = 72;
        for (var k = 0; k < dashes; k += 2) {
          canvas.drawArc(
            rect,
            k * 2 * pi / dashes,
            2 * pi / dashes,
            false,
            paint,
          );
        }
      }
    }

    // A wave going out from this phone, like the mark's arcs.
    final p = t.value;
    final wave = Rect.fromCenter(
      center: center,
      width: rx * 2 * (0.25 + 0.85 * p),
      height: ry * 2 * (0.25 + 0.85 * p),
    );
    canvas.drawOval(
      wave,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Sig.cyanLight.withValues(alpha: 0.5 * (1 - p)),
    );

    // Beams to connected devices, a pulse travelling along each.
    for (final target in linked) {
      final mid = Offset.lerp(center, target, 0.5)!;
      final normal =
          Offset(-(target.dy - center.dy), target.dx - center.dx) /
          (target - center).distance;
      final control = mid + normal * 22;
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..quadraticBezierTo(control.dx, control.dy, target.dx, target.dy);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..shader = ui.Gradient.linear(center, target, [
            Colors.white,
            Sig.cyanLight,
          ]),
      );
      final metric = path.computeMetrics().first;
      final at = metric.getTangentForOffset(metric.length * ((p * 2) % 1));
      if (at != null) {
        canvas.drawCircle(at.position, 3.5, Paint()..color = Colors.white);
        canvas.drawCircle(
          at.position,
          8,
          Paint()..color = Sig.cyanLight.withValues(alpha: 0.35),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_OrbitPainter old) =>
      old.center != center ||
      old.rx != rx ||
      old.ry != ry ||
      old.linked.length != linked.length ||
      !Iterable.generate(linked.length)
          .every((i) => old.linked[i] == linked[i]);
}
