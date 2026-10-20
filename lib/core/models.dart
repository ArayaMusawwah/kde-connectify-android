/// Plain data shapes shared by the UI and the node backend. They mirror the
/// structs in `linksy_core` (see `docs/protocol.md` §5 in linksy-desktop) so the Rust
/// bridge can map onto them one to one.
library;

enum DeviceKind {
  desktop,
  laptop,
  phone,
  tablet;

  static DeviceKind parse(String value) => DeviceKind.values.firstWhere(
    (k) => k.name == value,
    orElse: () => DeviceKind.desktop,
  );
}

class DeviceInfo {
  const DeviceInfo({
    required this.id,
    required this.name,
    required this.kind,
    required this.os,
  });

  /// SHA-256 of the device certificate, 64 lowercase hex chars.
  final String id;
  final String name;
  final DeviceKind kind;

  /// `linux`, `android`, `macos`, `windows`, …
  final String os;

  /// First 4 bytes of the id, `XXXX-XXXX`.
  String get shortId => shortDeviceId(id);

  /// "Linux laptop", "Android phone".
  String get description => '${osLabel(os)} ${kind.name}';

  DeviceInfo copyWith({String? name}) =>
      DeviceInfo(id: id, name: name ?? this.name, kind: kind, os: os);
}

String shortDeviceId(String id) {
  if (id.length < 8) return id.toUpperCase();
  final head = id.substring(0, 8).toUpperCase();
  return '${head.substring(0, 4)}-${head.substring(4)}';
}

String osLabel(String os) => switch (os) {
  'linux' => 'Linux',
  'android' => 'Android',
  'macos' => 'macOS',
  'windows' => 'Windows',
  'ios' => 'iOS',
  _ => os.isEmpty ? 'Unknown' : os[0].toUpperCase() + os.substring(1),
};

enum Presence { connected, nearby, notNearby }

class DeviceView {
  const DeviceView({
    required this.device,
    required this.trusted,
    required this.connected,
    required this.nearby,
    this.battery,
  });

  final DeviceInfo device;
  final bool trusted;
  final bool connected;
  final bool nearby;

  /// What the device last said about its battery, if it has one.
  final Battery? battery;

  Presence get presence => connected
      ? Presence.connected
      : nearby
      ? Presence.nearby
      : Presence.notNearby;
}

/// A device's battery (docs/protocol.md §4.5, `battery`).
class Battery {
  const Battery({required this.level, required this.charging});

  /// Percent, 0–100.
  final int level;
  final bool charging;

  @override
  bool operator ==(Object other) =>
      other is Battery && other.level == level && other.charging == charging;

  @override
  int get hashCode => Object.hash(level, charging);
}

class NodeSettings {
  const NodeSettings({
    required this.name,
    required this.downloadDir,
    required this.stayConnected,
    required this.autoAccept,
  });

  final String name;
  final String downloadDir;
  final bool stayConnected;
  final bool autoAccept;

  NodeSettings copyWith({
    String? name,
    String? downloadDir,
    bool? stayConnected,
    bool? autoAccept,
  }) => NodeSettings(
    name: name ?? this.name,
    downloadDir: downloadDir ?? this.downloadDir,
    stayConnected: stayConnected ?? this.stayConnected,
    autoAccept: autoAccept ?? this.autoAccept,
  );
}

class OfferedFile {
  const OfferedFile({required this.path, required this.size});

  /// Relative, `/`-separated.
  final String path;
  final int size;

  String get name => path.split('/').last;
}

/// Events from the node, same names as the desktop IPC.
sealed class LinksyEvent {
  const LinksyEvent();
}

class DeviceFound extends LinksyEvent {
  const DeviceFound(this.device);
  final DeviceInfo device;
}

class DeviceLost extends LinksyEvent {
  const DeviceLost(this.id);
  final String id;
}

class DeviceUpdated extends LinksyEvent {
  const DeviceUpdated(this.device);
  final DeviceInfo device;
}

class Connected extends LinksyEvent {
  const Connected(this.id);
  final String id;
}

class Disconnected extends LinksyEvent {
  const Disconnected(this.id);
  final String id;
}

class PairingRequest extends LinksyEvent {
  const PairingRequest({
    required this.request,
    required this.device,
    required this.code,
    required this.incoming,
  });

  final String request;
  final DeviceInfo device;

  /// Six digits, from the TLS exporter (§4.3).
  final String code;
  final bool incoming;
}

class Paired extends LinksyEvent {
  const Paired(this.device);
  final DeviceInfo device;
}

class PairingFailed extends LinksyEvent {
  const PairingFailed({this.device, required this.reason});
  final DeviceInfo? device;
  final String reason;
}

class TransferRequest extends LinksyEvent {
  const TransferRequest({
    required this.transfer,
    required this.from,
    required this.files,
    required this.total,
  });

  final String transfer;
  final DeviceInfo from;
  final List<OfferedFile> files;
  final int total;
}

class TransferStarted extends LinksyEvent {
  const TransferStarted(
    this.transfer, {
    this.peer,
    this.incoming = false,
    this.files = const [],
    this.total = 0,
  });

  final String transfer;

  /// Who it's with, so a transfer the app didn't start (auto-accepted
  /// incoming files) still lands in that device's timeline.
  final DeviceInfo? peer;
  final bool incoming;
  final List<OfferedFile> files;
  final int total;
}

class TransferProgress extends LinksyEvent {
  const TransferProgress({
    required this.transfer,
    required this.bytes,
    required this.total,
  });

  final String transfer;
  final int bytes;
  final int total;
}

class TransferComplete extends LinksyEvent {
  const TransferComplete({required this.transfer, required this.saved});
  final String transfer;

  /// Final paths of received files; empty for outgoing transfers.
  final List<String> saved;
}

class TransferFailed extends LinksyEvent {
  const TransferFailed({required this.transfer, required this.reason});
  final String transfer;
  final String reason;
}

class SettingsChanged extends LinksyEvent {
  const SettingsChanged(this.settings);
  final NodeSettings settings;
}

class NotificationReceived extends LinksyEvent {
  const NotificationReceived({
    required this.from,
    required this.title,
    required this.body,
  });

  final DeviceInfo from;
  final String title;
  final String body;
}

class ClipboardReceived extends LinksyEvent {
  const ClipboardReceived({required this.from, required this.text});
  final DeviceInfo from;
  final String text;
}

/// What a media session shares (docs/protocol.md §4.8).
enum SessionKind {
  /// The receiver shares its screen with the requester.
  screen,

  /// Like [screen], and the requester also controls it.
  control,

  /// The requester shares a virtual monitor the receiver shows full screen.
  display,

  /// The receiver shares its camera, used as a webcam.
  camera,

  /// This phone drives the computer's pointer and keyboard (touchpad,
  /// keyboard, presentation remote); no video.
  input;

  static SessionKind? parse(String value) =>
      SessionKind.values.where((k) => k.name == value).firstOrNull;
}

/// Ask the user whether [from] may start a session ([request] is its id).
class SessionRequest extends LinksyEvent {
  const SessionRequest({
    required this.request,
    required this.from,
    required this.kind,
  });

  final String request;
  final DeviceInfo from;
  final SessionKind kind;
}

class SessionStarted extends LinksyEvent {
  const SessionStarted({
    required this.session,
    required this.peer,
    required this.kind,
    required this.sharing,
  });

  final String session;
  final DeviceInfo peer;
  final SessionKind kind;

  /// This phone is the one sharing (its screen or camera).
  final bool sharing;
}

class SessionEnded extends LinksyEvent {
  const SessionEnded(this.session);
  final String session;
}

/// A paired device asks this phone to open a web link (`http`/`https`).
class OpenUrlReceived extends LinksyEvent {
  const OpenUrlReceived({required this.from, required this.url});
  final DeviceInfo from;
  final String url;
}

/// A paired device reported its battery.
class BatteryReported extends LinksyEvent {
  const BatteryReported({required this.from, required this.battery});
  final DeviceInfo from;
  final Battery battery;
}

/// A paired device wants this phone to ring so it can be found ([on]), or
/// to stop.
class RingRequested extends LinksyEvent {
  const RingRequested({required this.from, required this.on});
  final DeviceInfo from;
  final bool on;
}

/// One of a device's media players (docs/protocol.md §4.5, `media_state`).
class MediaPlayer {
  const MediaPlayer({
    required this.id,
    required this.app,
    this.title = '',
    this.artist = '',
    this.album = '',
    required this.playing,
    this.positionMs,
    this.lengthMs,
    this.canNext = false,
    this.canPrevious = false,
    this.canSeek = false,
    this.art,
  });

  final String id;
  final String app;
  final String title;
  final String artist;
  final String album;
  final bool playing;
  final int? positionMs;
  final int? lengthMs;
  final bool canNext;
  final bool canPrevious;
  final bool canSeek;

  /// Cover art, base64 JPEG or PNG.
  final String? art;
}

/// Everything a device plays; a later [seq] replaces an earlier one.
class MediaState {
  const MediaState({required this.seq, required this.players});
  final int seq;
  final List<MediaPlayer> players;
}

/// A computer's players changed (while this phone watches them).
class MediaStateReceived extends LinksyEvent {
  const MediaStateReceived({required this.from, required this.state});
  final DeviceInfo from;
  final MediaState state;
}

/// A computer wants (or no longer wants) a heartbeat every [everyS] seconds,
/// to lock itself when this phone leaves.
class HeartbeatWatchChanged extends LinksyEvent {
  const HeartbeatWatchChanged({
    required this.from,
    required this.on,
    required this.everyS,
  });
  final DeviceInfo from;
  final bool on;
  final int everyS;
}
