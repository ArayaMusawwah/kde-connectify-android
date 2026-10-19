import 'package:flutter_test/flutter_test.dart';
import 'package:linksy/core/invite.dart';

void main() {
  final id = 'ebb09ce2${'a' * 56}';
  final token = '0123456789abcdef' * 2;

  String link(String query) => 'linksy://pair?$query';

  test('parses a desktop invite', () {
    final invite = Invite.tryParse(
      link(
        'v=1&id=$id&n=Studio+Desktop&a=192.168.1.20:47200,'
        '%5Bfd00::1%5D:47200&t=$token',
      ),
    )!;
    expect(invite.id, id);
    expect(invite.name, 'Studio Desktop');
    expect(invite.addresses, ['192.168.1.20:47200', '[fd00::1]:47200']);
    expect(invite.token, token);
  });

  test('ignores unknown keys and keeps at most four addresses', () {
    final invite = Invite.tryParse(
      link(
        'v=1&id=$id&a=1.1.1.1:1,2.2.2.2:2,3.3.3.3:3,4.4.4.4:4,5.5.5.5:5'
        '&t=$token&future=yes',
      ),
    )!;
    expect(invite.addresses, hasLength(4));
    expect(invite.name, '');
  });

  test('rejects anything that is not a version-1 invite', () {
    final valid = 'id=$id&a=1.1.1.1:1&t=$token';
    expect(Invite.tryParse(link('v=2&$valid')), isNull);
    expect(Invite.tryParse(link(valid)), isNull);
    expect(Invite.tryParse('https://pair?v=1&$valid'), isNull);
    expect(Invite.tryParse(link('v=1&id=abc&a=1.1.1.1:1&t=$token')), isNull);
    expect(Invite.tryParse(link('v=1&id=$id&a=1.1.1.1:1&t=short')), isNull);
    expect(Invite.tryParse(link('v=1&id=$id&t=$token')), isNull);
    expect(Invite.tryParse('not a link'), isNull);
  });

  test('formats pairing codes as two groups of three', () {
    expect(formatPairingCode('123456'), '123 456');
    expect(formatPairingCode('42'), '000 042');
  });
}
