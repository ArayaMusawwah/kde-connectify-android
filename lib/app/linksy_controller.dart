import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import '../core/linksy_node.dart';
import '../core/models.dart';
import '../ui/format.dart';
import 'activity.dart';
import 'platform.dart';

/// App state on top of a [LinksyNode]: the device list, settings and every
/// device's activity. Consent prompts and notices go out on [prompts] for the
/// UI to show.
class LinksyController extends ChangeNotifier with WidgetsBindingObserver {
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

  /// Small settings kept by Android: `pause_calls`, `stay_running`,
  /// `share_files`, `photos.<device>`, `photos_since.<device>`…
  Map<String, String> prefs = {};

  /// Each computer's players, the newest state it sent while watched.
  final Map<String, MediaState> media = {};
  final Map<String, int> _mediaWatchers = {};

  /// Computers that lock themselves when this phone leaves.
  final Map<String, int> lockWatchers = {};

  /// Remote (touchpad and keyboard) sessions, by device.
  final Map<String, String> remotes = {};

  /// Each paired device's picture (a file path), chosen on this phone.
  Map<String, String> pictures = {};

  /// Bumped when a picture changes, so images reload.
  int pictureVersion = 0;

  /// Folders picked in Android's picker: shared with computers, backed up.
  String? filesFolder;
  String? photosFolder;

  /// Photo imports going out: transfer → (device, newest photo time, more).
  final Map<String, (String, int, bool)> _imports = {};
  bool _importing = false;
  Timer? _importTimer;
  StreamSubscription<String>? _callSub;
  StreamSubscription<(String, bool)>? _answerSub;

  bool get pauseOnCalls => prefs['pause_calls'] != 'off';
  bool get stayRunning => prefs['stay_running'] == 'on';
  bool get sharingFiles => prefs['share_files'] == 'on';
  bool backsUpPhotos(String id) => prefs['photos.$id'] == 'on';
  bool photosDeclined(String id) => prefs['photos_declined.$id'] == '1';
  DateTime? photosBackedUp(String id) => switch (prefs['photos_at.$id']) {
    final ms? => DateTime.fromMillisecondsSinceEpoch(int.parse(ms)),
    null => null,
  };

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
    _callSub = LinksyPlatform.callStates.listen(_onCall);
    _answerSub = LinksyPlatform.transferAnswers.listen(
      (a) => respond(a.$1, accept: a.$2),
    );
    unawaited(_loadPlatform());
    WidgetsBinding.instance.addObserver(this);
    unawaited(
      LinksyPlatform.battery().then((b) {
        _battery ??= b;
        for (final v in devices) {
          if (v.connected || v.nearby) _tellBattery(v.device.id, always: true);
        }
      }),
    );
  }

  /// Back in the app: new photos may be waiting.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _importAll();
  }

  /// Android-side settings and folders; not awaited by [start] (tests have
  /// no Android side).
  Future<void> _loadPlatform() async {
    prefs = await LinksyPlatform.prefs();
    // Shares that went on while the app's screen was recreated.
    for (final (session, kind, peerId) in await LinksyPlatform.activeShares()) {
      final peer = device(peerId)?.device;
      final k = SessionKind.parse(kind);
      if (peer == null || k == null || sharing.containsKey(session)) continue;
      sharing[session] = SessionStarted(
        session: session,
        peer: peer,
        kind: k,
        sharing: true,
      );
    }
    pictures = await LinksyPlatform.pictures();
    filesFolder = await LinksyPlatform.folder('files');
    photosFolder = await LinksyPlatform.folder('photos');
    await LinksyPlatform.shareFiles(sharingFiles && filesFolder != null);
    await LinksyPlatform.watchCalls(pauseOnCalls);
    _updateKeepAlive();
    notifyListeners();
    _importAll();
    _importTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => _importAll(),
    );
  }

  Future<void> _setPref(String key, String? value) async {
    if (value == null) {
      prefs.remove(key);
    } else {
      prefs[key] = value;
    }
    notifyListeners();
    await LinksyPlatform.setPref(key, value);
  }

  String _name(String id) => device(id)?.device.name ?? 'your computer';

  /// The quiet "stay connected" notification: while a computer locks when
  /// this phone leaves (CPU kept awake for heartbeats), or when the user
  /// wants Linksy to keep running in the background.
  void _updateKeepAlive() {
    final lockers = [for (final id in lockWatchers.keys) _name(id)];
    if (lockers.isNotEmpty) {
      LinksyPlatform.keepAlive(
        on: true,
        awake: true,
        text: 'Keeping ${lockers.join(' and ')} locked when you leave',
      );
    } else if (stayRunning) {
      LinksyPlatform.keepAlive(
        on: true,
        text: 'Staying connected to your computers',
      );
    } else {
      LinksyPlatform.keepAlive(on: false);
    }
  }

  Future<void> setStayRunning(bool on) async {
    await _setPref('stay_running', on ? 'on' : null);
    _updateKeepAlive();
  }

  // Calls (§4.5): paired computers that are around hear when a call rings,
  // goes on and ends, and pause what plays meanwhile.

  Future<void> setPauseOnCalls(bool on) async {
    await _setPref('pause_calls', on ? null : 'off');
    await LinksyPlatform.watchCalls(on);
  }

  void _onCall(String state) {
    if (!pauseOnCalls) return;
    for (final v in devices) {
      if (v.trusted && _isComputer(v.device) && (v.connected || v.nearby)) {
        node.sendCallState(v.device.id, state).catchError((Object _) {});
      }
    }
  }

  // Files (§4.9): computers browse the one folder the user picked.

  Future<String?> pickFilesFolder() async {
    final name = await LinksyPlatform.pickFolder('files');
    if (name == null) return null;
    filesFolder = name;
    await setSharingFiles(true);
    return name;
  }

  Future<void> setSharingFiles(bool on) async {
    await _setPref('share_files', on ? 'on' : null);
    await LinksyPlatform.shareFiles(on && filesFolder != null);
  }

  // Media (§4.5): a computer's players, while a page shows them.

  void watchMedia(String id) {
    final n = (_mediaWatchers[id] ?? 0) + 1;
    _mediaWatchers[id] = n;
    if (n == 1) node.watchMedia(id, on: true).catchError((Object _) {});
  }

  void unwatchMedia(String id) {
    final n = (_mediaWatchers[id] ?? 1) - 1;
    if (n > 0) {
      _mediaWatchers[id] = n;
      return;
    }
    _mediaWatchers.remove(id);
    node.watchMedia(id, on: false).catchError((Object _) {});
  }

  /// `play_pause`, `next`, `previous`…
  Future<String?> mediaCommand(String id, String player, String action) =>
      _run(() => node.mediaCommand(id, player, {'action': action}));

  // Remote (§4.8, `input`): this phone as the computer's touchpad and
  // keyboard.

  /// Asks the computer (its user allows it there); null when it's on.
  Future<String?> startRemote(String id) => _run(() async {
    final session = await node.startInput(id);
    remotes[id] = session;
    notifyListeners();
  });

  /// Input messages (`pointer_by`, `button`, `scroll`, `key`, `text`), each
  /// framed as u32 big-endian length + JSON. False once the computer ended it.
  Future<bool> remoteSend(String id, List<Map<String, Object>> messages) async {
    final session = remotes[id];
    if (session == null) return false;
    final out = BytesBuilder(copy: false);
    for (final m in messages) {
      final body = utf8.encode(jsonEncode(m));
      out
        ..add((ByteData(4)..setUint32(0, body.length)).buffer.asUint8List())
        ..add(body);
    }
    return node.sessionWrite(session, out.takeBytes());
  }

  Future<void> stopRemote(String id) async {
    final session = remotes.remove(id);
    notifyListeners();
    if (session != null) await node.endSession(session);
  }

  // Photo backup (§4.5, `import`): new photos from the picked folder go to
  // each computer that has it on, a batch at a time, while it's around.

  Future<bool> setPhotoBackup(String id, bool on) async {
    if (on && photosFolder == null) {
      photosFolder = await LinksyPlatform.pickFolder('photos');
      if (photosFolder == null) return false;
    }
    await _setPref('photos.$id', on ? 'on' : null);
    await _setPref('photos_declined.$id', null);
    // Only what's taken from now on; earlier photos aren't sent.
    if (on && prefs['photos_since.$id'] == null) {
      await _setPref(
        'photos_since.$id',
        '${DateTime.now().millisecondsSinceEpoch}',
      );
    }
    if (on) _importTo(id);
    return true;
  }

  Future<String?> pickPhotosFolder() async {
    final name = await LinksyPlatform.pickFolder('photos');
    if (name != null) {
      photosFolder = name;
      notifyListeners();
      _importAll();
    }
    return name;
  }

  void _importAll() {
    for (final v in devices) {
      _importTo(v.device.id);
    }
  }

  Future<void> _importTo(String id) async {
    final v = device(id);
    if (_importing ||
        photosFolder == null ||
        v == null ||
        !v.trusted ||
        !(v.connected || v.nearby) ||
        !backsUpPhotos(id) ||
        photosDeclined(id)) {
      return;
    }
    _importing = true;
    try {
      final since = int.tryParse(prefs['photos_since.$id'] ?? '') ?? 0;
      final batch = await LinksyPlatform.photoBatch(since);
      if (batch == null || batch.count == 0) {
        _importing = false;
        return;
      }
      final transfer = await node.importFiles(id, batch.folders);
      _imports[transfer] = (id, batch.newest, batch.more);
    } on Object {
      _importing = false;
    }
  }

  void _importEnded(String transfer, {required bool ok, String reason = ''}) {
    final entry = _imports.remove(transfer);
    if (entry == null) return;
    final (id, newest, more) = entry;
    _importing = false;
    if (ok) {
      _setPref('photos_since.$id', '$newest');
      _setPref('photos_at.$id', '${DateTime.now().millisecondsSinceEpoch}');
      if (more) {
        _importTo(id);
        return;
      }
    } else if (reason.toLowerCase().contains('declin')) {
      // That computer doesn't take imports (turned off there).
      _setPref('photos_declined.$id', '1');
    }
    _importAll();
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
        refresh().then((_) {
          _tellBattery(id, always: true);
          _importTo(id);
        });
      case Paired(:final device):
        refresh().then((_) => _tellBattery(device.id, always: true));
      case DeviceFound(:final device):
        // A paired computer came around: tell it the battery.
        refresh().then((_) {
          _tellBattery(device.id, always: true);
          _importTo(device.id);
        });
      case Disconnected(:final id):
        media.remove(id);
        refresh();
      case DeviceLost() || DeviceUpdated():
        refresh();
      case MediaStateReceived(:final from, :final state):
        final known = media[from.id];
        if (known == null || state.seq >= known.seq) {
          media[from.id] = state;
          notifyListeners();
        }
      case HeartbeatWatchChanged(:final from, :final on):
        if (on) {
          lockWatchers[from.id] = e.everyS;
        } else {
          lockWatchers.remove(from.id);
        }
        _updateKeepAlive();
        notifyListeners();
      // A computer's screen this phone asked to see: shown like a second
      // display.
      case SessionStarted(:final session)
          when !e.sharing &&
              (e.kind == SessionKind.screen || e.kind == SessionKind.control):
        displays[session] = e;
        _addSession(e);
      case SessionStarted(:final session, :final peer, kind: SessionKind.input):
        remotes[peer.id] = session;
        _addSession(e);
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
        // Not on screen: Accept / Decline right in the notification.
        if (WidgetsBinding.instance.lifecycleState !=
            AppLifecycleState.resumed) {
          LinksyPlatform.noticeTransfer(
            transfer,
            files.length == 1
                ? '${from.name} wants to send you a file'
                : '${from.name} wants to send you ${files.length} files',
            [
              if (files.length == 1) files.single.name,
              formatBytes(total),
            ].join(' · '),
          );
        }
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
      case TransferComplete(:final transfer)
          when _imports.containsKey(transfer):
        _update(transfer, (a) {
          a
            ..status = ActivityStatus.done
            ..bytes = a.total;
        });
        _importEnded(transfer, ok: true);
      case TransferFailed(:final transfer, :final reason)
          when _imports.containsKey(transfer):
        _update(transfer, (a) {
          a
            ..status = ActivityStatus.failed
            ..reason = reason;
        });
        _importEnded(transfer, ok: false, reason: reason);
      case TransferComplete(:final transfer, :final saved):
        LinksyPlatform.cancelNotice(transfer);
        _update(transfer, (a) {
          a
            ..status = ActivityStatus.done
            ..bytes = a.total
            ..saved = saved;
        });
        // Into Downloads/Linksy, where other apps find them.
        if (saved.isNotEmpty) {
          LinksyPlatform.publishDownloads(saved).then((moved) {
            _update(transfer, (a) => a.saved = moved);
          });
        }
        _lastSample.remove(transfer);
      case TransferFailed(:final transfer, :final reason):
        LinksyPlatform.cancelNotice(transfer);
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
        LinksyPlatform.startShare(session, kind.name, peer.name, peer.id);
        _addSession(e);
      case SessionStarted(:final session, kind: SessionKind.display)
          when !e.sharing:
        displays[session] = e;
        _addSession(e);
      case SessionEnded(:final session):
        if (remotes.containsValue(session)) {
          remotes.removeWhere((_, s) => s == session);
          notifyListeners();
        }
        // Whichever side ended it, the timeline says it's over.
        _update(session, (a) {
          if (a.isLive) a.status = ActivityStatus.done;
        });
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
      // The webcam's controls, when a computer starts using the camera.
      case SessionStarted(kind: SessionKind.camera) when e.sharing:
        _prompts.add(e);
      // The full-screen page for a second display or a computer's screen.
      case SessionStarted(:final kind)
          when !e.sharing && kind != SessionKind.input:
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
        _ when !e.sharing && e.kind != SessionKind.display =>
          ActivityKind.watch,
        SessionKind.screen => ActivityKind.screen,
        SessionKind.camera => ActivityKind.camera,
        SessionKind.control => ActivityKind.control,
        SessionKind.display => ActivityKind.display,
        SessionKind.input => ActivityKind.remote,
      },
      // Video coming in: a second display, or a computer's screen watched.
      incoming: !e.sharing && e.kind != SessionKind.input,
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
    LinksyPlatform.cancelNotice(request);
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
        case SessionKind.display || SessionKind.input:
          break;
      }
    }
    await node.respond(request.request, accept: allowed);
    return error;
  }

  /// Watch [id]'s screen ([control]: and use its mouse and keyboard). The
  /// screen opens full screen once its user picks what to share there.
  Future<String?> watchScreen(String id, {required bool control}) =>
      _run(() => node.startView(id, control: control));

  /// Front ↔ back camera while this phone is a webcam.
  Future<void> switchCamera(String session) =>
      LinksyPlatform.switchCamera(session);

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

  /// Choose [deviceId]'s picture from the phone's photos. False if cancelled.
  Future<bool> pickPicture(String deviceId) async {
    final path = await LinksyPlatform.pickPicture(deviceId);
    if (path == null) return false;
    await FileImage(File(path)).evict();
    pictures[deviceId] = path;
    pictureVersion++;
    notifyListeners();
    return true;
  }

  Future<void> removePicture(String deviceId) async {
    final path = pictures.remove(deviceId);
    if (path != null) await FileImage(File(path)).evict();
    pictureVersion++;
    notifyListeners();
    await LinksyPlatform.removePicture(deviceId);
  }

  Future<String?> forget(String deviceId) async {
    if (pictures.containsKey(deviceId)) await removePicture(deviceId);
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
    _callSub?.cancel();
    _answerSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _importTimer?.cancel();
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
