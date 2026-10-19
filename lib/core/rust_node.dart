import 'dart:async';
import 'dart:convert';

import '../src/rust/api/node.dart' as rust;
import '../src/rust/frb_generated.dart';
import 'core_json.dart';
import 'linksy_node.dart';
import 'models.dart';

/// [LinksyNode] on linksy-core itself, through the Rust bridge (rust/). This
/// is the node the app runs on; [DemoNode] is for tests and UI work.
class RustNode implements LinksyNode {
  RustNode._(this._node) {
    _events = _node
        .events()
        .map((raw) {
          final j = jsonDecode(raw) as Json;
          final event = eventFromJson(j);
          // A kind this app doesn't know: say "can't" straight away rather
          // than leave the other device waiting.
          if (event == null && j['type'] == 'session_request') {
            _node.declineUnsupported(request: j['request'] as String);
          }
          return event;
        })
        .where((e) => e != null)
        .cast<LinksyEvent>()
        .asBroadcastStream();
  }

  final rust.LinksyNode _node;
  late final Stream<LinksyEvent> _events;

  /// Loads the native library and starts this phone's node. Identity and
  /// paired devices live in [dataDir], which must be app-private.
  static Future<RustNode> start({
    required String dataDir,
    required String downloadDir,
    required String name,
  }) async {
    await RustLib.init();
    final node = await _guard(
      () => rust.startNode(
        dataDir: dataDir,
        downloadDir: downloadDir,
        name: name,
      ),
    );
    return RustNode._(node);
  }

  /// The port other devices reach this phone on, for "pair by address".
  int get port => _node.port();

  @override
  DeviceInfo get info => deviceFromJson(jsonDecode(_node.infoJson()) as Json);

  @override
  Stream<LinksyEvent> get events => _events;

  @override
  Future<List<DeviceView>> devices() async => _devices();

  List<DeviceView> _devices() => [
    for (final j in (jsonDecode(_node.devicesJson()) as List).cast<Json>())
      deviceViewFromJson(j),
  ];

  String _nameOf(String id) =>
      _devices().where((v) => v.device.id == id).firstOrNull?.device.name ??
      'That device';

  @override
  Future<void> pairDevice(String id) =>
      _guard(() => _node.pairDevice(id: id), name: _nameOf(id));

  @override
  Future<void> pairAddress(String address) => _guard(
    () => _node.pairAddress(address: address),
    name: 'The device at $address',
  );

  @override
  Future<void> pairWithInvite(String uri) =>
      _guard(() => _node.pairWithInvite(uri: uri), name: 'That device');

  @override
  Future<void> respond(String requestId, {required bool accept}) async {
    _node.respond(request: requestId, accept: accept);
  }

  @override
  Future<String> sendFiles(String id, List<String> paths) => _guard(
    () => _node.sendFiles(id: id, paths: paths),
    name: _nameOf(id),
  );

  @override
  Future<void> cancel(String transferId) async {
    _node.cancel(transfer: transferId);
  }

  @override
  Future<void> sendClipboard(String id, String text) => _guard(
    () => _node.sendClipboard(id: id, text: text),
    name: _nameOf(id),
  );

  @override
  Future<void> notify(String id, String title, String body) => _guard(
    () => _node.notify(id: id, title: title, body: body),
    name: _nameOf(id),
  );

  @override
  Future<NodeSettings> settings() async =>
      settingsFromJson(jsonDecode(_node.settingsJson()) as Json);

  @override
  Future<void> updateSettings(NodeSettings settings) => _guard(
    () => _node.updateSettings(
      settingsJson: jsonEncode(settingsToJson(settings)),
    ),
  );

  @override
  Future<void> forget(String id) =>
      _guard(() async => _node.forget(id: id), name: _nameOf(id));

  @override
  Future<void> declineUnsupported(String request) async =>
      _node.declineUnsupported(request: request);

  @override
  Future<void> endSession(String session) async =>
      _node.endSession(session: session);

  @override
  Future<void> shutdown() => _node.shutdown();

  /// Runs a bridge call, turning the core's error kinds into sentences that
  /// name the device.
  static Future<T> _guard<T>(
    FutureOr<T> Function() call, {
    String name = 'The other device',
  }) async {
    try {
      return await call();
    } on LinksyException {
      rethrow;
    } on Object catch (e) {
      throw LinksyException(describeCoreError(e is String ? e : '$e', name));
    }
  }
}

/// `unreachable`, `declined`, `invalid:…` and so on, as the user should read
/// them.
String describeCoreError(String error, String name) {
  final colon = error.indexOf(':');
  final kind = colon < 0 ? error : error.substring(0, colon);
  final detail = colon < 0 ? '' : error.substring(colon + 1).trim();
  return switch (kind) {
    'unreachable' =>
      "$name isn't reachable. Check that it's on and on this network.",
    'declined' => '$name declined.',
    'timeout' => "$name didn't answer in time.",
    'not_paired' => "$name isn't paired anymore. Pair again to share.",
    'unsupported' => "$name can't do that yet.",
    'invalid' => detail.isEmpty ? 'That didn’t work.' : detail,
    _ =>
      detail.isEmpty
          ? 'Something went wrong.'
          : 'Something went wrong: $detail',
  };
}
