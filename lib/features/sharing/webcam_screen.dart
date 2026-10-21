import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/platform.dart';
import '../../app/scope.dart';
import '../../core/models.dart';
import '../../ui/components.dart';
import '../../ui/sig.dart';

/// The phone as a webcam, with a camera app's controls: what the computer
/// sees (tap to focus there, pinch to zoom, hold to lock exposure and
/// focus), lenses and zoom, torch, exposure, focus, white balance,
/// stabilization and stream quality. Changes apply live; the computer can
/// change them too (docs/android-app.md), and this screen follows.
class WebcamScreen extends StatefulWidget {
  const WebcamScreen({super.key, required this.share});

  final SessionStarted share;

  @override
  State<WebcamScreen> createState() => _WebcamScreenState();
}

enum _Panel { exposure, focus, color, quality }

class _WebcamScreenState extends State<WebcamScreen> {
  Map<String, Object?> _state = const {};
  int? _texture;
  StreamSubscription<(String, Map<String, Object?>)>? _changes;
  _Panel _panel = _Panel.exposure;
  bool _mirror = true;

  /// Where the last tap landed (0..1 of the picture), for the focus ring.
  Offset? _ring;
  int _ringKey = 0;
  double _pinchStart = 1;
  bool _closing = false;

  String get _id => widget.share.session;

  @override
  void initState() {
    super.initState();
    _changes = LinksyPlatform.webcamChanges.listen((change) {
      if (change.$1 == _id && mounted) setState(() => _state = change.$2);
    });
    LinksyPlatform.webcamState(_id).then((s) {
      if (s != null && mounted) setState(() => _state = s);
    });
    LinksyPlatform.webcamPreview(_id, on: true).then((t) {
      if (mounted) setState(() => _texture = t);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Stopped from the computer or the notification.
    if (!LinksyScope.of(context).sharing.containsKey(_id) && !_closing) {
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
  }

  @override
  void dispose() {
    _changes?.cancel();
    LinksyPlatform.webcamPreview(_id, on: false);
    super.dispose();
  }

  // State, as CameraShare reports it.

  T _get<T>(String key, T fallback) {
    final v = _state[key];
    if (v is T) return v;
    if (T == double && v is num) return v.toDouble() as T;
    if (T == int && v is num) return v.toInt() as T;
    return fallback;
  }

  List<T> _list<T>(String key) =>
      (_state[key] as List? ?? const []).whereType<T>().toList();

  bool get _front => _get('facing', 'back') == 'front';

  bool get _portrait => _get('orientation', 'landscape') == 'portrait';

  void _set(Map<String, Object?> controls) {
    // Show it at once; the camera's report follows.
    setState(() => _state = {..._state, ...controls});
    LinksyPlatform.webcamSet(_id, controls);
  }

  // Gestures on the picture.

  Offset _toPicture(Offset local, Size size) {
    var x = (local.dx / size.width).clamp(0.0, 1.0);
    final y = (local.dy / size.height).clamp(0.0, 1.0);
    // The phone shows the front camera mirrored; the computer gets it as is.
    if (_front && _mirror) x = 1 - x;
    return Offset(x, y);
  }

  void _tap(Offset local, Size size, {bool lock = false}) {
    final p = _toPicture(local, size);
    HapticFeedback.selectionClick();
    setState(() {
      _ring = Offset(local.dx / size.width, local.dy / size.height);
      _ringKey++;
    });
    _set({
      'focus_point': [p.dx, p.dy],
      if (_list<String>('focus_modes').contains('point')) 'focus': 'point',
      'exposure_lock': lock,
    });
  }

  void _resetFocus() {
    setState(() => _ring = null);
    _set({'focus': 'auto', 'focus_point': null, 'exposure_lock': false});
  }

  @override
  Widget build(BuildContext context) {
    final c = LinksyScope.of(context);
    final peer = widget.share.peer.name;
    return Theme(
      data: buildTheme(Brightness.dark),
      child: Builder(
        builder: (context) {
          final s = Sig.of(context);
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: overlayFor(Brightness.dark),
            child: Scaffold(
              backgroundColor: s.bg,
              body: SafeArea(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    _TopBar(
                      peer: peer,
                      onStop: () {
                        _closing = true;
                        c.stopSharing(_id);
                        Navigator.of(context).maybePop();
                      },
                    ),
                    const SizedBox(height: 14),
                    _preview(s),
                    const SizedBox(height: 14),
                    _zoomRow(s),
                    const SizedBox(height: 14),
                    _toggles(s),
                    const SizedBox(height: 18),
                    _panelTabs(s),
                    const SizedBox(height: 12),
                    _panelBody(s),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // The picture, as the computer sees it.

  Widget _preview(Sig s) {
    final w = _get('width', 1280).toDouble();
    final h = _get('height', 720).toDouble();
    final texture = _texture;
    final zoom = _get('zoom', 1.0);
    final locked = _get('exposure_lock', false);
    final focus = _get('focus', 'auto');
    return AspectRatio(
      aspectRatio: w / h,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.lg),
        child: LayoutBuilder(
          builder: (context, box) {
            final size = box.biggest;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => _tap(d.localPosition, size),
              onLongPressStart: (d) {
                HapticFeedback.mediumImpact();
                _tap(d.localPosition, size, lock: true);
              },
              onDoubleTap: _resetFocus,
              onScaleStart: (_) => _pinchStart = zoom,
              onScaleUpdate: (d) {
                if (d.pointerCount < 2) return;
                final z = (_pinchStart * d.scale).clamp(
                  _get('zoom_min', 1.0),
                  _get('zoom_max', 1.0),
                );
                _set({'zoom': (z * 10).round() / 10});
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Colors.black),
                  if (texture != null)
                    Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.diagonal3Values(
                        _front && _mirror ? -1 : 1,
                        1,
                        1,
                      ),
                      child: Texture(textureId: texture),
                    ),
                  if (_ring case final ring?)
                    _FocusRing(
                      key: ValueKey(_ringKey),
                      at: Offset(ring.dx * size.width, ring.dy * size.height),
                      locked: locked,
                    ),
                  Positioned(
                    left: 12,
                    top: 12,
                    child: Row(
                      children: [
                        const _Badge(live: true, label: 'LIVE'),
                        const SizedBox(width: 6),
                        _Badge(label: _zoomLabel(zoom)),
                        if (locked) ...[
                          const SizedBox(width: 6),
                          const _Badge(label: 'AE/AF LOCK'),
                        ],
                        if (focus == 'manual') ...[
                          const SizedBox(width: 6),
                          const _Badge(label: 'MF'),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  static String _zoomLabel(double z) {
    final r = (z * 10).round() / 10;
    return r == r.roundToDouble() ? '${r.round()}×' : '$r×';
  }

  // Lenses and zoom: chips like a camera app's, and a fine slider.

  Widget _zoomRow(Sig s) {
    final zoom = _get('zoom', 1.0);
    final presets = _list<num>('zoom_presets')
        .map((n) => n.toDouble())
        .toList();
    final current = _get('lens', '');
    final facing = _get('facing', 'back');
    // Other lenses of this facing that the zoom range doesn't reach.
    final others = (_state['lenses'] as List? ?? const [])
        .whereType<Map<Object?, Object?>>()
        .where((l) => l['facing'] == facing && l['id'] != current)
        .where(
          (l) => !presets.any(
            (p) => (p - (l['zoom'] as num).toDouble()).abs() < 0.15,
          ),
        )
        .toList();
    final min = _get('zoom_min', 1.0);
    final max = _get('zoom_max', 1.0);
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final p in presets)
              _Chip(
                label: _zoomLabel(p),
                selected: (zoom - p).abs() < 0.05,
                onTap: () => _set({'zoom': p}),
              ),
            for (final l in others)
              _Chip(
                label: _zoomLabel((l['zoom'] as num).toDouble()),
                hint: 'lens',
                selected: false,
                onTap: () => _set({'lens': l['id']}),
              ),
          ],
        ),
        if (max > min)
          Slider(
            value: zoom.clamp(min, max),
            min: min,
            max: max,
            onChanged: (v) => _set({'zoom': (v * 10).round() / 10}),
          ),
      ],
    );
  }

  // Quick toggles.

  Widget _toggles(Sig s) {
    final lenses = (_state['lenses'] as List? ?? const [])
        .whereType<Map<Object?, Object?>>();
    final canFlip =
        lenses.any((l) => l['facing'] == 'front') &&
        lenses.any((l) => l['facing'] == 'back');
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _Toggle(
          icon: Ph.cameraRotate,
          label: _front ? 'Front' : 'Back',
          on: false,
          enabled: canFlip,
          onTap: () => _set({'facing': _front ? 'back' : 'front'}),
        ),
        _Toggle(
          icon: Ph.flashlight,
          label: 'Torch',
          on: _get('torch', false),
          enabled: _get('has_torch', false),
          onTap: () => _set({'torch': !_get('torch', false)}),
        ),
        _Toggle(
          icon: Ph.lockSimple,
          label: 'Lock',
          on: _get('exposure_lock', false),
          onTap: () => _set({
            'exposure_lock': !_get('exposure_lock', false),
            'white_balance_lock': !_get('exposure_lock', false),
          }),
        ),
        _Toggle(
          icon: Ph.hand,
          label: 'Steady',
          on: _get('stabilization', false),
          enabled: _get('has_stabilization', false),
          onTap: () => _set({'stabilization': !_get('stabilization', false)}),
        ),
        _Toggle(
          icon: _portrait ? Ph.deviceMobile : Ph.monitor,
          label: _portrait ? 'Portrait' : 'Landscape',
          on: _portrait,
          onTap: () =>
              _set({'orientation': _portrait ? 'landscape' : 'portrait'}),
        ),
        _Toggle(
          icon: Ph.arrowsLeftRight,
          label: 'Mirror',
          on: _front && _mirror,
          enabled: _front,
          onTap: () => setState(() => _mirror = !_mirror),
        ),
      ],
    );
  }

  // Adjustments.

  Widget _panelTabs(Sig s) {
    Widget tab(_Panel p, String label) {
      final on = _panel == p;
      return Expanded(
        child: Pressable(
          onTap: () => setState(() => _panel = p),
          semanticLabel: label,
          child: Container(
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? Sig.blue : Colors.transparent,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
                color: on ? Colors.white : s.muted,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: s.card,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        children: [
          tab(_Panel.exposure, 'Exposure'),
          tab(_Panel.focus, 'Focus'),
          tab(_Panel.color, 'Color'),
          tab(_Panel.quality, 'Picture'),
        ],
      ),
    );
  }

  Widget _panelBody(Sig s) => SigCard(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
    child: switch (_panel) {
      _Panel.exposure => _exposurePanel(s),
      _Panel.focus => _focusPanel(s),
      _Panel.color => _colorPanel(s),
      _Panel.quality => _qualityPanel(s),
    },
  );

  Widget _exposurePanel(Sig s) {
    final min = _get('exposure_min', 0);
    final max = _get('exposure_max', 0);
    final step = _get('exposure_step', 0.0);
    final ev = _get('exposure', 0);
    if (max <= min) {
      return _Note(s, 'This camera sets exposure by itself.');
    }
    final value = ev * step;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Brightness', style: sora(15, color: s.ink)),
            const Spacer(),
            Text(
              '${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)} EV',
              style: TextStyle(color: s.muted, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        Slider(
          value: ev.toDouble().clamp(min.toDouble(), max.toDouble()),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: max - min,
          onChanged: (v) => _set({'exposure': v.round()}),
        ),
        Row(
          children: [
            Expanded(
              child: _Note(
                s,
                'Hold the picture to lock exposure and focus on a spot.',
              ),
            ),
            if (ev != 0)
              SigButton(
                label: 'Reset',
                kind: SigButtonKind.quiet,
                height: 36,
                onTap: () => _set({'exposure': 0}),
              ),
          ],
        ),
      ],
    );
  }

  Widget _focusPanel(Sig s) {
    final modes = _list<String>('focus_modes');
    final focus = _get('focus', 'auto');
    if (modes.length <= 1) {
      return _Note(s, 'This camera has fixed focus.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            _Chip(label: 'Auto', selected: focus == 'auto', onTap: _resetFocus),
            if (modes.contains('point'))
              _Chip(
                label: 'Tapped spot',
                selected: focus == 'point',
                onTap: () => _set({
                  'focus': 'point',
                  'focus_point': [0.5, 0.5],
                }),
              ),
            if (modes.contains('manual'))
              _Chip(
                label: 'Manual',
                selected: focus == 'manual',
                onTap: () => _set({'focus': 'manual'}),
              ),
          ],
        ),
        if (focus == 'manual') ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Text('Far', style: TextStyle(color: s.muted, fontSize: 12.5)),
              Expanded(
                child: Slider(
                  value: _get('focus_distance', 0.0).clamp(0.0, 1.0),
                  onChanged: (v) => _set({'focus_distance': v}),
                ),
              ),
              Text('Near', style: TextStyle(color: s.muted, fontSize: 12.5)),
            ],
          ),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _Note(
              s,
              'Tap the picture to focus there; double-tap to go back to auto.',
            ),
          ),
      ],
    );
  }

  Widget _colorPanel(Sig s) {
    const names = {
      'auto': 'Auto',
      'daylight': 'Daylight',
      'cloudy': 'Cloudy',
      'shade': 'Shade',
      'incandescent': 'Warm light',
      'fluorescent': 'Office light',
    };
    final modes = _list<String>('white_balances');
    final wb = _get('white_balance', 'auto');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('White balance', style: sora(15, color: s.ink)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in modes)
              _Chip(
                label: names[m] ?? m,
                selected: wb == m,
                onTap: () => _set({'white_balance': m}),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _Note(
                s,
                'Lock keeps the colors from shifting as the light changes.',
              ),
            ),
            Switch(
              value: _get('white_balance_lock', false),
              onChanged: (v) => _set({'white_balance_lock': v}),
            ),
          ],
        ),
      ],
    );
  }

  Widget _qualityPanel(Sig s) {
    final q = _get('quality', 'standard');
    Widget option(String id, String title, String detail) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Pressable(
        onTap: () => _set({'quality': id}),
        semanticLabel: title,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: q == id ? Sig.blue : s.raised,
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: q == id ? Colors.white : s.ink,
                      ),
                    ),
                    Text(
                      detail,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: q == id ? Colors.white70 : s.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (q == id)
                const Icon(PhBold.check, color: Colors.white, size: 18),
            ],
          ),
        ),
      ),
    );
    final w = _get('width', 1280);
    final h = _get('height', 720);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Orientation', style: sora(15, color: s.ink)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _Chip(
                label: 'Landscape',
                selected: !_portrait,
                onTap: () => _set({'orientation': 'landscape'}),
              ),
            ),
            Expanded(
              child: _Chip(
                label: 'Portrait',
                selected: _portrait,
                onTap: () => _set({'orientation': 'portrait'}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _Note(
          s,
          _portrait
              ? 'Hold the phone upright. The picture stays upright, with bars '
                    'at the sides.'
              : 'Hold the phone sideways. The picture fills the frame and '
                    'stays upright either way round.',
        ),
        const SizedBox(height: 16),
        Text('Quality', style: sora(15, color: s.ink)),
        const SizedBox(height: 10),
        option('saver', 'Data saver', '2 Mbps · for busy Wi-Fi'),
        option('standard', 'Standard', '4 Mbps · sharp for video calls'),
        option('high', 'High', '8 Mbps · the most detail'),
        _Note(s, '$w×$h at 30 fps, H.264. Changes apply live.'),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.peer, required this.onStop});

  final String peer;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    return Row(
      children: [
        RoundButton(
          icon: Ph.arrowLeft,
          tooltip: 'Back',
          onTap: () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Webcam', style: sora(20, color: s.ink)),
              Text(
                'What $peer sees',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: s.muted, fontSize: 13),
              ),
            ],
          ),
        ),
        SigButton(
          label: 'Stop',
          kind: SigButtonKind.danger,
          height: 40,
          onTap: onStop,
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, this.live = false});

  final String label;
  final bool live;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xB30A1024),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (live) ...[
          const PulseDot(color: Color(0xFFFF5C72), size: 6),
          const SizedBox(width: 5),
        ],
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
      ],
    ),
  );
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.hint,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Pressable(
        onTap: onTap,
        semanticLabel: hint == null ? label : '$label $hint',
        // As wide as its label (a row of chips), or as its slot if given one.
        child: IntrinsicWidth(
          child: Container(
            constraints: const BoxConstraints(minWidth: 48),
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? Sig.blue : s.card,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
                color: selected ? Colors.white : s.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.icon,
    required this.label,
    required this.on,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final bool on;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: Pressable(
        onTap: enabled ? onTap : null,
        semanticLabel: label,
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? Sig.blue : s.card,
              ),
              child: Icon(icon, size: 22, color: on ? Colors.white : s.ink),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: on ? s.ink : s.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Where the camera focuses: a square that settles, cyan while locked.
class _FocusRing extends StatelessWidget {
  const _FocusRing({super.key, required this.at, required this.locked});

  final Offset at;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    const size = 72.0;
    return Positioned(
      left: at.dx - size / 2,
      top: at.dy - size / 2,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 1.35, end: 1),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              border: Border.all(
                color: locked ? Sig.cyan : Colors.white,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: Center(
              child: Transform.rotate(
                angle: math.pi / 4,
                child: Container(
                  width: 6,
                  height: 6,
                  color: locked ? Sig.cyan : Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.s, this.text);

  final Sig s;
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(color: s.muted, fontSize: 12.5, height: 1.4));
}
