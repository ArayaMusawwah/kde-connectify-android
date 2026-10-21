/// Linksy's service information (docs/protocol.md §4.12): relays, the latest
/// Android release, notices. Information only: a wrong copy can at worst fail
/// to connect, so nothing ever waits on it.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'core_json.dart';

const serviceUrl = 'https://linksy.diary.mg/linksy-relay';

/// The relay built into the core, used until the service says otherwise.
const defaultRelay = 'https://linksy-relay.diary.mg';

/// The protocol version this app speaks.
const protocolVersion = 1;

class ServiceNotice {
  const ServiceNotice({
    required this.id,
    required this.title,
    required this.body,
    required this.warning,
  });
  final String id;
  final String title;
  final String body;
  final bool warning;
}

class ServiceInfo {
  const ServiceInfo({
    required this.relays,
    required this.minimumProtocol,
    required this.androidDownload,
    required this.notices,
  });

  /// `https` relays, best first.
  final List<String> relays;
  final int minimumProtocol;

  /// Where the newest Android app is, if the service says.
  final String? androidDownload;

  /// Notices for Android that haven't run out yet.
  final List<ServiceNotice> notices;

  String get relay => relays.firstOrNull ?? defaultRelay;

  /// This app's protocol is too old to keep connecting.
  bool get outdated => minimumProtocol > protocolVersion;

  /// Null when [raw] isn't a schema 1 file.
  static ServiceInfo? parse(String raw, {DateTime? now}) {
    if (raw.length > 64 * 1024) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Json || decoded['schema'] != 1) return null;
    final at = now ?? DateTime.now();
    List<Json> list(Object? v) => [
      for (final e in v is List ? v : const []) ?e is Json ? e : null,
    ];
    final protocol = decoded['protocol'];
    final latest = decoded['latest'];
    final android = latest is Json ? latest['android'] : null;
    return ServiceInfo(
      relays: [
        for (final r in list(decoded['relays']))
          if (r['url'] case final String url when url.startsWith('https://'))
            url,
      ],
      minimumProtocol: protocol is Json && protocol['minimum'] is num
          ? (protocol['minimum'] as num).toInt()
          : 1,
      androidDownload: switch (android) {
        {'download': final String url} when url.startsWith('https://') => url,
        _ => null,
      },
      notices: [
        for (final n in list(decoded['notices']))
          if (n['id'] is String &&
              (n['platforms'] is! List ||
                  (n['platforms'] as List).contains('android')) &&
              !_expired(n['until'], at))
            ServiceNotice(
              id: n['id'] as String,
              title: n['title'] as String? ?? '',
              body: n['body'] as String? ?? '',
              warning: n['level'] == 'warning',
            ),
      ],
    );
  }

  static bool _expired(Object? until, DateTime now) =>
      until is String && (DateTime.tryParse(until)?.isBefore(now) ?? false);
}

/// Keeps the last good copy in [cache] and fetches a new one at most daily.
class ServiceInfoStore {
  ServiceInfoStore(this.cache);
  final File cache;

  /// The cached copy, read at start-up without the network.
  ServiceInfo? cached() {
    try {
      return ServiceInfo.parse(cache.readAsStringSync());
    } on Object {
      return null;
    }
  }

  /// A fresh copy when the cache is a day old or missing; else null.
  Future<ServiceInfo?> refresh() async {
    try {
      if (cache.existsSync() &&
          DateTime.now().difference(cache.lastModifiedSync()) <
              const Duration(days: 1)) {
        return null;
      }
    } on Object {
      // Unreadable cache: fetch.
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client
          .getUrl(Uri.parse(serviceUrl))
          .timeout(const Duration(seconds: 5));
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      if (response.statusCode != 200) return null;
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 5))) {
        bytes.addAll(chunk);
        if (bytes.length > 64 * 1024) return null;
      }
      final raw = utf8.decode(bytes, allowMalformed: true);
      final info = ServiceInfo.parse(raw);
      if (info != null) await cache.writeAsString(raw);
      return info;
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
