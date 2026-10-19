import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'app/activity.dart';
import 'app/app.dart';
import 'app/linksy_controller.dart';
import 'core/demo_node.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final support = await getApplicationSupportDirectory();
  final downloads =
      await getExternalStorageDirectory() ??
      await getApplicationDocumentsDirectory();

  // Until the Rust core is bridged in (see README), the app runs on a demo node.
  final node = DemoNode(name: 'My Phone', downloadDir: downloads.path);
  final controller = LinksyController(
    node,
    ActivityStore(File('${support.path}/history.json')),
  );
  await controller.start();

  runApp(LinksyApp(controller: controller));
}
