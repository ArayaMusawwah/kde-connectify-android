import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/activity.dart';
import '../../app/scope.dart';
import '../../ui/format.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'activity_tile.dart';

/// A device's page: big actions, then everything shared with it by day.
class DeviceScreen extends StatelessWidget {
  const DeviceScreen({super.key, required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context) {
    final c = LinksyScope.of(context);
    final view = c.device(deviceId);
    if (view == null || !view.trusted) {
      // Forgotten while open.
      return const Scaffold(body: SizedBox.shrink());
    }
    final d = view.device;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tint = deviceScheme(d.id, theme.brightness);
    final days = _byDay(c.activityFor(deviceId));

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.scrolledUnder)
              ? scheme.surfaceContainer
              : Colors.transparent,
        ),
        actions: [
          PopupMenuButton<void>(
            icon: const Icon(Icons.more_vert_rounded),
            itemBuilder: (_) => [
              PopupMenuItem(
                onTap: () => _forget(context),
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.link_off_rounded),
                  title: Text('Forget device'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    tint.primaryContainer.withValues(alpha: 0.75),
                    scheme.surface,
                  ],
                ),
              ),
              padding: EdgeInsets.fromLTRB(
                16,
                MediaQuery.paddingOf(context).top + kToolbarHeight,
                16,
                8,
              ),
              child: Column(
                children: [
                  DeviceAvatar(device: d, size: 96),
                  const SizedBox(height: 16),
                  Text(
                    d.name,
                    style: theme.textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      PresencePill(
                        presence: view.presence,
                        background: scheme.surface.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        kindIcon(d.kind),
                        size: 18,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        d.description,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _Action(
                        icon: Icons.upload_file_rounded,
                        label: 'Send files',
                        primary: true,
                        onTap: () => _sendFiles(context),
                      ),
                      _Action(
                        icon: Icons.content_paste_go_rounded,
                        label: 'Clipboard',
                        onTap: () => report(context, c.sendClipboard(deviceId)),
                      ),
                      _Action(
                        icon: Icons.notifications_active_rounded,
                        label: 'Ping',
                        onTap: () => report(context, c.ping(deviceId)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SectionHeader('Activity')),
          if (days.isEmpty)
            SliverToBoxAdapter(child: _NoActivity(name: d.name))
          else
            for (final (day, entries) in days) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
                  child: Text(
                    day,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.primary,
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Grouped(
                  children: [
                    for (final a in entries) ActivityTile(activity: a),
                  ],
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            ],
          SliverToBoxAdapter(
            child: SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom),
          ),
        ],
      ),
    );
  }

  static List<(String, List<Activity>)> _byDay(List<Activity> entries) {
    final days = <(String, List<Activity>)>[];
    for (final a in entries) {
      final day = formatDay(a.time);
      if (days.isEmpty || days.last.$1 != day) days.add((day, []));
      days.last.$2.add(a);
    }
    return days;
  }

  Future<void> _sendFiles(BuildContext context) async {
    final c = LinksyScope.read(context);
    final picked = await FilePicker.pickFiles();
    final paths = [for (final f in picked) ?f.path];
    if (context.mounted) await report(context, c.sendFiles(deviceId, paths));
  }

  Future<void> _forget(BuildContext context) async {
    final c = LinksyScope.read(context);
    final name = c.device(deviceId)?.device.name ?? 'this device';
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        icon: const Icon(Icons.link_off_rounded),
        title: Text('Forget $name?'),
        content: const Text(
          'You’ll need to pair again to share with it. Its activity on this '
          'phone is cleared too.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialog).colorScheme.error,
              foregroundColor: Theme.of(dialog).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    Navigator.of(context).pop();
    await c.forget(deviceId);
  }
}

/// A rounded button with its label underneath, like the Contacts app.
class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (bg, fg) = primary
        ? (scheme.primary, scheme.onPrimary)
        : (scheme.surfaceContainerHighest, scheme.onSurface);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.lg),
    );
    return SizedBox(
      width: 96,
      child: Column(
        children: [
          Material(
            color: bg,
            shape: shape,
            elevation: primary ? 2 : 0,
            shadowColor: scheme.primary.withValues(alpha: 0.4),
            child: InkWell(
              customBorder: shape,
              onTap: onTap,
              child: SizedBox(
                width: 72,
                height: 64,
                child: Icon(icon, color: fg, size: 28),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: theme.textTheme.labelLarge,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _NoActivity extends StatelessWidget {
  const _NoActivity({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Grouped(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
          child: Column(
            children: [
              IconBadge(
                icon: Icons.swap_horiz_rounded,
                foreground: scheme.primary,
                background: scheme.primaryContainer,
                size: 56,
              ),
              const SizedBox(height: 16),
              Text('Nothing shared yet', style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                'Files, clipboard text and pings you share with $name '
                'show up here.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
