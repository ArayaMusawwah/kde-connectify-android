import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/models.dart';
import 'format.dart';
import 'icons.dart';
import 'sig.dart';

export 'icons.dart';

/// Shrinks a little while pressed, instead of an ink ripple.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.97,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final String? semanticLabel;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      button: enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapUp: enabled ? (_) => _set(false) : null,
        onTapCancel: enabled ? () => _set(false) : null,
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                widget.onTap!();
              }
            : null,
        child: AnimatedScale(
          scale: _down ? widget.scale : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}

/// White (or ink) surface with a hairline border.
class SigCard extends StatelessWidget {
  const SigCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.radius = Radii.lg,
    this.color,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final double radius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? s.card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: s.line),
      ),
      child: child,
    );
    return onTap == null ? card : Pressable(onTap: onTap, child: card);
  }
}

enum SigButtonKind { primary, secondary, quiet, danger }

class SigButton extends StatelessWidget {
  const SigButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.kind = SigButtonKind.primary,
    this.expand = false,
    this.height = 54,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final SigButtonKind kind;
  final bool expand;
  final double height;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    final fg = switch (kind) {
      SigButtonKind.primary || SigButtonKind.danger => Colors.white,
      SigButtonKind.secondary => s.ink,
      SigButtonKind.quiet => Sig.blue,
    };
    final decoration = switch (kind) {
      SigButtonKind.primary => BoxDecoration(
        gradient: Sig.sendGradient,
        borderRadius: BorderRadius.circular(99),
        boxShadow: [
          BoxShadow(
            color: Sig.blue.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      SigButtonKind.danger => BoxDecoration(
        color: s.red,
        borderRadius: BorderRadius.circular(99),
      ),
      SigButtonKind.secondary => BoxDecoration(
        color: s.card,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: s.line, width: 1.5),
      ),
      SigButtonKind.quiet => const BoxDecoration(),
    };
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, color: fg, size: 20),
          const SizedBox(width: 10),
        ],
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: Sig.body,
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
              color: fg,
              letterSpacing: -0.1,
            ),
          ),
        ),
      ],
    );
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Pressable(
        onTap: onTap,
        semanticLabel: label,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: decoration,
          child: ExcludeSemantics(child: content),
        ),
      ),
    );
  }
}

/// A round hairline button for top bars.
class RoundButton extends StatelessWidget {
  const RoundButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.onDark = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String tooltip;

  /// White on the ink hero panels.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    return Tooltip(
      message: tooltip,
      child: Pressable(
        onTap: onTap,
        scale: 0.9,
        semanticLabel: tooltip,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: onDark ? Colors.white.withValues(alpha: 0.1) : s.card,
            border: Border.all(
              color: onDark ? Colors.white.withValues(alpha: 0.14) : s.line,
            ),
          ),
          child: Icon(icon, size: 20, color: onDark ? Colors.white : s.ink),
        ),
      ),
    );
  }
}

/// "DEVICES  3": small caps above a group.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
      child: Row(
        children: [
          Text(
            text.toUpperCase(),
            style: TextStyle(
              fontFamily: Sig.body,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.4,
              color: s.muted,
            ),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

Color presenceColor(Sig s, Presence p) => switch (p) {
  Presence.connected => Sig.cyan,
  Presence.nearby => s.mint,
  Presence.notNearby => s.faint,
};

String presenceLabel(Presence p) => switch (p) {
  Presence.connected => 'Connected',
  Presence.nearby => 'Nearby',
  Presence.notNearby => 'Not nearby',
};

/// A device as a glowing orb in its own hue, initials in Sora. Its presence
/// is the ring: cyan when connected, mint when nearby, none when away (and
/// the orb dims).
class Orb extends StatelessWidget {
  const Orb({
    super.key,
    required this.device,
    this.size = 52,
    this.presence,
    this.glow = false,
  });

  final DeviceInfo device;
  final double size;
  final Presence? presence;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    final hue = deviceHue(device.id);
    final away = presence == Presence.notNearby;
    final hsl = HSLColor.fromColor(hue);
    final light = hsl.withLightness(min(1, hsl.lightness + 0.14)).toColor();
    final dark = hsl.withLightness(max(0, hsl.lightness - 0.2)).toColor();
    final ring = presence == null || away ? null : presenceColor(s, presence!);
    final ringWidth = max(2.0, size * 0.045);

    Widget orb = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.35, -0.45),
          radius: 1.05,
          colors: [light, hue, dark],
          stops: const [0, 0.55, 1],
        ),
        boxShadow: glow && !away
            ? [
                BoxShadow(
                  color: hue.withValues(alpha: 0.5),
                  blurRadius: size * 0.5,
                  spreadRadius: -size * 0.05,
                ),
              ]
            : null,
      ),
      child: Text(
        initials(device.name),
        style: sora(
          size * 0.34,
          weight: FontWeight.w700,
          color: Colors.white,
          spacing: 0.5,
        ),
      ),
    );
    if (away) {
      orb = Opacity(
        opacity: 0.45,
        child: ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            0.5, 0.4, 0.1, 0, 0, //
            0.3, 0.6, 0.1, 0, 0, //
            0.3, 0.4, 0.3, 0, 0, //
            0, 0, 0, 1, 0, //
          ]),
          child: orb,
        ),
      );
    }
    if (ring == null) return orb;
    return Container(
      padding: EdgeInsets.all(ringWidth + 1.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ring, width: ringWidth),
      ),
      child: orb,
    );
  }
}

/// Icon in a soft circle of its color.
class IconCircle extends StatelessWidget {
  const IconCircle({
    super.key,
    required this.icon,
    required this.color,
    this.size = 44,
    this.filled = false,
  });

  final IconData icon;
  final Color color;
  final double size;
  final bool filled;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: filled ? color : color.withValues(alpha: 0.13),
    ),
    child: Icon(icon, size: size * 0.48, color: filled ? Colors.white : color),
  );
}

IconData kindIcon(DeviceKind kind) => switch (kind) {
  DeviceKind.desktop => Ph.desktop,
  DeviceKind.laptop => Ph.laptop,
  DeviceKind.phone => Ph.deviceMobile,
  DeviceKind.tablet => Ph.deviceTablet,
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
    'svg' => Ph.fileImage,
    'mp4' || 'mov' || 'mkv' || 'webm' || 'avi' => Ph.fileVideo,
    'mp3' || 'wav' || 'flac' || 'ogg' || 'm4a' || 'opus' => Ph.fileAudio,
    'pdf' => Ph.filePdf,
    'zip' || 'tar' || 'gz' || '7z' || 'rar' => Ph.fileZip,
    'txt' || 'md' || 'doc' || 'docx' || 'odt' => Ph.fileText,
    _ => Ph.file,
  };
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

/// Mark plus the "Linksy" wordmark.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const LinksyMark(size: 30),
      const SizedBox(width: 8),
      Text(
        'Linksy',
        style: sora(
          24,
          weight: FontWeight.w700,
          color: color ?? Sig.of(context).ink,
          spacing: -0.8,
        ),
      ),
    ],
  );
}

/// Loops [controller], or holds it still when the system asks for less
/// motion.
void loopUnlessReduced(BuildContext context, AnimationController controller) {
  if (MediaQuery.disableAnimationsOf(context)) {
    controller.stop();
  } else if (!controller.isAnimating) {
    controller.repeat();
  }
}

/// A small dot that breathes, for "visible" and "looking".
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
    loopUnlessReduced(context, _controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: widget.size * 2.4,
    child: AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final p = _controller.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: widget.size * (1 + 1.4 * p),
              height: widget.size * (1 + 1.4 * p),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: 0.4 * (1 - p)),
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
