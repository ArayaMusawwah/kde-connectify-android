import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// What happened lately (connections, transfers, direct links), with the
/// time of each, for when something goes wrong. Kept on this phone only, in
/// the app's own storage, and never sent anywhere: people copy it themselves
/// into an issue. The newest [keep] lines.
class AppLog extends ChangeNotifier {
  AppLog(this._file, {this.keep = 600});

  final File? _file;
  final int keep;
  final lines = <String>[];
  Timer? _save;

  Future<void> load() async {
    final file = _file;
    if (file == null || !await file.exists()) return;
    try {
      final old = await file.readAsLines();
      lines.insertAll(0, old.skip(old.length > keep ? old.length - keep : 0));
      notifyListeners();
    } on Object {
      // A broken log is no reason to fail: start a new one
    }
  }

  void add(String line) {
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final ms = t.millisecond.toString().padLeft(3, '0');
    lines.add(
      '${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.$ms  $line',
    );
    if (lines.length > keep) lines.removeRange(0, lines.length - keep);
    notifyListeners();
    // A few writes a second during a transfer: once they settle
    if (_file == null) return;
    _save?.cancel();
    _save = Timer(const Duration(seconds: 2), _write);
  }

  Future<void> clear() async {
    lines.clear();
    notifyListeners();
    await _write();
  }

  Future<void> _write() async {
    try {
      await _file?.writeAsString(lines.isEmpty ? '' : '${lines.join('\n')}\n');
    } on Object {
      // Storage full or gone: the lines stay in memory
    }
  }

  @override
  void dispose() {
    _save?.cancel();
    super.dispose();
  }
}
