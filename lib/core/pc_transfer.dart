/// A file transfer this phone started from the computer-files browser
/// (a download from the computer, or an upload to it). It lives in memory;
/// restart loses it, and that's fine — the user taps again.
class PcTransfer {
  PcTransfer({
    required this.id,
    required this.kind,
    required this.name,
    required this.remote,
    this.size,
    this.localPath,
  });

  /// Random id; only for the UI.
  final String id;

  /// Download from the computer, or upload to it.
  final PcTransferKind kind;

  /// Display name of the file being moved.
  final String name;

  /// Path on the computer: the file for a download, the directory for an upload.
  final String remote;

  /// Size in bytes, from stat; null when not known yet.
  int? size;

  /// For a download: where it is being written; for an upload: the local file.
  String? localPath;

  /// Bytes done so far.
  int done = 0;

  /// Queue state: not started, moving, waiting for something, finished.
  PcTransferState state = PcTransferState.pending;

  /// Reason it stopped, shown when it didn't finish.
  String? error;

  /// Paused by the user.
  bool paused = false;

  /// When it was queued, used by "up next" order.
  final DateTime queuedAt = DateTime.now();

  bool get active => state == PcTransferState.running;
}

enum PcTransferKind { download, upload }

enum PcTransferState { pending, running, paused, done, failed, cancelled }
