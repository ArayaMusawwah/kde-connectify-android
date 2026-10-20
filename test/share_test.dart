import 'package:flutter_test/flutter_test.dart';
import 'package:linksy/features/share/share_sheet.dart';

void main() {
  test('finds the link in shared text', () {
    expect(
      findWebLink('https://example.com/a?b=1'),
      'https://example.com/a?b=1',
    );
    expect(
      findWebLink(
        'Linksy — phone and computer, together https://linksy.diary.mg/',
      ),
      'https://linksy.diary.mg/',
    );
    expect(findWebLink('HTTP://EXAMPLE.COM'), 'HTTP://EXAMPLE.COM');
    expect(findWebLink('just some words'), isNull);
    expect(findWebLink('ftp://example.com/file'), isNull);
  });
}
