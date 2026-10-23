import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/activity.dart';
import '../../app/linksy_controller.dart';
import '../../app/scope.dart';
import '../../core/models.dart';
import '../../ui/components.dart';
import '../../ui/format.dart';
import '../../ui/l10n.dart';
import '../../ui/sig.dart';

/// Files on their way, in or out, on every device: how many, and how far
/// along all of them are.
class _Batch {
  _Batch(this.transfers);

  final List<Activity> transfers;

  int get files => transfers.fold(0, (n, a) => n + a.names.length);
  int get bytes => transfers.fold(0, (n, a) => n + a.bytes);
  int get total => transfers.fold(0, (n, a) => n + a.total);
  double get speed => transfers.fold(0.0, (n, a) => n + a.speed);
  bool get waiting =>
      transfers.every((a) => a.status == ActivityStatus.waiting);
  double? get progress => waiting || total == 0 ? null : bytes / total;

  /// Files finished so far: whole files the bytes cover, in order.
  int get filesDone => transfers.fold(0, (n, a) => n + _done(a));

  static int _done(Activity a) {
    var left = a.bytes;
    var done = 0;
    for (final size in a.sizes) {
      if (left < size || size == 0 && left == 0) break;
      left -= size;
      done++;
    }
    return done;
  }
}

/// While files are sent or received: a small circle at the bottom left with
/// how many, ringed by their progress. It shows a check for a moment when
/// they're all done. Tapping it opens [TransfersScreen].
class TransferBubble extends StatefulWidget {
  const TransferBubble({super.key});

  @override
  State<TransferBubble> createState() => _TransferBubbleState();
}

class _TransferBubbleState extends State<TransferBubble> {
  /// How many files the last batch had, kept for the check after it ends.
  int _lastFiles = 0;
  Timer? _done;

  @override
  void dispose() {
    _done?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = LinksyScope.of(context);
    final batch = _Batch(c.liveTransfers);
    final live = batch.transfers.isNotEmpty;
    if (live) {
      _lastFiles = batch.files;
      _done?.cancel();
      _done = null;
    } else if (_lastFiles > 0 && _done == null) {
      _done = Timer(const Duration(milliseconds: 2500), () {
        if (mounted) setState(() => _lastFiles = 0);
      });
    }
    final visible = live || _lastFiles > 0;
    return Positioned(
      left: 16,
      bottom: 16 + MediaQuery.paddingOf(context).bottom,
      child: AnimatedScale(
        scale: visible ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        curve: visible ? Curves.easeOutBack : Curves.easeIn,
        child: visible
            ? _Bubble(
                files: live ? batch.files : _lastFiles,
                progress: live ? batch.progress : 1,
                done: !live,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const TransfersScreen(),
                  ),
                ),
              )
            : const SizedBox.square(dimension: 60),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.files,
    required this.progress,
    required this.done,
    required this.onTap,
  });

  final int files;
  final double? progress;
  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    return Pressable(
      onTap: onTap,
      semanticLabel: context.l10n.transfersBubble(files),
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: s.card,
          boxShadow: const [
            BoxShadow(
              color: Color(0x2E0A1024),
              blurRadius: 14,
              offset: Offset(0, 5),
            ),
          ],
        ),
        padding: const EdgeInsets.all(4),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Turning while the other side hasn't accepted yet.
            TweenAnimationBuilder<double>(
              tween: Tween(end: progress ?? 0),
              duration: const Duration(milliseconds: 400),
              builder: (context, value, _) => CircularProgressIndicator(
                value: progress == null ? null : value,
                strokeWidth: 4,
                strokeCap: StrokeCap.round,
                color: done ? Sig.cyan : Sig.blue,
                backgroundColor: s.line,
              ),
            ),
            Center(
              child: done
                  ? const Icon(PhBold.check, color: Sig.cyan, size: 24)
                  : Text(
                      '$files',
                      style: sora(
                        files > 99 ? 14 : 18,
                        weight: FontWeight.w700,
                        color: s.ink,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Everything on its way: the speed on top, then each file.
class TransfersScreen extends StatelessWidget {
  const TransfersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = LinksyScope.of(context);
    final s = Sig.of(context);
    final l = context.l10n;
    final batch = _Batch(c.liveTransfers);
    final left = batch.total - batch.bytes;
    return Scaffold(
      appBar: AppBar(title: Text(l.transfersTitle)),
      body: batch.transfers.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(PhBold.check, color: Sig.cyan, size: 40),
                  const SizedBox(height: 10),
                  Text(l.transfersAllDone, style: sora(20, color: s.ink)),
                ],
              ),
            )
          : ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                24 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                SigCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        batch.waiting || batch.speed == 0
                            ? l.transfersWaiting
                            : formatSpeed(batch.speed),
                        style: sora(34, weight: FontWeight.w700, color: s.ink),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          l.transfersFilesDone(batch.filesDone, batch.files),
                          l.activityProgress(
                            formatBytes(batch.bytes),
                            formatBytes(batch.total),
                          ),
                          if (batch.speed > 0 && left > 0)
                            formatTimeLeft(left, batch.speed),
                        ].join(' · '),
                        style: TextStyle(fontSize: 14, color: s.muted),
                      ),
                      const SizedBox(height: 14),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: batch.progress,
                          minHeight: 6,
                          color: Sig.blue,
                          backgroundColor: s.line,
                        ),
                      ),
                    ],
                  ),
                ),
                for (final a in batch.transfers) _Transfer(c: c, activity: a),
              ],
            ),
    );
  }
}

class _Transfer extends StatelessWidget {
  const _Transfer({required this.c, required this.activity});

  final LinksyController c;
  final Activity activity;

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final s = Sig.of(context);
    final l = context.l10n;
    final name = c.device(a.deviceId)?.device.name ?? shortDeviceId(a.deviceId);
    final color = a.incoming ? Sig.incoming : Sig.outgoing;
    final doneCount = _Batch._done(a);
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                a.incoming ? PhBold.arrowDownLeft : PhBold.arrowUpRight,
                size: 15,
                color: color,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  a.incoming ? l.transfersFrom(name) : l.transfersTo(name),
                  style: sora(15, weight: FontWeight.w600, color: s.ink),
                ),
              ),
              TextButton(
                onPressed: () => c.cancel(a.id),
                child: Text(l.commonCancel),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SigCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < a.names.length; i++)
                  _File(
                    name: a.names[i],
                    size: i < a.sizes.length ? a.sizes[i] : null,
                    state: i < doneCount
                        ? _FileState.done
                        : i == doneCount && a.status == ActivityStatus.active
                        ? _FileState.going
                        : _FileState.next,
                    progress: _fileProgress(a, i),
                    color: color,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// How far along file [i] is, from the bytes past the files before it.
  static double? _fileProgress(Activity a, int i) {
    if (i >= a.sizes.length || a.sizes[i] == 0) return null;
    final before = a.sizes.take(i).fold(0, (n, s) => n + s);
    return ((a.bytes - before) / a.sizes[i]).clamp(0.0, 1.0);
  }
}

enum _FileState { done, going, next }

class _File extends StatelessWidget {
  const _File({
    required this.name,
    required this.size,
    required this.state,
    required this.progress,
    required this.color,
  });

  final String name;
  final int? size;
  final _FileState state;
  final double? progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: [
          Icon(
            fileIcon(name),
            size: 22,
            color: state == _FileState.next ? s.faint : color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                    color: s.ink,
                  ),
                ),
                if (state == _FileState.going) ...[
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: progress,
                    color: color,
                    backgroundColor: s.line,
                  ),
                ] else if (size != null)
                  Text(
                    formatBytes(size!),
                    style: TextStyle(fontSize: 12.5, color: s.muted),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          switch (state) {
            _FileState.done => const Icon(
              PhBold.check,
              size: 18,
              color: Sig.cyan,
            ),
            _FileState.going => Text(
              '${((progress ?? 0) * 100).round()}%',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            _FileState.next => Icon(Ph.clock, size: 18, color: s.faint),
          },
        ],
      ),
    );
  }
}
