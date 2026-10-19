import 'dart:async';

import 'package:flutter/services.dart';

/// The few things only Android knows (android/…/MainActivity.kt).
abstract final class LinksyPlatform {
  static const _channel = MethodChannel('app.linksy/platform');
  static final _links = StreamController<String>.broadcast();
  static var _listening = false;

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
      await _channel.invokeMethod<bool>('requestScreenCapture', {
        'session': session,
      }) ??
      false;

  /// The camera permission. True if granted.
  static Future<bool> requestCamera() async =>
      await _channel.invokeMethod<bool>('requestCamera') ?? false;

  /// Starts encoding the screen or camera into [session] (a foreground
  /// service, so it goes on in other apps).
  static Future<void> startShare(
    String session,
    String kind,
    String peer,
  ) async {
    try {
      await _channel.invokeMethod('startShare', {
        'session': session,
        'kind': kind,
        'peer': peer,
      });
    } on MissingPluginException {
      // No Android side (tests).
    }
  }

  static Future<void> stopShare(String session) async {
    try {
      await _channel.invokeMethod('stopShare', {'session': session});
    } on MissingPluginException {
      // No Android side (tests).
    }
  }

  /// Links that arrive while the app is running.
  static Stream<String> get links {
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'link' && call.arguments is String) {
          _links.add(call.arguments as String);
        }
      });
    }
    return _links.stream;
  }
}
