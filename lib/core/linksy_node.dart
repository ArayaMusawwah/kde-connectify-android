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

  Future<NodeSettings> settings();

  Future<void> updateSettings(NodeSettings settings);

  Future<void> forget(String id);

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
