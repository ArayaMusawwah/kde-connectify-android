import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:linksy/app/activity.dart';

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('linksy'));
  tearDown(() => dir.delete(recursive: true));

  Activity entry(ActivityKind kind, ActivityStatus status, {String? text}) =>
      Activity(
        id: '$kind$status',
        deviceId: 'dev',
        kind: kind,
        incoming: true,
        time: DateTime(2026, 10, 19),
        status: status,
        text: text,
      );

  test('never writes clipboard text to disk', () async {
    final store = ActivityStore(File('${dir.path}/history.json'));
    await store.save([
      entry(ActivityKind.clipboard, ActivityStatus.done, text: 'hunter2'),
      entry(ActivityKind.ping, ActivityStatus.done, text: 'Ping'),
    ]);
    expect(await store.file!.readAsString(), isNot(contains('hunter2')));
    final loaded = await store.load();
    expect(loaded.first.text, isNull);
    expect(loaded.last.text, 'Ping');
  });

  test(
    'a transfer still running when saved comes back as interrupted',
    () async {
      final store = ActivityStore(File('${dir.path}/history.json'));
      await store.save([entry(ActivityKind.files, ActivityStatus.active)]);
      final loaded = (await store.load()).single;
      expect(loaded.status, ActivityStatus.failed);
      expect(loaded.reason, 'Interrupted');
    },
  );

  test('a missing or broken file is an empty history', () async {
    final file = File('${dir.path}/history.json');
    expect(await ActivityStore(file).load(), isEmpty);
    await file.writeAsString('{not json');
    expect(await ActivityStore(file).load(), isEmpty);
  });
}
