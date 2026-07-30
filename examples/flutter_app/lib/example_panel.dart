import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A collapsible dark control card shared by the example overlays: a fixed
/// header row (icon, title, expand chevron) above a body that scrolls within
/// whatever height the overlay slot provides.
///
/// Owns its open state unless both [open] and [onToggle] are passed.
class ExamplePanelCard extends StatefulWidget {
  const ExamplePanelCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.trailing,
    this.maxBodyHeight = 360,
    this.bodyPadding = const EdgeInsets.fromLTRB(12, 8, 12, 12),
    this.width,
    this.open,
    this.onToggle,
  });

  final IconData icon;
  final String title;

  /// The collapsible content, wrapped in a scroll view bounded by the slot
  /// height and [maxBodyHeight].
  final Widget body;

  /// Extra header content between the title and the chevron, still usable
  /// while the body is collapsed (e.g. a mode dropdown).
  final Widget? trailing;

  final double maxBodyHeight;
  final EdgeInsetsGeometry bodyPadding;
  final double? width;

  /// Pass with [onToggle] to control the open state externally.
  final bool? open;
  final VoidCallback? onToggle;

  @override
  State<ExamplePanelCard> createState() => _ExamplePanelCardState();
}

class _ExamplePanelCardState extends State<ExamplePanelCard> {
  bool _open = true;

  // Header row, divider, and card margins, subtracted from the slot height
  // to bound the scrolling body.
  static const double _headerAllowance = 57;

  bool get _isOpen => widget.open ?? _open;

  void _toggle() {
    final onToggle = widget.onToggle;
    if (onToggle != null) return onToggle();
    setState(() => _open = !_open);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bodyMaxHeight = constraints.hasBoundedHeight
              ? math.min(
                  widget.maxBodyHeight,
                  math.max(0.0, constraints.maxHeight - _headerAllowance),
                )
              : widget.maxBodyHeight;

          return Card(
            color: Colors.black54,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: _toggle,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                    child: Row(
                      children: [
                        Icon(widget.icon, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (widget.trailing != null) ...[
                          const SizedBox(width: 8),
                          Expanded(child: widget.trailing!),
                        ] else
                          const Spacer(),
                        Icon(
                          _isOpen ? Icons.expand_less : Icons.expand_more,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_isOpen) ...[
                  const Divider(height: 1, color: Colors.white24),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: bodyMaxHeight),
                    child: SingleChildScrollView(
                      padding: widget.bodyPadding,
                      child: widget.body,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A centered dark card for loading and failure states, so those states keep
/// a visible surface over whatever the scene shows.
class ExampleStatusCard extends StatelessWidget {
  const ExampleStatusCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: Card(
      color: Colors.black87,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(padding: const EdgeInsets.all(20), child: child),
      ),
    ),
  );
}

/// A load-failure [ExampleStatusCard] with a title and detail text.
class ExampleLoadFailureCard extends StatelessWidget {
  const ExampleLoadFailureCard({
    super.key,
    required this.title,
    required this.detail,
  });

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => ExampleStatusCard(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Colors.white)),
        const SizedBox(height: 8),
        Text(detail, style: const TextStyle(color: Colors.white70)),
      ],
    ),
  );
}
