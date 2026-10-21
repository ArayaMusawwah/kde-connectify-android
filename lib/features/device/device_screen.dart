import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/activity.dart';
import '../../app/linksy_controller.dart';
import '../../app/platform.dart';
import '../../app/scope.dart';
import '../../core/models.dart';
import '../../ui/components.dart';
import '../../ui/format.dart';
import '../../ui/sig.dart';
import '../remote/remote_screen.dart';
import 'activity_tile.dart';

/// Picks files and sends them to a device, reporting any error.
Future<void> pickAndSend(BuildContext context, String deviceId) async {
  final c = LinksyScope.read(context);
  final paths = await LinksyPlatform.pickFiles();
  if (context.mounted) await report(context, c.sendFiles(deviceId, paths));
}

/// A device's page: big actions, then everything shared with it, as a
/// timeline by day.
class DeviceScreen extends StatefulWidget {
  const DeviceScreen({super.key, required this.deviceId});

  final String deviceId;

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  late final LinksyController _c;

  String get deviceId => widget.deviceId;

  // A computer's players show here while the page is open.
  @override
  void initState() {
    super.initState();
    _c = LinksyScope.read(context);
    _c.watchMedia(deviceId);
  }

  @override
  void dispose() {
    _c.unwatchMedia(deviceId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = LinksyScope.of(context);
    final view = c.device(deviceId);
    if (view == null || !view.trusted) {
      // Forgotten while open.
      return const Scaffold(body: SizedBox.shrink());
    }
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
              // The banner's top under its shadow, so the two meet without
              // a seam.
              backgroundColor: Color.alphaBlend(
                const Color(0x590A1024),
                Sig.deep,
              ),
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
                  if (c.media[deviceId]?.players case final players?
                      when players.isNotEmpty)
                    for (final p in players)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                        child: _NowPlaying(deviceId: deviceId, player: p),
                      ),
                  if (_isComputer(view.device)) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: _WatchScreen(view: view),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: _PhotoBackup(view: view),
                    ),
                  ],
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

  static bool _isComputer(DeviceInfo d) =>
      d.kind == DeviceKind.desktop || d.kind == DeviceKind.laptop;

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

  /// Tall enough for the name and its lines, plus the 64 px the action card
  /// overlaps at the bottom.
  static const height = 330.0;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    final c = LinksyScope.of(context);
    final d = view.device;
    final picture = c.pictures[d.id];

    final details = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          d.name,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: sora(30, weight: FontWeight.w700, color: Colors.white),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
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
        if (c.lockWatchers.containsKey(d.id)) ...[
          const SizedBox(height: 6),
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Ph.lockSimple, size: 16, color: Colors.white70),
              SizedBox(width: 5),
              Text(
                'Locks when you leave with this phone',
                style: TextStyle(fontSize: 14, color: Colors.white70),
              ),
            ],
          ),
        ],
      ],
    );

    Widget button(IconData icon, String tip, VoidCallback onTap) =>
        RoundButton(icon: icon, tooltip: tip, onDark: true, onTap: onTap);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(36)),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (picture != null)
              Image.file(
                File(picture),
                key: ValueKey(c.pictureVersion),
                fit: BoxFit.cover,
                gaplessPlayback: true,
              )
            else
              const _GridBanner(),
            // An inner shadow: deep at the bottom, where the name sits, and
            // light at the top, under the buttons; the picture or the grid
            // fades into it. (The one gradient in the app, on purpose.)
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x590A1024),
                    Color(0x000A1024),
                    Color(0x000A1024),
                    Color(0xCC0A1024),
                    Color(0xF20A1024),
                  ],
                  stops: [0, 0.22, 0.38, 0.72, 1],
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              top: 8,
              child: Row(
                children: [
                  button(
                    Ph.arrowLeft,
                    'Back',
                    () => Navigator.of(context).maybePop(),
                  ),
                  const Spacer(),
                  button(Ph.dotsThree, 'More', () => _more(context, d)),
                ],
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 64,
              child: Center(child: details),
            ),
          ],
        ),
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
                    label: LinksyScope.read(context).pictures.containsKey(d.id)
                        ? 'Change picture'
                        : 'Add a picture',
                    icon: Ph.images,
                    kind: SigButtonKind.secondary,
                    expand: true,
                    onTap: () {
                      Navigator.of(sheet).pop();
                      LinksyScope.read(context).pickPicture(d.id);
                    },
                  ),
                  if (LinksyScope.read(context).pictures.containsKey(d.id)) ...[
                    const SizedBox(height: 10),
                    SigButton(
                      label: 'Remove picture',
                      kind: SigButtonKind.quiet,
                      expand: true,
                      onTap: () {
                        Navigator.of(sheet).pop();
                        LinksyScope.read(context).removePicture(d.id);
                      },
                    ),
                  ],
                  const SizedBox(height: 10),
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _SmallAction(
                  icon: Ph.mouseSimple,
                  title: 'Remote',
                  caption: 'Touchpad and slides',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => RemoteScreen(device: view.device),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: _FindAction(view: view)),
            ],
          ),
        ],
      ),
    );
  }
}

/// The banner without a picture: deep blue with a fine grid, which the
/// banner's shadow fades out toward the name.
class _GridBanner extends StatelessWidget {
  const _GridBanner();

  @override
  Widget build(BuildContext context) =>
      const CustomPaint(painter: _Grid(), child: SizedBox.expand());
}

class _Grid extends CustomPainter {
  const _Grid();

  static const _cell = 28.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Sig.deep);
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.13)
      ..strokeWidth = 1;
    // Centered, so the grid sits evenly on any width.
    final dx = (size.width % _cell) / 2;
    for (var x = dx; x <= size.width; x += _cell) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (var y = 0.0; y <= size.height; y += _cell) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  @override
  bool shouldRepaint(_Grid oldDelegate) => false;
}

/// "Find my computer": rings it until stopped (or 30 s), so it can be found.
class _FindAction extends StatelessWidget {
  const _FindAction({required this.view});

  final DeviceView view;

  @override
  Widget build(BuildContext context) {
    final c = LinksyScope.of(context);
    final id = view.device.id;
    final ringing = c.isFinding(id);
    return _SmallAction(
      icon: ringing ? PhFill.bellRinging : Ph.binoculars,
      title: ringing ? 'Ringing…' : 'Find it',
      caption: ringing ? 'Tap to stop' : 'Make it ring loudly',
      active: ringing,
      onTap: () => report(context, ringing ? c.stopFinding(id) : c.find(id)),
    );
  }
}

/// What a computer plays (its MPRIS players), with play/pause and skip.
class _NowPlaying extends StatelessWidget {
  const _NowPlaying({required this.deviceId, required this.player});

  final String deviceId;
  final MediaPlayer player;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    final c = LinksyScope.read(context);
    final p = player;
    final art = p.art;
    Uint8List? cover;
    if (art != null) {
      try {
        cover = base64Decode(art);
      } on FormatException {
        cover = null;
      }
    }
    Widget control(
      IconData icon,
      String tip,
      String action, {
      bool big = false,
    }) => Tooltip(
      message: tip,
      child: Pressable(
        onTap: () => report(context, c.mediaCommand(deviceId, p.id, action)),
        semanticLabel: tip,
        child: Container(
          width: big ? 48 : 40,
          height: big ? 48 : 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: big ? Sig.blue : Colors.transparent,
          ),
          child: Icon(
            icon,
            size: big ? 22 : 20,
            color: big ? Colors.white : s.ink,
          ),
        ),
      ),
    );
    return SigCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.sm),
            child: SizedBox(
              width: 52,
              height: 52,
              child: cover != null
                  ? Image.memory(
                      cover,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    )
                  : ColoredBox(
                      color: s.raised,
                      child: Icon(Ph.musicNotes, color: s.muted),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.title.isEmpty ? p.app : p.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: s.ink,
                  ),
                ),
                Text(
                  [if (p.artist.isNotEmpty) p.artist, p.app].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: s.muted),
                ),
              ],
            ),
          ),
          if (p.canPrevious) control(PhFill.skipBack, 'Previous', 'previous'),
          control(
            p.playing ? PhFill.pause : PhFill.play,
            p.playing ? 'Pause' : 'Play',
            'play_pause',
            big: true,
          ),
          if (p.canNext) control(PhFill.skipForward, 'Next', 'next'),
        ],
      ),
    );
  }
}

/// A computer's screen on this phone: just watch it, or drive it with touch.
/// Its user allows it and picks the screen there.
class _WatchScreen extends StatelessWidget {
  const _WatchScreen({required this.view});

  final DeviceView view;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    final c = LinksyScope.read(context);
    final id = view.device.id;
    Widget button(String label, bool control) => Expanded(
      child: SigButton(
        label: label,
        kind: control ? SigButtonKind.primary : SigButtonKind.secondary,
        height: 44,
        onTap: () {
          showMessage(context, 'Allow it on ${view.device.name}…');
          report(context, c.watchScreen(id, control: control));
        },
      ),
    );
    return SigCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconCircle(icon: Ph.monitor, color: Sig.blue, size: 40),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('See its screen', style: sora(16, color: s.ink)),
                    const SizedBox(height: 2),
                    Text(
                      'Watch it here, or control it with touch',
                      style: TextStyle(fontSize: 12.5, color: s.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              button('Watch', false),
              const SizedBox(width: 10),
              button('Control', true),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Back up new photos to fedora": photo auto-import from the folder picked
/// in Android's picker, while the computer is around.
class _PhotoBackup extends StatelessWidget {
  const _PhotoBackup({required this.view});

  final DeviceView view;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    final c = LinksyScope.of(context);
    final id = view.device.id;
    final on = c.backsUpPhotos(id);
    final name = view.device.name;
    final at = c.photosBackedUp(id);
    final detail = !on
        ? 'New photos go to $name’s Pictures folder'
        : c.photosDeclined(id)
        ? '$name doesn’t take photos. Turn on “Import Photos From Phones” there.'
        : [
            'From ${c.photosFolder ?? 'your camera folder'}',
            if (at != null) 'last ${formatClock(at)}',
          ].join(' · ');
    return SigCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          IconCircle(icon: Ph.images, color: Sig.blue, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Back up photos', style: sora(16, color: s.ink)),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: on && c.photosDeclined(id) ? s.red : s.muted,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: on, onChanged: (v) => c.setPhotoBackup(id, v)),
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
    this.active = false,
  });

  final IconData icon;
  final String title;
  final String caption;
  final VoidCallback onTap;

  /// Blue while it's going on (ringing).
  final bool active;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    return SigCard(
      onTap: onTap,
      color: active ? Sig.blue : null,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          active
              ? Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Sig.deep,
                  ),
                  child: Icon(icon, color: Colors.white, size: 20),
                )
              : IconCircle(icon: icon, color: Sig.blue, size: 40),
          const SizedBox(height: 14),
          Text(title, style: sora(16, color: active ? Colors.white : s.ink)),
          const SizedBox(height: 2),
          Text(
            caption,
            style: TextStyle(
              fontSize: 12.5,
              color: active ? Colors.white70 : s.muted,
            ),
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
