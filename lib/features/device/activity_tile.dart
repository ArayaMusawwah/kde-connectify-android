import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';

import '../../app/activity.dart';
import '../../app/scope.dart';
import '../../ui/components.dart';
import '../../ui/format.dart';
import '../../ui/sig.dart';

IconData activityIcon(Activity a) => switch (a.kind) {
  ActivityKind.files when a.names.length > 1 => Ph.files,
  ActivityKind.files when a.names.isNotEmpty => fileIcon(a.names.first),
  ActivityKind.files => Ph.file,
  ActivityKind.clipboard => Ph.clipboardText,
  ActivityKind.ping => Ph.bellRinging,
  ActivityKind.screen => Ph.screencast,
  ActivityKind.camera => Ph.videoCamera,
};

/// File name, "N items", quoted clipboard text or the ping title.
String activityTitle(Activity a) => switch (a.kind) {
  ActivityKind.files when a.names.length == 1 => a.names.first,
  ActivityKind.files => '${a.names.length} items',
  ActivityKind.clipboard when a.text != null => '“${a.text!.trim()}”',
  ActivityKind.clipboard => 'Clipboard text',
  ActivityKind.ping => a.text ?? 'Ping',
  ActivityKind.screen => 'Your screen',
  ActivityKind.camera => 'Your camera',
};

/// "Received · 2.1 MB", "Declined".
String activityDetail(Activity a) {
  final live = a.isLive;
  if (a.kind == ActivityKind.screen) {
    return live ? 'Watching now' : 'Watched';
  }
  if (a.kind == ActivityKind.camera) {
    return live ? 'In use as a webcam' : 'Used as a webcam';
  }
  final verb = switch (a.status) {
    ActivityStatus.declined => 'Declined',
    ActivityStatus.failed => a.reason ?? 'Failed',
    ActivityStatus.waiting || ActivityStatus.active => 'In progress',
    _ when a.kind == ActivityKind.clipboard && a.incoming => 'Copied here',
    _ => a.incoming ? 'Received' : 'Sent',
  };
  return [
    verb,
    if (a.kind == ActivityKind.files && a.total > 0) formatBytes(a.total),
  ].join(' · ');
}

/// One row of a device's timeline: the time, a node on the rail (blue
/// outgoing, cyan incoming, red failed or declined), and a card.
class TimelineEntry extends StatelessWidget {
  const TimelineEntry({
    super.key,
    required this.activity,
    this.first = false,
    this.last = false,
  });

  final Activity activity;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final s = Sig.of(context);
    final bad =
        a.status == ActivityStatus.failed ||
        a.status == ActivityStatus.declined;
    final color = bad
        ? s.red
        : a.incoming
        ? Sig.incoming
        : Sig.outgoing;
    final openable = a.incoming && a.saved.isNotEmpty;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 64,
            child: Padding(
              padding: const EdgeInsets.only(top: 22, right: 6),
              child: Text(
                formatClock(a.time),
                textAlign: TextAlign.right,
                style: sora(12.5, weight: FontWeight.w500, color: s.muted),
              ),
            ),
          ),
          SizedBox(
            width: 28,
            child: CustomPaint(
              painter: _Rail(
                color: color,
                line: s.line,
                first: first,
                last: last,
                live: a.isLive,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 5, 16, 5),
              child: SigCard(
                onTap: openable ? () => _open(context, a) : null,
                padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                radius: Radii.md + 2,
                child: Row(
                  children: [
                    Icon(activityIcon(a), color: color, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            activityTitle(a),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: s.ink,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          if (a.isLive && !_isSession(a))
                            _Live(activity: a, color: color)
                          else
                            Row(
                              children: [
                                Icon(
                                  a.incoming
                                      ? PhBold.arrowDownLeft
                                      : PhBold.arrowUpRight,
                                  size: 12,
                                  color: color,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    activityDetail(a),
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: bad ? s.red : s.muted,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    ?_trailing(context, a, s),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget? _trailing(BuildContext context, Activity a, Sig s) {
    Widget button(IconData icon, String tip, VoidCallback onTap) => Tooltip(
      message: tip,
      child: Pressable(
        onTap: onTap,
        scale: 0.85,
        semanticLabel: tip,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 19, color: s.muted),
        ),
      ),
    );

    if (a.isLive && _isSession(a)) {
      return button(
        Ph.x,
        'Stop sharing',
        () => LinksyScope.read(context).stopSharing(a.id),
      );
    }
    if (a.isLive && (!a.incoming || a.status == ActivityStatus.active)) {
      return button(
        Ph.x,
        'Cancel',
        () => report(context, LinksyScope.read(context).cancel(a.id)),
      );
    }
    if (a.kind == ActivityKind.clipboard && a.text != null) {
      return button(Ph.copy, 'Copy again', () async {
        await Clipboard.setData(ClipboardData(text: a.text!));
        if (context.mounted) showMessage(context, 'Copied');
      });
    }
    if (a.incoming && a.saved.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Icon(Ph.arrowSquareOut, size: 18, color: s.faint),
      );
    }
    return null;
  }

  static bool _isSession(Activity a) =>
      a.kind == ActivityKind.screen || a.kind == ActivityKind.camera;

  static Future<void> _open(BuildContext context, Activity a) async {
    if (a.saved.length == 1) return _openFile(context, a.saved.single);
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheet) {
        final s = Sig.of(sheet);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Text(
                '${a.saved.length} files',
                textAlign: TextAlign.center,
                style: sora(20, color: s.ink),
              ),
              const SizedBox(height: 16),
              for (final path in a.saved)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SigCard(
                    onTap: () => _openFile(sheet, path),
                    color: s.bg,
                    child: Row(
                      children: [
                        Icon(fileIcon(path), color: Sig.incoming),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            path.split('/').last,
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: s.ink,
                            ),
                          ),
                        ),
                        Icon(Ph.arrowSquareOut, size: 18, color: s.faint),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  static Future<void> _openFile(BuildContext context, String path) async {
    final messenger = ScaffoldMessenger.of(context);
    final name = path.split('/').last;
    final result = await OpenFilex.open(path);
    if (result.type == ResultType.done) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(switch (result.type) {
          ResultType.fileNotFound => '$name isn’t there anymore.',
          ResultType.noAppToOpen => 'No app on this phone opens $name.',
          _ => 'Couldn’t open $name.',
        }),
      ),
    );
  }
}

/// The rail: a hairline through the day, a node for this entry.
class _Rail extends CustomPainter {
  _Rail({
    required this.color,
    required this.line,
    required this.first,
    required this.last,
    required this.live,
  });

  final Color color;
  final Color line;
  final bool first;
  final bool last;
  final bool live;

  static const _nodeY = 30.0;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    final rail = Paint()
      ..color = line
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(x, first ? _nodeY : 0),
      Offset(x, last ? _nodeY : size.height),
      rail,
    );
    if (live) {
      canvas.drawCircle(
        Offset(x, _nodeY),
        10,
        Paint()..color = color.withValues(alpha: 0.2),
      );
    }
    canvas.drawCircle(Offset(x, _nodeY), 6, Paint()..color = color);
    canvas.drawCircle(Offset(x, _nodeY), 2.4, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_Rail old) =>
      old.color != color ||
      old.line != line ||
      old.first != first ||
      old.last != last ||
      old.live != live;
}

class _Live extends StatelessWidget {
  const _Live({required this.activity, required this.color});

  final Activity activity;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final s = Sig.of(context);
    final String text;
    final double? value;
    if (a.status == ActivityStatus.waiting) {
      final name = LinksyScope.of(context).device(a.deviceId)?.device.name;
      text = a.incoming
          ? 'Waiting for you to accept…'
          : 'Waiting for ${name ?? 'the device'} to accept…';
      value = null;
    } else {
      text = [
        '${formatBytes(a.bytes)} of ${formatBytes(a.total)}',
        if (a.speed > 0) formatSpeed(a.speed),
        if (a.speed > 0) formatTimeLeft(a.total - a.bytes, a.speed),
      ].join(' · ');
      value = a.total == 0 ? null : a.bytes / a.total;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: TextStyle(fontSize: 12.5, color: s.muted),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: LinearProgressIndicator(value: value, color: color),
        ),
      ],
    );
  }
}
