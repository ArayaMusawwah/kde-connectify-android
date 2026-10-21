import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/platform.dart';
import '../../app/scope.dart';
import '../../core/models.dart';
import '../../ui/components.dart';
import '../../ui/sig.dart';
import '../device/activity_tile.dart' show linkLabel;

/// The first web link in [text], or null. A link shared from a browser comes
/// alone or after the page title.
String? findWebLink(String text) => RegExp(
  r'https?://[^\s<>"]+',
  caseSensitive: false,
).firstMatch(text)?.group(0);

/// "Share → Linksy": pick a paired computer. A link opens in its browser
/// (or goes to its clipboard, as text), other text goes to its clipboard,
/// files are sent.
class ShareSheet extends StatefulWidget {
  const ShareSheet({super.key, required this.shared});

  final SharedIn shared;

  @override
  State<ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<ShareSheet> {
  /// For a link: open it, or send the text to the clipboard instead.
  bool _asText = false;

  /// For one file: onto the computer's clipboard instead of its Downloads.
  bool _toClipboard = false;

  /// One file small enough for a clipboard (≤ 10 MiB, §4.5).
  bool get _clippable => switch (widget.shared) {
    SharedFiles(:final paths) when paths.length == 1 => (() {
      try {
        return File(paths.single).lengthSync() <= 10 * 1024 * 1024;
      } on FileSystemException {
        return false;
      }
    })(),
    _ => false,
  };

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    final c = LinksyScope.of(context);
    final shared = widget.shared;
    final link = shared is SharedText ? findWebLink(shared.text) : null;
    final (icon, title, detail) = switch (shared) {
      SharedFiles(:final paths) when _toClipboard => (
        Ph.clipboard,
        'Put on a clipboard',
        paths.single.split('/').last,
      ),
      SharedFiles(:final paths) => (
        Ph.files,
        paths.length == 1 ? 'Send a file' : 'Send ${paths.length} files',
        paths.length == 1 ? paths.single.split('/').last : null,
      ),
      SharedText() when link != null && !_asText => (
        Ph.globe,
        'Open on a computer',
        linkLabel(link),
      ),
      SharedText(:final text) => (
        Ph.clipboardText,
        'Send to a clipboard',
        text.trim(),
      ),
    };
    // Only computers that take a file onto their clipboard.
    final devices = _toClipboard
        ? [
            for (final v in c.paired)
              if (v.device.features.contains('clipboard_file')) v,
          ]
        : c.paired;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconCircle(icon: icon, color: Sig.blue, size: 48),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: sora(20, color: s.ink)),
                      if (detail != null && detail.isNotEmpty)
                        Text(
                          detail,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: s.muted, fontSize: 13.5),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (devices.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  _toClipboard
                      ? 'None of your computers takes files on its clipboard '
                            'yet. Update Linksy there.'
                      : 'Pair a computer first, then share to it from any app.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: s.muted, height: 1.4),
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final v in devices)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SigCard(
                          color: s.raised,
                          padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
                          radius: Radii.md,
                          onTap: () => _send(v.device.id, link),
                          child: Row(
                            children: [
                              Orb(
                                picture: c.pictureOf(v.device.id),
                                device: v.device,
                                size: 40,
                                presence: v.presence,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      v.device.name,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                        color: s.ink,
                                      ),
                                    ),
                                    Text(
                                      presenceText(v),
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: s.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                PhBold.arrowRight,
                                color: Sig.blue,
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (_clippable)
              SigButton(
                label: _toClipboard
                    ? 'Send the file instead'
                    : 'Put it on the computer’s clipboard instead',
                kind: SigButtonKind.quiet,
                expand: true,
                height: 46,
                onTap: () => setState(() => _toClipboard = !_toClipboard),
              ),
            if (link != null)
              SigButton(
                label: _asText
                    ? 'Open the link instead'
                    : 'Send as text to the clipboard instead',
                kind: SigButtonKind.quiet,
                expand: true,
                height: 46,
                onTap: () => setState(() => _asText = !_asText),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _send(String deviceId, String? link) async {
    final c = LinksyScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final name = c.device(deviceId)?.device.name ?? 'the computer';
    Navigator.of(context).pop();
    final shared = widget.shared;
    final (error, done) = switch (shared) {
      SharedFiles(:final paths) when _toClipboard => (
        await c.sendToClipboard(deviceId, paths.single),
        'Putting it on $name’s clipboard',
      ),
      SharedFiles(:final paths) => (await c.sendFiles(deviceId, paths), null),
      SharedText() when link != null && !_asText => (
        await c.openUrl(deviceId, link),
        'Opened on $name',
      ),
      SharedText(:final text) => (
        await c.sendText(deviceId, text),
        'Sent to $name’s clipboard',
      ),
    };
    final message = error ?? done;
    if (message != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

/// "Studio Desktop sent a link": open it here, copy it, or leave it (it's in
/// the device's timeline either way).
class LinkReceivedDialog extends StatelessWidget {
  const LinkReceivedDialog({super.key, required this.event});

  final OpenUrlReceived event;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(
              child: IconCircle(icon: Ph.link, color: Sig.incoming, size: 64),
            ),
            const SizedBox(height: 18),
            Text(
              '${event.from.name} sent a link',
              textAlign: TextAlign.center,
              style: sora(21, color: s.ink, height: 1.2),
            ),
            const SizedBox(height: 8),
            Text(
              linkLabel(event.url),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: s.muted, height: 1.4),
            ),
            const SizedBox(height: 24),
            SigButton(
              label: 'Open',
              icon: Ph.arrowSquareOut,
              expand: true,
              onTap: () async {
                Navigator.of(context).pop();
                await LinksyPlatform.openUrl(event.url);
              },
            ),
            SigButton(
              label: 'Copy link',
              kind: SigButtonKind.quiet,
              expand: true,
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.of(context).pop();
                await Clipboard.setData(ClipboardData(text: event.url));
                messenger.showSnackBar(
                  const SnackBar(content: Text('Link copied')),
                );
              },
            ),
            SigButton(
              label: 'Not now',
              kind: SigButtonKind.quiet,
              expand: true,
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
