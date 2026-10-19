/// Reads linksy-core's JSON (its serde shapes, the same as the desktop IPC)
/// into the app's models. Unknown event types come back as null, so a newer
/// core never breaks the app.
library;

import 'models.dart';

typedef Json = Map<String, Object?>;

DeviceInfo deviceFromJson(Json j) => DeviceInfo(
  id: j['id'] as String,
  name: j['name'] as String,
  kind: DeviceKind.parse(j['kind'] as String? ?? ''),
  os: j['os'] as String? ?? '',
);

DeviceView deviceViewFromJson(Json j) => DeviceView(
  device: deviceFromJson(j['device'] as Json),
  trusted: j['trusted'] as bool? ?? false,
  connected: j['connected'] as bool? ?? false,
  nearby: j['nearby'] as bool? ?? false,
);

NodeSettings settingsFromJson(Json j) => NodeSettings(
  name: j['name'] as String,
  downloadDir: j['download_dir'] as String,
  stayConnected: j['stay_connected'] as bool? ?? false,
  autoAccept: j['auto_accept'] as bool? ?? false,
);

Json settingsToJson(NodeSettings s) => {
  'name': s.name,
  'download_dir': s.downloadDir,
  'stay_connected': s.stayConnected,
  'auto_accept': s.autoAccept,
};

List<OfferedFile> _files(Object? list) => [
  for (final f in (list as List? ?? const []).cast<Json>())
    OfferedFile(path: f['path'] as String, size: (f['size'] as num).toInt()),
];

int _int(Object? n) => (n as num? ?? 0).toInt();

LinksyEvent? eventFromJson(Json j) {
  DeviceInfo device([String key = 'device']) => deviceFromJson(j[key] as Json);
  return switch (j['type']) {
    'device_found' => DeviceFound(device()),
    'device_lost' => DeviceLost(j['id'] as String),
    'device_updated' => DeviceUpdated(device()),
    'connected' => Connected(device().id),
    'disconnected' => Disconnected(j['id'] as String),
    'pairing_request' => PairingRequest(
      request: j['request'] as String,
      device: device(),
      code: j['code'] as String,
      incoming: j['incoming'] as bool? ?? false,
    ),
    'paired' => Paired(device()),
    'pairing_failed' => PairingFailed(
      device: device(),
      reason: j['reason'] as String? ?? '',
    ),
    'transfer_request' => TransferRequest(
      transfer: j['transfer'] as String,
      from: device('from'),
      files: _files(j['files']),
      total: _int(j['total']),
    ),
    'transfer_started' => TransferStarted(
      j['transfer'] as String,
      peer: device('peer'),
      incoming: j['direction'] == 'incoming',
      files: _files(j['files']),
      total: _int(j['total']),
    ),
    'transfer_progress' => TransferProgress(
      transfer: j['transfer'] as String,
      bytes: _int(j['bytes']),
      total: _int(j['total']),
    ),
    'transfer_complete' => TransferComplete(
      transfer: j['transfer'] as String,
      saved: (j['saved'] as List? ?? const []).cast<String>(),
    ),
    'transfer_failed' => TransferFailed(
      transfer: j['transfer'] as String,
      reason: j['reason'] as String? ?? '',
    ),
    'settings_changed' => SettingsChanged(
      settingsFromJson(j['settings'] as Json),
    ),
    'notification' => NotificationReceived(
      from: device('from'),
      title: j['title'] as String? ?? '',
      body: j['body'] as String? ?? '',
    ),
    'clipboard' => ClipboardReceived(
      from: device('from'),
      text: j['text'] as String? ?? '',
    ),
    _ => null,
  };
}
