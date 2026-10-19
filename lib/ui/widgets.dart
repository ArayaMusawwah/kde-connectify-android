import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/models.dart';
import 'format.dart';
import 'theme.dart';

/// Colored initials in the device's own color, with an optional presence dot.
class DeviceAvatar extends StatelessWidget {
  const DeviceAvatar({
    super.key,
    required this.device,
    this.size = 48,
    this.presence,
    this.ring,
  });

  final DeviceInfo device;
  final double size;
  final Presence? presence;

  /// The color behind the avatar, so the presence dot looks cut out of it.
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final scheme = deviceScheme(device.id, Theme.of(context).brightness);
    final avatar = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primaryContainer, scheme.secondaryContainer],
        ),
      ),
      child: Text(
        initials(device.name),
        style: TextStyle(
          color: scheme.onPrimaryContainer,
          fontSize: size * 0.36,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
    final p = presence;
    if (p == null) return avatar;
    final dot = max(12.0, size * 0.28);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            right: size * 0.02 - 2,
            bottom: size * 0.02 - 2,
            child: PresenceDot(presence: p, size: dot, ring: ring),
          ),
        ],
      ),
    );
  }
}

Color presenceColor(ColorScheme scheme, Presence p) => switch (p) {
  Presence.connected => scheme.primary,
  Presence.nearby => scheme.nearby,
  Presence.notNearby => scheme.outline,
};

class PresenceDot extends StatelessWidget {
  const PresenceDot({
    super.key,
    required this.presence,
    this.size = 12,
    this.ring,
  });

  final Presence presence;
  final double size;

  /// Defaults to the surface, so the dot reads as cut out of the avatar.
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: presenceColor(scheme, presence),
        shape: BoxShape.circle,
        border: Border.all(
          color: ring ?? scheme.surface,
          width: max(2, size * 0.18),
        ),
      ),
    );
  }
}

/// "● Nearby" as a small pill.
class PresencePill extends StatelessWidget {
  const PresencePill({super.key, required this.presence, this.background});

  final Presence presence;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = presenceColor(theme.colorScheme, presence);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
      decoration: BoxDecoration(
        color: background ?? color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            presenceLabel(presence),
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

String presenceLabel(Presence p) => switch (p) {
  Presence.connected => 'Connected',
  Presence.nearby => 'Nearby',
  Presence.notNearby => 'Not nearby',
};

IconData kindIcon(DeviceKind kind) => switch (kind) {
  DeviceKind.desktop => Icons.desktop_windows_rounded,
  DeviceKind.laptop => Icons.laptop_rounded,
  DeviceKind.phone => Icons.smartphone_rounded,
  DeviceKind.tablet => Icons.tablet_android_rounded,
};

IconData fileIcon(String name) {
  final dot = name.lastIndexOf('.');
  final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  return switch (ext) {
    'jpg' ||
    'jpeg' ||
    'png' ||
    'gif' ||
    'webp' ||
    'heic' ||
    'svg' => Icons.image_rounded,
    'mp4' || 'mov' || 'mkv' || 'webm' || 'avi' => Icons.movie_rounded,
    'mp3' ||
    'wav' ||
    'flac' ||
    'ogg' ||
    'm4a' ||
    'opus' => Icons.music_note_rounded,
    'pdf' => Icons.picture_as_pdf_rounded,
    'zip' || 'tar' || 'gz' || '7z' || 'rar' => Icons.folder_zip_rounded,
    'apk' => Icons.android_rounded,
    _ => Icons.insert_drive_file_rounded,
  };
}

/// Section title above a group: "Your devices  2".
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.count, this.trailing});

  final String title;
  final int? count;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 16, 10),
      child: Row(
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.2,
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '$count',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

/// Items in one group, Android settings style: large outer corners, small
/// inner ones, a hairline gap between items.
class Grouped extends StatelessWidget {
  const Grouped({
    super.key,
    required this.children,
    this.color,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final List<Widget> children;
  final Color? color;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final fill = color ?? groupFill(Theme.of(context).colorScheme);
    const outer = Radius.circular(Radii.lg);
    const inner = Radius.circular(6);
    return Padding(
      padding: padding,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 3),
            ClipRRect(
              borderRadius: BorderRadius.vertical(
                top: i == 0 ? outer : inner,
                bottom: i == children.length - 1 ? outer : inner,
              ),
              child: Material(color: fill, child: children[i]),
            ),
          ],
        ],
      ),
    );
  }
}

/// Icon in a tinted circle.
class IconBadge extends StatelessWidget {
  const IconBadge({
    super.key,
    required this.icon,
    required this.foreground,
    required this.background,
    this.size = 44,
  });

  final IconData icon;
  final Color foreground;
  final Color background;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: background, shape: BoxShape.circle),
    child: Icon(icon, color: foreground, size: size * 0.5),
  );
}

/// The "Sender" mark in Signal colors.
class LinksyMark extends StatelessWidget {
  const LinksyMark({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/brand/linksy-mark--signal.svg',
    width: size,
    height: size,
    semanticsLabel: 'Linksy',
  );
}

/// Rings spreading out from [child], for "looking for devices".
class Radar extends StatefulWidget {
  const Radar({
    super.key,
    required this.child,
    this.size = 220,
    this.color,
    this.rings = 3,
  });

  final Widget child;
  final double size;
  final Color? color;
  final int rings;

  @override
  State<Radar> createState() => _RadarState();
}

class _RadarState extends State<Radar> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
    value: 0.35,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loopUnlessReduced(context, _controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return SizedBox.square(
      dimension: widget.size,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _RadarPainter(_controller, color, widget.rings),
          child: Center(child: widget.child),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter(this.t, this.color, this.rings) : super(repaint: t);

  final Animation<double> t;
  final Color color;
  final int rings;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = size.shortestSide / 2;
    final minR = maxR * 0.3;
    for (var i = 0; i < rings; i++) {
      final p = (t.value + i / rings) % 1;
      final r = minR + (maxR - minR) * Curves.easeOut.transform(p);
      final paint = Paint()
        ..color = color.withValues(alpha: 0.22 * (1 - p))
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.color != color;
}

/// A small dot that breathes, for "visible to nearby devices".
class PulseDot extends StatefulWidget {
  const PulseDot({super.key, required this.color, this.size = 8});

  final Color color;
  final double size;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loopUnlessReduced(context, _controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: widget.size * 2.5,
    child: AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final p = _controller.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: widget.size * (1 + 1.5 * p),
              height: widget.size * (1 + 1.5 * p),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: 0.35 * (1 - p)),
              ),
            ),
            Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color,
              ),
            ),
          ],
        );
      },
    ),
  );
}

/// Loops [controller], or holds it still when the system asks for less
/// motion.
void _loopUnlessReduced(BuildContext context, AnimationController controller) {
  if (MediaQuery.disableAnimationsOf(context)) {
    controller.stop();
  } else if (!controller.isAnimating) {
    controller.repeat();
  }
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Runs a controller action and shows its error, if any. The messenger is
/// taken before waiting, so the screen may close meanwhile.
Future<void> report(BuildContext context, Future<String?> action) async {
  final messenger = ScaffoldMessenger.of(context);
  final error = await action;
  if (error == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(error)));
}
