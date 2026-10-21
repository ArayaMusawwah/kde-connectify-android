import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:linksy/core/models.dart';
import 'package:linksy/ui/format.dart';

void main() {
  // Dates come from intl in the app's language; tests load its data.
  setUpAll(initializeDateFormatting);

  test('bytes in decimal units', () {
    expect(formatBytes(512), '512 bytes');
    expect(formatBytes(2100000), '2.1 MB');
    expect(formatBytes(400000000), '400 MB');
    expect(formatBytes(1500), '2 kB');
  });

  test('time left', () {
    expect(formatTimeLeft(304000000, 38000000), '8 seconds left');
    expect(formatTimeLeft(1000, 1000), '1 second left');
    expect(formatTimeLeft(180000, 1000), '3 minutes left');
    expect(formatTimeLeft(1, 0), '');
  });

  test('day headers', () {
    final now = DateTime(2026, 10, 19, 15);
    expect(formatDay(DateTime(2026, 10, 19, 1), now: now), 'Today');
    expect(formatDay(DateTime(2026, 10, 18, 23), now: now), 'Yesterday');
    expect(formatDay(DateTime(2026, 10, 12), now: now), 'Monday 12 October');
    expect(formatDay(DateTime(2025, 3, 1), now: now), '1 March 2025');
  });

  test('paths read like the Files app', () {
    expect(
      friendlyPath('/storage/emulated/0/Download/Linksy'),
      'Phone › Download › Linksy',
    );
    expect(friendlyPath('/data/user/0/app.linksy'), '/data/user/0/app.linksy');
  });

  test('initials and short ids', () {
    expect(initials('Studio Desktop'), 'SD');
    expect(initials('ThinkPad'), 'T');
    expect(initials('my living room pc'), 'ML');
    expect(shortDeviceId('ebb09ce2${'0' * 56}'), 'EBB0-9CE2');
  });
}
