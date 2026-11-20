import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/scope.dart';
import '../../ui/components.dart';
import '../../ui/l10n.dart';
import '../../ui/sig.dart';

class CommandsScreen extends StatefulWidget {
  const CommandsScreen({super.key, required this.deviceId});

  final String deviceId;

  @override
  State<CommandsScreen> createState() => _CommandsScreenState();
}

class _CommandsScreenState extends State<CommandsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = LinksyScope.read(context);
      c.requestCommands(widget.deviceId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = LinksyScope.of(context);
    final s = Sig.of(context);
    final view = c.device(widget.deviceId);
    final deviceName = view?.device.name ?? tr.ctlYourComputer;
    final list = c.commands[widget.deviceId] ?? const [];
    final connected = view?.connected ?? false;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  RoundButton(
                    icon: Ph.arrowLeft,
                    tooltip: context.l10n.settingsBack,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const Spacer(),
                  RoundButton(
                    icon: Ph.arrowClockwise,
                    tooltip: 'Refresh',
                    onTap: () {
                      HapticFeedback.lightImpact();
                      c.requestCommands(widget.deviceId);
                      showMessage(context, 'Refreshing commands from $deviceName...');
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.deviceSavedCommands,
                      style: sora(30, weight: FontWeight.w700, color: s.ink),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      deviceName,
                      style: TextStyle(fontSize: 14, color: s.muted),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: list.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconCircle(
                              icon: Ph.terminalWindow,
                              color: Sig.blue,
                              size: 56,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              context.l10n.deviceNoCommandsSaved,
                              style: sora(16, weight: FontWeight.w600, color: s.ink),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              connected
                                  ? 'Add commands on $deviceName in Linksy to run them here.'
                                  : 'Connect to $deviceName to sync and run saved commands.',
                              style: TextStyle(fontSize: 13, color: s.muted),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final cmd = list[index];
                        return SigCard(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            if (!connected) {
                              showMessage(context, '$deviceName is not connected');
                              return;
                            }
                            c.runCommand(widget.deviceId, cmd.key);
                            showMessage(context, 'Running "${cmd.name}" on $deviceName');
                          },
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              IconCircle(
                                icon: PhFill.play,
                                color: Sig.blue,
                                size: 40,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      cmd.name,
                                      style: sora(16, weight: FontWeight.w600, color: s.ink),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: s.raised,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        cmd.command,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontFamily: 'Sora',
                                          color: s.muted,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(Ph.caretRight, color: s.faint, size: 18),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
