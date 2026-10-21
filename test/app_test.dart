import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linksy/app/activity.dart';
import 'package:linksy/app/app.dart';
import 'package:linksy/app/linksy_controller.dart';
import 'package:linksy/core/demo_node.dart';

/// Pumps frames for half a second, for screens with something that never
/// stops animating (an indeterminate progress bar).
Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  Future<(LinksyController, DemoNode)> pumpApp(WidgetTester tester) async {
    final node = DemoNode(name: 'Test Phone', downloadDir: '/downloads');
    final c = LinksyController(node, ActivityStore(null));
    // Set up already (language, permissions): straight to home.
    c.prefs = {'onboarded': '1'};
    // Looping animations stop when motion is reduced, so the tree settles.
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    // A phone, not the default 800×600.
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await c.start();
    // Cancels its timers (photo backup checks) before the test ends.
    addTearDown(c.dispose);
    await tester.pumpWidget(LinksyApp(controller: c));
    await tester.pumpAndSettle();
    return (c, node);
  }

  testWidgets('home lists paired and unpaired devices', (tester) async {
    await pumpApp(tester);
    expect(find.text('YOUR DEVICES'), findsOneWidget);
    expect(find.text('Studio Desktop'), findsOneWidget);
    expect(find.text('ThinkPad'), findsOneWidget);
    expect(find.text('NEARBY, NOT PAIRED'), findsOneWidget);
    expect(find.text('Living Room PC'), findsOneWidget);
    expect(find.text('Pair'), findsOneWidget);
  });

  testWidgets('a device page offers its actions', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Studio Desktop'));
    await tester.pumpAndSettle();
    expect(find.text('Send files'), findsOneWidget);
    expect(find.text('Clipboard'), findsOneWidget);
    expect(find.text('Ping'), findsOneWidget);
    expect(find.text('Remote'), findsOneWidget);
    expect(find.text('Find it'), findsOneWidget);
    expect(find.text('Back up photos'), findsOneWidget);
  });

  testWidgets('incoming files ask first', (tester) async {
    final (_, node) = await pumpApp(tester);
    node.simulateIncomingFiles();
    await frames(tester);
    final title = find.text(
      'Studio Desktop is sending you 3 files',
      findRichText: true,
    );
    expect(title, findsOneWidget);
    expect(find.text('6.3 MB in total'), findsOneWidget);
    await tester.tap(find.text('Decline'));
    await frames(tester);
    expect(title, findsNothing);
  });
}
