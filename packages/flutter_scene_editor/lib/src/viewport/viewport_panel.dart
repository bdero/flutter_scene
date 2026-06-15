import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../controller/editor_controller.dart';
import 'orbit_camera.dart';
import 'transform_gizmo.dart';

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

  // The selected node's local transform components at the start of a gizmo
  // drag, decomposed so each mode can rebuild the preview.
  final vm.Vector3 _startT = vm.Vector3.zero();
  final vm.Quaternion _startR = vm.Quaternion.identity();
  final vm.Vector3 _startS = vm.Vector3(1, 1, 1);

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
        final grabbed = _gizmo.grab(
          event.localPosition,
          live.globalTransform.getTranslation(),
          _camera.camera,
          viewSize,
        );
        if (grabbed) {
          _draggingGizmo = true;
          // Decompose the node's local transform so each mode can rebuild it.
          live.localTransform.decompose(_startT, _startR, _startS);
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

    _gizmo.update(
      event.localPosition,
      live.globalTransform.getTranslation(),
      _camera.camera,
      _viewSize,
    );
    _ctrl.previewLocalTransform(primary, _previewMatrix());
    _bumpView();
  }

  void _onPointerUp(PointerUpEvent event) {
    if (!_draggingGizmo) return;
    final primary = _ctrl.selection.primary;
    if (primary != null) {
      switch (_gizmo.mode) {
        case GizmoMode.translate:
          if (_gizmo.translation.length2 > 1e-10) {
            final t = _startT + _gizmo.translation;
            _ctrl.setNodeTransformRouted(
              primary,
              translation: {'x': t.x, 'y': t.y, 'z': t.z},
            );
          }
        case GizmoMode.rotate:
          if (_gizmo.angle.abs() > 1e-5) {
            final r = _rotatedStart();
            _ctrl.setNodeTransformRouted(
              primary,
              rotation: {'x': r.x, 'y': r.y, 'z': r.z, 'w': r.w},
            );
          }
        case GizmoMode.scale:
          final s = _scaledStart();
          if ((s - _startS).length2 > 1e-10) {
            _ctrl.setNodeTransformRouted(
              primary,
              scale: {'x': s.x, 'y': s.y, 'z': s.z},
            );
          }
      }
    }
    _gizmo.end();
    _draggingGizmo = false;
  }

  vm.Quaternion _rotatedStart() =>
      (vm.Quaternion.axisAngle(_gizmo.axisVec, _gizmo.angle) * _startR)
        ..normalize();

  vm.Vector3 _scaledStart() => vm.Vector3(
    _startS.x * _gizmo.scale.x,
    _startS.y * _gizmo.scale.y,
    _startS.z * _gizmo.scale.z,
  );

  // The previewed local transform for the active drag, built from the start
  // components plus the gizmo's accumulated delta for the current mode.
  vm.Matrix4 _previewMatrix() {
    final t = _gizmo.mode == GizmoMode.translate
        ? _startT + _gizmo.translation
        : _startT;
    final r = _gizmo.mode == GizmoMode.rotate ? _rotatedStart() : _startR;
    final s = _gizmo.mode == GizmoMode.scale ? _scaledStart() : _startS;
    return vm.Matrix4.compose(t, r, s);
  }

  void _setMode(GizmoMode mode) {
    if (_gizmo.mode == mode) return;
    _gizmo.mode = mode;
    _bumpView();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // Plain W/E/R switch the gizmo mode (Unity-style), ignored with modifiers
    // so app shortcuts still work.
    final keys = HardwareKeyboard.instance;
    if (keys.isMetaPressed || keys.isControlPressed || keys.isAltPressed) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.keyW:
        _setMode(GizmoMode.translate);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyE:
        _setMode(GizmoMode.rotate);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyR:
        _setMode(GizmoMode.scale);
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
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
                        onKeyEvent: _onKey,
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
                            painter: TransformGizmoPainter(
                              origin: live.globalTransform.getTranslation(),
                              mode: _gizmo.mode,
                              camera: cam,
                              activeAxis: _gizmo.activeAxis,
                            ),
                            size: size,
                          ),
                        ),
                      Positioned(
                        top: 8,
                        left: 8,
                        child: _GizmoModeBar(
                          mode: _gizmo.mode,
                          onChanged: _setMode,
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

/// Translate/rotate/scale mode selector (also bound to W/E/R).
class _GizmoModeBar extends StatelessWidget {
  const _GizmoModeBar({required this.mode, required this.onChanged});
  final GizmoMode mode;
  final void Function(GizmoMode) onChanged;

  @override
  Widget build(BuildContext context) {
    Widget button(GizmoMode m, IconData icon, String tip) {
      final active = mode == m;
      return Tooltip(
        message: tip,
        child: InkWell(
          onTap: () => onChanged(m),
          child: Container(
            width: 28,
            height: 24,
            color: active
                ? Theme.of(context).colorScheme.primary
                : Colors.black.withValues(alpha: 0.55),
            child: Icon(
              icon,
              size: 15,
              color: active ? Colors.black : Colors.white,
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(GizmoMode.translate, Icons.open_with, 'Move (W)'),
          button(GizmoMode.rotate, Icons.threesixty, 'Rotate (E)'),
          button(GizmoMode.scale, Icons.aspect_ratio, 'Scale (R)'),
        ],
      ),
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
