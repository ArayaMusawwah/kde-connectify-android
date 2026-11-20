import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/platform.dart';
import '../../app/scope.dart';
import '../../core/models.dart';
import '../../core/pc_transfer.dart';
import '../../ui/components.dart';
import '../../ui/format.dart';
import '../../ui/l10n.dart';
import '../../ui/sig.dart';


/// A transfer in the queue: what it is and how to stop it.
class _Queued {
  _Queued(this.transfer) {
    progress = ValueNotifier(0);
  }
  final PcTransfer transfer;
  final _Control control = _Control();
  late final ValueNotifier<int> progress;
  void bump(int done) {
    if (progress.value != done) {
      progress.value = done;
    }
  }
}

class _Control {
  /// Pause: the chunk loop stops after the current chunk.
  bool paused = false;
  /// Cancel: the chunk loop stops for good (finished files stay finished).
  bool cancelled = false;
}

enum _Sort { dirsFirst, name, date, size }

/// Browses the files a computer shares with this phone, and acts on them:
/// download to Downloads (queued), upload to the folder (queued), new folder,
/// rename, delete, open on the computer. Paused transfers wait in their slot.
class PcFilesScreen extends StatefulWidget {
  const PcFilesScreen({super.key, required this.deviceId});

  final String deviceId;

  @override
  State<PcFilesScreen> createState() => _PcFilesScreenState();
}

class _PcFilesScreenState extends State<PcFilesScreen> {
  List<PcFileEntry> _entries = const [];
  List<String> _stack = ['/']; // where we are; last is current
  bool _loading = true;
  String? _error;

  /// The queue, in the order it will run: running, then pending (oldest first),
  /// then ended.
  final List<_Queued> _queue = [];
  bool _running = false;

  /// Search + sort over the folder we're in.
  final _search = TextEditingController();
  String _query = '';
  _Sort _sort = _Sort.dirsFirst;

  String get _path => _stack.last;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(_path));
    _search.addListener(() => setState(() => _query = _search.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  // ---- listing -----------------------------------------------------------

  Future<void> _load(String path) async {
    setState(() { _loading = true; _error = null; });
    try {
      final entries = await LinksyScope.read(context).fsList(widget.deviceId, path);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _stack = [..._stack.takeWhile((p) => p != path), path];
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _error = context.l10n.deviceCannotOpenFolder; });
    }
  }

  Future<void> _open(PcFileEntry e) async {
    HapticFeedback.lightImpact();
    await _load(_at(e.name));
  }

  void _up() {
    if (_stack.length <= 1) {
      Navigator.of(context).maybePop();
      return;
    }
    HapticFeedback.lightImpact();
    _load(_stack[_stack.length - 2]);
  }

  String _at(String name) => _path == '/' ? '/$name' : '$_path/$name';

  /// The entries as the user sees them: filtered by the search text, ordered by
  /// the chosen sort. Folder-ness is always derived from the entry itself.
  List<PcFileEntry> get _shown {
    var list = _query.isEmpty
        ? _entries
        : _entries.where((e) => e.name.toLowerCase().contains(_query)).toList();
    return switch (_sort) {
      _Sort.dirsFirst => [...list]..sort((a, b) => _byName(a, b, dirsFirst: true)),
      _Sort.name => [...list]..sort(_byName),
      _Sort.date => [...list]..sort((a, b) => b.modifiedMs.compareTo(a.modifiedMs)),
      _Sort.size => [...list]..sort((a, b) => b.size.compareTo(a.size)),
    };
  }

  int _byName(PcFileEntry a, PcFileEntry b, {bool dirsFirst = false}) {
    if (dirsFirst && a.dir != b.dir) return a.dir ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  // ---- queue -------------------------------------------------------------

  void _enqueue(PcTransfer transfer) {
    _queue.add(_Queued(transfer));
    setState(() {});
    _pump();
  }

  /// One transfer at a time, like Google Drive on a phone. A paused slot is
  /// skipped (its neighbors move ahead of it), and the pump advances past
  /// paused ones immediately.
  Future<void> _pump() async {
    if (_running) return;
    _Queued? next;
    for (final q in _queue) {
      if (q.transfer.state == PcTransferState.pending && !q.control.paused) { next = q; break; }
    }
    if (next == null) return;
    _running = true;
    await _run(next);
    _running = false;
    if (mounted) {
      setState(() {});
      _pump();
    }
  }

  Future<void> _run(_Queued q) async {
    final c = LinksyScope.read(context);
    final l = context.l10n;

    setState(() => q.transfer.state = PcTransferState.running);

    try {
      switch (q.transfer.kind) {
        case PcTransferKind.download:
          final saved = await c.fsDownloadToPhone(
            widget.deviceId,
            q.transfer.remote,
            onProgress: (done, total) {
              if (!mounted) return;
              setState(() {
                q.transfer.done = done;
                q.transfer.size = total;
                q.bump(done);
              });
            },
            shouldCancel: () => q.control.cancelled,
          );
          if (q.control.cancelled) {
            setState(() => q.transfer.state = PcTransferState.cancelled);
            if (mounted) showMessage(context, l.transfersCancelledMsg(q.transfer.name));
            return;
          }
          setState(() {
            q.transfer.state = PcTransferState.done;
            q.transfer.done = q.transfer.size ?? q.transfer.done;
          });
          if (mounted) showMessage(context, l.deviceDownloaded(_short(saved)));

        case PcTransferKind.upload:
          await c.fsUpload(
            widget.deviceId,
            q.transfer.remote,
            q.transfer.localPath!,
            onProgress: (done, total) {
              if (!mounted) return;
              setState(() {
                q.transfer.done = done;
                q.transfer.size = total;
                q.bump(done);
              });
            },
            shouldCancel: () => q.control.cancelled,
          );
          if (q.control.cancelled) {
            setState(() => q.transfer.state = PcTransferState.cancelled);
            if (mounted) showMessage(context, l.transfersCancelledMsg(q.transfer.name));
            return;
          }
          setState(() {
            q.transfer.state = PcTransferState.done;
            q.transfer.done = q.transfer.size ?? q.transfer.done;
          });
          if (mounted) showMessage(context, l.deviceUploadedTo(q.transfer.remote));
      }
    } catch (e) {
      setState(() {
        q.transfer.state = PcTransferState.failed;
        q.transfer.error = '$e';
      });
      if (mounted) showMessage(context, l.transfersFailedMsg(q.transfer.name));
      return;
    }

    if (mounted) await _load(_path);
  }

  // ---- single-file actions (no transfer) --------------------------------

  Future<void> _openOnPc(PcFileEntry e) async {
    final c = LinksyScope.read(context);
    final l = context.l10n;
    try {
      await c.fsOpen(widget.deviceId, _at(e.name));
      showMessage(context, l.deviceOpened(e.name));
    } catch (err) {
      showMessage(context, '$err');
    }
  }

  Future<void> _rename(PcFileEntry e) async {
    final c = LinksyScope.read(context);
    final l = context.l10n;
    final name = await _askName(title: l.deviceRename, confirm: l.deviceRename, initial: e.name);
    if (name == null || name.isEmpty || name == e.name) return;
    try {
      await c.fsRename(widget.deviceId, _at(e.name), _at(name));
      showMessage(context, l.deviceRenamed(name));
      await _load(_path);
    } catch (err) {
      showMessage(context, '$err');
    }
  }

  Future<void> _delete(PcFileEntry e) async {
    final c = LinksyScope.read(context);
    final l = context.l10n;
    if (!await _confirm(l.deviceDeleteConfirm(e.name))) return;
    try {
      await c.fsDelete(widget.deviceId, _at(e.name));
      showMessage(context, l.deviceDeleted(e.name));
      await _load(_path);
    } catch (err) {
      showMessage(context, '$err');
    }
  }

  Future<void> _newFolder() async {
    final c = LinksyScope.read(context);
    final l = context.l10n;
    final name = await _askName(title: l.deviceNewFolder, confirm: l.deviceNewFolder);
    if (name == null || name.isEmpty) return;
    try {
      await c.fsMkdir(widget.deviceId, _at(name));
      showMessage(context, l.deviceFolderCreated(name));
      await _load(_path);
    } catch (err) {
      showMessage(context, '$err');
    }
  }

  Future<void> _upload() async {
    final paths = await LinksyPlatform.pickFiles();
    if (paths.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => _QueueScreen(entries: _queue, onChanged: () => setState(() {}))),
    );
    for (final path in paths) {
      _enqueue(PcTransfer(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        kind: PcTransferKind.upload,
        name: path.split('/').last,
        remote: _path,
        localPath: path,
      ));
    }
  }

  Future<void> _download(PcFileEntry e) async {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => _QueueScreen(entries: _queue, onChanged: () => setState(() {}))),
    );
    _enqueue(PcTransfer(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      kind: PcTransferKind.download,
      name: e.name,
      remote: _at(e.name),
      size: e.size,
    ));
  }

  // ---- dialogs -----------------------------------------------------------

  static String _short(String path) => path.split('/').last;

  Future<String?> _askName({required String title, required String confirm, String initial = ''}) async {
    final s = Sig.of(context);
    final field = TextEditingController(text: initial);
    field.selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: s.card,
        title: Text(title, style: sora(17, weight: FontWeight.w700, color: s.ink)),
        content: TextField(
          controller: field,
          autofocus: true,
          style: TextStyle(color: s.ink),
          decoration: InputDecoration(hintText: context.l10n.deviceRenameTo),
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        actions: [
          SigButton(label: context.l10n.deviceCancel, kind: SigButtonKind.quiet, height: 44, onTap: () => Navigator.of(context).pop()),
          SigButton(label: confirm, height: 44, onTap: () => Navigator.of(context).pop(field.text.trim())),
        ],
      ),
    );
    field.dispose();
    return name;
  }

  Future<bool> _confirm(String question) async {
    final s = Sig.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: s.card,
        title: Text(question, style: sora(17, weight: FontWeight.w700, color: s.ink)),
        content: Text(context.l10n.deviceDeleteCantUndo, style: TextStyle(fontSize: 14, color: s.muted, height: 1.4)),
        actions: [
          SigButton(label: context.l10n.deviceCancel, kind: SigButtonKind.quiet, height: 44, onTap: () => Navigator.of(context).pop(false)),
          SigButton(label: context.l10n.deviceDelete, kind: SigButtonKind.danger, height: 44, onTap: () => Navigator.of(context).pop(true)),
        ],
      ),
    );
    return yes ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final c = LinksyScope.of(context);
    final s = Sig.of(context);
    final view = c.device(widget.deviceId);
    final deviceName = view?.device.name ?? 'this computer';

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  RoundButton(icon: Ph.arrowLeft, tooltip: context.l10n.settingsBack, onTap: _up),
                  const Spacer(),
                  RoundButton(icon: PhBold.plus, tooltip: context.l10n.deviceNewFolder, onTap: _newFolder),
                  const SizedBox(width: 8),
                  RoundButton(icon: Ph.arrowCircleUp, tooltip: context.l10n.deviceUpload, onTap: _upload),
                  const SizedBox(width: 8),
                  RoundButton(icon: Ph.arrowClockwise, tooltip: 'Refresh', onTap: () => _load(_path)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.l10n.devicePcFiles, style: sora(30, weight: FontWeight.w700, color: s.ink)),
                    const SizedBox(height: 4),
                    Text('$deviceName · $_path', style: TextStyle(fontSize: 12.5, color: s.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _search,
                      decoration: InputDecoration(
                        hintText: context.l10n.deviceSearchHint,
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<_Sort>(
                    tooltip: 'Sort',
                    icon: const Icon(Ph.arrowsLeftRight, size: 20),
                    initialValue: _sort,
                    onSelected: (v) => setState(() => _sort = v),
                    itemBuilder: (_) => [
                      PopupMenuItem(value: _Sort.dirsFirst, child: Text(context.l10n.deviceSortByDirFirst)),
                      PopupMenuItem(value: _Sort.name, child: Text(context.l10n.deviceSortByName)),
                      PopupMenuItem(value: _Sort.date, child: Text(context.l10n.deviceSortByDate)),
                      PopupMenuItem(value: _Sort.size, child: Text(context.l10n.deviceSortBySize)),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: switch ((_loading, _error)) {
                (true, _) => const Center(child: CircularProgressIndicator()),
                (false, final String e?) => Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(child: Text(e, style: TextStyle(color: s.muted), textAlign: TextAlign.center)),
                  ),
                (false, null) => _shown.isEmpty
                    ? (_query.isNotEmpty
                        ? Center(child: Text(context.l10n.deviceNoSearchResults(_query), style: TextStyle(color: s.muted)))
                        : _Empty(deviceName: deviceName, connected: view?.connected ?? false))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                        itemCount: _shown.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final entry = _shown[index];
                          return _Row(
                            entry: entry,
                            onTap: entry.dir ? () => _open(entry) : null,
                            onAction: (action) => switch (action) {
                              _Action.download => _download(entry),
                              _Action.openOnPc => _openOnPc(entry),
                              _Action.rename => _rename(entry),
                              _Action.delete => _delete(entry),
                            },
                          );
                        },
                      ),
              },
            ),
          ],
        ),
      ),
      floatingActionButton: _queue.isNotEmpty
          ? FloatingActionButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => _QueueScreen(entries: _queue, onChanged: () => setState(() {}))),
              ),
              child: const Icon(Ph.arrowsDownUp),
            )
          : null,
    );
  }
}


/// The transfer center: what's moving, what's next, and what finished —
/// with pause, resume, cancel and up/down. Like Google Drive's downloads
/// panel, but for files between this phone and the computer.
class _QueueScreen extends StatefulWidget {
  const _QueueScreen({required this.entries, required this.onChanged});

  /// The same list the files screen owns, so a change lands on both.
  final List<_Queued> entries;
  final VoidCallback onChanged;

  @override
  State<_QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<_QueueScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Called by a row; marks the screen dirty and notifies the files list.
  void refresh(void Function() mutate) {
    setState(mutate);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    final l = context.l10n;
    final active = widget.entries.where((q) => q.transfer.active).toList();
    final pending = widget.entries.where((q) => q.transfer.state == PcTransferState.pending).toList();
    final done = widget.entries
        .where((q) => q.transfer.state == PcTransferState.done
            || q.transfer.state == PcTransferState.cancelled
            || q.transfer.state == PcTransferState.failed)
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text(l.transfersQueueTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (active.isEmpty && pending.isEmpty && done.isEmpty)
            SigCard(
              padding: const EdgeInsets.all(20),
              child: Text(l.transfersQueueEmpty, style: TextStyle(color: s.muted)),
            ),
          if (active.isNotEmpty) ...[
            Text(l.transfersActiveNow.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.2, color: s.muted)),
            const SizedBox(height: 8),
            for (final q in active) _QueueRow(q: q, parent: this),
            const SizedBox(height: 16),
          ],
          if (pending.isNotEmpty) ...[
            Text(l.transfersQueuedNow(pending.length).toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.2, color: s.muted)),
            const SizedBox(height: 8),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: pending.length,
              onReorderItem: (oldIndex, newIndex) {
                setState(() {
                  final item = pending.removeAt(oldIndex);
                  pending.insert(newIndex, item);
                  widget.onChanged();
                });
              },
              itemBuilder: (ctx, i) => _QueueRow(q: pending[i], parent: this, index: i, totalPending: pending.length, key: ValueKey(pending[i].transfer.id)),
            ),
            const SizedBox(height: 16),
          ],
          if (done.isNotEmpty) ...[
            Text(l.transfersDoneNow.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.2, color: s.muted)),
            const SizedBox(height: 8),
            for (final q in done) _QueueRow(q: q, parent: this),
          ],
        ],
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({super.key, required this.q, required this.parent, this.index = 0, this.totalPending = 1});

  final _Queued q;
  final _QueueScreenState parent;
  final int index;
  final int totalPending;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    final l = context.l10n;
    final t = q.transfer;

    return SigCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconCircle(
                icon: t.kind == PcTransferKind.download ? Ph.downloadSimple : Ph.arrowCircleUp,
                color: Sig.blue,
                size: 36,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.name, style: sora(14, weight: FontWeight.w600, color: s.ink), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      switch (t.state) {
                        PcTransferState.running => '${formatBytes(t.done)} / ${t.size != null ? formatBytes(t.size!) : '?'}',
                        PcTransferState.pending => l.transfersWaiting,
                        PcTransferState.paused => l.transfersPausedMsg(t.name),
                        PcTransferState.done => l.deviceDownloaded(t.name),
                        PcTransferState.failed => t.error ?? l.transfersFailedMsg(t.name),
                        PcTransferState.cancelled => l.transfersCancelledMsg(t.name),
                      },
                      style: TextStyle(fontSize: 12, color: s.muted),
                    ),
                  ],
                ),
              ),
              if (t.state == PcTransferState.running || t.state == PcTransferState.pending)
                PopupMenuButton<_QueueAction>(
                  tooltip: l.deviceMenuMore,
                  icon: Icon(Ph.dotsThree, size: 20, color: s.faint),
                  onSelected: (a) => parent.refresh(() {
                    switch (a) {
                      case _QueueAction.pause:
                        q.control.paused = true; q.transfer.paused = true;
                      case _QueueAction.resume:
                        q.control.paused = false; q.transfer.paused = false;
                      case _QueueAction.cancel:
                        q.control.cancelled = true;
                        q.transfer.state = PcTransferState.cancelled;
                      case _QueueAction.up:
                        break;
                      case _QueueAction.down:
                        break;
                    }
                    parent.widget.onChanged();
                  }),
                  itemBuilder: (_) => [
                    if (!q.control.paused)
                      PopupMenuItem(value: _QueueAction.pause, child: Text(l.transfersPausing)),
                    if (q.control.paused)
                      PopupMenuItem(value: _QueueAction.resume, child: Text(l.transfersResuming)),
                    PopupMenuItem(value: _QueueAction.cancel, child: Text(l.deviceCancel)),

                  ],
                ),
            ],
          ),
          ValueListenableBuilder<int>(
            valueListenable: q.progress,
            builder: (_, done, _) {
              final total = t.size;
              final v = (total != null && total > 0) ? done.clamp(0, total) / total.toDouble() : null;
              if (v == null) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: v.clamp(0.0, 1.0), minHeight: 4, backgroundColor: s.raised, color: Sig.blue),
                  const SizedBox(height: 4),
                  Text('${formatBytes(done)} / ${formatBytes(total ?? 0)}', style: TextStyle(fontSize: 11.5, color: s.muted)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

}

enum _QueueAction { pause, resume, cancel, up, down }

enum _Action { download, openOnPc, rename, delete }

class _Row extends StatelessWidget {
  const _Row({required this.entry, this.onTap, required this.onAction});

  final PcFileEntry entry;
  final VoidCallback? onTap;
  final void Function(_Action action) onAction;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    final l = context.l10n;
    return SigCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          IconCircle(
            icon: entry.dir ? Ph.folderOpen : Ph.file,
            color: entry.dir ? Sig.blue : Sig.cyan,
            size: 40,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  style: sora(16, weight: FontWeight.w600, color: s.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (!entry.dir)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      formatBytes(entry.size),
                      style: TextStyle(fontSize: 12.5, color: s.muted),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          PopupMenuButton<_Action>(
            tooltip: l.deviceMenuMore,
            icon: Icon(Ph.dotsThree, color: s.faint, size: 22),
            color: s.card,
            onSelected: onAction,
            itemBuilder: (_) => [
              if (!entry.dir)
                PopupMenuItem(
                  value: _Action.download,
                  child: _MenuLabel(icon: Ph.downloadSimple, text: l.deviceDownload),
                ),
              if (!entry.dir)
                PopupMenuItem(
                  value: _Action.openOnPc,
                  child: _MenuLabel(icon: Ph.arrowSquareOut, text: l.deviceOpenOnPc),
                ),
              PopupMenuItem(
                value: _Action.rename,
                child: _MenuLabel(icon: Ph.pencilSimple, text: l.deviceRename),
              ),
              PopupMenuItem(
                value: _Action.delete,
                child: _MenuLabel(icon: Ph.x, text: l.deviceDelete, danger: true),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MenuLabel extends StatelessWidget {
  const _MenuLabel({required this.icon, required this.text, this.danger = false});

  final IconData icon;
  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    final color = danger ? s.red : s.ink;
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 12),
        Text(text, style: TextStyle(fontSize: 14.5, color: color)),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.deviceName, required this.connected});

  final String deviceName;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconCircle(icon: Ph.folderOpen, color: Sig.blue, size: 56),
            const SizedBox(height: 16),
            Text(
              context.l10n.deviceNoPcFiles,
              style: sora(16, weight: FontWeight.w600, color: s.ink),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              connected
                  ? 'Nothing is shared in this folder.'
                  : 'Connect to $deviceName to browse its files.',
              style: TextStyle(fontSize: 13, color: s.muted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
