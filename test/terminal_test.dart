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

  test('exit in the shell closes the tab and its session', () async {
    final node = DemoNode(name: 'Pixel', downloadDir: '/tmp');
    final studio = (await node.devices())
        .firstWhere((d) => d.device.name == 'Studio Desktop')
        .device;
    final terminals = Terminals(node);
    final gone = <TerminalTab>[];
    terminals.gone.listen(gone.add);
    final tab = terminals.add(studio.id);
    await tab.open(DemoNode.demoTerminalCode);
    tab.key('exit\r');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(gone, [tab]);
    expect(terminals.of(studio.id), isEmpty);
    expect(await node.terminals(studio.id), isEmpty);
  });

  test('Close ends the shell, nothing left on the computer', () async {
    final node = DemoNode(name: 'Pixel', downloadDir: '/tmp');
    final studio = (await node.devices())
        .firstWhere((d) => d.device.name == 'Studio Desktop')
        .device;
    final terminals = Terminals(node);
    final tab = terminals.add(studio.id);
    await tab.open(DemoNode.demoTerminalCode);
    await tab.close();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(terminals.of(studio.id), isEmpty);
    expect(await node.terminals(studio.id), isEmpty);
  });

  test('refusal messages say what to do', () {
    expect(
      TerminalRefused(TerminalRefusal.off, name: 'fedora').message,
      'On fedora, open this phone’s page and allow the terminal there.',
    );
    expect(
      TerminalRefused(TerminalRefusal.locked, name: 'fedora').message,
      'Too many wrong codes. Unlock the terminal on fedora.',
    );
  });
}
