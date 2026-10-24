import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

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

/// Everything on its way: the speed on top, then each transfer's files,
/// then the ones that ended.
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
            _Speed(c: c, batch: batch),
            _Feels(speed: batch.waiting ? 0 : batch.speed),
            for (final a in batch.transfers) _Transfer(c: c, activity: a),
          ],
          if (recent.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 28, 8, 10),
              child: Text(
                l.transfersRecent.toUpperCase(),
                style: _label(Sig.of(context)),
              ),
            ),
            for (final a in recent) _Recent(c: c, activity: a),
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

/// The speed of everything together, with files flowing between the two
/// devices as fast as they really go.
class _Speed extends StatelessWidget {
  const _Speed({required this.c, required this.batch});

  final LinksyController c;
  final _Batch batch;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    final l = context.l10n;
    final first = batch.transfers.first;
    final other = c.device(first.deviceId)?.device.kind ?? DeviceKind.desktop;
    final going = !batch.waiting && batch.speed > 0;
    final computer = _End(kindIcon(other), Sig.incoming);
    const phone = _End(Ph.deviceMobile, Sig.outgoing);
    final speed = formatSpeed(batch.speed).split(' ');
    return SigCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: going
                    ? Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: speed.first),
                            TextSpan(
                              text: ' ${speed.skip(1).join(' ')}',
                              style: TextStyle(fontSize: 15, color: s.muted),
                            ),
                          ],
                        ),
                        style: sora(28, weight: FontWeight.w700, color: s.ink)
                            .copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                      )
                    : Text(l.transfersWaiting, style: sora(22, color: s.ink)),
              ),
              if (batch.progress != null)
                Text(
                  '${(batch.progress! * 100).round()}%',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Sig.blue,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (first.incoming) computer else phone,
              const SizedBox(width: 10),
              Expanded(child: _Flow(speed: going ? batch.speed : 0)),
              const SizedBox(width: 10),
              if (first.incoming) phone else computer,
            ],
          ),
        ],
      ),
    );
  }
}

/// One end of the lane: a device in a tinted tile.
class _End extends StatelessWidget {
  const _End(this.icon, this.color);

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 32,
    height: 32,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.13),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Icon(icon, size: 18, color: color),
  );
}

/// A lane with files running along it: the faster the transfer, the faster
/// they run. Still while it waits.
class _Flow extends StatefulWidget {
  const _Flow({required this.speed});

  /// Bytes per second.
  final double speed;

  @override
  State<_Flow> createState() => _FlowState();
}

class _FlowState extends State<_Flow> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  /// How far the files have run, in lanes.
  double _phase = 0;

  /// Lanes a second, eased towards the speed so a jump doesn't jolt.
  double _pace = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration now) {
    final dt = (now - _last).inMicroseconds / 1e6;
    _last = now;
    // 1 MB/s crawls, 100 MB/s races; past that it stays readable.
    final mb = widget.speed / 1e6;
    final target = mb <= 0 ? 0.0 : (0.12 + mb / 80).clamp(0.12, 1.6);
    _pace += (target - _pace) * (dt * 3).clamp(0.0, 1.0);
    if (_pace < 0.001) return;
    setState(() => _phase = (_phase + _pace * dt) % 1);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 10,
    child: CustomPaint(
      painter: _FlowPainter(
        phase: _phase,
        track: Sig.of(context).raised,
        dot: Sig.blue,
        still: widget.speed <= 0,
      ),
    ),
  );
}

class _FlowPainter extends CustomPainter {
  _FlowPainter({
    required this.phase,
    required this.track,
    required this.dot,
    required this.still,
  });

  final double phase;
  final Color track;
  final Color dot;
  final bool still;

  static const _dots = 6;

  @override
  void paint(Canvas canvas, Size size) {
    final lane = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    canvas.drawRRect(lane, Paint()..color = track);
    if (still) return;
    canvas.save();
    canvas.clipRRect(lane);
    const w = 14.0, h = 6.0;
    for (var i = 0; i < _dots; i++) {
      final t = (phase + i / _dots) % 1;
      final x = -w + t * (size.width + w);
      // Fade in at the start, out at the end.
      final fade = (t * 8).clamp(0.0, 1.0) * ((1 - t) * 8).clamp(0.0, 1.0);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, (size.height - h) / 2, w, h),
          const Radius.circular(3),
        ),
        Paint()..color = dot.withValues(alpha: fade),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FlowPainter old) =>
      old.phase != phase || old.still != still || old.track != track;
}

/// The speed as something felt, under the card: a movie, photos, songs. A
/// new one every few seconds.
class _Feels extends StatefulWidget {
  const _Feels({required this.speed});

  final double speed;

  @override
  State<_Feels> createState() => _FeelsState();
}

class _FeelsState extends State<_Feels> {
  int _turn = 0;
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => setState(() => _turn++),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final mb = widget.speed / 1e6;
    // Only once it's fast enough to enjoy.
    if (mb < 15) return const SizedBox.shrink();
    final lines = [
      // A 1 GB movie, 3 MB photos, 5 MB songs.
      l.transfersFastMovie((1000 / mb).round()),
      if (mb / 3 >= 2) l.transfersFastPhotos((mb / 3).round()),
      if (mb / 5 >= 2) l.transfersFastSongs((mb / 5).round()),
    ];
    if (lines.isEmpty) return const SizedBox(height: 4);
    final i = _turn % lines.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
      child: Row(
        children: [
          const Icon(PhFill.lightning, size: 15, color: Sig.blue),
          const SizedBox(width: 7),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              layoutBuilder: (current, previous) => Stack(
                alignment: AlignmentDirectional.centerStart,
                children: [...previous, ?current],
              ),
              child: Text(
                lines[i],
                key: ValueKey(i),
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: Sig.blue,
                ),
              ),
            ),
          ),
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
    final doneCount = _Batch._done(a);
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    [
                      a.incoming ? l.transfersFrom(name) : l.transfersTo(name),
                      l.transfersFilesDone(doneCount, a.names.length),
                    ].join(' · ').toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _label(s),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => c.cancel(a.id),
                style: TextButton.styleFrom(foregroundColor: s.muted),
                child: Text(l.commonCancel),
              ),
            ],
          ),
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

/// The small caps above a list.
TextStyle _label(Sig s) => TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w600,
  letterSpacing: 1.3,
  color: s.muted,
);

enum _FileState { done, going, next }

/// A small icon in a soft circle; for the file on its way, blue and ringed
/// by its progress, like the bubble on the home screen.
class _Round extends StatelessWidget {
  const _Round(this.icon, {this.progress, this.going = false});

  final IconData icon;
  final double? progress;
  final bool going;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    return SizedBox.square(
      dimension: 40,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: going
                  ? Sig.blue.withValues(alpha: 0.10)
                  : s.ink.withValues(alpha: 0.05),
            ),
          ),
          if (going)
            TweenAnimationBuilder<double>(
              tween: Tween(end: progress ?? 0),
              duration: const Duration(milliseconds: 400),
              builder: (context, v, _) => CircularProgressIndicator(
                value: progress == null ? null : v,
                strokeWidth: 2.5,
                strokeCap: StrokeCap.round,
                color: Sig.blue,
                backgroundColor: s.line,
              ),
            ),
          Icon(icon, size: 18, color: going ? Sig.blue : s.faint),
        ],
      ),
    );
  }
}

class _File extends StatelessWidget {
  const _File({
    required this.name,
    required this.size,
    required this.state,
    required this.progress,
  });

  final String name;
  final int? size;
  final _FileState state;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    final l = context.l10n;
    final size = this.size;
    final going = state == _FileState.going;
    final percent = '${((progress ?? 0) * 100).round()}%';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          _Round(fileIcon(name), progress: progress, going: going),
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
                    fontWeight: going ? FontWeight.w600 : FontWeight.w500,
                    color: going ? s.ink : s.muted,
                  ),
                ),
                if (going && size != null && progress != null)
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text:
                              '${l.activityProgress(formatBytes((size * progress!).round()), formatBytes(size))} · ',
                        ),
                        TextSpan(
                          text: percent,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Sig.blue,
                          ),
                        ),
                      ],
                    ),
                    style: TextStyle(
                      fontSize: 12.5,
                      color: s.muted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  )
                else if (size != null)
                  Text(
                    formatBytes(size),
                    style: TextStyle(fontSize: 12.5, color: s.faint),
                  ),
              ],
            ),
          ),
          if (state == _FileState.done) ...[
            const SizedBox(width: 10),
            Icon(PhBold.check, size: 16, color: s.faint),
          ],
        ],
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
    final today = DateUtils.isSameDay(a.time, DateTime.now());
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          _Round(
            a.names.length == 1
                ? fileIcon(a.names.first)
                : a.incoming
                ? PhBold.arrowDownLeft
                : PhBold.arrowUpRight,
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
                  style: TextStyle(fontSize: 12.5, color: s.faint),
                ),
              ],
            ),
          ),
          if (a.status != ActivityStatus.done) ...[
            const SizedBox(width: 10),
            Text(
              a.status == ActivityStatus.declined
                  ? l.activityDeclined
                  : l.activityFailed,
              style: TextStyle(fontSize: 12.5, color: s.red),
            ),
          ],
        ],
      ),
    );
  }
}
