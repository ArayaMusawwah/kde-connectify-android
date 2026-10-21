import 'dart:typed_data';
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'invite.dart';
import 'linksy_node.dart';
import 'models.dart';

/// An in-memory node with made-up devices, so the app runs before the Rust
/// bridge exists. Transfers, pairing and presence are simulated.
class DemoNode implements LinksyNode {
  DemoNode({required String name, required String downloadDir})
    : _settings = NodeSettings(
        name: name,
        downloadDir: downloadDir,
        stayConnected: false,
        autoAccept: false,
      ),
      info = DeviceInfo(
        id: _fakeId(name),
        name: name,
        kind: DeviceKind.phone,
        os: 'android',
      ) {
    for (final v in _seed) {
      _devices[v.device.id] = v;
    }
  }

  @override
  DeviceInfo info;

  NodeSettings _settings;
  final _events = StreamController<LinksyEvent>.broadcast();
  final _devices = <String, DeviceView>{};
  final _random = Random();
  final _pendingPairings = <String, DeviceInfo>{};
  final _timers = <String, Timer>{};
  final _cancelled = <String>{};

  static final _seed = [
    DeviceView(
      device: DeviceInfo(
        id: _fakeId('Studio Desktop'),
        name: 'Studio Desktop',
        kind: DeviceKind.desktop,
        os: 'linux',
      ),
      trusted: true,
      connected: false,
      nearby: true,
    ),
    DeviceView(
      device: DeviceInfo(
        id: _fakeId('ThinkPad'),
        name: 'ThinkPad',
        kind: DeviceKind.laptop,
        os: 'linux',
      ),
      trusted: true,
      connected: false,
      nearby: false,
    ),
    DeviceView(
      device: DeviceInfo(
        id: _fakeId('Living Room PC'),
        name: 'Living Room PC',
        kind: DeviceKind.desktop,
        os: 'linux',
      ),
      trusted: false,
      connected: false,
      nearby: true,
    ),
  ];

  static String _fakeId(String seed) {
    var h = seed.hashCode & 0x7fffffff;
    final buf = StringBuffer();
    while (buf.length < 64) {
      h = (h * 1103515245 + 12345) & 0x7fffffff;
      buf.write((h % 16).toRadixString(16));
    }
    return buf.toString();
  }

  String _code() => _random.nextInt(1000000).toString().padLeft(6, '0');

  String _uuid() => List.generate(
    16,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  void _emit(LinksyEvent e) {
    if (!_events.isClosed) _events.add(e);
  }

  void _setConnected(String id, bool connected) {
    final v = _devices[id];
    if (v == null || v.connected == connected) return;
    _devices[id] = DeviceView(
      device: v.device,
      trusted: v.trusted,
      connected: connected,
      nearby: v.nearby || connected,
    );
    _emit(connected ? Connected(id) : Disconnected(id));
  }

  DeviceView _reachable(String id) {
    final v = _devices[id];
    if (v == null || !v.nearby) {
      final name = v?.device.name ?? 'That device';
      throw LinksyException(
        "$name isn't reachable. Check that it's on and on this network.",
      );
    }
    return v;
  }

  @override
  Stream<LinksyEvent> get events => _events.stream;

  @override
  Future<List<DeviceView>> devices() async => _devices.values.toList();

  @override
  Future<void> pairDevice(String id) async {
    final v = _reachable(id);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final request = _uuid();
    _pendingPairings[request] = v.device;
    _emit(
      PairingRequest(
        request: request,
        device: v.device,
        code: _code(),
        incoming: false,
      ),
    );
  }

  @override
  Future<void> pairAddress(String address) async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    final unpaired = _devices.values.where((v) => !v.trusted && v.nearby);
    if (unpaired.isEmpty) {
      throw LinksyException("Nothing answered at $address.");
    }
    await pairDevice(unpaired.first.device.id);
  }

  @override
  Future<void> pairWithInvite(String uri) async {
    final invite = Invite.tryParse(uri);
    if (invite == null) throw LinksyException("That's not a Linksy QR code.");
    await Future<void>.delayed(const Duration(milliseconds: 900));
    final device = DeviceInfo(
      id: invite.id,
      name: invite.name.isEmpty ? shortDeviceId(invite.id) : invite.name,
      kind: DeviceKind.desktop,
      os: 'linux',
    );
    _devices[device.id] = DeviceView(
      device: device,
      trusted: true,
      connected: true,
      nearby: true,
    );
    _emit(Paired(device));
  }

  @override
  Future<void> respond(String requestId, {required bool accept}) async {
    final pairing = _pendingPairings.remove(requestId);
    if (pairing != null) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!accept) {
        _emit(PairingFailed(device: pairing, reason: 'Declined'));
        return;
      }
      final v = _devices[pairing.id];
      _devices[pairing.id] = DeviceView(
        device: pairing,
        trusted: true,
        connected: true,
        nearby: true,
      );
      if (v == null) _emit(DeviceFound(pairing));
      _emit(Paired(pairing));
      return;
    }
    final incoming = _pendingIncoming.remove(requestId);
    if (incoming != null) {
      if (!accept) return;
      _runTransfer(requestId, incoming.$1.id, incoming.$2, received: true);
    }
  }

  final _pendingIncoming = <String, (DeviceInfo, List<OfferedFile>)>{};

  @override
  Future<String> sendFiles(String id, List<String> paths) async {
    _reachable(id);
    final transfer = _uuid();
    final files = [
      for (final p in paths)
        OfferedFile(path: p.split('/').last, size: _sizeOf(p)),
    ];
    _setConnected(id, true);
    // "Waiting for … to accept" for a moment, then progress.
    _timers[transfer] = Timer(const Duration(milliseconds: 1500), () {
      _runTransfer(transfer, id, files, received: false);
    });
    return transfer;
  }

  int _sizeOf(String path) {
    try {
      return File(path).lengthSync();
    } on FileSystemException {
      return 4 * 1024 * 1024;
    }
  }

  void _runTransfer(
    String transfer,
    String peer,
    List<OfferedFile> files, {
    required bool received,
  }) {
    if (_cancelled.remove(transfer)) return;
    final total = files.fold<int>(0, (s, f) => s + f.size);
    _emit(
      TransferStarted(
        transfer,
        peer: _devices[peer]?.device,
        incoming: received,
        files: files,
        total: total,
      ),
    );
    // About three seconds whatever the size, in ten steps.
    var sent = 0;
    _timers[transfer] = Timer.periodic(const Duration(milliseconds: 300), (t) {
      sent = min(total, sent + (total / 10).ceil());
      _emit(TransferProgress(transfer: transfer, bytes: sent, total: total));
      if (sent >= total) {
        t.cancel();
        _timers.remove(transfer);
        _emit(
          TransferComplete(
            transfer: transfer,
            saved: received
                ? [for (final f in files) '${_settings.downloadDir}/${f.name}']
                : const [],
          ),
        );
      }
    });
  }

  @override
  Future<void> cancel(String transferId) async {
    _timers.remove(transferId)?.cancel();
    _cancelled.add(transferId);
    _emit(TransferFailed(transfer: transferId, reason: 'Cancelled'));
  }

  @override
  Future<void> sendClipboard(String id, String text) async {
    _reachable(id);
    _setConnected(id, true);
  }

  @override
  Future<void> notify(String id, String title, String body) async {
    _reachable(id);
    _setConnected(id, true);
  }

  @override
  Future<void> openUrl(String id, String url) async {
    _reachable(id);
    _setConnected(id, true);
  }

  @override
  Future<void> sendBattery(String id, Battery battery) async {}

  @override
  Future<void> ring(String id, {required bool on}) async {
    _reachable(id);
    _setConnected(id, true);
  }

  @override
  Future<String> startInput(String id) async {
    _reachable(id);
    _setConnected(id, true);
    final session = _uuid();
    _emit(
      SessionStarted(
        session: session,
        peer: _devices[id]!.device,
        kind: SessionKind.input,
        sharing: true,
      ),
    );
    return session;
  }

  @override
  Future<String> startView(String id, {required bool control}) async {
    _reachable(id);
    _setConnected(id, true);
    final session = _uuid();
    _emit(
      SessionStarted(
        session: session,
        peer: _devices[id]!.device,
        kind: control ? SessionKind.control : SessionKind.screen,
        sharing: false,
      ),
    );
    return session;
  }

  @override
  Future<bool> sessionWrite(String session, Uint8List bytes) async => true;

  @override
  Future<void> watchMedia(String id, {required bool on}) async {}

  @override
  Future<void> mediaCommand(
    String id,
    String player,
    Map<String, Object> command,
  ) async {}

  @override
  Future<void> sendCallState(String id, String state) async {}

  @override
  Future<String> importFiles(String id, List<String> paths) =>
      sendFiles(id, paths);

  @override
  Future<NodeSettings> settings() async => _settings;

  @override
  Future<void> updateSettings(NodeSettings settings) async {
    _settings = settings;
    info = info.copyWith(name: settings.name);
    _emit(SettingsChanged(settings));
  }

  @override
  Future<void> forget(String id) async {
    final v = _devices[id];
    if (v == null) return;
    if (v.nearby) {
      _devices[id] = DeviceView(
        device: v.device,
        trusted: false,
        connected: false,
        nearby: true,
      );
      _emit(DeviceUpdated(v.device));
    } else {
      _devices.remove(id);
      _emit(DeviceLost(id));
    }
  }

  @override
  Future<void> declineUnsupported(String request) async {}

  @override
  Future<void> endSession(String session) async => _emit(SessionEnded(session));

  @override
  Future<void> shutdown() async {
    for (final t in _timers.values) {
      t.cancel();
    }
    await _events.close();
  }

  // Demo-only triggers for the flows that start on the other device.

  void simulateIncomingFiles() {
    final from = _devices.values.firstWhere((v) => v.trusted).device;
    final transfer = _uuid();
    final files = [
      const OfferedFile(path: 'Holiday/IMG_2041.jpg', size: 3400000),
      const OfferedFile(path: 'Holiday/IMG_2042.jpg', size: 2900000),
      const OfferedFile(path: 'Holiday/notes.txt', size: 1200),
    ];
    _pendingIncoming[transfer] = (from, files);
    _setConnected(from.id, true);
    if (_settings.autoAccept) {
      _pendingIncoming.remove(transfer);
      _runTransfer(transfer, from.id, files, received: true);
      return;
    }
    _emit(
      TransferRequest(
        transfer: transfer,
        from: from,
        files: files,
        total: files.fold(0, (s, f) => s + f.size),
      ),
    );
  }

  void simulateIncomingPairing() {
    final v = _devices.values.where((v) => !v.trusted && v.nearby).firstOrNull;
    if (v == null) return;
    final request = _uuid();
    _pendingPairings[request] = v.device;
    _emit(
      PairingRequest(
        request: request,
        device: v.device,
        code: _code(),
        incoming: true,
      ),
    );
  }

  void simulateClipboard() {
    final from = _devices.values.firstWhere((v) => v.trusted).device;
    _setConnected(from.id, true);
    _emit(
      ClipboardReceived(from: from, text: 'https://linksy.app/docs/pairing'),
    );
  }
}
