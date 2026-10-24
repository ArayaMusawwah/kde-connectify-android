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

/// Always at the bottom left, so the transfers page is always a tap away.
/// While files are sent or received it shows how many, ringed by their
/// progress, and a check for a moment when they're all done.
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
    final finished = !live && _lastFiles > 0;
    return Positioned(
      left: 16,
      bottom: 16 + MediaQuery.paddingOf(context).bottom,
      child: _Bubble(
        files: live ? batch.files : _lastFiles,
        progress: live ? batch.progress : 1,
        state: live
            ? _BubbleState.going
            : finished
            ? _BubbleState.done
            : _BubbleState.idle,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const TransfersScreen()),
        ),
      ),
    );
  }
}

enum _BubbleState { idle, going, done }

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.files,
    required this.progress,
    required this.state,
    required this.onTap,
  });

  final int files;
  final double? progress;
  final _BubbleState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    final done = state == _BubbleState.done;
    return Pressable(
      onTap: onTap,
      semanticLabel: state == _BubbleState.idle
          ? context.l10n.transfersTitle
          : context.l10n.transfersBubble(files),
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
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: state == _BubbleState.idle
              ? Icon(
                  Ph.arrowsDownUp,
                  key: const ValueKey('idle'),
                  color: Sig.blue,
                  size: 24,
                )
              : Stack(
                  key: const ValueKey('going'),
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
      ),
    );
  }
}

/// How much of a tint the done part of a card or row gets.
const _tint = 0.02;

/// [child] on a card whose done part, from the left, is tinted [color]: the
/// progress is the card itself, not a bar in it.
class _Filled extends StatelessWidget {
  const _Filled({
    required this.progress,
    required this.color,
    required this.child,
  });

  /// Null when it hasn't started: no tint.
  final double? progress;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: progress ?? 0),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
            builder: (context, v, _) => FractionallySizedBox(
              widthFactor: v,
              heightFactor: 1,
              child: ColoredBox(color: color.withValues(alpha: _tint)),
            ),
          ),
        ),
      ),
      child,
    ],
  );
}

/// Everything on its way: the speed on top, then each transfer with its
/// own speed above its files, then the ones that ended.
class TransfersScreen extends StatelessWidget {
  const TransfersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = LinksyScope.of(context);
    final l = context.l10n;
    final batch = _Batch(c.liveTransfers);
    final recent = c.recentTransfers;
    return Scaffold(
      appBar: AppBar(title: Text(l.transfersTitle)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          if (batch.transfers.isEmpty)
            const _Nothing()
          else ...[
            _Speed(batch: batch),
            for (final a in batch.transfers) _Transfer(c: c, activity: a),
          ],
          if (recent.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 28, 8, 10),
              child: Text(
                l.transfersRecent.toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.4,
                  color: Sig.of(context).muted,
                ),
              ),
            ),
            SigCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < recent.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 1,
                        indent: 62,
                        color: Sig.of(context).line,
                      ),
                    _Recent(c: c, activity: recent[i]),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A round icon on a light tint of its color.
class _Badge extends StatelessWidget {
  const _Badge(this.icon, this.color, {this.size = 36});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color.withValues(alpha: 0.12),
    ),
    child: Icon(icon, size: size * 0.48, color: color),
  );
}

class _Nothing extends StatelessWidget {
  const _Nothing();

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    final l = context.l10n;
    return SigCard(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Row(
        children: [
          const _Badge(Ph.arrowsDownUp, Sig.blue, size: 52),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.transfersNone, style: sora(18, color: s.ink)),
                const SizedBox(height: 4),
                Text(
                  l.transfersNoneBody,
                  style: TextStyle(fontSize: 13.5, height: 1.4, color: s.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The speed of everything together, on a card that fills as it goes.
class _Speed extends StatelessWidget {
  const _Speed({required this.batch});

  final _Batch batch;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    final l = context.l10n;
    final left = batch.total - batch.bytes;
    final percent = ((batch.progress ?? 0) * 100).round();
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.lg),
      child: ColoredBox(
        color: s.card,
        child: _Filled(
          progress: batch.progress,
          color: Sig.blue,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        batch.waiting || batch.speed == 0
                            ? l.transfersWaiting
                            : formatSpeed(batch.speed),
                        style: sora(34, weight: FontWeight.w700, color: s.ink)
                            .copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                      ),
                    ),
                    if (batch.progress != null)
                      Text(
                        '$percent%',
                        style: sora(
                          20,
                          weight: FontWeight.w700,
                          color: Sig.blue,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
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
              ],
            ),
          ),
        ),
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
    final going = a.status == ActivityStatus.active && a.speed > 0;
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Its own speed, on top of its files.
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 0, 8),
            child: Row(
              children: [
                _Badge(
                  a.incoming ? PhBold.arrowDownLeft : PhBold.arrowUpRight,
                  color,
                  size: 32,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.incoming
                            ? l.transfersFrom(name)
                            : l.transfersTo(name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sora(15, weight: FontWeight.w600, color: s.ink),
                      ),
                      Text(
                        l.transfersFilesDone(doneCount, a.names.length),
                        style: TextStyle(fontSize: 12.5, color: s.muted),
                      ),
                    ],
                  ),
                ),
                Text(
                  going ? formatSpeed(a.speed) : l.transfersWaiting,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: going ? color : s.muted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                IconButton(
                  onPressed: () => c.cancel(a.id),
                  tooltip: l.commonCancel,
                  icon: Icon(Ph.x, size: 18, color: s.muted),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.lg),
            child: ColoredBox(
              color: s.card,
              child: Column(
                children: [
                  for (var i = 0; i < a.names.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: s.line),
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
                ],
              ),
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
    final size = this.size;
    return _Filled(
      progress: switch (state) {
        _FileState.done => 1,
        _FileState.going => progress,
        _FileState.next => null,
      },
      color: Sig.blue,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
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
                      color: state == _FileState.next ? s.muted : s.ink,
                    ),
                  ),
                  if (size != null)
                    Text(
                      state == _FileState.going && progress != null
                          ? context.l10n.activityProgress(
                              formatBytes((size * progress!).round()),
                              formatBytes(size),
                            )
                          : formatBytes(size),
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
                  fontWeight: FontWeight.w700,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              _FileState.next => Icon(Ph.clock, size: 18, color: s.faint),
            },
          ],
        ),
      ),
    );
  }
}

/// One transfer that ended: what, with whom, how big, when, and how.
class _Recent extends StatelessWidget {
  const _Recent({required this.c, required this.activity});

  final LinksyController c;
  final Activity activity;

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final s = Sig.of(context);
    final l = context.l10n;
    final name = c.device(a.deviceId)?.device.name ?? shortDeviceId(a.deviceId);
    final ok = a.status == ActivityStatus.done;
    final today = DateUtils.isSameDay(a.time, DateTime.now());
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
      child: Row(
        children: [
          _Badge(
            a.incoming ? PhBold.arrowDownLeft : PhBold.arrowUpRight,
            a.incoming ? Sig.incoming : Sig.outgoing,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.names.length == 1
                      ? a.names.first
                      : l.activityItems(a.names.length),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                    color: s.ink,
                  ),
                ),
                Text(
                  [
                    a.incoming ? l.transfersFrom(name) : l.transfersTo(name),
                    if (a.total > 0) formatBytes(a.total),
                    today ? formatClock(a.time) : formatDay(a.time),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: s.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ok
              ? const Icon(PhBold.check, size: 18, color: Sig.cyan)
              : Text(
                  a.status == ActivityStatus.declined
                      ? l.activityDeclined
                      : l.activityFailed,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: s.red,
                  ),
                ),
        ],
      ),
    );
  }
}
