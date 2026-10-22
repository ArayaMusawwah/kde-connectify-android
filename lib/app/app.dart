import 'dart:async';

import 'package:flutter/material.dart';

import '../core/invite.dart';
import '../core/models.dart';
import '../features/devices/home_screen.dart';
import '../features/pairing/pairing_flows.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/ring/ring_screen.dart';
import '../features/share/share_sheet.dart';
import '../features/sharing/display_screen.dart';
import '../features/sharing/sharing.dart';
import '../features/sharing/webcam_screen.dart';
import '../features/transfer/incoming_sheet.dart';
import '../ui/l10n.dart';
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
  StreamSubscription<SharedIn>? _shares;
  StreamSubscription<String>? _webcams;

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
    // "Share → Linksy" from another app, before or while the app runs.
    _shares = LinksyPlatform.shares.listen(_shareOut);
    // The webcam notification opens its controls.
    _webcams = LinksyPlatform.openWebcam.listen((session) {
      final share = widget.controller.sharing[session];
      if (share != null) _openWebcam(share);
    });
    LinksyPlatform.takeShare().then((shared) {
      if (shared != null) _shareOut(shared);
    });
    // First run: the language, then what Linksy may do.
    if (!widget.controller.onboarded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigator.currentState?.push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => const OnboardingScreen(),
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    _prompts?.cancel();
    _links?.cancel();
    _shares?.cancel();
    _webcams?.cancel();
    super.dispose();
  }

  Future<void> _pairWith(String link) async {
    final invite = Invite.tryParse(link);
    if (invite == null) {
      _say(tr.appInvalidPairingLink);
      return;
    }
    _say(
      invite.name.isEmpty
          ? tr.pairingWithOtherDevice
          : tr.pairingWith(invite.name),
    );
    final error = await widget.controller.pairWithInvite(link);
    if (error != null) _say(error);
  }

  void _shareOut(SharedIn shared) {
    final context = _navigator.currentContext;
    if (context == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ShareSheet(shared: shared),
    );
  }

  void _openWebcam(SessionStarted share) => _navigator.currentState?.push(
    MaterialPageRoute<void>(builder: (_) => WebcamScreen(share: share)),
  );

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
              ? tr.appPairingFailed(reason)
              : tr.appCouldntPair(device.name, reason),
        );
      case Paired(:final device):
        _say(tr.appPairedWith(device.name));
      case SessionStarted(kind: SessionKind.camera) when e.sharing:
        _openWebcam(e);
      case SessionStarted() when !e.sharing && e.kind != SessionKind.input:
        _navigator.currentState?.push(
          MaterialPageRoute<void>(builder: (_) => DisplayScreen(session: e)),
        );
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
        _say(tr.appNotification(from.name, body.isEmpty ? title : body));
      case ClipboardReceived(:final from):
        _say(tr.appCopiedText(from.name));
      case ClipboardFileReceived(:final from, :final path):
        _say(tr.appCopiedFile(path.split('/').last, from.name));
      case OpenUrlReceived():
        showDialog<void>(
          context: context,
          builder: (_) => LinkReceivedDialog(event: e),
        );
      case RingRequested(:final from, on: true):
        _navigator.currentState?.push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => RingScreen(from: from),
          ),
        );
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => LinksyScope(
    controller: widget.controller,
    child: ListenableBuilder(
      listenable: Listenable.merge([
        widget.controller.locale,
        widget.controller.themeMode,
      ]),
      builder: (context, _) => MaterialApp(
        title: 'Linksy',
        debugShowCheckedModeBanner: false,
        navigatorKey: _navigator,
        scaffoldMessengerKey: _messenger,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: widget.controller.themeMode.value,
        locale: widget.controller.locale.value,
        supportedLocales: [for (final l in languages) Locale(l.code)],
        localizationsDelegates: localizationsDelegates,
        home: const HomeScreen(),
      ),
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
                    tr.appCouldntStart,
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
