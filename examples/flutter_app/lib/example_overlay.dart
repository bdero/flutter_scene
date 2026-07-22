import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Positions example-specific controls around the shared app chrome.
///
/// The scene remains edge-to-edge, while controls avoid system insets. Top
/// controls also start below the picker and settings button shared by every
/// example screen.
abstract final class ExampleOverlay {
  /// Minimum padding kept between controls and the screen edge.
  static const double edge = 8;

  /// Height reserved for the shared picker/settings chrome row.
  static const double appChromeHeight = 64;

  /// Width reserved for the shared example picker (top-left).
  static const double pickerReservation = 224;

  /// Width reserved for the shared settings button (top-right).
  static const double settingsReservation = 64;

  static const double _sidePanelWidth = 340;

  /// System insets clamped to at least [edge] on every side.
  static EdgeInsets safeInsetsOf(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return EdgeInsets.fromLTRB(
      math.max(padding.left, edge),
      math.max(padding.top, edge),
      math.max(padding.right, edge),
      math.max(padding.bottom, edge),
    );
  }

  static Widget topCenter({required Widget child}) =>
      _TopOverlay(alignment: Alignment.topCenter, child: child);

  /// A compact, single-purpose action centered in the safe viewport. Narrow
  /// layouts fall back below the shared chrome when the exact center is not
  /// wide enough to avoid both global controls.
  static Widget topCenterAction({
    required Widget child,
    double maxWidth = 360,
    double? minHeaderWidth,
    double leadingReservation = pickerReservation,
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
  /// compact viewport each panel is narrowed enough to preserve a center gap
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
    final insets = ExampleOverlay.safeInsetsOf(context);
    final top = insets.top + ExampleOverlay.appChromeHeight;

    if (alignment == Alignment.topLeft) {
      return Positioned(top: top, left: insets.left, child: child);
    }
    if (alignment == Alignment.topRight) {
      return Positioned(top: top, right: insets.right, child: child);
    }
    return Positioned(
      top: top,
      left: insets.left,
      right: insets.right,
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
    final insets = ExampleOverlay.safeInsetsOf(context);

    final safeCenter = (insets.left + size.width - insets.right) / 2;
    final safeLeft = insets.left + leadingReservation;
    final safeRight =
        size.width - insets.right - ExampleOverlay.settingsReservation;
    final centeredMaxWidth = math
        .max(0.0, 2 * math.min(safeCenter - safeLeft, safeRight - safeCenter))
        .toDouble();

    if (centeredMaxWidth < minHeaderWidth) {
      return ExampleOverlay.topCenter(child: child);
    }

    return Positioned(
      top: insets.top,
      left: insets.left,
      right: insets.right,
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: math.min(maxWidth, centeredMaxWidth),
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
    final insets = ExampleOverlay.safeInsetsOf(context);
    final left = insets.left + ExampleOverlay.pickerReservation;
    final availableWidth =
        size.width - left - insets.right - ExampleOverlay.settingsReservation;

    if (availableWidth < minWidth) {
      return ExampleOverlay.topCenter(child: child);
    }

    return Positioned(top: insets.top, left: left, child: child);
  }
}

class _TopRightPanel extends StatelessWidget {
  const _TopRightPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final insets = ExampleOverlay.safeInsetsOf(context);
    final top = insets.top + ExampleOverlay.appChromeHeight;
    final maxHeight = size.height - top - insets.bottom;

    return Positioned(
      top: top,
      right: insets.right,
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
    final insets = ExampleOverlay.safeInsetsOf(context);

    if (alignment == Alignment.bottomLeft) {
      return Positioned(bottom: insets.bottom, left: insets.left, child: child);
    }
    if (alignment == Alignment.bottomRight) {
      return Positioned(
        bottom: insets.bottom,
        right: insets.right,
        child: child,
      );
    }
    return Positioned(
      bottom: insets.bottom,
      left: insets.left,
      right: insets.right,
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
    final size = MediaQuery.sizeOf(context);
    final insets = ExampleOverlay.safeInsetsOf(context);
    final top = insets.top + ExampleOverlay.appChromeHeight;
    final availableWidth = math.max(
      0.0,
      size.width - insets.left - insets.right,
    );
    final panelWidth = paired
        ? math.min(
            ExampleOverlay._sidePanelWidth,
            math.max(0.0, (availableWidth - ExampleOverlay.edge) / 2),
          )
        : math.min(ExampleOverlay._sidePanelWidth, availableWidth);

    return Positioned(
      top: top,
      bottom: insets.bottom,
      left: alignment == Alignment.bottomLeft ? insets.left : null,
      right: alignment == Alignment.bottomRight ? insets.right : null,
      child: SizedBox(
        width: panelWidth,
        child: Align(alignment: alignment, child: child),
      ),
    );
  }
}
