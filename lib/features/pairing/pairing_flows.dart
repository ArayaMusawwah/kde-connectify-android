import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/scope.dart';
import '../../core/invite.dart';
import '../../core/linksy_node.dart';
import '../../core/models.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'scan_screen.dart';

/// "Add device": the QR scanner first, pairing by address as the fallback.
Future<void> showAddDevice(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  builder: (sheet) {
    final theme = Theme.of(sheet);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Add a device',
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'On the other device, open Linksy and choose “Pair with QR Code”.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Grouped(
              padding: EdgeInsets.zero,
              color: theme.colorScheme.surfaceContainer,
              children: [
                _Option(
                  icon: Icons.qr_code_scanner_rounded,
                  title: 'Scan QR code',
                  subtitle: 'Fastest. Nothing to type.',
                  highlighted: true,
                  onTap: () {
                    Navigator.of(sheet).pop();
                    scanAndPair(context);
                  },
                ),
                _Option(
                  icon: Icons.lan_rounded,
                  title: 'Pair by address',
                  subtitle: 'When the other device can’t be found.',
                  onTap: () {
                    Navigator.of(sheet).pop();
                    pairByAddress(context);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  },
);

class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            IconBadge(
              icon: icon,
              size: 52,
              foreground: highlighted ? scheme.onPrimary : scheme.primary,
              background: highlighted
                  ? scheme.primary
                  : scheme.primaryContainer,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: scheme.outline),
          ],
        ),
      ),
    );
  }
}

/// Scanning is the user's consent: no code is shown unless the desktop falls
/// back to the code flow (expired or reused token), which arrives as a normal
/// pairing request.
Future<void> scanAndPair(BuildContext context) async {
  final c = LinksyScope.read(context);
  final uri = await Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) => const ScanScreen(),
      fullscreenDialog: true,
    ),
  );
  final invite = uri == null ? null : Invite.tryParse(uri);
  if (invite == null || !context.mounted) return;
  final name = invite.name.isEmpty ? shortDeviceId(invite.id) : invite.name;
  showMessage(context, 'Pairing with $name…');
  await report(context, c.pairWithInvite(uri!));
}

Future<void> pairByAddress(BuildContext context) async {
  final c = LinksyScope.read(context);
  final address = await showDialog<String>(
    context: context,
    builder: (_) => const _AddressDialog(),
  );
  if (address == null || address.isEmpty || !context.mounted) return;
  await report(context, c.pairAddress(address));
}

class _AddressDialog extends StatefulWidget {
  const _AddressDialog();

  @override
  State<_AddressDialog> createState() => _AddressDialogState();
}

class _AddressDialogState extends State<_AddressDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_text.text.trim());

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.lan_rounded),
    title: const Text('Pair by address'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Find the address in Linksy’s Preferences on the other device.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _text,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F.:\[\]]')),
          ],
          decoration: const InputDecoration(
            hintText: '192.168.1.20',
            prefixIcon: Icon(Icons.router_rounded),
            helperText: 'Port $defaultPort unless you add another.',
          ),
          onSubmitted: (_) => _submit(),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Pair')),
    ],
  );
}

/// Both screens show the same code; both users confirm (§4.3, §4.4).
class PairingDialog extends StatelessWidget {
  const PairingDialog({super.key, required this.request});

  final PairingRequest request;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = request.device.name;
    final digits = request.code.padLeft(6, '0');
    return AlertDialog(
      icon: DeviceAvatar(device: request.device, size: 64),
      title: Text(request.incoming ? '$name wants to pair' : 'Pair with $name'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Check that $name shows the same code.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          Semantics(
            label: 'Code ${formatPairingCode(digits)}',
            excludeSemantics: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 6; i++) ...[
                  if (i == 3) const SizedBox(width: 14),
                  if (i != 0 && i != 3) const SizedBox(width: 6),
                  _Digit(digits[i]),
                ],
              ],
            ),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: () => _answer(context, false),
          child: const Text('Decline'),
        ),
        FilledButton(
          onPressed: () => _answer(context, true),
          child: const Text('Codes match'),
        ),
      ],
    );
  }

  Future<void> _answer(BuildContext context, bool accept) async {
    final c = LinksyScope.read(context);
    Navigator.of(context).pop();
    await c.respond(request.request, accept: accept);
  }
}

class _Digit extends StatelessWidget {
  const _Digit(this.digit);

  final String digit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 34,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(Radii.sm + 2),
      ),
      child: Text(
        digit,
        style: theme.textTheme.headlineSmall?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
