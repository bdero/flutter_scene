/// In-window modal dialogs for the editor shell.
///
/// With the windowing feature enabled, showDialog hosts dialogs in their own
/// OS window. On the stable revision the editor distributions build against,
/// that window never receives its content size (it opens 0x0) while still
/// blocking the app modally, and its widget tree mounts outside the shell's
/// theme scope, so forui controls throw on mount. Pushing the DialogRoute
/// directly keeps every editor dialog a classic modal inside the main
/// window. All shell dialogs go through this helper, never showDialog.
library;

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// Shows [builder]'s widget as a modal dialog inside the current window.
///
/// A drop-in for showDialog that never hosts the dialog in a separate OS
/// window. Returns the value passed to `Navigator.pop`, like showDialog.
Future<T?> showEditorDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  return navigator.push(
    DialogRoute<T>(
      context: context,
      builder: builder,
      barrierColor: Colors.black54,
      barrierDismissible: barrierDismissible,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
    ),
  );
}

/// Shows a forui dialog with a [Material] ancestor in scope.
///
/// [FDialogRoute] builds its content from the navigator's context, so nothing
/// above it in the dialog's tree is a [Material]. Every material-library
/// control that paints ink — [InkWell], [ListTile], [IconButton] — asserts on
/// mount without one and paints its red error box where the control should
/// be. The editor's dialogs mix forui controls with those freely, so the
/// ancestor belongs here rather than around each row that happens to use one.
///
/// The [Material] is transparent and inherits the surrounding text style, so
/// it changes nothing a dialog already draws.
Future<T?> showEditorFDialog<T>({
  required BuildContext context,
  required Widget Function(
    BuildContext context,
    FDialogStyle style,
    Animation<double> animation,
  )
  builder,
  bool barrierDismissible = true,
}) {
  return showFDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (context, style, animation) => Material(
      type: MaterialType.transparency,
      textStyle: DefaultTextStyle.of(context).style,
      child: builder(context, style, animation),
    ),
  );
}
