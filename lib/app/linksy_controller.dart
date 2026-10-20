import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/linksy_node.dart';
import '../core/models.dart';
import 'activity.dart';
import 'platform.dart';

/// App state on top of a [LinksyNode]: the device list, settings and every
/// device's activity. Consent prompts and notices go out on [prompts] for the
/// UI to show.
class LinksyController extends ChangeNotifier {
  LinksyController(this.node, this._store);

  final LinksyNode node;
  final ActivityStore _store;

  List<DeviceView> devices = const [];
  NodeSettings? settings;
  final List<Activity> _activity = [];
  final _prompts = StreamController<LinksyEvent>.broadcast();
  StreamSubscription<LinksyEvent>? _sub;
  final _lastSample = <String, (DateTime, int)>{};
  Timer? _saveTimer;

  /// What this phone is sharing right now (its screen or camera), by session.
  final Map<String, SessionStarted> sharing = {};

  /// Second-display sessions showing on this phone, by session.
  final Map<String, SessionStarted> displays = {};

  /// Who is making this phone ring right now ("Find my phone").
  DeviceInfo? ringingFrom;
  Timer? _ringTimer;

  /// When each device last sent `ring_stop` with nothing ringing: a `ring`
  /// right behind it arrived out of order and is already over (§4.5).
  final _strayRingStops = <String, DateTime>{};

  /// Devices this phone is making ring ("Find my computer"), each until
  /// stopped or for [ringFor].
  final Map<String, Timer> _finding = {};

  bool isFinding(String deviceId) => _finding.containsKey(deviceId);

  /// This phone's battery, and what each computer was last told.
  Battery? _battery;
  final _toldBattery = <String, Battery>{};
  StreamSubscription<Battery>? _batterySub;

  /// How long a ring lasts at most (§4.5).
  static const ringFor = Duration(seconds: 30);

  /// Pairing and transfer requests, failures, and things received.
  Stream<LinksyEvent> get prompts => _prompts.stream;

  List<DeviceView> get paired =>
      devices.where((d) => d.trusted).toList()..sort(_byPresenceThenName);

  List<DeviceView> get unpaired =>
      devices.where((d) => !d.trusted && d.nearby).toList()
        ..sort(_byPresenceThenName);

  DeviceView? device(String id) =>
      devices.where((d) => d.device.id == id).firstOrNull;

  List<Activity> activityFor(String deviceId) =>
      _activity.where((a) => a.deviceId == deviceId).toList();

  Activity? lastActivity(String deviceId) =>
      _activity.where((a) => a.deviceId == deviceId).firstOrNull;

  static int _byPresenceThenName(DeviceView a, DeviceView b) {
    final p = a.presence.index.compareTo(b.presence.index);
    return p != 0
        ? p
        : a.device.name.toLowerCase().compareTo(b.device.name.toLowerCase());
  }

  Future<void> start() async {
    _activity.addAll(await _store.load());
    _sub = node.events.listen(_onEvent);
    devices = await node.devices();
    settings = await node.settings();
    notifyListeners();
    _batterySub = LinksyPlatform.batteryChanges.listen(_onBattery);
    unawaited(
      LinksyPlatform.battery().then((b) {
        _battery ??= b;
        for (final v in devices) {
          if (v.connected || v.nearby) _tellBattery(v.device.id, always: true);
        }
      }),
    );
  }

  // Battery (docs/protocol.md §4.5): sent to paired computers on connecting, then
  // when it moves by 5 points or charging starts or stops. Each send may open
  // a connection, so no more often than that.

  bool _isComputer(DeviceInfo d) =>
      d.kind == DeviceKind.desktop || d.kind == DeviceKind.laptop;

  void _onBattery(Battery b) {
    _battery = b;
    for (final v in devices) {
      if (v.trusted && (v.connected || v.nearby)) _tellBattery(v.device.id);
    }
  }

  Future<void> _tellBattery(String id, {bool always = false}) async {
    final b = _battery;
    final v = device(id);
    if (b == null || v == null || !v.trusted || !_isComputer(v.device)) return;
    final told = _toldBattery[id];
    if (!always &&
        told != null &&
        told.charging == b.charging &&
        (told.level - b.level).abs() < 5) {
      return;
    }
    _toldBattery[id] = b;
    try {
      await node.sendBattery(id, b);
    } on LinksyException {
      // Not around after all: say it again next time it connects.
      _toldBattery.remove(id);
    }
  }

  Future<void> refresh() async {
    devices = await node.devices();
    notifyListeners();
  }

  void _onEvent(LinksyEvent e) {
    switch (e) {
      case Connected(:final id):
        refresh().then((_) => _tellBattery(id, always: true));
      case Paired(:final device):
        refresh().then((_) => _tellBattery(device.id, always: true));
      case DeviceFound(:final device):
        // A paired computer came around: tell it the battery.
        refresh().then((_) => _tellBattery(device.id, always: true));
      case DeviceLost() || DeviceUpdated() || Disconnected():
        refresh();
      case BatteryReported():
        // Also in the device list; read it again to show it.
        refresh();
      case OpenUrlReceived(:final from, :final url):
        _addLocal(from.id, ActivityKind.link, incoming: true, text: url);
      case RingRequested(:final from, on: true):
        final stray = _strayRingStops.remove(from.id);
        if (stray != null &&
            DateTime.now().difference(stray) < const Duration(seconds: 1)) {
          return;
        }
        _startRinging(from);
      case RingRequested(:final from, on: false):
        if (ringingFrom?.id == from.id) {
          stopRinging();
        } else {
          _strayRingStops[from.id] = DateTime.now();
        }
      case SettingsChanged(:final settings):
        this.settings = settings;
        notifyListeners();
      case TransferRequest(
        :final transfer,
        :final from,
        :final files,
        :final total,
      ):
        _add(
          Activity(
            id: transfer,
            deviceId: from.id,
            kind: ActivityKind.files,
            incoming: true,
            time: DateTime.now(),
            status: ActivityStatus.waiting,
            names: [for (final f in files) f.name],
            total: total,
          ),
        );
      case TransferStarted(
        :final transfer,
        :final peer,
        :final incoming,
        :final files,
        :final total,
      ):
        // Outgoing transfers start when offered: they wait for the other side
        // until bytes flow. Incoming ones start once accepted.
        if (_activity.any((a) => a.id == transfer)) {
          if (incoming) {
            _update(transfer, (a) => a.status = ActivityStatus.active);
          }
        } else if (peer != null) {
          // Not started here (auto-accepted files): file it under the peer.
          _add(
            Activity(
              id: transfer,
              deviceId: peer.id,
              kind: ActivityKind.files,
              incoming: incoming,
              time: DateTime.now(),
              status: incoming ? ActivityStatus.active : ActivityStatus.waiting,
              names: [for (final f in files) f.name],
              total: total,
            ),
          );
        }
      case TransferProgress(:final transfer, :final bytes, :final total):
        _update(transfer, (a) {
          a
            ..status = ActivityStatus.active
            ..bytes = bytes
            ..total = total
            ..speed = _speed(transfer, bytes, a.speed);
        }, save: false);
      case TransferComplete(:final transfer, :final saved):
        _update(transfer, (a) {
          a
            ..status = ActivityStatus.done
            ..bytes = a.total
            ..saved = saved;
        });
        _lastSample.remove(transfer);
      case TransferFailed(:final transfer, :final reason):
        _update(transfer, (a) {
          final declined = reason.toLowerCase().contains('declin');
          a
            ..status = declined
                ? ActivityStatus.declined
                : ActivityStatus.failed
            ..reason = reason;
        });
        _lastSample.remove(transfer);
      case ClipboardReceived(:final from, :final text):
        Clipboard.setData(ClipboardData(text: text));
        _addLocal(from.id, ActivityKind.clipboard, incoming: true, text: text);
      case NotificationReceived(:final from, :final title):
        _addLocal(from.id, ActivityKind.ping, incoming: true, text: title);
      case SessionStarted(:final session, :final peer, :final kind)
          when e.sharing && kind != SessionKind.display:
        sharing[session] = e;
        LinksyPlatform.startShare(session, kind.name, peer.name);
        _addSession(e);
      case SessionStarted(:final session, kind: SessionKind.display)
          when !e.sharing:
        displays[session] = e;
        _addSession(e);
      case SessionEnded(:final session):
        if (sharing.remove(session) != null) {
          LinksyPlatform.stopShare(session);
          _update(session, (a) => a.status = ActivityStatus.done);
        }
        if (displays.remove(session) != null) {
          _update(session, (a) => a.status = ActivityStatus.done);
        }
      case PairingRequest() ||
          PairingFailed() ||
          SessionRequest() ||
          SessionStarted():
        break;
    }
    switch (e) {
      case PairingRequest() ||
          PairingFailed() ||
          SessionRequest() ||
          Paired() ||
          TransferRequest() ||
          NotificationReceived() ||
          ClipboardReceived() ||
          OpenUrlReceived():
        _prompts.add(e);
      // The full-screen page for a second display.
      case SessionStarted(kind: SessionKind.display) when !e.sharing:
        _prompts.add(e);
      default:
        break;
    }
  }

  void _startRinging(DeviceInfo from) {
    final already = ringingFrom != null;
    ringingFrom = from;
    _ringTimer?.cancel();
    _ringTimer = Timer(ringFor, stopRinging);
    if (!already) {
      LinksyPlatform.startRing();
      _addLocal(from.id, ActivityKind.ring, incoming: true);
      // The full-screen "Found it".
      _prompts.add(RingRequested(from: from, on: true));
    }
    notifyListeners();
  }

  /// "Found it", `ring_stop`, or 30 seconds.
  void stopRinging() {
    _ringTimer?.cancel();
    _ringTimer = null;
    if (ringingFrom == null) return;
    ringingFrom = null;
    LinksyPlatform.stopRing();
    notifyListeners();
  }

  void _addSession(SessionStarted e) => _add(
    Activity(
      id: e.session,
      deviceId: e.peer.id,
      kind: switch (e.kind) {
        SessionKind.screen => ActivityKind.screen,
        SessionKind.camera => ActivityKind.camera,
        SessionKind.control => ActivityKind.control,
        SessionKind.display => ActivityKind.display,
      },
      incoming: e.kind == SessionKind.display,
      time: DateTime.now(),
      status: ActivityStatus.active,
    ),
  );

  double _speed(String transfer, int bytes, double previous) {
    final now = DateTime.now();
    final last = _lastSample[transfer];
    _lastSample[transfer] = (now, bytes);
    if (last == null) return previous;
    final seconds = now.difference(last.$1).inMicroseconds / 1e6;
    if (seconds <= 0) return previous;
    final instant = (bytes - last.$2) / seconds;
    return previous == 0 ? instant : previous * 0.7 + instant * 0.3;
  }

  void _add(Activity a) {
    _activity.insert(0, a);
    if (_activity.length > ActivityStore.maxEntries) _activity.removeLast();
    _changed();
  }

  void _addLocal(
    String deviceId,
    ActivityKind kind, {
    required bool incoming,
    String? text,
    ActivityStatus status = ActivityStatus.done,
    String? reason,
  }) {
    _add(
      Activity(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        deviceId: deviceId,
        kind: kind,
        incoming: incoming,
        time: DateTime.now(),
        status: status,
        text: text,
        reason: reason,
      ),
    );
  }

  void _update(String id, void Function(Activity) change, {bool save = true}) {
    final a = _activity.where((a) => a.id == id).firstOrNull;
    if (a == null) return;
    change(a);
    save ? _changed() : notifyListeners();
  }

  void _changed() {
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), () {
      _store.save(_activity);
    });
  }

  // Actions. Each returns an error message to show, or null.

  Future<String?> sendFiles(String deviceId, List<String> paths) async {
    if (paths.isEmpty) return null;
    try {
      final transfer = await node.sendFiles(deviceId, paths);
      // Progress events can race the return; only add if not seen yet.
      if (_activity.every((a) => a.id != transfer)) {
        _add(
          Activity(
            id: transfer,
            deviceId: deviceId,
            kind: ActivityKind.files,
            incoming: false,
            time: DateTime.now(),
            status: ActivityStatus.waiting,
            names: [for (final p in paths) p.split('/').last],
          ),
        );
      }
      return null;
    } on LinksyException catch (e) {
      return e.message;
    }
  }

  Future<String?> sendClipboard(String deviceId) async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    if (text.isEmpty) return 'The clipboard is empty.';
    if (utf8.encode(text).length > maxClipboardBytes) {
      return 'The clipboard holds too much text to send.';
    }
    return _run(() async {
      await node.sendClipboard(deviceId, text);
      _addLocal(deviceId, ActivityKind.clipboard, incoming: false, text: text);
    });
  }

  Future<String?> ping(String deviceId) => _run(() async {
    await node.notify(deviceId, 'Ping', 'From ${node.info.name}');
    _addLocal(deviceId, ActivityKind.ping, incoming: false, text: 'Ping');
  });

  /// "Find my computer": makes it ring until [stopFinding].
  Future<String?> find(String deviceId) => _run(() async {
    await node.ring(deviceId, on: true);
    _finding.remove(deviceId)?.cancel();
    _finding[deviceId] = Timer(ringFor, () {
      _finding.remove(deviceId);
      notifyListeners();
    });
    _addLocal(deviceId, ActivityKind.ring, incoming: false);
  });

  Future<String?> stopFinding(String deviceId) => _run(() async {
    _finding.remove(deviceId)?.cancel();
    notifyListeners();
    await node.ring(deviceId, on: false);
  });

  /// "Open on PC": the computer opens [url] in its browser.
  Future<String?> openUrl(String deviceId, String url) => _run(() async {
    await node.openUrl(deviceId, url);
    _addLocal(deviceId, ActivityKind.link, incoming: false, text: url);
  });

  /// Text shared from another app, to [deviceId]'s clipboard.
  Future<String?> sendText(String deviceId, String text) async {
    if (utf8.encode(text).length > maxClipboardBytes) {
      return 'That’s too much text to send.';
    }
    return _run(() async {
      await node.sendClipboard(deviceId, text);
      _addLocal(deviceId, ActivityKind.clipboard, incoming: false, text: text);
    });
  }

  Future<String?> cancel(String transfer) => _run(() => node.cancel(transfer));

  Future<String?> respond(String request, {required bool accept}) async {
    final error = await _run(() => node.respond(request, accept: accept));
    if (!accept) {
      _update(request, (a) {
        a
          ..status = ActivityStatus.declined
          ..reason = 'Declined';
      });
    }
    return error;
  }

  /// Answers "X wants to see your screen / use your camera / …". Allowing
  /// also needs Android's own consent: screen capture (screen, control) or
  /// the camera permission. A second display needs nothing more.
  Future<String?> respondSession(
    SessionRequest request, {
    required bool accept,
  }) async {
    var allowed = accept;
    String? error;
    if (accept) {
      switch (request.kind) {
        case SessionKind.screen || SessionKind.control:
          allowed = await LinksyPlatform.requestScreenCapture(request.request);
          if (!allowed) {
            error =
                'Sharing the screen needs Android’s permission to capture it.';
          }
        case SessionKind.camera:
          allowed = await LinksyPlatform.requestCamera();
          if (!allowed) {
            error = 'Linksy needs the camera permission to work as a webcam.';
          }
        case SessionKind.display:
          break;
      }
    }
    await node.respond(request.request, accept: allowed);
    return error;
  }

  /// Leaves a second display (back from its full-screen page).
  Future<void> stopDisplay(String session) async {
    await LinksyPlatform.stopDisplay(session);
    await node.endSession(session);
  }

  /// The Stop button: ends sharing into [session].
  Future<void> stopSharing(String session) async {
    await LinksyPlatform.stopShare(session);
    await node.endSession(session);
  }

  Future<String?> pair(String deviceId) =>
      _run(() => node.pairDevice(deviceId));

  Future<String?> pairAddress(String address) {
    final withPort = address.contains(RegExp(r':\d+$'))
        ? address
        : '$address:$defaultPort';
    return _run(() => node.pairAddress(withPort));
  }

  Future<String?> pairWithInvite(String uri) =>
      _run(() => node.pairWithInvite(uri));

  Future<String?> forget(String deviceId) async {
    final error = await _run(() => node.forget(deviceId));
    _activity.removeWhere((a) => a.deviceId == deviceId);
    _changed();
    // The core announces no event for this: read the list again.
    await refresh();
    return error;
  }

  Future<String?> updateSettings(NodeSettings s) =>
      _run(() => node.updateSettings(s));

  Future<String?> _run(Future<void> Function() action) async {
    try {
      await action();
      return null;
    } on LinksyException catch (e) {
      return e.message;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _batterySub?.cancel();
    _ringTimer?.cancel();
    for (final t in _finding.values) {
      t.cancel();
    }
    _saveTimer?.cancel();
    _store.save(_activity);
    _prompts.close();
    super.dispose();
  }
}
