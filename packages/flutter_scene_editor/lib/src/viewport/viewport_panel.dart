// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/specs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../controller/editor_controller.dart';
import 'orbit_camera.dart';
import 'translate_gizmo.dart';

/// Interactive viewport: renders the live scene, handles selection via
/// raycast, and drives a translate gizmo that commits one command per drag.
///
/// Rebuild isolation: per-frame ticks and camera/selection/edit changes flow
/// through a [ValueNotifier] (_viewEpoch), so the viewport subtree repaints
/// only when something actually changes, never every frame via a whole-widget
/// setState. Each enclosing panel is behind a [RepaintBoundary] from the
/// docking shell.
class ViewportPanel extends StatefulWidget {
  const ViewportPanel({super.key, required this.controller});

  final EditorController controller;

  @override
  State<ViewportPanel> createState() => _ViewportPanelState();
}

class _ViewportPanelState extends State<ViewportPanel> {
  final _camera = OrbitCamera(radius: 10.0, elevation: 0.3);
  final _gizmo = GizmoController();
  final _viewEpoch = ValueNotifier<int>(0);
  final _fps = ValueNotifier<double>(0);
  // Holds keyboard focus while the viewport is the active surface, so the
  // app-level shortcuts (undo, delete) fire after the viewport is clicked.
  final _focusNode = FocusNode(debugLabel: 'editorViewport');

  bool _draggingGizmo = false;

  // Accumulated world-space translation during a gizmo drag.
  vm.Vector3 _dragAccum = vm.Vector3.zero();
  // The local transform of the selected node at the start of the drag.
  vm.Matrix4? _dragStartLocalTransform;

  Size _viewSize = Size.zero;

  EditorController get _ctrl => widget.controller;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(ViewportPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      _ctrl.addListener(_onControllerChanged);
      _bumpView();
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onControllerChanged);
    _viewEpoch.dispose();
    _fps.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onControllerChanged() => _bumpView();

  void _bumpView() => _viewEpoch.value++;

  void _onTick(Duration elapsed, double deltaSeconds) {
    if (deltaSeconds > 0) {
      final inst = 1.0 / deltaSeconds;
      final prev = _fps.value;
      _fps.value = prev == 0 ? inst : prev * 0.9 + inst * 0.1;
    }
  }

  // --- pointer handling ----------------------------------------------------

  void _onPointerDown(PointerDownEvent event, Size viewSize) {
    _focusNode.requestFocus();
    _viewSize = viewSize;
    final primary = _ctrl.selection.primary;
    if (primary != null) {
      final live = _ctrl.liveNode(primary);
      if (live != null) {
        final axis = _gizmo.hitTest(
          event.localPosition,
          live.globalTransform.getTranslation(),
          _camera.camera,
          viewSize,
        );
        if (axis != null) {
          _draggingGizmo = true;
          _dragAccum = vm.Vector3.zero();
          _dragStartLocalTransform = live.localTransform.clone();
          return;
        }
      }
    }
    _performRaycast(event.localPosition, viewSize);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_draggingGizmo) return;
    final primary = _ctrl.selection.primary;
    if (primary == null) return;
    final live = _ctrl.liveNode(primary);
    if (live == null) return;

    final delta = _gizmo.dragDelta(
      event.localPosition,
      live.globalTransform.getTranslation(),
      _camera.camera,
      _viewSize,
    );
    if (delta.length2 < 1e-10) return;

    _dragAccum += delta;

    // Preview by adding the world-space delta straight onto the transform's
    // translation column. Adding it here (rather than translateByVector3, which
    // applies in the node's scaled and rotated frame) keeps the preview 1:1
    // with the pointer and matching the world-space value committed on release,
    // so a scaled node no longer drifts.
    final start = _dragStartLocalTransform!;
    final preview = start.clone()
      ..setTranslation(start.getTranslation() + _dragAccum);
    _ctrl.previewLocalTransform(primary, preview);
    _bumpView();
  }

  void _onPointerUp(PointerUpEvent event) {
    if (!_draggingGizmo) return;
    final primary = _ctrl.selection.primary;
    if (primary != null && _dragAccum.length2 > 1e-10) {
      // Commit the whole drag as one undoable edit.
      final start = _dragStartLocalTransform;
      if (start != null) {
        final doc = _ctrl.document;
        final docNode = doc.node(primary);
        TrsTransform? trs;
        if (docNode != null && docNode.transform is TrsTransform) {
          trs = docNode.transform as TrsTransform;
        }
        final oldTranslation = trs?.translation ?? vm.Vector3.zero();
        final newTranslation = oldTranslation + _dragAccum;
        _ctrl.run('setNodeTransform', {
          'nodeId': primary.toToken(),
          'translation': {
            'x': newTranslation.x,
            'y': newTranslation.y,
            'z': newTranslation.z,
          },
        });
      }
    }
    _gizmo.endDrag();
    _draggingGizmo = false;
    _dragAccum = vm.Vector3.zero();
    _dragStartLocalTransform = null;
  }

  void _performRaycast(Offset position, Size viewSize) {
    final ray = _camera.camera.screenPointToRay(position, viewSize);
    final hit = _ctrl.scene.raycast(ray);
    if (hit == null) {
      _ctrl.selection.clear();
    } else {
      // Resolve the hit to the source node the editor can act on (the node
      // itself, or the enclosing prefab instance for prefab-internal geometry).
      final id = _ctrl.sourceIdForLiveNode(hit.node);
      if (id != null) {
        _ctrl.selection.selectOnly(id);
      } else {
        _ctrl.selection.clear();
      }
    }
    _bumpView();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return Stack(
          fit: StackFit.expand,
          children: [
            // Viewport and gizmo overlay. Repaints only when viewEpoch bumps.
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: _viewEpoch,
                builder: (context, _) {
                  final primary = _ctrl.selection.primary;
                  final live = primary != null ? _ctrl.liveNode(primary) : null;
                  final cam = _camera.camera;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Focus(
                        focusNode: _focusNode,
                        child: OrbitCameraController(
                          camera: _camera,
                          isLocked: () => _draggingGizmo,
                          onChanged: _bumpView,
                          child: Listener(
                            behavior: HitTestBehavior.opaque,
                            onPointerDown: (e) => _onPointerDown(e, size),
                            onPointerMove: _onPointerMove,
                            onPointerUp: _onPointerUp,
                            child: SceneView(
                              _ctrl.scene,
                              camera: cam,
                              onTick: _onTick,
                            ),
                          ),
                        ),
                      ),
                      if (live != null)
                        IgnorePointer(
                          child: CustomPaint(
                            painter: TranslateGizmoPainter(
                              nodePosition: live.globalTransform
                                  .getTranslation(),
                              camera: cam,
                              activeAxis: _gizmo.activeAxis,
                            ),
                            size: size,
                          ),
                        ),
                      if (primary != null)
                        Positioned(
                          bottom: 8,
                          left: 8,
                          child: _InfoBadge(
                            text: () {
                              final node = _ctrl.document.node(primary);
                              final name = node?.name ?? '';
                              return 'Selected: ${name.isEmpty ? primary.toToken() : name}';
                            }(),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            // FPS readout, updated independently of the main viewport.
            Positioned(
              top: 8,
              right: 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ValueListenableBuilder<double>(
                    valueListenable: _fps,
                    builder: (context, fps, _) => RepaintBoundary(
                      child: _InfoBadge(text: 'FPS ${fps.toStringAsFixed(0)}'),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const _InfoBadge(
                    text: 'LMB drag orbit, Shift+LMB pan, Scroll zoom',
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _InfoBadge extends StatelessWidget {
  const _InfoBadge({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white, fontSize: 11),
        ),
      ),
    );
  }
}
