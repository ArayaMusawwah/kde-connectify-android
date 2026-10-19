import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/linksy_controller.dart';
import '../../app/scope.dart';
import '../../core/models.dart';
import '../../ui/components.dart';
import '../../ui/orbit.dart';
import '../../ui/sig.dart';
import '../device/activity_tile.dart';
import '../device/device_screen.dart';
import '../pairing/pairing_flows.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = LinksyScope.of(context);
    final s = Sig.of(context);
    final paired = c.paired;
    final unpaired = c.unpaired;
    final top = MediaQuery.paddingOf(context).top;

    void open(DeviceView v) => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DeviceScreen(deviceId: v.device.id)),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // The hero is ink in both themes.
      value: overlayFor(Brightness.dark),
      child: Scaffold(
        body: CustomScrollView(
          slivers: [
            // Keeps the status bar on ink once the hero scrolls away.
            SliverAppBar(
              pinned: true,
              toolbarHeight: 0,
              collapsedHeight: 0,
              systemOverlayStyle: overlayFor(Brightness.dark),
              backgroundColor: s.heroTop,
            ),
            SliverToBoxAdapter(
              child: _Hero(
                controller: c,
                onDevice: open,
                onPair: (v) => report(context, c.pair(v.device.id)),
                topPadding: top,
              ),
            ),
            if (paired.isEmpty)
              const SliverToBoxAdapter(child: _GetStarted())
            else ...[
              SliverToBoxAdapter(
                child: SectionLabel(
                  'Your devices',
                  trailing: Text(
                    '${paired.length}',
                    style: sora(13, color: s.muted),
                  ),
                ),
              ),
              SliverList.separated(
                itemCount: paired.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _DeviceRow(
                    view: paired[i],
                    controller: c,
                    onTap: () => open(paired[i]),
                  ),
                ),
              ),
            ],
            if (unpaired.isNotEmpty) ...[
              const SliverToBoxAdapter(
                child: SectionLabel('Nearby, not paired'),
              ),
              SliverList.separated(
                itemCount: unpaired.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _NearbyRow(view: unpaired[i]),
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: paired.isEmpty
            ? null
            : SigButton(
                label: 'Add a device',
                icon: PhBold.qrCode,
                onTap: () => showAddDevice(context),
              ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.controller,
    required this.onDevice,
    required this.onPair,
    required this.topPadding,
  });

  final LinksyController controller;
  final ValueChanged<DeviceView> onDevice;
  final ValueChanged<DeviceView> onPair;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    final c = controller;
    final name = c.settings?.name ?? c.node.info.name;
    final views = [...c.paired, ...c.unpaired];
    final connected = c.paired.where((d) => d.connected).length;
    final nearby = c.paired.where((d) => d.nearby).length;

    return Container(
      decoration: BoxDecoration(
        gradient: s.hero,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(36)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Wordmark(color: Colors.white),
              const Spacer(),
              RoundButton(
                icon: Ph.gearSix,
                tooltip: 'Settings',
                onDark: true,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          OrbitView(devices: views, onDevice: onDevice, onPair: onPair),
          const SizedBox(height: 8),
          Row(
            children: [
              PulseDot(color: Sig.cyan, size: 7),
              const SizedBox(width: 4),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextSpan(
                        text: ' is visible on this Wi-Fi',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                  style: const TextStyle(
                    fontFamily: Sig.body,
                    fontSize: 13.5,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (c.paired.isNotEmpty) ...[
                _Stat(value: nearby, label: 'near'),
                const SizedBox(width: 6),
                _Stat(value: connected, label: 'linked', accent: true),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.accent = false});

  final int value;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: accent
          ? Sig.cyan.withValues(alpha: 0.16)
          : Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$value ',
            style: sora(12.5, weight: FontWeight.w700, spacing: 0),
          ),
          TextSpan(text: label),
        ],
      ),
      style: TextStyle(
        fontFamily: Sig.body,
        fontSize: 12,
        color: accent ? Sig.cyan : Colors.white.withValues(alpha: 0.75),
      ),
    ),
  );
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.view,
    required this.controller,
    required this.onTap,
  });

  final DeviceView view;
  final LinksyController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    final d = view.device;
    final last = controller.lastActivity(d.id);
    final away = view.presence == Presence.notNearby;

    return SigCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Row(
        children: [
          Orb(device: d, size: 46, presence: view.presence),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d.name,
                  style: sora(16.5, color: s.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(kindIcon(d.kind), size: 14, color: s.muted),
                    const SizedBox(width: 5),
                    Text(
                      presenceLabel(view.presence),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: away ? s.faint : presenceColor(s, view.presence),
                      ),
                    ),
                    if (last != null && !last.isLive) ...[
                      Text('  ·  ', style: TextStyle(color: s.faint)),
                      Expanded(
                        child: Text(
                          activityTitle(last),
                          style: TextStyle(fontSize: 13, color: s.muted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
                if (last != null && last.isLive) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    color: last.incoming ? Sig.incoming : Sig.outgoing,
                    value: last.total == 0 || last.bytes == 0
                        ? null
                        : last.bytes / last.total,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (away)
            Icon(Ph.caretRight, color: s.faint, size: 18)
          else
            _QuickSend(deviceId: d.id),
        ],
      ),
    );
  }
}

/// Send files without opening the device first.
class _QuickSend extends StatelessWidget {
  const _QuickSend({required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: () => pickAndSend(context, deviceId),
    scale: 0.88,
    semanticLabel: 'Send files',
    child: Container(
      width: 44,
      height: 44,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: Sig.sendGradient,
      ),
      child: const Icon(PhFill.paperPlaneTilt, color: Colors.white, size: 19),
    ),
  );
}

class _NearbyRow extends StatelessWidget {
  const _NearbyRow({required this.view});

  final DeviceView view;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    final d = view.device;
    return SigCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Row(
        children: [
          IconCircle(icon: kindIcon(d.kind), color: Sig.cyan, size: 46),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.name, style: sora(16, color: s.ink)),
                Text(
                  '${d.description} · ${d.shortId}',
                  style: TextStyle(fontSize: 12.5, color: s.muted),
                ),
              ],
            ),
          ),
          SigButton(
            label: 'Pair',
            height: 40,
            kind: SigButtonKind.secondary,
            onTap: () => report(context, LinksyScope.read(context).pair(d.id)),
          ),
        ],
      ),
    );
  }
}

/// No devices yet: how pairing works, in three steps.
class _GetStarted extends StatelessWidget {
  const _GetStarted();

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    const steps = [
      ('Open Linksy on your computer', Ph.desktop),
      ('Choose “Pair with QR Code”', Ph.qrCode),
      ('Scan it with this phone', Ph.scan),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Connect your\nfirst device',
              style: sora(
                30,
                weight: FontWeight.w700,
                color: s.ink,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Straight over your Wi-Fi. No account, no cloud.',
              style: TextStyle(fontSize: 15, color: s.muted),
            ),
          ),
          const SizedBox(height: 20),
          SigCard(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
            child: Column(
              children: [
                for (var i = 0; i < steps.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Sig.blue.withValues(alpha: 0.1),
                          ),
                          child: Text(
                            '${i + 1}',
                            style: sora(
                              14,
                              weight: FontWeight.w700,
                              color: Sig.blue,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            steps[i].$1,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: s.ink,
                            ),
                          ),
                        ),
                        Icon(steps[i].$2, color: s.faint, size: 22),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SigButton(
            label: 'Scan QR code',
            icon: PhBold.scan,
            expand: true,
            height: 58,
            onTap: () => scanAndPair(context),
          ),
          const SizedBox(height: 4),
          SigButton(
            label: 'Pair by address instead',
            kind: SigButtonKind.quiet,
            expand: true,
            onTap: () => pairByAddress(context),
          ),
        ],
      ),
    );
  }
}
