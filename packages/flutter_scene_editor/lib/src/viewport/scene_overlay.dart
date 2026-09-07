/// Overlays: the small panels that float over the scene rather than docking
/// beside it.
///
/// A setting that changes what a drag *does* belongs where you can see it
/// without asking. Local versus global is the clearest case: the gizmo's
/// arrows point differently in each, so not knowing which you are in turns an
/// ordinary drag into a confusing one — and it was behind a gear menu, which
/// is a place you go to change a setting, not a place that tells you what the
/// setting is.
///
/// This is the chrome those panels share: a rounded, bordered card that sits
/// over the viewport, dark enough to read against a bright scene and quiet
/// enough to ignore. Not a dockable, draggable overlay system — these
/// are pinned to their corners — but the same idea and the same job.
library;

import 'package:flutter/material.dart';

import '../shell/editor_theme.dart';

/// A floating panel over the scene.
class SceneOverlay extends StatelessWidget {
  const SceneOverlay({
    super.key,
    required this.child,
    this.label,
    this.direction = Axis.horizontal,
  });

  /// What is in it.
  final Widget child;

  /// A caption above the contents, or null for a bare strip of controls.
  ///
  /// Worth having on a panel of dropdowns whose labels are their values, and
  /// noise on a row of icon buttons that explain themselves.
  final String? label;

  /// Which way the contents run, which decides the padding's shape.
  final Axis direction;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        // Not quite opaque: an overlay that blacks out the scene behind it is
        // a hole in the thing you are looking at.
        color: editorPanelColor.withValues(alpha: 0.93),
        border: Border.all(color: editorLineColor),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: direction == Axis.horizontal
          ? const EdgeInsets.symmetric(horizontal: 6, vertical: 4)
          : const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: label == null
          ? child
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: 3),
                  child: Text(label!.toUpperCase(), style: editorMicroText),
                ),
                child,
              ],
            ),
    );
  }
}

/// A two-way choice drawn as a pair of segments, the way a setting that is
/// always one of two things reads best.
///
/// A dropdown for two options hides one of them behind a click; segments show
/// both and which one you are in, which is the entire reason this is on the
/// scene rather than in a menu.
class OverlaySegments<T> extends StatelessWidget {
  const OverlaySegments({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  /// The choices, in the order they are drawn, each with what it is called.
  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final entry in options.entries)
        Padding(
          padding: const EdgeInsets.only(right: 2),
          child: InkWell(
            onTap: () => onChanged(entry.key),
            borderRadius: BorderRadius.circular(3),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: entry.key == value
                    ? editorAccentColor.withValues(alpha: 0.22)
                    : Colors.transparent,
                border: Border.all(
                  color: entry.key == value
                      ? editorAccentColor
                      : Colors.transparent,
                ),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                entry.value,
                style: TextStyle(
                  fontSize: 11,
                  color: entry.key == value
                      ? editorTextColor
                      : editorMutedTextColor,
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
