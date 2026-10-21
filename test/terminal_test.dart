import 'package:flutter_test/flutter_test.dart';
import 'package:linksy/app/terminals.dart';
import 'package:linksy/core/demo_node.dart';
import 'package:linksy/core/linksy_node.dart';
import 'package:linksy/core/models.dart';

void main() {
  test('wrong code, then the right one, then a command', () async {
    final node = DemoNode(name: 'Pixel', downloadDir: '/tmp');
    final studio = (await node.devices())
        .firstWhere((d) => d.device.name == 'Studio Desktop')
        .device;
    final terminals = Terminals(node);
    final tab = terminals.add(studio.id);

    await expectLater(
      tab.open('000000'),
      throwsA(
        isA<TerminalRefused>()
            .having((e) => e.reason, 'reason', TerminalRefusal.code)
            .having((e) => e.message, 'message', 'Wrong code, 4 tries left.'),
      ),
    );

    await tab.open(DemoNode.demoTerminalCode);
    expect(tab.state, TabState.live);
    tab.key('pwd\r');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final screen = [
      for (var i = 0; i < tab.term.buffer.lines.length; i++)
        tab.term.buffer.lines[i].toString(),
    ].join('\n');
    expect(screen, contains('/home/axel'));

    await tab.detach();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(tab.state, TabState.detached);
    expect(await node.terminals(studio.id), hasLength(1));
  });

  test('refusal messages say what to do', () {
    expect(
      TerminalRefused(TerminalRefusal.off, name: 'fedora').message,
      'Turn on Allow Terminal for this phone on fedora.',
    );
    expect(
      TerminalRefused(TerminalRefusal.locked, name: 'fedora').message,
      'Too many wrong codes. Unlock the terminal on fedora.',
    );
  });
}
