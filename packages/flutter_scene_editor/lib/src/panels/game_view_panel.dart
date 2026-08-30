/// The Game view: the scene through the camera that will shoot it.
///
/// The Scene view is where you stand; this is where the player stands. They
/// are different questions, and a composition that reads from the editor
/// camera routinely does not read from the one the game uses — the horizon is
/// somewhere else, the framing is loose, the thing you centred is behind a
/// wall.
///
/// This renders through the scene's own camera at a chosen aspect, so what it
/// shows is a frame of the game rather than a frame of the editor. It is not
/// the running project: Play still launches that as its own process, and this
/// asks nothing of it. What it costs is one more render of a scene that is
/// already being rendered, which is why it is a tab rather than always on.
library;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';

import '../controller/editor_controller.dart';
import '../shell/editor_theme.dart';

/// A frame shape the view can be held to.
///
/// Free follows the panel, which is the only honest default: until a game
/// declares what it targets, the editor guessing is worse than not saying.
class GameAspect {
  const GameAspect(this.label, this.ratio);

  final String label;

  /// Width over height, or null to follow the panel.
  final double? ratio;
}

/// The shapes offered, widest last so the list reads as a progression.
const List<GameAspect> gameAspects = [
  GameAspect('Free Aspect', null),
  GameAspect('4:3', 4 / 3),
  GameAspect('16:10', 16 / 10),
  GameAspect('16:9', 16 / 9),
  GameAspect('21:9', 21 / 9),
];

/// The rectangle a frame of [ratio] occupies inside [available], centred.
///
/// Letterboxes rather than crops or stretches: a preview that stretched would
/// be a preview lying about the framing, which is the one thing it is for.
Rect gameFrameRect(Size available, double? ratio) {
  if (ratio == null || ratio <= 0) {
    return Offset.zero & available;
  }
  final width = available.width;
  final height = available.height;
  if (width <= 0 || height <= 0) return Rect.zero;
  final fitted = width / height > ratio
      ? Size(height * ratio, height)
      : Size(width, width / ratio);
  return Rect.fromLTWH(
    (width - fitted.width) / 2,
    (height - fitted.height) / 2,
    fitted.width,
    fitted.height,
  );
}

/// The Game view panel.
class GameViewPanel extends StatefulWidget {
  const GameViewPanel({super.key, required this.controller});

  final EditorController controller;

  @override
  State<GameViewPanel> createState() => _GameViewPanelState();
}

class _GameViewPanelState extends State<GameViewPanel> {
  EditorController get _ctrl => widget.controller;

  GameAspect _aspect = gameAspects.first;
  bool _stats = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(GameViewPanel old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// The camera the game is shot through: the first one in the scene.
  ///
  /// Document order rather than a tag, because there are no tags. A scene with
  /// two cameras shoots through the first, which is at least a rule somebody
  /// can predict and work with.
  CameraComponent? get _sceneCamera {
    final root = _ctrl.realizedRoot;
    if (root == null) return null;
    CameraComponent? found;
    void visit(Node node) {
      if (found != null) return;
      final camera = node.getComponent<CameraComponent>();
      if (camera != null) {
        found = camera;
        return;
      }
      for (final child in node.children) {
        visit(child);
      }
    }

    visit(root);
    return found;
  }

  @override
  Widget build(BuildContext context) {
    final camera = _sceneCamera;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EditorToolbar(
          children: [
            const Icon(Icons.videogame_asset_outlined, size: 14),
            const SizedBox(width: 6),
            Text('Game', style: editorBodyText),
            const SizedBox(width: 12),
            SizedBox(
              height: 24,
              child: DropdownButtonHideUnderline(
                child: DropdownButton<GameAspect>(
                  value: _aspect,
                  isDense: true,
                  style: editorBodyText.copyWith(color: editorTextColor),
                  dropdownColor: editorRaisedColor,
                  items: [
                    for (final aspect in gameAspects)
                      DropdownMenuItem(
                        value: aspect,
                        child: Text(aspect.label),
                      ),
                  ],
                  onChanged: (picked) =>
                      picked == null ? null : setState(() => _aspect = picked),
                ),
              ),
            ),
            const Spacer(),
            _Toggle(
              label: 'Stats',
              value: _stats,
              onChanged: (value) => setState(() => _stats = value),
            ),
          ],
        ),
        Expanded(
          child: Container(
            color: Colors.black,
            child: camera == null
                ? const _NoCamera()
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final frame = gameFrameRect(
                        constraints.biggest,
                        _aspect.ratio,
                      );
                      return Stack(
                        children: [
                          Positioned.fromRect(
                            rect: frame,
                            child: SceneView(
                              _ctrl.scene,
                              viewsBuilder: (_) => [
                                RenderView(camera: camera.toCamera()),
                              ],
                            ),
                          ),
                          if (_stats)
                            Positioned(
                              right: 8,
                              top: 8,
                              child: _Stats(frame: frame.size, aspect: _aspect),
                            ),
                        ],
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

/// What the panel says with no camera in the scene.
///
/// Every template ships one, so this is mostly the state a scene reaches by
/// having its camera deleted -- worth saying plainly rather than showing an
/// empty black rectangle that looks like a broken renderer.
class _NoCamera extends StatelessWidget {
  const _NoCamera();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.videocam_off_outlined,
            size: 22,
            color: editorMutedTextColor,
          ),
          const SizedBox(height: 8),
          Text(
            'This scene has no camera, so there is no shot to show.',
            textAlign: TextAlign.center,
            style: editorDetailText,
          ),
          const SizedBox(height: 4),
          Text('Add one from Add › Camera.', style: editorMicroText),
        ],
      ),
    ),
  );
}

class _Stats extends StatelessWidget {
  const _Stats({required this.frame, required this.aspect});

  final Size frame;
  final GameAspect aspect;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: BoxDecoration(
      color: editorPanelColor.withValues(alpha: 0.9),
      border: Border.all(color: editorLineColor),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Frame', style: editorMicroText),
        Text(
          '${frame.width.round()} x ${frame.height.round()}',
          style: editorBodyText,
        ),
        const SizedBox(height: 4),
        Text('Aspect', style: editorMicroText),
        Text(
          aspect.ratio == null
              ? 'free (${(frame.width / frame.height).toStringAsFixed(2)})'
              : aspect.label,
          style: editorBodyText,
        ),
      ],
    ),
  );
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => onChanged(!value),
    borderRadius: BorderRadius.circular(3),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: value ? editorRaisedColor : Colors.transparent,
        border: Border.all(color: value ? editorAccentColor : editorLineColor),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: value ? editorTextColor : editorMutedTextColor,
        ),
      ),
    ),
  );
}
