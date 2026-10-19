import 'dart:async';

import 'package:flutter/material.dart';

import '../core/invite.dart';
import '../core/models.dart';
import '../features/devices/home_screen.dart';
import '../features/pairing/pairing_flows.dart';
import '../features/sharing/sharing.dart';
import '../features/transfer/incoming_sheet.dart';
import '../ui/sig.dart';
import 'linksy_controller.dart';
import 'platform.dart';
import 'scope.dart';

class LinksyApp extends StatefulWidget {
  const LinksyApp({super.key, required this.controller});

  final LinksyController controller;

  @override
  State<LinksyApp> createState() => _LinksyAppState();
}

class _LinksyAppState extends State<LinksyApp> {
  final _navigator = GlobalKey<NavigatorState>();
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  StreamSubscription<LinksyEvent>? _prompts;
  StreamSubscription<String>? _links;

  /// The pairing dialog on screen, so a decline from the other side closes it.
  String? _openPairing;

  @override
  void initState() {
    super.initState();
    _prompts = widget.controller.prompts.listen(_onPrompt);
    // A pairing link opened the app (the desktop's QR code scanned with the
    // camera app), or arrives while it runs.
    _links = LinksyPlatform.links.listen(_pairWith);
    LinksyPlatform.takeLink().then((link) {
      if (link != null) _pairWith(link);
    });
  }

  @override
  void dispose() {
    _prompts?.cancel();
    _links?.cancel();
    super.dispose();
  }

  Future<void> _pairWith(String link) async {
    final invite = Invite.tryParse(link);
    if (invite == null) {
      _say('That pairing link isn’t valid.');
      return;
    }
    _say(
      'Pairing with ${invite.name.isEmpty ? 'the other device' : invite.name}…',
    );
    final error = await widget.controller.pairWithInvite(link);
    if (error != null) _say(error);
  }

  void _say(String text) => _messenger.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  void _onPrompt(LinksyEvent e) {
    final context = _navigator.currentContext;
    if (context == null) return;
    switch (e) {
      case PairingRequest():
        _openPairing = e.request;
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => PairingDialog(request: e),
        ).whenComplete(() {
          if (_openPairing == e.request) _openPairing = null;
        });
      case PairingFailed(:final device, :final reason):
        if (_openPairing != null) {
          _openPairing = null;
          _navigator.currentState?.pop();
        }
        _say(
          device == null
              ? 'Pairing failed: $reason'
              : 'Couldn’t pair with ${device.name}: $reason',
        );
      case Paired(:final device):
        _say('Paired with ${device.name}');
      case SessionRequest():
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => SessionRequestDialog(request: e),
        );
      case TransferRequest():
        showModalBottomSheet<void>(
          context: context,
          isDismissible: false,
          enableDrag: false,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => IncomingFilesSheet(request: e),
        );
      case NotificationReceived(:final from, :final title, :final body):
        _say(body.isEmpty ? '${from.name}: $title' : '${from.name}: $body');
      case ClipboardReceived(:final from):
        _say('Copied text from ${from.name}');
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => LinksyScope(
    controller: widget.controller,
    child: MaterialApp(
      title: 'Linksy',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigator,
      scaffoldMessengerKey: _messenger,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: const HomeScreen(),
    ),
  );
}

/// Shown instead of the app when this phone's node can't start.
class StartupFailedApp extends StatelessWidget {
  const StartupFailedApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildTheme(Brightness.light),
    darkTheme: buildTheme(Brightness.dark),
    home: Builder(
      builder: (context) {
        final s = Sig.of(context);
        return Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Linksy couldn’t start',
                    style: sora(24, color: s.ink),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    style: TextStyle(color: s.muted, height: 1.4),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
