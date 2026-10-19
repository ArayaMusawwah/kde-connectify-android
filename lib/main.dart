import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'app/activity.dart';
import 'app/app.dart';
import 'app/linksy_controller.dart';
import 'app/platform.dart';
import 'core/demo_node.dart';
import 'core/linksy_node.dart';
import 'core/rust_node.dart';

/// `--dart-define=LINKSY_DEMO=true` runs on made-up devices, for UI work.
const _demo = bool.fromEnvironment('LINKSY_DEMO');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final support = await getApplicationSupportDirectory();
  final storage =
      await getExternalStorageDirectory() ??
      await getApplicationDocumentsDirectory();
  final received = Directory('${storage.path}/Received')
    ..createSync(recursive: true);
  final name = await LinksyPlatform.deviceName();

  final LinksyNode node;
  if (_demo) {
    node = DemoNode(name: name, downloadDir: received.path);
  } else {
    try {
      node = await RustNode.start(
        // Holds this phone's private key: app-private storage only.
        dataDir: '${support.path}/node',
        downloadDir: received.path,
        name: name,
      );
    } on Object catch (e) {
      runApp(StartupFailedApp(message: '$e'));
      return;
    }
  }

  final controller = LinksyController(
    node,
    ActivityStore(File('${support.path}/history.json')),
  );
  await controller.start();
  runApp(LinksyApp(controller: controller));
}
