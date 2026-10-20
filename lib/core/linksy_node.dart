import 'dart:typed_data';

import 'models.dart';

/// What the app needs from a Linksy node. The real implementation wraps
/// `linksy_core::Node` through flutter_rust_bridge (see `docs/protocol.md` §3 and §5
/// in linksy-desktop); [DemoNode] stands in until that bridge exists.
abstract interface class LinksyNode {
  DeviceInfo get info;

  /// Every event from the node. Consent questions (pairing, incoming files)
  /// carry an id that is answered with [respond].
  Stream<LinksyEvent> get events;

  Future<List<DeviceView>> devices();

  Future<void> pairDevice(String id);

  /// Pair by address (`ip:port`, default port 47200) when discovery is blocked.
  Future<void> pairAddress(String address);

  /// Pair with a scanned `linksy://pair?…` invite (§4.7).
  Future<void> pairWithInvite(String uri);

  Future<void> respond(String requestId, {required bool accept});

  /// Returns the transfer id.
  Future<String> sendFiles(String id, List<String> paths);

  Future<void> cancel(String transferId);

  Future<void> sendClipboard(String id, String text);

  Future<void> notify(String id, String title, String body);

  /// "Open on PC": asks [id] to open an `http(s)` [url] in its browser.
  Future<void> openUrl(String id, String url);

  /// Tells [id] this phone's battery.
  Future<void> sendBattery(String id, Battery battery);

  /// "Find my computer": makes [id] ring, or stops it.
  Future<void> ring(String id, {required bool on});

  /// Touchpad and keyboard: asks [id] for an `input` session; returns its id.
  Future<String> startInput(String id);

  /// Framed input messages into a session. False once it has ended.
  Future<bool> sessionWrite(String session, Uint8List bytes);

  /// Ask [id] for its players while [on] (`MediaStateReceived` events).
  Future<void> watchMedia(String id, {required bool on});

  /// `{"action": "play_pause"}` and so on, for [player] on [id].
  Future<void> mediaCommand(
    String id,
    String player,
    Map<String, Object> command,
  );

  /// `ringing`, `active` or `idle`.
  Future<void> sendCallState(String id, String state);

  /// Photo auto-import into [id]'s picture library; returns the transfer id.
  Future<String> importFiles(String id, List<String> paths);

  Future<NodeSettings> settings();

  Future<void> updateSettings(NodeSettings settings);

  Future<void> forget(String id);

  /// Turns down a session this phone can't do at all, so the other device
  /// says "can't" instead of "didn't allow it".
  Future<void> declineUnsupported(String request);

  /// Stops sharing into a media session from this side.
  Future<void> endSession(String session);

  Future<void> shutdown();
}

/// Default QUIC port of a Linksy device.
const defaultPort = 47200;

/// Largest clipboard text the protocol carries (§4.5).
const maxClipboardBytes = 256 * 1024;

/// A failure worth showing to the user as is, naming the device in plain words.
class LinksyException implements Exception {
  const LinksyException(this.message);
  final String message;

  @override
  String toString() => message;
}
