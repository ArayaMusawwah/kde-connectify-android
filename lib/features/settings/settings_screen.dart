import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/platform.dart';
import '../../app/scope.dart';
import '../../core/demo_node.dart';
import '../../core/models.dart';
import '../../ui/components.dart';
import '../permissions/permissions_sheet.dart';
import '../../ui/format.dart';
import '../../ui/sig.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = LinksyScope.of(context);
    final st = c.settings;
    final s = Sig.of(context);
    final demo = c.node is DemoNode ? c.node as DemoNode : null;

    Future<void> update(NodeSettings next) =>
        report(context, c.updateSettings(next));

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: st == null
            ? const SizedBox.shrink()
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                children: [
                  Row(
                    children: [
                      RoundButton(
                        icon: Ph.arrowLeft,
                        tooltip: 'Back',
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 20, 8, 20),
                    child: Text(
                      'Settings',
                      style: sora(34, weight: FontWeight.w700, color: s.ink),
                    ),
                  ),
                  _ThisPhone(
                    name: st.name,
                    shortId: c.node.info.shortId,
                    onRename: () async {
                      final name = await _askName(context, st.name);
                      if (name != null && name.isNotEmpty && name != st.name) {
                        await update(st.copyWith(name: name));
                      }
                    },
                  ),
                  const SectionLabel('Receiving'),
                  _Group(
                    children: [
                      _Row(
                        icon: Ph.folderSimple,
                        title: 'Save location',
                        caption: friendlyPath(st.downloadDir),
                      ),
                      _Row(
                        icon: Ph.shieldCheck,
                        title: 'Accept from my devices',
                        caption:
                            'Files from paired devices arrive without '
                            'asking.',
                        trailing: Switch(
                          value: st.autoAccept,
                          onChanged: (v) => update(st.copyWith(autoAccept: v)),
                        ),
                      ),
                    ],
                  ),
                  const SectionLabel('Connection'),
                  _Group(
                    children: [
                      _Row(
                        icon: Ph.lightning,
                        title: 'Stay connected',
                        caption:
                            'Faster sharing with nearby devices. Uses '
                            'more battery.',
                        trailing: Switch(
                          value: st.stayConnected,
                          onChanged: (v) =>
                              update(st.copyWith(stayConnected: v)),
                        ),
                      ),
                      _Row(
                        icon: Ph.deviceMobile,
                        title: 'Keep running in the background',
                        caption:
                            'Files, photo backup and calls keep working '
                            'when Linksy is closed. Shows a quiet '
                            'notification.',
                        trailing: Switch(
                          value: c.stayRunning,
                          onChanged: c.setStayRunning,
                        ),
                      ),
                    ],
                  ),
                  const SectionLabel('With your computers'),
                  _Group(
                    children: [
                      _Row(
                        icon: Ph.phoneCall,
                        title: 'Pause music during calls',
                        caption:
                            'Your computers pause what plays while a call '
                            'rings or goes on, and resume after.',
                        trailing: Switch(
                          value: c.pauseOnCalls,
                          onChanged: c.setPauseOnCalls,
                        ),
                      ),
                      _Row(
                        icon: Ph.folderOpen,
                        title: 'Let computers browse files',
                        caption: c.filesFolder == null
                            ? 'Choose a folder your computers can open in '
                                  'their Files app, like Documents (Android '
                                  'doesn’t allow Download).'
                            : 'Shares “${c.filesFolder}”. Tap to choose '
                                  'another folder.',
                        onTap: c.pickFilesFolder,
                        trailing: Switch(
                          value: c.sharingFiles && c.filesFolder != null,
                          onChanged: (v) => v && c.filesFolder == null
                              ? c.pickFilesFolder()
                              : c.setSharingFiles(v),
                        ),
                      ),
                      _Row(
                        icon: Ph.images,
                        title: 'Photo folder',
                        caption: c.photosFolder == null
                            ? 'Choose your camera folder (DCIM › Camera) '
                                  'to back up photos to a computer.'
                            : 'Backs up “${c.photosFolder}”. Turn it on '
                                  'per computer, on its page.',
                        onTap: c.pickPhotosFolder,
                      ),
                    ],
                  ),
                  const SectionLabel('Notifications'),
                  _Group(
                    children: [
                      _Row(
                        icon: Ph.bellRinging,
                        title: 'News from Linksy',
                        caption:
                            'Updates and announcements arrive as '
                            'notifications. Tap to copy this phone’s push '
                            'token (for a test message).',
                        onTap: () async {
                          final token = await LinksyPlatform.pushToken();
                          if (!context.mounted) return;
                          if (token == null) {
                            showMessage(
                              context,
                              'Push needs Google Play services on this phone.',
                            );
                            return;
                          }
                          await Clipboard.setData(ClipboardData(text: token));
                          if (context.mounted) {
                            showMessage(context, 'Push token copied');
                          }
                        },
                      ),
                    ],
                  ),
                  const SectionLabel('Permissions'),
                  const _Group(children: [_Permissions()]),
                  if (demo != null) ...[
                    const SectionLabel('Demo'),
                    _Group(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Simulated devices until the Linksy core is '
                            'connected. These start what another device '
                            'would.',
                            style: TextStyle(color: s.muted, height: 1.4),
                          ),
                        ),
                        _Row(
                          icon: Ph.downloadSimple,
                          title: 'Receive files',
                          onTap: demo.simulateIncomingFiles,
                        ),
                        _Row(
                          icon: Ph.handshake,
                          title: 'Receive a pairing request',
                          onTap: demo.simulateIncomingPairing,
                        ),
                        _Row(
                          icon: Ph.clipboardText,
                          title: 'Receive clipboard text',
                          onTap: demo.simulateClipboard,
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 40),
                  const Center(child: AppIcon(size: 52)),
                  const SizedBox(height: 10),
                  Text(
                    'Your devices, connected.\nNo account, no cloud.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: s.faint, fontSize: 13, height: 1.5),
                  ),
                ],
              ),
      ),
    );
  }

  static Future<String?> _askName(BuildContext context, String current) {
    final text = TextEditingController(text: current);
    return showDialog<String>(
      context: context,
      builder: (dialog) {
        final s = Sig.of(dialog);
        return Dialog(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Name this phone',
                  textAlign: TextAlign.center,
                  style: sora(21, color: s.ink),
                ),
                const SizedBox(height: 6),
                Text(
                  'Your other devices see this name.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: s.muted),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: text,
                  autofocus: true,
                  maxLength: 48,
                  style: sora(18, weight: FontWeight.w500, color: s.ink),
                  onSubmitted: (v) => Navigator.of(dialog).pop(v.trim()),
                ),
                const SizedBox(height: 8),
                SigButton(
                  label: 'Save',
                  expand: true,
                  onTap: () => Navigator.of(dialog).pop(text.text.trim()),
                ),
                SigButton(
                  label: 'Cancel',
                  kind: SigButtonKind.quiet,
                  expand: true,
                  onTap: () => Navigator.of(dialog).pop(),
                ),
              ],
            ),
          ),
        );
      },
    ).whenComplete(text.dispose);
  }
}

class _ThisPhone extends StatelessWidget {
  const _ThisPhone({
    required this.name,
    required this.shortId,
    required this.onRename,
  });

  final String name;
  final String shortId;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    return Pressable(
      onTap: onRename,
      semanticLabel: 'Rename $name',
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: s.hero,
          borderRadius: BorderRadius.circular(Radii.xl),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
              child: const Center(child: LinksyMark(size: 32)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: sora(21, color: Colors.white)),
                  const SizedBox(height: 2),
                  Text(
                    'This phone · $shortId',
                    style: sora(
                      12.5,
                      weight: FontWeight.w500,
                      color: Colors.white60,
                      spacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Ph.pencilSimple, color: Colors.white70),
          ],
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    return SigCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: s.line),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    this.caption,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? caption;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      child: Row(
        children: [
          Icon(icon, color: Sig.blue, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    color: s.ink,
                  ),
                ),
                if (caption != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    caption!,
                    style: TextStyle(
                      fontSize: 13,
                      color: s.muted,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          if (onTap != null) Icon(Ph.caretRight, color: s.faint, size: 18),
        ],
      ),
    );
    return onTap == null ? row : Pressable(onTap: onTap, child: row);
  }
}

/// How many of Linksy's permissions are allowed; opens the sheet that asks
/// Android for the rest. Read again on return.
class _Permissions extends StatefulWidget {
  const _Permissions();

  @override
  State<_Permissions> createState() => _PermissionsState();
}

class _PermissionsState extends State<_Permissions>
    with WidgetsBindingObserver {
  int? _allowed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _read();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _read();
  }

  Future<void> _read() async {
    final p = await LinksyPlatform.permissions();
    if (!mounted || p == null) return;
    setState(
      () => _allowed = [p.notifications, p.camera].where((x) => x).length,
    );
  }

  @override
  Widget build(BuildContext context) => _Row(
    icon: Ph.shieldCheck,
    title: 'Notifications and camera',
    caption: _allowed == null
        ? 'What Linksy asks Android for, and why.'
        : _allowed == 2
        ? 'Both allowed.'
        : '$_allowed of 2 allowed. Tap to allow the rest.',
    onTap: () async {
      await showPermissions(context);
      await _read();
    },
  );
}
