/// `linksy://pair?v=1&id=<64 hex>&n=<name>&a=<ip:port>,…&t=<token>` links shown
/// as QR codes by the desktop (`docs/protocol.md` §4.7).
library;

class Invite {
  const Invite({
    required this.id,
    required this.name,
    required this.addresses,
    required this.token,
  });

  final String id;
  final String name;

  /// Best first, at most four. IPv6 in brackets: `[fd00::1]:47200`.
  final List<String> addresses;

  /// One-time, 32 hex chars, valid five minutes.
  final String token;

  static final _hex64 = RegExp(r'^[0-9a-f]{64}$');
  static final _hex32 = RegExp(r'^[0-9a-f]{32}$');

  /// Returns null for anything that isn't a valid version-1 invite.
  static Invite? tryParse(String text) {
    final uri = Uri.tryParse(text.trim());
    if (uri == null || uri.scheme != 'linksy' || uri.host != 'pair') {
      return null;
    }
    // Uri decodes `+` as a space in queryParameters, as the format requires.
    final q = uri.queryParameters;
    if (q['v'] != '1') return null;
    final id = q['id']?.toLowerCase() ?? '';
    final token = q['t']?.toLowerCase() ?? '';
    if (!_hex64.hasMatch(id) || !_hex32.hasMatch(token)) return null;
    final addresses = (q['a'] ?? '')
        .split(',')
        .map((a) => a.trim())
        .where((a) => a.isNotEmpty)
        .take(4)
        .toList();
    if (addresses.isEmpty) return null;
    return Invite(
      id: id,
      name: q['n']?.trim() ?? '',
      addresses: addresses,
      token: token,
    );
  }
}

/// "123456" → "123 456".
String formatPairingCode(String code) {
  final digits = code.padLeft(6, '0');
  return '${digits.substring(0, 3)} ${digits.substring(3)}';
}
