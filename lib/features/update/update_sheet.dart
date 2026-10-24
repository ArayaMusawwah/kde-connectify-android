import 'package:flutter/material.dart';

import '../../app/app_update.dart';
import '../../app/platform.dart';
import '../../app/scope.dart';
import '../../ui/components.dart';
import '../../ui/l10n.dart';
import '../../ui/sig.dart';

/// "Linksy X Is Available": what's in it, and Update Now with its progress.
Future<void> showUpdate(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => const _UpdateSheet(),
);

class _UpdateSheet extends StatelessWidget {
  const _UpdateSheet();

  @override
  Widget build(BuildContext context) {
    final u = LinksyScope.read(context).updates;
    final s = Sig.of(context);
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: u,
      builder: (context, _) {
        final release = u.available;
        if (release == null) return const SizedBox.shrink();
        final busy =
            u.phase == UpdatePhase.downloading ||
            u.phase == UpdatePhase.installing;
        final notes = _plain(release.notes);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.updateAvailable(release.version),
                  style: sora(24, color: s.ink),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.updateBody(u.installed ?? ''),
                  style: TextStyle(color: s.muted, fontSize: 14.5, height: 1.4),
                ),
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.3,
                    ),
                    child: SigCard(
                      child: SingleChildScrollView(
                        child: Text(
                          notes,
                          style: TextStyle(
                            color: s.ink,
                            fontSize: 13.5,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                if (u.phase == UpdatePhase.downloading) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: u.progress > 0 ? u.progress : null,
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.updateDownloading('${(u.progress * 100).round()}'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: s.muted, fontSize: 13),
                  ),
                ] else if (u.phase == UpdatePhase.installing)
                  Text(
                    l10n.updateInstalling,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: s.muted, fontSize: 13),
                  )
                else if (u.phase == UpdatePhase.failed)
                  Text(
                    _failure(l10n, u.failure),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: s.red, fontSize: 13, height: 1.4),
                  ),
                const SizedBox(height: 14),
                SigButton(
                  label: l10n.updateNow,
                  expand: true,
                  onTap: busy ? null : u.run,
                ),
                const SizedBox(height: 4),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    if (release.page.isNotEmpty)
                      TextButton(
                        onPressed: () => LinksyPlatform.openUrl(release.page),
                        child: Text(l10n.newsAllChanges(release.version)),
                      ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l10n.updateLater),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _failure(AppLocalizations l10n, String? reason) =>
      switch (reason) {
        'network' => l10n.updateFailedNetwork,
        'bad_sum' || 'unlisted' => l10n.updateFailedCheck,
        'allow' => l10n.updateAllow,
        _ => l10n.updateFailedInstall(reason ?? ''),
      };

  /// Release notes without Markdown's marks: headings, bold, code, links.
  static String _plain(String notes) => notes
      .split('\n')
      .map(
        (line) => line
            .replaceFirst(RegExp(r'^#+\s*'), '')
            .replaceFirst(RegExp(r'^\s*[-*]\s+'), '• ')
            .replaceAll(RegExp(r'\*\*|__|`'), '')
            .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m[1]!),
      )
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}
