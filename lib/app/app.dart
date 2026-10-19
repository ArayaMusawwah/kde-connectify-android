import 'dart:async';

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../features/devices/home_screen.dart';
import '../features/pairing/pairing_flows.dart';
import '../features/transfer/incoming_sheet.dart';
import '../ui/sig.dart';
import 'linksy_controller.dart';
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

  /// The pairing dialog on screen, so a decline from the other side closes it.
  String? _openPairing;

  @override
  void initState() {
    super.initState();
    _prompts = widget.controller.prompts.listen(_onPrompt);
  }

  @override
  void dispose() {
    _prompts?.cancel();
    super.dispose();
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
