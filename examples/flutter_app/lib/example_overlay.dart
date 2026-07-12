import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Positions example-specific controls around the shared app chrome.
///
/// The scene remains edge-to-edge, while controls avoid system insets. Top
/// controls also start below the picker and settings button shared by every
/// example screen.
abstract final class ExampleOverlay {
  static const double _edge = 8;
  static const double _appChromeHeight = 64;
  static const double _sidePanelWidth = 340;

  static Widget topCenter({required Widget child}) =>
      _TopOverlay(alignment: Alignment.topCenter, child: child);

  /// A compact, single-purpose action centred in the safe viewport. Narrow
  /// layouts fall back below the shared chrome when the exact centre is not
  /// wide enough to avoid both global controls.
  static Widget topCenterAction({
    required Widget child,
    double maxWidth = 360,
    double? minHeaderWidth,
    double leadingReservation = 224,
  }) => _TopCenterAction(
    maxWidth: maxWidth,
    minHeaderWidth: minHeaderWidth ?? maxWidth,
    leadingReservation: leadingReservation,
    child: child,
  );

  /// A compact navigation action immediately after the shared picker.
  ///
  /// Larger groups fall back below the shared chrome when they cannot fit
  /// between the picker and settings button.
  static Widget topLeadingAction({
    required Widget child,
    double minWidth = 48,
  }) => _TopLeadingAction(minWidth: minWidth, child: child);

  static Widget topLeft({required Widget child}) =>
      _TopOverlay(alignment: Alignment.topLeft, child: child);

  static Widget topRight({required Widget child}) =>
      _TopOverlay(alignment: Alignment.topRight, child: child);

  /// Positions a tall settings panel below the shared settings button and
  /// constrains it to the remaining safe viewport height.
  static Widget topRightPanel({required Widget child}) =>
      _TopRightPanel(child: child);

  static Widget bottomLeft({required Widget child}) =>
      _BottomOverlay(alignment: Alignment.bottomLeft, child: child);

  /// Positions a tall left-side panel below the shared picker. The child gets
  /// the remaining safe viewport height and can scroll instead of covering it.
  static Widget bottomLeftPanel({required Widget child, bool paired = false}) =>
      _BottomSidePanel(
        alignment: Alignment.bottomLeft,
        paired: paired,
        child: child,
      );

  /// Positions a tall right-side panel with the same bounds as a left panel.
  ///
  /// Pass [paired] for pages that show editable panels on both sides. On a
  /// compact viewport each panel is narrowed enough to preserve a centre gap
  /// instead of overlapping the other panel.
  static Widget bottomRightPanel({
    required Widget child,
    bool paired = false,
  }) => _BottomSidePanel(
    alignment: Alignment.bottomRight,
    paired: paired,
    child: child,
  );

  static Widget bottomRight({required Widget child}) =>
      _BottomOverlay(alignment: Alignment.bottomRight, child: child);

  static Widget bottomCenter({required Widget child}) =>
      _BottomOverlay(alignment: Alignment.bottomCenter, child: child);
}

class _TopOverlay extends StatelessWidget {
  const _TopOverlay({required this.alignment, required this.child});

  final Alignment alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final edgeLeft = padding.left > ExampleOverlay._edge
        ? padding.left
        : ExampleOverlay._edge;
    final edgeRight = padding.right > ExampleOverlay._edge
        ? padding.right
        : ExampleOverlay._edge;
    final top =
        (padding.top > ExampleOverlay._edge
            ? padding.top
            : ExampleOverlay._edge) +
        ExampleOverlay._appChromeHeight;

    if (alignment == Alignment.topLeft) {
      return Positioned(top: top, left: edgeLeft, child: child);
    }
    if (alignment == Alignment.topRight) {
      return Positioned(top: top, right: edgeRight, child: child);
    }
    return Positioned(
      top: top,
      left: edgeLeft,
      right: edgeRight,
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: child,
        ),
      ),
    );
  }
}

class _TopCenterAction extends StatelessWidget {
  const _TopCenterAction({
    required this.child,
    required this.maxWidth,
    required this.minHeaderWidth,
    required this.leadingReservation,
  });

  final Widget child;
  final double maxWidth;
  final double minHeaderWidth;
  final double leadingReservation;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final edgeLeft = padding.left > ExampleOverlay._edge
        ? padding.left
        : ExampleOverlay._edge;
    final edgeRight = padding.right > ExampleOverlay._edge
        ? padding.right
        : ExampleOverlay._edge;
    const settingsReservation = 64.0;

    final safeCenter = (edgeLeft + size.width - edgeRight) / 2;
    final safeLeft = edgeLeft + leadingReservation;
    final safeRight = size.width - edgeRight - settingsReservation;
    final centredMaxWidth = math
        .max(0.0, 2 * math.min(safeCenter - safeLeft, safeRight - safeCenter))
        .toDouble();

    if (centredMaxWidth < minHeaderWidth) {
      return ExampleOverlay.topCenter(child: child);
    }

    return Positioned(
      top: padding.top > ExampleOverlay._edge
          ? padding.top
          : ExampleOverlay._edge,
      left: edgeLeft,
      right: edgeRight,
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: math.min(maxWidth, centredMaxWidth),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _TopLeadingAction extends StatelessWidget {
  const _TopLeadingAction({required this.child, required this.minWidth});

  final Widget child;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final edgeLeft = padding.left > ExampleOverlay._edge
        ? padding.left
        : ExampleOverlay._edge;
    final edgeRight = padding.right > ExampleOverlay._edge
        ? padding.right
        : ExampleOverlay._edge;
    const pickerReservation = 224.0;
    const settingsReservation = 64.0;
    final left = edgeLeft + pickerReservation;
    final availableWidth = size.width - left - edgeRight - settingsReservation;

    if (availableWidth < minWidth) {
      return ExampleOverlay.topCenter(child: child);
    }

    return Positioned(
      top: padding.top > ExampleOverlay._edge
          ? padding.top
          : ExampleOverlay._edge,
      left: left,
      child: child,
    );
  }
}

class _TopRightPanel extends StatelessWidget {
  const _TopRightPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final size = MediaQuery.sizeOf(context);
    final edgeRight = padding.right > ExampleOverlay._edge
        ? padding.right
        : ExampleOverlay._edge;
    final edgeBottom = padding.bottom > ExampleOverlay._edge
        ? padding.bottom
        : ExampleOverlay._edge;
    final top =
        (padding.top > ExampleOverlay._edge
            ? padding.top
            : ExampleOverlay._edge) +
        ExampleOverlay._appChromeHeight;
    final maxHeight = size.height - top - edgeBottom;

    return Positioned(
      top: top,
      right: edgeRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: child,
      ),
    );
  }
}

class _BottomOverlay extends StatelessWidget {
  const _BottomOverlay({required this.alignment, required this.child});

  final Alignment alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final edgeLeft = padding.left > ExampleOverlay._edge
        ? padding.left
        : ExampleOverlay._edge;
    final edgeRight = padding.right > ExampleOverlay._edge
        ? padding.right
        : ExampleOverlay._edge;
    final bottom = padding.bottom > ExampleOverlay._edge
        ? padding.bottom
        : ExampleOverlay._edge;

    if (alignment == Alignment.bottomLeft) {
      return Positioned(bottom: bottom, left: edgeLeft, child: child);
    }
    if (alignment == Alignment.bottomRight) {
      return Positioned(bottom: bottom, right: edgeRight, child: child);
    }
    return Positioned(
      bottom: bottom,
      left: edgeLeft,
      right: edgeRight,
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: child,
        ),
      ),
    );
  }
}

class _BottomSidePanel extends StatelessWidget {
  const _BottomSidePanel({
    required this.alignment,
    required this.paired,
    required this.child,
  });

  final Alignment alignment;
  final bool paired;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final edgeLeft = padding.left > ExampleOverlay._edge
        ? padding.left
        : ExampleOverlay._edge;
    final edgeRight = padding.right > ExampleOverlay._edge
        ? padding.right
        : ExampleOverlay._edge;
    final edgeBottom = padding.bottom > ExampleOverlay._edge
        ? padding.bottom
        : ExampleOverlay._edge;
    final top =
        (padding.top > ExampleOverlay._edge
            ? padding.top
            : ExampleOverlay._edge) +
        ExampleOverlay._appChromeHeight;
    final size = MediaQuery.sizeOf(context);
    final availableWidth = math.max(0.0, size.width - edgeLeft - edgeRight);
    final panelWidth = paired
        ? math.min(
            ExampleOverlay._sidePanelWidth,
            math.max(0.0, (availableWidth - ExampleOverlay._edge) / 2),
          )
        : math.min(ExampleOverlay._sidePanelWidth, availableWidth);

    return Positioned(
      top: top,
      bottom: edgeBottom,
      left: alignment == Alignment.bottomLeft ? edgeLeft : null,
      right: alignment == Alignment.bottomRight ? edgeRight : null,
      child: SizedBox(
        width: panelWidth,
        child: Align(alignment: alignment, child: child),
      ),
    );
  }
}
