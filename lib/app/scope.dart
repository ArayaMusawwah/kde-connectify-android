import 'package:flutter/widgets.dart';

import 'linksy_controller.dart';

/// Hands the controller down the tree and rebuilds dependents on change.
class LinksyScope extends InheritedNotifier<LinksyController> {
  const LinksyScope({
    super.key,
    required LinksyController controller,
    required super.child,
  }) : super(notifier: controller);

  static LinksyController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LinksyScope>()!.notifier!;

  /// Without subscribing to changes, for callbacks.
  static LinksyController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<LinksyScope>()!.notifier!;
}
