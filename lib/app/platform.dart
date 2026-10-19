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
