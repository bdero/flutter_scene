// Split out of animation_panel.dart; see the owning library there.
part of '../animation_panel.dart';

/// A tooltip tuned for the panel's explanatory copy: appears quickly, stays
/// readable, and wraps multi-line guidance.
class _PanelTip extends StatelessWidget {
  const _PanelTip({required this.message, required this.child});

  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: message,
    waitDuration: const Duration(milliseconds: 350),
    showDuration: const Duration(seconds: 8),
    margin: const EdgeInsets.symmetric(horizontal: 40),
    padding: const EdgeInsets.all(10),
    child: child,
  );
}
