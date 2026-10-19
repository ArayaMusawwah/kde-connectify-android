import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/linksy_node.dart';
import '../core/models.dart';
import 'activity.dart';

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
  }

  Future<void> refresh() async {
    devices = await node.devices();
    notifyListeners();
  }

  void _onEvent(LinksyEvent e) {
    switch (e) {
      case DeviceFound() ||
          DeviceLost() ||
          DeviceUpdated() ||
          Connected() ||
          Disconnected() ||
          Paired():
        refresh();
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
      case PairingRequest() || PairingFailed():
        break;
    }
    switch (e) {
      case PairingRequest() ||
          PairingFailed() ||
          Paired() ||
          TransferRequest() ||
          NotificationReceived() ||
          ClipboardReceived():
        _prompts.add(e);
      default:
        break;
    }
  }

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
    _saveTimer?.cancel();
    _store.save(_activity);
    _prompts.close();
    super.dispose();
  }
}
