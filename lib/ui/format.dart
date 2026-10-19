/// Decimal units, like the desktop: "2.1 MB".
String formatBytes(int bytes) {
  if (bytes < 1000) return '$bytes bytes';
  const units = ['kB', 'MB', 'GB', 'TB'];
  var value = bytes / 1000;
  var unit = 0;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000;
    unit++;
  }
  final digits = value >= 100 || unit == 0 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

String formatSpeed(double bytesPerSecond) =>
    '${formatBytes(bytesPerSecond.round())}/s';

/// "8 seconds left", "3 minutes left", "about 2 hours left".
String formatTimeLeft(int remaining, double bytesPerSecond) {
  if (bytesPerSecond <= 0) return '';
  final s = (remaining / bytesPerSecond).ceil();
  if (s < 60) return s == 1 ? '1 second left' : '$s seconds left';
  final m = (s / 60).round();
  if (m < 60) return m == 1 ? '1 minute left' : '$m minutes left';
  final h = (m / 60).round();
  return h == 1 ? 'about 1 hour left' : 'about $h hours left';
}

String formatClock(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// "Today", "Yesterday", "Monday 12 October", with the year when it isn't
/// this year.
String formatDay(DateTime t, {DateTime? now}) {
  final today = _date(now ?? DateTime.now());
  final day = _date(t);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return day.year == today.year
      ? '${_weekdays[day.weekday - 1]} ${day.day} ${_months[day.month - 1]}'
      : '${day.day} ${_months[day.month - 1]} ${day.year}';
}

DateTime _date(DateTime t) => DateTime(t.year, t.month, t.day);

/// "/storage/emulated/0/Download/Linksy" → "Phone › Download › Linksy".
String friendlyPath(String path) {
  const roots = {'/storage/emulated/0': 'Phone', '/sdcard': 'Phone'};
  for (final MapEntry(:key, :value) in roots.entries) {
    if (path == key || path.startsWith('$key/')) {
      final rest = path
          .substring(key.length)
          .split('/')
          .where((p) => p.isNotEmpty);
      return [value, ...rest].join(' › ');
    }
  }
  return path;
}

/// Up to two initials: "Studio Desktop" → "SD", "ThinkPad" → "T".
String initials(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  return words.take(2).map((w) => w.characters.first.toUpperCase()).join();
}

extension on String {
  Iterable<String> get characters => runes.map(String.fromCharCode);
}
