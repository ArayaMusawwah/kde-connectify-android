import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/linksy_controller.dart';
import '../../app/platform.dart';
import '../../app/scope.dart';
import '../../core/models.dart';
import '../../ui/components.dart';
import '../../ui/sig.dart';

/// X11 keysyms the computer understands (docs/protocol.md §4.8).
abstract final class Keysym {
  static const left = 0xff51;
  static const right = 0xff53;
  static const enter = 0xff0d;
  static const backspace = 0xff08;
  static const escape = 0xff1b;
  static const f5 = 0xffc2;
}

/// This phone as a computer's touchpad, keyboard and presentation remote
/// (session kind `input`). Asks the computer when it opens; its user allows
/// it there. Going back ends it.
class RemoteScreen extends StatefulWidget {
  const RemoteScreen({super.key, required this.device});

  final DeviceInfo device;

  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

enum _Mode { touchpad, slides }

class _RemoteScreenState extends State<RemoteScreen> {
  late final LinksyController _c;
  _Mode _mode = _Mode.touchpad;
  String? _error;
  bool _asking = true;
  StreamSubscription<bool>? _volume;

  String get _id => widget.device.id;

  @override
  void initState() {
    super.initState();
    _c = LinksyScope.read(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  Future<void> _connect() async {
    setState(() {
      _asking = true;
      _error = null;
    });
    final error = await _c.startRemote(_id);
    if (!mounted) return;
    setState(() {
      _asking = false;
      _error = error;
    });
  }

  @override
  void dispose() {
    _volume?.cancel();
    LinksyPlatform.presentation(false);
    _c.stopRemote(_id);
    super.dispose();
  }

  void _send(List<Map<String, Object>> messages) {
    _c.remoteSend(_id, messages).then((ok) {
      if (!ok && mounted && _c.remotes[_id] == null) setState(() {});
    });
  }

  void _key(int keysym) => _send([
    {'type': 'key', 'keysym': keysym, 'pressed': true},
    {'type': 'key', 'keysym': keysym, 'pressed': false},
  ]);

  void _setMode(_Mode mode) {
    setState(() => _mode = mode);
    final slides = mode == _Mode.slides;
    LinksyPlatform.presentation(slides);
    _volume?.cancel();
    _volume = slides
        ? LinksyPlatform.volumeKeys.listen(
            (up) => _key(up ? Keysym.left : Keysym.right),
          )
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    final c = LinksyScope.of(context);
    final live = c.remotes.containsKey(_id);
    final name = widget.device.name;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayFor(Theme.of(context).brightness),
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
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
                          Text('Remote', style: sora(20, color: s.ink)),
                          Text(
                            name,
                            style: TextStyle(color: s.muted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (!live)
                  Expanded(
                    child: _Waiting(
                      name: name,
                      asking: _asking,
                      error: _error,
                      ended: !_asking && _error == null,
                      onRetry: _connect,
                    ),
                  )
                else ...[
                  _ModeSwitch(mode: _mode, onChanged: _setMode),
                  const SizedBox(height: 14),
                  Expanded(
                    child: _mode == _Mode.touchpad
                        ? _Touchpad(send: _send, onKey: _key)
                        : _Slides(onKey: _key),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({
    required this.name,
    required this.asking,
    required this.error,
    required this.ended,
    required this.onRetry,
  });

  final String name;
  final bool asking;
  final String? error;
  final bool ended;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    final (title, detail) = asking
        ? (
            'Allow it on $name',
            'Linksy on $name asks whether this phone may move its pointer and type.',
          )
        : error != null
        ? ('That didn’t work', error!)
        : ('The remote stopped', '$name ended it.');
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconCircle(icon: Ph.mouseSimple, color: Sig.blue, size: 72),
        const SizedBox(height: 18),
        Text(
          title,
          textAlign: TextAlign.center,
          style: sora(20, color: s.ink),
        ),
        const SizedBox(height: 8),
        Text(
          detail,
          textAlign: TextAlign.center,
          style: TextStyle(color: s.muted, height: 1.4),
        ),
        if (!asking) ...[
          const SizedBox(height: 22),
          SigButton(label: 'Try again', onTap: onRetry),
        ],
      ],
    );
  }
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.mode, required this.onChanged});

  final _Mode mode;
  final ValueChanged<_Mode> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    Widget tab(_Mode m, IconData icon, String label) {
      final on = mode == m;
      return Expanded(
        child: Pressable(
          onTap: () => onChanged(m),
          semanticLabel: label,
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: on ? Sig.blue : Colors.transparent,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: on ? Colors.white : s.muted),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: on ? Colors.white : s.muted,
                  ),
                ),
              ],
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
          tab(_Mode.touchpad, Ph.mouseSimple, 'Touchpad'),
          tab(_Mode.slides, Ph.presentation, 'Slides'),
        ],
      ),
    );
  }
}

/// One finger moves the pointer, a tap clicks, a two-finger tap right-clicks,
/// two fingers scroll. The keyboard types into whatever has focus there.
class _Touchpad extends StatefulWidget {
  const _Touchpad({required this.send, required this.onKey});

  final void Function(List<Map<String, Object>>) send;
  final void Function(int keysym) onKey;

  @override
  State<_Touchpad> createState() => _TouchpadState();
}

class _TouchpadState extends State<_Touchpad> {
  final _pointers = <int, Offset>{};
  int _maxFingers = 0;
  DateTime _downAt = DateTime.now();
  double _travel = 0;
  Offset? _scrollFrom;
  Offset _pending = Offset.zero;
  Timer? _flush;

  // The keyboard: a hidden field that always holds one placeholder, so
  // Backspace on an empty field still shows up as a change.
  static const _placeholder = '​';
  final _field = TextEditingController(text: _placeholder);
  final _focus = FocusNode();

  @override
  void dispose() {
    _flush?.cancel();
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  Offset _centroid() =>
      _pointers.values.reduce((a, b) => a + b) / _pointers.length.toDouble();

  void _down(PointerDownEvent e) {
    if (_pointers.isEmpty) {
      _downAt = DateTime.now();
      _travel = 0;
      _maxFingers = 0;
    }
    _pointers[e.pointer] = e.localPosition;
    _maxFingers = _pointers.length > _maxFingers
        ? _pointers.length
        : _maxFingers;
    if (_pointers.length >= 2) _scrollFrom = _centroid();
  }

  void _move(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _travel += e.delta.distance;
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 1 && _maxFingers == 1) {
      // Faster swipes go further, as on a laptop's touchpad.
      final speed = e.delta.distance;
      final gain = 1.4 + (speed / 12).clamp(0.0, 1.6);
      _pending += e.delta * gain;
      _flush ??= Timer(const Duration(milliseconds: 12), _sendMove);
    } else if (_pointers.length >= 2 && _scrollFrom != null) {
      final now = _centroid();
      final d = now - _scrollFrom!;
      _scrollFrom = now;
      widget.send([
        {'type': 'scroll', 'dx': -d.dx, 'dy': -d.dy, 'discrete': false},
      ]);
    }
  }

  void _sendMove() {
    _flush = null;
    if (_pending == Offset.zero) return;
    widget.send([
      {'type': 'pointer_by', 'dx': _pending.dx, 'dy': _pending.dy},
    ]);
    _pending = Offset.zero;
  }

  void _up(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.isNotEmpty) {
      if (_pointers.length >= 2) _scrollFrom = _centroid();
      return;
    }
    _scrollFrom = null;
    final quick =
        DateTime.now().difference(_downAt) < const Duration(milliseconds: 220);
    if (quick && _travel < 12) {
      _click(_maxFingers >= 2 ? 'right' : 'left');
    }
  }

  void _click(String button) {
    HapticFeedback.selectionClick();
    widget.send([
      {'type': 'button', 'button': button, 'pressed': true},
      {'type': 'button', 'button': button, 'pressed': false},
    ]);
  }

  void _typed(String value) {
    if (value.length < _placeholder.length || !value.startsWith(_placeholder)) {
      widget.onKey(Keysym.backspace);
    } else if (value.length > _placeholder.length) {
      widget.send([
        {'type': 'text', 'text': value.substring(_placeholder.length)},
      ]);
    }
    _field.value = const TextEditingValue(
      text: _placeholder,
      selection: TextSelection.collapsed(offset: _placeholder.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _down,
            onPointerMove: _move,
            onPointerUp: _up,
            onPointerCancel: _up,
            child: Container(
              decoration: BoxDecoration(
                color: s.card,
                borderRadius: BorderRadius.circular(Radii.xl),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Ph.handPointing, size: 34, color: s.faint),
                  const SizedBox(height: 10),
                  Text(
                    'Move with one finger, tap to click\n'
                    'Two fingers scroll, two-finger tap right-clicks',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: s.faint, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _PadButton(
                label: 'Left click',
                onTap: () => _click('left'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PadButton(
                label: 'Right click',
                onTap: () => _click('right'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Off screen, but focusable: it brings up the keyboard.
        SizedBox(
          height: 0,
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: _field,
              focusNode: _focus,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.send,
              onChanged: _typed,
              onSubmitted: (_) {
                widget.onKey(Keysym.enter);
                _focus.requestFocus();
              },
            ),
          ),
        ),
        SigButton(
          label: 'Keyboard',
          icon: Ph.keyboard,
          kind: SigButtonKind.secondary,
          expand: true,
          onTap: () {
            if (_focus.hasFocus) {
              _focus.unfocus();
            } else {
              _focus.requestFocus();
              SystemChannels.textInput.invokeMethod<void>('TextInput.show');
            }
          },
        ),
      ],
    );
  }
}

class _PadButton extends StatelessWidget {
  const _PadButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: s.card,
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Text(
          label,
          style: TextStyle(fontWeight: FontWeight.w600, color: s.ink),
        ),
      ),
    );
  }
}

/// Presentation remote: big Back / Next, and the volume keys do the same
/// with the phone in a pocket. The screen stays on meanwhile.
class _Slides extends StatelessWidget {
  const _Slides({required this.onKey});

  final void Function(int keysym) onKey;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: Pressable(
            onTap: () {
              HapticFeedback.lightImpact();
              onKey(Keysym.right);
            },
            semanticLabel: 'Next slide',
            child: Container(
              decoration: BoxDecoration(
                color: Sig.blue,
                borderRadius: BorderRadius.circular(Radii.xl),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Ph.caretRight, color: Colors.white, size: 56),
                  Text(
                    'Next',
                    style: sora(
                      26,
                      weight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          flex: 2,
          child: Pressable(
            onTap: () {
              HapticFeedback.lightImpact();
              onKey(Keysym.left);
            },
            semanticLabel: 'Previous slide',
            child: Container(
              decoration: BoxDecoration(
                color: s.card,
                borderRadius: BorderRadius.circular(Radii.xl),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Ph.caretLeft, color: s.ink, size: 44),
                  Text('Back', style: sora(20, color: s.ink)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _PadButton(
                label: 'Start (F5)',
                onTap: () => onKey(Keysym.f5),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PadButton(
                label: 'End (Esc)',
                onTap: () => onKey(Keysym.escape),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Volume down: next · Volume up: back. The screen stays on.',
          textAlign: TextAlign.center,
          style: TextStyle(color: s.muted, fontSize: 13),
        ),
      ],
    );
  }
}
