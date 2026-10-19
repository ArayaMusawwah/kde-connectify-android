import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../core/models.dart';
import '../../ui/components.dart';
import '../../ui/format.dart';
import '../../ui/sig.dart';

/// "Studio Desktop is sending you 3 files": names, sizes, Accept / Decline.
class IncomingFilesSheet extends StatelessWidget {
  const IncomingFilesSheet({super.key, required this.request});

  final TransferRequest request;

  static const _shown = 4;

  @override
  Widget build(BuildContext context) {
    final s = Sig.of(context);
    final files = request.files;
    final what = files.length == 1 ? 'a file' : '${files.length} files';
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Orb(device: request.from, size: 56, glow: true),
                const SizedBox(width: 6),
                const Icon(PhBold.arrowRight, color: Sig.incoming, size: 18),
                const SizedBox(width: 6),
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Sig.incoming.withValues(alpha: 0.14),
                  ),
                  child: const Icon(
                    Ph.deviceMobile,
                    color: Sig.incoming,
                    size: 26,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: request.from.name),
                  TextSpan(
                    text: ' is sending you $what',
                    style: TextStyle(color: s.muted),
                  ),
                ],
              ),
              style: sora(23, color: s.ink, height: 1.2),
            ),
            const SizedBox(height: 6),
            Text(
              '${formatBytes(request.total)} in total',
              style: TextStyle(fontSize: 14, color: s.muted),
            ),
            const SizedBox(height: 18),
            for (final f in files.take(_shown))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SigCard(
                  color: s.bg,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Icon(fileIcon(f.name), color: Sig.incoming, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          f.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: s.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        formatBytes(f.size),
                        style: sora(
                          13,
                          weight: FontWeight.w500,
                          color: s.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (files.length > _shown)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  '+ ${files.length - _shown} more',
                  style: TextStyle(color: s.muted),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: SigButton(
                    label: 'Decline',
                    kind: SigButtonKind.secondary,
                    expand: true,
                    height: 56,
                    onTap: () => _answer(context, false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SigButton(
                    label: 'Accept',
                    icon: PhBold.downloadSimple,
                    expand: true,
                    height: 56,
                    onTap: () => _answer(context, true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _answer(BuildContext context, bool accept) async {
    final c = LinksyScope.read(context);
    Navigator.of(context).pop();
    await c.respond(request.transfer, accept: accept);
  }
}
