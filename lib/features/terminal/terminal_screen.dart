import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../../app/scope.dart';
import '../../app/terminals.dart';
import '../../core/linksy_node.dart';
import '../../core/models.dart';
import '../../ui/components.dart';
import '../../ui/format.dart';
import '../../ui/sig.dart';

/// Signal's navy, with the brand's blue and cyan in the palette.
const _theme = TerminalTheme(
  cursor: Color(0xFF22C3E6),
  selection: Color(0x662563FF),
  foreground: Color(0xFFE6EBF5),
  background: Color(0xFF080D1F),
  black: Color(0xFF0A1024),
  red: Color(0xFFFF5C72),
  green: Color(0xFF3DDC84),
  yellow: Color(0xFFF5C451),
  blue: Color(0xFF5B8CFF),
  magenta: Color(0xFFC77DFF),
  cyan: Color(0xFF22C3E6),
  white: Color(0xFFE6EBF5),
  brightBlack: Color(0xFF56628A),
  brightRed: Color(0xFFFF8A9A),
  brightGreen: Color(0xFF7BEAB0),
  brightYellow: Color(0xFFFFDC85),
  brightBlue: Color(0xFF8FB0FF),
  brightMagenta: Color(0xFFDDA8FF),
  brightCyan: Color(0xFF9FE6F5),
  brightWhite: Color(0xFFFFFFFF),
  searchHitBackground: Color(0xFFF5C451),
  searchHitBackgroundCurrent: Color(0xFF3DDC84),
  searchHitForeground: Color(0xFF0A1024),
);

const _bg = Color(0xFF080D1F);
const _panel = Color(0xFF111A3A);
const _raised = Color(0xFF1A2550);
const _muted = Color(0xFF94A0C0);

/// A shell on a computer (docs/protocol.md §4.15): tabs, the terminal, a key bar
/// above the keyboard. Each open asks for the code set on the computer.
class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key, required this.deviceId});

  final String deviceId;

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  TerminalTab? _current;
  final _focus = FocusNode();
  StreamSubscription<TerminalTab>? _gone;

  @override
  void initState() {
    super.initState();
    // `exit` typed in the shell (or Close): the tab goes, and says so.
    _gone = LinksyScope.read(context).terminals.gone.listen((t) {
      if (!mounted || t.deviceId != widget.deviceId) return;
      // Nothing to type into any more: the keyboard goes too.
      if (LinksyScope.read(context).terminals.of(widget.deviceId).isEmpty) {
        _focus.unfocus();
      }
      showMessage(
        context,
        t.closedHere ? '“${t.title}” closed' : '“${t.title}” ended on $_name',
      );
    });
  }

  @override
  void dispose() {
    _gone?.cancel();
    _focus.dispose();
    super.dispose();
  }

  /// Close, made obvious: asks first (a shell may be busy), offers to leave
  /// it running instead. A detached one is reattached to end it.
  Future<void> _close(TerminalTab tab) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Close this terminal?'),
        content: Text(
          'The shell ends on $_name, with anything still running in it. '
          'To come back to it later, keep it running instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop('keep'),
            child: const Text('Keep running'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop('close'),
            style: TextButton.styleFrom(foregroundColor: Sig.of(context).red),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'keep') {
      if (tab.state == TabState.live) await tab.detach();
      return;
    }
    if (tab.state == TabState.detached) {
      // Ending it takes the shell itself: open it once more, then close.
      if (!await askCodeAndOpen(context, tab, _name)) return;
    }
    if (!mounted) return;
    if (tab.state == TabState.locked || tab.state == TabState.opening) {
      LinksyScope.read(context).terminals.remove(tab);
      return;
    }
    await tab.close();
  }

  String get _name =>
      LinksyScope.read(context).device(widget.deviceId)?.device.name ??
      'the computer';

  Future<void> _newTab({RemoteTerminal? resume}) async {
    final terminals = LinksyScope.read(context).terminals;
    final tab = terminals.add(widget.deviceId);
    if (resume != null) {
      tab
        ..terminalId = resume.id
        ..title = resume.title;
    }
    setState(() => _current = tab);
    final opened = await askCodeAndOpen(context, tab, _name);
    if (!mounted) return;
    if (!opened && tab.state != TabState.live) {
      terminals.remove(tab);
      setState(() => _current = terminals.of(widget.deviceId).lastOrNull);
    } else {
      _focus.requestFocus();
    }
  }

  Future<void> _reattach(TerminalTab tab) async {
    final opened = await askCodeAndOpen(context, tab, _name);
    if (opened && mounted) _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final c = LinksyScope.of(context);
    final terminals = c.terminals;
    return ListenableBuilder(
      listenable: terminals,
      builder: (context, _) {
        final tabs = terminals.of(widget.deviceId);
        var tab = _current;
        if (tab == null || !tabs.contains(tab)) tab = tabs.lastOrNull;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: overlayFor(Brightness.dark),
          child: Scaffold(
            backgroundColor: _bg,
            body: SafeArea(
              child: Column(
                children: [
                  _Header(
                    name: _name,
                    tab: tab,
                    onDetach: tab == null || tab.state != TabState.live
                        ? null
                        : () => tab!.detach(),
                    onClose: tab == null ? null : () => _close(tab!),
                  ),
                  _Tabs(
                    tabs: tabs,
                    current: tab,
                    onPick: (t) => setState(() => _current = t),
                    onClose: _close,
                    onAdd: _newTab,
                  ),
                  Expanded(
                    child: tab == null
                        ? _Start(
                            deviceId: widget.deviceId,
                            name: _name,
                            onNew: () => _newTab(),
                            onResume: (r) => _newTab(resume: r),
                          )
                        : Stack(
                            children: [
                              Positioned.fill(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    8,
                                    4,
                                    4,
                                    0,
                                  ),
                                  child: TerminalView(
                                    tab.term,
                                    key: ObjectKey(tab),
                                    theme: _theme,
                                    focusNode: _focus,
                                    autofocus: tab.state == TabState.live,
                                    readOnly: tab.state != TabState.live,
                                    keyboardType: TextInputType.visiblePassword,
                                    textStyle: const TerminalStyle(
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                              if (tab.state == TabState.detached)
                                _StateCard(
                                  icon: Ph.terminalWindow,
                                  title: 'Detached',
                                  detail:
                                      'Still running on $_name. Reattach to '
                                      'see it again; the code is asked again.',
                                  action: 'Reattach',
                                  onAction: () => _reattach(tab!),
                                ),
                              if (tab.state == TabState.ended)
                                const SizedBox.shrink(),
                              if (tab.state == TabState.opening)
                                const Center(
                                  child: CircularProgressIndicator(
                                    color: Sig.cyan,
                                  ),
                                ),
                            ],
                          ),
                  ),
                  if (tab != null && tab.state == TabState.live)
                    _KeyBar(tab: tab),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.tab,
    required this.onDetach,
    required this.onClose,
  });

  final String name;
  final TerminalTab? tab;
  final VoidCallback? onDetach;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final state = switch (tab?.state) {
      TabState.live => 'Terminal on $name',
      TabState.detached => 'Detached · still running on $name',
      TabState.opening => 'Opening on $name…',
      TabState.locked => 'Waiting for the code',
      TabState.ended => 'Ended',
      null => 'Terminal on $name',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
      child: Row(
        children: [
          RoundButton(
            icon: Ph.arrowLeft,
            tooltip: 'Back',
            onDark: true,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tab?.title ?? 'Terminal',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sora(17, color: Colors.white),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (tab?.state == TabState.live) ...[
                      const PulseDot(color: Sig.cyan, size: 6),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        state,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, color: _muted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (tab != null && onDetach != null)
            PopupMenuButton<String>(
              tooltip: 'Terminal menu',
              icon: const Icon(Ph.dotsThree, color: Colors.white),
              color: _panel,
              onSelected: (v) =>
                  v == 'detach' ? onDetach?.call() : onClose?.call(),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'detach',
                  child: Text(
                    'Leave it running (detach)',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          if (tab != null)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: SizedBox(
                height: 40,
                child: TextButton.icon(
                  onPressed: onClose,
                  icon: const Icon(Ph.x, size: 16),
                  label: const Text('Close'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFFF8A9A),
                    backgroundColor: const Color(0x26FF5C72),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    textStyle: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.tabs,
    required this.current,
    required this.onPick,
    required this.onClose,
    required this.onAdd,
  });

  final List<TerminalTab> tabs;
  final TerminalTab? current;
  final ValueChanged<TerminalTab> onPick;
  final ValueChanged<TerminalTab> onClose;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    if (tabs.isEmpty) return const SizedBox(height: 4);
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          for (final t in tabs)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Pressable(
                onTap: () => onPick(t),
                semanticLabel: t.title,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 200),
                  padding: const EdgeInsets.only(left: 14),
                  decoration: BoxDecoration(
                    color: t == current ? Sig.blue : _panel,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: switch (t.state) {
                            TabState.live => Sig.cyan,
                            TabState.detached => const Color(0xFFF5C451),
                            _ => _muted,
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Pressable(
                        onTap: () => onClose(t),
                        scale: 0.85,
                        semanticLabel: 'Close ${t.title}',
                        child: const SizedBox(
                          width: 36,
                          height: 36,
                          child: Icon(Ph.x, color: Colors.white70, size: 15),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Pressable(
            onTap: onAdd,
            semanticLabel: 'New terminal',
            child: Container(
              width: 36,
              decoration: BoxDecoration(
                color: _panel,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(PhBold.plus, color: Colors.white, size: 16),
            ),
          ),
        ],
      ),
    );
  }
}

/// No tab yet: what still runs on the computer, and a new one.
class _Start extends StatefulWidget {
  const _Start({
    required this.deviceId,
    required this.name,
    required this.onNew,
    required this.onResume,
  });

  final String deviceId;
  final String name;
  final VoidCallback onNew;
  final ValueChanged<RemoteTerminal> onResume;

  @override
  State<_Start> createState() => _StartState();
}

class _StartState extends State<_Start> {
  late final Future<List<RemoteTerminal>> _running = LinksyScope.read(context)
      .terminals
      .running(widget.deviceId)
      .catchError((Object _) => <RemoteTerminal>[]);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      children: [
        const Icon(Ph.terminalWindow, color: Sig.cyan, size: 44),
        const SizedBox(height: 14),
        Text(
          'A shell on ${widget.name}',
          textAlign: TextAlign.center,
          style: sora(22, color: Colors.white),
        ),
        const SizedBox(height: 8),
        const Text(
          'Runs as you on the computer, in your home folder. Each time it '
          'opens, it asks for the terminal code set there.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted, height: 1.4),
        ),
        const SizedBox(height: 22),
        SigButton(
          label: 'New terminal',
          icon: PhBold.plus,
          expand: true,
          onTap: widget.onNew,
        ),
        FutureBuilder(
          future: _running,
          builder: (context, snap) {
            final list = snap.data ?? const <RemoteTerminal>[];
            if (list.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(6, 26, 6, 10),
                  child: Text(
                    'STILL RUNNING',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.4,
                      color: _muted,
                    ),
                  ),
                ),
                for (final r in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Pressable(
                      onTap: () => widget.onResume(r),
                      semanticLabel: 'Reattach ${r.title}',
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                        decoration: BoxDecoration(
                          color: _panel,
                          borderRadius: BorderRadius.circular(Radii.md + 2),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Ph.terminalWindow,
                              color: Color(0xFFF5C451),
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    r.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Started ${formatClock(r.started)}',
                                    style: const TextStyle(
                                      color: _muted,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Text(
                              'Reattach',
                              style: TextStyle(
                                color: Sig.cyanLight,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.icon,
    required this.title,
    required this.detail,
    required this.action,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 16,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: _raised),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFFF5C451), size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: sora(16, color: Colors.white)),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 42,
              child: TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  backgroundColor: Sig.blue,
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: Text(action),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Keys a phone keyboard lacks, above it: Esc, Ctrl and Alt (for the next
/// key), Tab, arrows and the symbols shells want.
class _KeyBar extends StatelessWidget {
  const _KeyBar({required this.tab});

  final TerminalTab tab;

  @override
  Widget build(BuildContext context) {
    Widget key(
      String label,
      VoidCallback onTap, {
      bool on = false,
      IconData? icon,
    }) => Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Pressable(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        scale: 0.9,
        semanticLabel: label,
        child: Container(
          constraints: const BoxConstraints(minWidth: 44),
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? Sig.blue : _raised,
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: icon != null
              ? Icon(icon, color: Colors.white, size: 18)
              : Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    fontFamily: 'monospace',
                  ),
                ),
        ),
      ),
    );
    return ListenableBuilder(
      listenable: tab,
      builder: (context, _) => Container(
        color: _panel,
        height: 56,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          children: [
            key('Esc', () => tab.key('\x1b')),
            key('Ctrl', tab.toggleCtrl, on: tab.ctrl),
            key('Alt', tab.toggleAlt, on: tab.alt),
            key('Tab', () => tab.key('\t')),
            key('Left', () => tab.key('\x1b[D'), icon: Ph.arrowLeft),
            key('Up', () => tab.key('\x1b[A'), icon: Ph.arrowUp),
            key('Down', () => tab.key('\x1b[B'), icon: Ph.arrowDown),
            key('Right', () => tab.key('\x1b[C'), icon: PhBold.arrowRight),
            key('|', () => tab.key('|')),
            key('~', () => tab.key('~')),
            key('/', () => tab.key('/')),
            key('-', () => tab.key('-')),
          ],
        ),
      ),
    );
  }
}

/// Asks for the computer's terminal code and opens [tab] with it. The code
/// is never kept: it's typed each time (§4.15). True once open.
Future<bool> askCodeAndOpen(
  BuildContext context,
  TerminalTab tab,
  String name,
) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CodeSheet(tab: tab, name: name),
    ) ??
    false;

class _CodeSheet extends StatefulWidget {
  const _CodeSheet({required this.tab, required this.name});

  final TerminalTab tab;
  final String name;

  @override
  State<_CodeSheet> createState() => _CodeSheetState();
}

class _CodeSheetState extends State<_CodeSheet> {
  final _code = TextEditingController();
  final _field = FocusNode();
  bool _letters = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code
      ..clear()
      ..dispose();
    _field.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final code = _code.text;
    if (code.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.tab.open(code);
      if (mounted) Navigator.of(context).pop(true);
    } on LinksyException catch (e) {
      _code.clear();
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
        // Straight back to typing it again.
        _field.requestFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: IconCircle(icon: Ph.lockSimple, color: Sig.blue, size: 56),
          ),
          const SizedBox(height: 14),
          Text(
            'Terminal code',
            textAlign: TextAlign.center,
            style: sora(21, color: s.ink),
          ),
          const SizedBox(height: 6),
          Text(
            'The code set on ${widget.name} in Preferences › Terminal. '
            'Linksy never keeps it.',
            textAlign: TextAlign.center,
            style: TextStyle(color: s.muted, height: 1.4),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _code,
            focusNode: _field,
            autofocus: true,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            enabled: !_busy,
            keyboardType: _letters
                ? TextInputType.visiblePassword
                : TextInputType.number,
            textAlign: TextAlign.center,
            style: sora(22, color: s.ink, spacing: 4),
            onSubmitted: (_) => _open(),
            decoration: InputDecoration(
              hintText: _letters ? 'Passphrase' : '6 or more digits',
              hintStyle: TextStyle(
                fontSize: 16,
                letterSpacing: 0,
                color: s.faint,
              ),
              errorText: _error,
              errorMaxLines: 3,
            ),
          ),
          Align(
            child: TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() => _letters = !_letters),
              child: Text(_letters ? 'Use digits' : 'Use letters'),
            ),
          ),
          const SizedBox(height: 6),
          SigButton(
            label: _busy ? 'Opening…' : 'Open terminal',
            icon: Ph.terminalWindow,
            expand: true,
            onTap: _busy ? null : _open,
          ),
        ],
      ),
    );
  }
}
