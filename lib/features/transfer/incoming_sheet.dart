import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../core/models.dart';
import '../../ui/format.dart';
import '../../ui/widgets.dart';

/// "Studio Desktop wants to share": names, count and size, Accept / Decline.
class IncomingFilesSheet extends StatelessWidget {
  const IncomingFilesSheet({super.key, required this.request});

  final TransferRequest request;

  static const _shown = 4;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final files = request.files;
    final count = files.length == 1 ? '1 item' : '${files.length} items';
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  DeviceAvatar(device: request.from, size: 72),
                  Positioned(
                    right: -6,
                    bottom: -6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        shape: BoxShape.circle,
                      ),
                      child: IconBadge(
                        icon: Icons.south_rounded,
                        size: 28,
                        foreground: scheme.onPrimary,
                        background: scheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '${request.from.name} wants to share',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              '$count · ${formatBytes(request.total)}',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Grouped(
              padding: EdgeInsets.zero,
              color: scheme.surfaceContainer,
              children: [
                for (final f in files.take(_shown))
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(fileIcon(f.name), color: scheme.primary),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            f.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          formatBytes(f.size),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (files.length > _shown)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Text(
                      'and ${files.length - _shown} more',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                    ),
                    onPressed: () => _answer(context, false),
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                    ),
                    onPressed: () => _answer(context, true),
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Accept'),
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
