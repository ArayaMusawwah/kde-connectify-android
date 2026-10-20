import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/activity.dart';
import '../../app/platform.dart';
import '../../app/scope.dart';
import '../../core/models.dart';
import '../../ui/components.dart';
import '../../ui/format.dart';
import '../../ui/sig.dart';
import 'activity_tile.dart';

/// Picks files and sends them to a device, reporting any error.
Future<void> pickAndSend(BuildContext context, String deviceId) async {
  final c = LinksyScope.read(context);
  final paths = await LinksyPlatform.pickFiles();
  if (context.mounted) await report(context, c.sendFiles(deviceId, paths));
}

/// A device's page: big actions, then everything shared with it, as a
/// timeline by day.
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
    final s = Sig.of(context);
    final days = _byDay(c.activityFor(deviceId));

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayFor(Brightness.dark),
      child: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              toolbarHeight: 0,
              collapsedHeight: 0,
              systemOverlayStyle: overlayFor(Brightness.dark),
              backgroundColor: s.heroTop,
            ),
            // One box, so the actions paint over the hero they overlap.
            SliverToBoxAdapter(
              child: Column(
                children: [
                  _Hero(view: view),
                  Transform.translate(
                    offset: const Offset(0, -34),
                    child: _Actions(view: view),
                  ),
                ],
              ),
            ),
            if (days.isEmpty)
              SliverToBoxAdapter(child: _NoActivity(name: view.device.name))
            else
              for (final (day, entries) in days) ...[
                SliverToBoxAdapter(child: SectionLabel(day)),
                SliverList.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, i) => TimelineEntry(
                    activity: entries[i],
                    first: i == 0,
                    last: i == entries.length - 1,
                  ),
                ),
              ],
            SliverToBoxAdapter(
              child: SizedBox(
                height: 32 + MediaQuery.paddingOf(context).bottom,
              ),
            ),
          ],
        ),
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
}

class _Hero extends StatelessWidget {
  const _Hero({required this.view});

  final DeviceView view;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    final d = view.device;
    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(36)),
        color: s.hero,
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 64),
      child: Column(
        children: [
          Row(
            children: [
              RoundButton(
                icon: Ph.arrowLeft,
                tooltip: 'Back',
                onDark: true,
                onTap: () => Navigator.of(context).maybePop(),
              ),
              const Spacer(),
              RoundButton(
                icon: Ph.dotsThree,
                tooltip: 'More',
                onDark: true,
                onTap: () => _more(context, d),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Orb(device: d, size: 104, presence: view.presence, onBlue: true),
          const SizedBox(height: 18),
          Text(
            d.name,
            textAlign: TextAlign.center,
            style: sora(30, weight: FontWeight.w700, color: Colors.white),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (view.presence == Presence.notNearby)
                Icon(Ph.wifiSlash, size: 15, color: Colors.white54)
              else
                PulseDot(
                  color: presenceColor(s, view.presence, onBlue: true),
                  size: 7,
                ),
              const SizedBox(width: 4),
              Text(
                presenceLabel(view.presence),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: presenceColor(s, view.presence, onBlue: true),
                ),
              ),
              Text(
                '   ${d.description}',
                style: const TextStyle(fontSize: 14, color: Colors.white70),
              ),
            ],
          ),
          if (view.battery case final battery?
              when view.presence != Presence.notNearby) ...[
            const SizedBox(height: 6),
            _BatteryLine(battery: battery),
          ],
        ],
      ),
    );
  }

  Future<void> _more(BuildContext context, DeviceInfo d) =>
      showModalBottomSheet<void>(
        context: context,
        builder: (sheet) {
          final s = Sig.of(sheet);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    d.name,
                    textAlign: TextAlign.center,
                    style: sora(20, color: s.ink),
                  ),
                  Text(
                    'ID ${d.shortId}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: s.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  SigButton(
                    label: 'Forget this device',
                    icon: Ph.linkBreak,
                    kind: SigButtonKind.secondary,
                    expand: true,
                    onTap: () {
                      Navigator.of(sheet).pop();
                      _forget(context, d);
                    },
                  ),
                ],
              ),
            ),
          );
        },
      );

  Future<void> _forget(BuildContext context, DeviceInfo d) async {
    final c = LinksyScope.read(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) {
        final s = Sig.of(dialog);
        return Dialog(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: IconCircle(icon: Ph.linkBreak, color: s.red, size: 56),
                ),
                const SizedBox(height: 16),
                Text(
                  'Forget ${d.name}?',
                  textAlign: TextAlign.center,
                  style: sora(21, color: s.ink),
                ),
                const SizedBox(height: 8),
                Text(
                  'You’ll need to pair again to share with it. Its activity on '
                  'this phone is cleared too.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: s.muted, height: 1.4),
                ),
                const SizedBox(height: 24),
                SigButton(
                  label: 'Forget',
                  kind: SigButtonKind.danger,
                  expand: true,
                  onTap: () => Navigator.of(dialog).pop(true),
                ),
                SigButton(
                  label: 'Cancel',
                  kind: SigButtonKind.quiet,
                  expand: true,
                  onTap: () => Navigator.of(dialog).pop(false),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (ok != true || !context.mounted) return;
    Navigator.of(context).pop();
    await c.forget(d.id);
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.view});

  final DeviceView view;

  @override
  Widget build(BuildContext context) {
    final c = LinksyScope.read(context);
    final s = Sig.of(context);
    final id = view.device.id;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Pressable(
            onTap: () => pickAndSend(context, id),
            semanticLabel: 'Send files',
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 18, 18),
              // White on the blue header it overlaps; the blue is in the button.
              decoration: BoxDecoration(
                color: s.card,
                borderRadius: BorderRadius.circular(Radii.lg),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Send files', style: sora(21, color: s.ink)),
                        const SizedBox(height: 2),
                        Text(
                          'Photos, documents, anything',
                          style: TextStyle(fontSize: 13.5, color: s.muted),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Sig.blue,
                    ),
                    child: const Icon(
                      PhFill.paperPlaneTilt,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _SmallAction(
                  icon: Ph.clipboardText,
                  title: 'Clipboard',
                  caption: 'Send what you copied',
                  onTap: () => report(context, c.sendClipboard(id)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SmallAction(
                  icon: Ph.bellRinging,
                  title: 'Ping',
                  caption: 'Make it chime',
                  onTap: () => report(context, c.ping(id)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _FindAction(view: view),
        ],
      ),
    );
  }
}

/// "Find my computer": rings it until stopped (or 30 s), so it can be found.
class _FindAction extends StatelessWidget {
  const _FindAction({required this.view});

  final DeviceView view;

  @override
  Widget build(BuildContext context) {
    final c = LinksyScope.of(context);
    final s = Sig.of(context);
    final id = view.device.id;
    final ringing = c.isFinding(id);
    return SigCard(
      onTap: () => report(context, ringing ? c.stopFinding(id) : c.find(id)),
      color: ringing ? Sig.blue : null,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          ringing
              ? Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Sig.deep,
                  ),
                  child: const Icon(
                    PhFill.bellRinging,
                    color: Colors.white,
                    size: 20,
                  ),
                )
              : IconCircle(icon: Ph.binoculars, color: Sig.blue, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ringing ? 'Ringing…' : 'Find ${view.device.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sora(16, color: ringing ? Colors.white : s.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  ringing
                      ? 'Tap to stop'
                      : 'Make it ring loudly so you can find it',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: ringing ? Colors.white70 : s.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "82% · Charging" under the device's name.
class _BatteryLine extends StatelessWidget {
  const _BatteryLine({required this.battery});

  final Battery battery;

  @override
  Widget build(BuildContext context) {
    final b = battery;
    final icon = b.charging
        ? Ph.batteryCharging
        : b.level >= 90
        ? Ph.batteryFull
        : b.level >= 60
        ? Ph.batteryHigh
        : b.level >= 30
        ? Ph.batteryMedium
        : b.level > 15
        ? Ph.batteryLow
        : Ph.batteryWarning;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 17, color: Colors.white70),
        const SizedBox(width: 5),
        Text(
          '${b.level}%${b.charging ? ' · Charging' : ''}',
          style: const TextStyle(fontSize: 14, color: Colors.white70),
        ),
      ],
    );
  }
}

class _SmallAction extends StatelessWidget {
  const _SmallAction({
    required this.icon,
    required this.title,
    required this.caption,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    return SigCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconCircle(icon: icon, color: Sig.blue, size: 40),
          const SizedBox(height: 14),
          Text(title, style: sora(16, color: s.ink)),
          const SizedBox(height: 2),
          Text(caption, style: TextStyle(fontSize: 12.5, color: s.muted)),
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
    final s = Sig.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 12, 40, 0),
      child: Column(
        children: [
          Icon(Ph.arrowsLeftRight, size: 34, color: s.faint),
          const SizedBox(height: 12),
          Text('Nothing shared yet', style: sora(17, color: s.ink)),
          const SizedBox(height: 6),
          Text(
            'Files, clipboard text and pings between this phone and $name '
            'line up here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: s.muted, height: 1.4),
          ),
        ],
      ),
    );
  }
}
