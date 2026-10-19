import 'dart:async';

import 'package:flutter/services.dart';

/// The few things only Android knows (android/…/MainActivity.kt).
abstract final class LinksyPlatform {
  static const _channel = MethodChannel('app.linksy/platform');
  static final _links = StreamController<String>.broadcast();
  static final _displaySizes =
      StreamController<(String, double, double)>.broadcast();
  static final _displaysEnded = StreamController<String>.broadcast();
  static var _listening = false;

  /// Calls from Android: pairing links, and second-display size and end.
  static void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'link' when call.arguments is String:
          _links.add(call.arguments as String);
        case 'displaySize':
          final a = call.arguments as Map;
          _displaySizes.add((
            a['session'] as String,
            (a['width'] as num).toDouble(),
            (a['height'] as num).toDouble(),
          ));
        case 'displayEnded' when call.arguments is String:
          _displaysEnded.add(call.arguments as String);
      }
    });
  }

  static Future<T?> _call<T>(String method, [Object? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      // No Android side (tests).
      return null;
    }
  }

  /// The name the user gave this phone, else its model.
  static Future<String> deviceName() async {
    try {
      final name = await _channel.invokeMethod<String>('deviceName');
      return name == null || name.trim().isEmpty ? 'Android phone' : name;
    } on Object {
      return 'Android phone';
    }
  }

  /// A `linksy://pair?…` link that opened the app, once.
  static Future<String?> takeLink() async {
    try {
      return await _channel.invokeMethod<String>('takeLink');
    } on Object {
      return null;
    }
  }

  /// Android's own screen capture prompt, for [session]. True if allowed.
  static Future<bool> requestScreenCapture(String session) async =>
      await _call<bool>('requestScreenCapture', {'session': session}) ?? false;

  /// The camera permission. True if granted.
  static Future<bool> requestCamera() async =>
      await _call<bool>('requestCamera') ?? false;

  /// Starts encoding the screen or camera into [session] (a foreground
  /// service, so it goes on in other apps). `control` also plays the other
  /// side's input.
  static Future<void> startShare(String session, String kind, String peer) =>
      _call<void>('startShare', {
        'session': session,
        'kind': kind,
        'peer': peer,
      });

  static Future<void> stopShare(String session) =>
      _call<void>('stopShare', {'session': session});

  /// What's allowed now: (notifications, camera, remote control). Null
  /// without an Android side (tests).
  static Future<({bool notifications, bool camera, bool control})?>
  permissions() async {
    final m = await _call<Map<Object?, Object?>>('permissions');
    if (m == null) return null;
    return (
      notifications: m['notifications'] == true,
      camera: m['camera'] == true,
      control: m['control'] == true,
    );
  }

  /// True the first time it's asked on this install (then false), for the
  /// permissions sheet shown on first launch.
  static Future<bool> firstPermissionsVisit() async =>
      await _call<bool>('firstPermissionsVisit') ?? false;

  /// Android's own permission dialog for `camera` or `notifications` (or
  /// Linksy's app settings once Android stops showing it). True if granted.
  static Future<bool> requestPermission(String name) async =>
      await _call<bool>('requestPermission', {'name': name}) ?? false;

  /// Whether remote control is switched on (Settings → Accessibility).
  static Future<bool> controlEnabled() async =>
      await _call<bool>('controlEnabled') ?? false;

  /// Linksy's page in Android's Accessibility settings (there's no dialog
  /// for this one).
  static Future<void> openAccessibilitySettings() =>
      _call<void>('openAccessibilitySettings');

  /// Decodes a second-display session; returns the texture id to show.
  static Future<int?> startDisplay(String session) =>
      _call<int>('startDisplay', {'session': session});

  static Future<void> stopDisplay(String session) =>
      _call<void>('stopDisplay', {'session': session});

  /// Framed input messages for a second display (u32 length + JSON each).
  static Future<void> displayInput(String session, Uint8List frames) =>
      _call<void>('displayInput', {'session': session, 'frames': frames});

  /// Links that arrive while the app is running.
  static Stream<String> get links {
    _listen();
    return _links.stream;
  }

  /// A second display's video size once known: (session, width, height).
  static Stream<(String, double, double)> get displaySizes {
    _listen();
    return _displaySizes.stream;
  }

  /// A second display whose video stopped.
  static Stream<String> get displaysEnded {
    _listen();
    return _displaysEnded.stream;
  }
}
