import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';

import '../../app/activity.dart';
import '../../app/scope.dart';
import '../../ui/format.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

IconData activityIcon(Activity a) => switch (a.kind) {
  ActivityKind.files when a.names.length > 1 => Icons.folder_copy_rounded,
  ActivityKind.files when a.names.isNotEmpty => fileIcon(a.names.first),
  ActivityKind.files => Icons.insert_drive_file_rounded,
  ActivityKind.clipboard => Icons.content_paste_rounded,
  ActivityKind.ping => Icons.notifications_rounded,
};

/// File name, "N items", quoted clipboard text or the ping title.
String activityTitle(Activity a) => switch (a.kind) {
  ActivityKind.files when a.names.length == 1 => a.names.first,
  ActivityKind.files => '${a.names.length} items',
  ActivityKind.clipboard when a.text != null => '“${a.text!.trim()}”',
  ActivityKind.clipboard => 'Clipboard text',
  ActivityKind.ping => a.text ?? 'Ping',
};

/// "Received · 2.1 MB · 14:03", "Declined · 14:03".
String activityDetail(Activity a) {
  final verb = switch (a.status) {
    ActivityStatus.declined => 'Declined',
    ActivityStatus.failed => a.reason ?? 'Failed',
    ActivityStatus.waiting || ActivityStatus.active => 'In progress',
    _ when a.kind == ActivityKind.clipboard && a.incoming => 'Copied',
    _ => a.incoming ? 'Received' : 'Sent',
  };
  return [
    verb,
    if (a.kind == ActivityKind.files && a.total > 0) formatBytes(a.total),
    formatClock(a.time),
  ].join(' · ');
}

/// Icon in a tinted circle (green incoming, accent outgoing, red failed or
/// declined), title and detail; live transfers add progress and cancel.
/// Received files open on tap.
class ActivityTile extends StatelessWidget {
  const ActivityTile({super.key, required this.activity});

  final Activity activity;

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bad =
        a.status == ActivityStatus.failed ||
        a.status == ActivityStatus.declined;
    final (fg, bg) = bad
        ? (scheme.error, scheme.errorContainer)
        : a.incoming
        ? (scheme.incoming, scheme.incomingContainer)
        : (scheme.primary, scheme.primaryContainer);
    final openable = a.incoming && a.saved.isNotEmpty;

    return InkWell(
      onTap: openable ? () => _open(context, a) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                IconBadge(
                  icon: activityIcon(a),
                  foreground: fg,
                  background: bg,
                ),
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: groupFill(scheme),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      a.incoming
                          ? Icons.south_west_rounded
                          : Icons.north_east_rounded,
                      size: 14,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activityTitle(a),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  if (a.isLive)
                    _Live(activity: a)
                  else
                    Text(
                      activityDetail(a),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: bad ? scheme.error : scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            ?_trailing(context, a),
          ],
        ),
      ),
    );
  }

  Widget? _trailing(BuildContext context, Activity a) {
    if (a.isLive && (!a.incoming || a.status == ActivityStatus.active)) {
      return IconButton(
        tooltip: 'Cancel',
        icon: const Icon(Icons.close_rounded),
        onPressed: () =>
            report(context, LinksyScope.read(context).cancel(a.id)),
      );
    }
    if (a.kind == ActivityKind.clipboard && a.text != null) {
      return IconButton(
        tooltip: 'Copy again',
        icon: const Icon(Icons.copy_rounded),
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: a.text!));
          if (context.mounted) showMessage(context, 'Copied');
        },
      );
    }
    if (a.incoming && a.saved.isNotEmpty) {
      return const Padding(
        padding: EdgeInsets.only(right: 8),
        child: Icon(Icons.open_in_new_rounded, size: 20),
      );
    }
    return null;
  }

  static Future<void> _open(BuildContext context, Activity a) async {
    if (a.saved.length == 1) return _openFile(context, a.saved.single);
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(
                '${a.saved.length} files',
                style: Theme.of(sheet).textTheme.titleLarge,
              ),
            ),
            Grouped(
              color: Theme.of(sheet).colorScheme.surfaceContainer,
              children: [
                for (final path in a.saved)
                  ListTile(
                    leading: Icon(fileIcon(path)),
                    title: Text(path.split('/').last),
                    onTap: () => _openFile(sheet, path),
                  ),
              ],
            ),
          ],
        ),
      ),
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

class _Live extends StatelessWidget {
  const _Live({required this.activity});

  final Activity activity;

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final theme = Theme.of(context);
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
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: value),
      ],
    );
  }
}
