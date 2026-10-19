import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../core/demo_node.dart';
import '../../core/models.dart';
import '../../ui/format.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = LinksyScope.of(context);
    final s = c.settings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final demo = c.node is DemoNode ? c.node as DemoNode : null;

    Future<void> update(NodeSettings next) =>
        report(context, c.updateSettings(next));

    Future<void> rename() async {
      if (s == null) return;
      final name = await _askName(context, s.name);
      if (name != null && name.isNotEmpty && name != s.name) {
        await update(s.copyWith(name: name));
      }
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar.large(title: Text('Settings')),
          if (s != null)
            SliverList.list(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Material(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(Radii.xl),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(Radii.xl),
                      onTap: rename,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            IconBadge(
                              icon: Icons.smartphone_rounded,
                              size: 56,
                              foreground: scheme.onPrimary,
                              background: scheme.primary,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.name,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      color: scheme.onPrimaryContainer,
                                    ),
                                  ),
                                  Text(
                                    'Android phone · ${c.node.info.shortId}',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: scheme.onPrimaryContainer
                                          .withValues(alpha: 0.75),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.edit_rounded,
                              color: scheme.onPrimaryContainer,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SectionHeader('Receiving'),
                Grouped(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.folder_rounded),
                      title: const Text('Save location'),
                      subtitle: Text(friendlyPath(s.downloadDir)),
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.verified_user_rounded),
                      title: const Text('Accept from paired devices'),
                      subtitle: const Text(
                        'Files from your devices arrive without asking.',
                      ),
                      value: s.autoAccept,
                      onChanged: (v) => update(s.copyWith(autoAccept: v)),
                    ),
                  ],
                ),
                const SectionHeader('Connection'),
                Grouped(
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.link_rounded),
                      title: const Text('Stay connected'),
                      subtitle: const Text(
                        'Keeps links to nearby devices open for faster '
                        'sharing. Uses more battery.',
                      ),
                      value: s.stayConnected,
                      onChanged: (v) => update(s.copyWith(stayConnected: v)),
                    ),
                  ],
                ),
                if (demo != null) ...[
                  const SectionHeader('Demo'),
                  Grouped(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                        child: Text(
                          'This build runs on a simulated node with made-up '
                          'devices until the Linksy core is connected. These '
                          'start what another device would.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.download_rounded),
                        title: const Text('Receive files'),
                        onTap: demo.simulateIncomingFiles,
                      ),
                      ListTile(
                        leading: const Icon(Icons.handshake_rounded),
                        title: const Text('Receive a pairing request'),
                        onTap: demo.simulateIncomingPairing,
                      ),
                      ListTile(
                        leading: const Icon(Icons.content_paste_rounded),
                        title: const Text('Receive clipboard text'),
                        onTap: demo.simulateClipboard,
                      ),
                    ],
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                  child: Column(
                    children: [
                      const LinksyMark(size: 32),
                      const SizedBox(height: 8),
                      Text(
                        'Linksy · Your devices, connected.\n'
                        'No account, no cloud. Everything stays on your '
                        'network.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  static Future<String?> _askName(BuildContext context, String current) {
    final text = TextEditingController(text: current);
    return showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        icon: const Icon(Icons.badge_rounded),
        title: const Text('Device name'),
        content: TextField(
          controller: text,
          autofocus: true,
          maxLength: 48,
          decoration: const InputDecoration(
            helperText: 'Your other devices see this name.',
          ),
          onSubmitted: (v) => Navigator.of(dialog).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialog).pop(text.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    ).whenComplete(text.dispose);
  }
}
