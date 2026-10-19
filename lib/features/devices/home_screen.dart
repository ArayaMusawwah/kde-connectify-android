import 'package:flutter/material.dart';

import '../../app/linksy_controller.dart';
import '../../app/scope.dart';
import '../../core/models.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../device/activity_tile.dart';
import '../device/device_screen.dart';
import '../pairing/pairing_flows.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = LinksyScope.of(context);
    final paired = c.paired;
    final unpaired = c.unpaired;
    final empty = paired.isEmpty;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: c.refresh,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              toolbarHeight: 68,
              titleSpacing: 20,
              title: Row(
                children: [
                  const LinksyMark(size: 34),
                  const SizedBox(width: 10),
                  Text(
                    'Linksy',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: IconButton.filledTonal(
                    tooltip: 'Settings',
                    icon: const Icon(Icons.settings_rounded),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ),
                  ),
                ),
              ],
            ),
            if (empty) ...[
              const SliverToBoxAdapter(child: _EmptyState()),
              if (unpaired.isNotEmpty) ..._nearby(context, unpaired),
            ] else ...[
              SliverToBoxAdapter(child: _ThisPhone(controller: c)),
              SliverToBoxAdapter(
                child: SectionHeader('Your devices', count: paired.length),
              ),
              SliverToBoxAdapter(
                child: Grouped(
                  children: [
                    for (final d in paired) _DeviceCard(view: d, controller: c),
                  ],
                ),
              ),
              ..._nearby(context, unpaired),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 112)),
          ],
        ),
      ),
      floatingActionButton: empty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => showAddDevice(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add device'),
            ),
    );
  }

  static List<Widget> _nearby(BuildContext context, List<DeviceView> views) {
    final scheme = Theme.of(context).colorScheme;
    return [
      SliverToBoxAdapter(
        child: SectionHeader(
          'Nearby',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PulseDot(color: scheme.nearby, size: 6),
              Text(
                'Looking',
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Grouped(
          children: views.isEmpty
              ? [
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'Other devices with Linksy open on this Wi‑Fi show up '
                      'here.',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ]
              : [for (final v in views) _NearbyRow(view: v)],
        ),
      ),
    ];
  }
}

/// This phone as others see it: its name, and that it can be found.
class _ThisPhone extends StatelessWidget {
  const _ThisPhone({required this.controller});

  final LinksyController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = controller.settings?.name ?? controller.node.info.name;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.xl),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.primaryContainer, scheme.tertiaryContainer],
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Icon(
                Icons.smartphone_rounded,
                color: scheme.onPrimaryContainer,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: scheme.onPrimaryContainer,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Transform.translate(
                        offset: const Offset(-5, 0),
                        child: PulseDot(color: scheme.nearby, size: 7),
                      ),
                      Expanded(
                        child: Text(
                          'Visible to your devices on this Wi‑Fi',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onPrimaryContainer.withValues(
                              alpha: 0.8,
                            ),
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
          ],
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.view, required this.controller});

  final DeviceView view;
  final LinksyController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final d = view.device;
    final last = controller.lastActivity(d.id);

    return InkWell(
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => DeviceScreen(deviceId: d.id))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
        child: Row(
          children: [
            DeviceAvatar(
              device: d,
              size: 52,
              presence: view.presence,
              ring: groupFill(scheme),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.name,
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: presenceLabel(view.presence),
                          style: TextStyle(
                            color: presenceColor(scheme, view.presence),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(text: '  ·  ${d.description}'),
                      ],
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (last != null) ...[
                    const SizedBox(height: 8),
                    if (last.isLive)
                      LinearProgressIndicator(
                        value: last.total == 0 || last.bytes == 0
                            ? null
                            : last.bytes / last.total,
                      )
                    else
                      Row(
                        children: [
                          Icon(
                            activityIcon(last),
                            size: 16,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${activityTitle(last)} · '
                              '${activityDetail(last)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, color: scheme.outline),
          ],
        ),
      ),
    );
  }
}

class _NearbyRow extends StatelessWidget {
  const _NearbyRow({required this.view});

  final DeviceView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = view.device;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          DeviceAvatar(device: d, size: 44),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.name, style: theme.textTheme.titleMedium),
                Text(
                  '${d.description} · ${d.shortId}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(minimumSize: const Size(72, 40)),
            onPressed: () =>
                report(context, LinksyScope.read(context).pair(d.id)),
            child: const Text('Pair'),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Column(
        children: [
          Radar(
            size: 240,
            child: Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLowest,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.18),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Center(child: LinksyMark(size: 60)),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Connect your first device',
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            'Open Linksy on your computer, choose “Pair with QR Code”, '
            'then scan it here. No account needed.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            onPressed: () => scanAndPair(context),
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Text('Scan QR code'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            onPressed: () => pairByAddress(context),
            icon: const Icon(Icons.lan_rounded),
            label: const Text('Pair by address'),
          ),
        ],
      ),
    );
  }
}
