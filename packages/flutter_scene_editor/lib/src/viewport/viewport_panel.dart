import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../controller/editor_controller.dart';
import 'orbit_camera.dart';
import 'orientation_gizmo.dart';
import 'transform_gizmo.dart';
import 'viewport_camera_handle.dart';

/// Interactive viewport: renders the live scene, handles selection via
/// raycast, and drives a translate gizmo that commits one command per drag.
///
/// Rebuild isolation: per-frame ticks and camera/selection/edit changes flow
/// through a [ValueNotifier] (_viewEpoch), so the viewport subtree repaints
/// only when something actually changes, never every frame via a whole-widget
/// setState. Each enclosing panel is behind a [RepaintBoundary] from the
/// docking shell.
class ViewportPanel extends StatefulWidget {
  const ViewportPanel({
    super.key,
    required this.controller,
    this.repaintBoundaryKey,
    this.cameraHandle,
  });

  final EditorController controller;

  /// Optional key on the viewport's [RepaintBoundary], so a host can capture
  /// the rendered viewport as an image (the MCP screenshot perception tool).
  final GlobalKey? repaintBoundaryKey;

  /// Optional remote control this viewport attaches its camera to (the MCP
  /// camera tools).
  final ViewportCameraHandle? cameraHandle;

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
  bool _showFps = false;

  // The pointer's last position over this viewport, kept for starting a
  // modal transform at the right anchor.
  Offset _mousePos = Offset.zero;

  // The active keyboard-driven transform (G/R/S), if any.
  _ModalTransform? _modal;

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
    // Repaint overlays while a drag in any viewport previews a transform.
    _ctrl.previewEpoch.addListener(_onControllerChanged);
    widget.cameraHandle?.attach(_camera, _bumpView);
  }

  @override
  void didUpdateWidget(ViewportPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      oldWidget.controller.previewEpoch.removeListener(_onControllerChanged);
      _ctrl.addListener(_onControllerChanged);
      _ctrl.previewEpoch.addListener(_onControllerChanged);
      _bumpView();
    }
    if (oldWidget.cameraHandle != widget.cameraHandle) {
      oldWidget.cameraHandle?.detach(_camera);
      widget.cameraHandle?.attach(_camera, _bumpView);
    }
  }

  @override
  void dispose() {
    widget.cameraHandle?.detach(_camera);
    _ctrl.removeListener(_onControllerChanged);
    _ctrl.previewEpoch.removeListener(_onControllerChanged);
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
    // A click ends the modal transform, left confirms, anything else
    // (right/middle) cancels. Swallow it either way.
    if (_modal != null) {
      if (event.buttons & kPrimaryMouseButton != 0) {
        _commitModal();
      } else {
        _cancelModal();
      }
      return;
    }
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

  // --- modal transforms (G/R/S) --------------------------------------------

  void _startModal(_ModalOp op) {
    final primary = _ctrl.selection.primary;
    if (primary == null) return;
    final live = _ctrl.liveNode(primary);
    if (live == null) return;
    live.localTransform.decompose(_startT, _startR, _startS);
    final origin = live.globalTransform.getTranslation();
    _modal = _ModalTransform(
      op: op,
      origin: origin,
      startPointer: _mousePos,
      pivotScreen:
          _camera.camera.worldToScreen(origin, _viewSize) ??
          _viewSize.center(Offset.zero),
    )..pointer = _mousePos;
    _bumpView();
  }

  void _updateModal(Offset pointer) {
    final modal = _modal;
    final primary = _ctrl.selection.primary;
    if (modal == null || primary == null) return;
    modal.pointer = pointer;
    _ctrl.previewLocalTransform(primary, _modalMatrix(modal));
    _bumpView();
  }

  void _commitModal() {
    final modal = _modal;
    final primary = _ctrl.selection.primary;
    if (modal == null || primary == null) {
      _modal = null;
      return;
    }
    switch (modal.op) {
      case _ModalOp.translate:
        final t = _startT + _modalTranslation(modal);
        _ctrl.setNodeTransformRouted(
          primary,
          translation: {'x': t.x, 'y': t.y, 'z': t.z},
        );
      case _ModalOp.rotate:
        final r = _modalRotation(modal);
        _ctrl.setNodeTransformRouted(
          primary,
          rotation: {'x': r.x, 'y': r.y, 'z': r.z, 'w': r.w},
        );
      case _ModalOp.scale:
        final s = _modalScaleVec(modal);
        _ctrl.setNodeTransformRouted(
          primary,
          scale: {'x': s.x, 'y': s.y, 'z': s.z},
        );
    }
    _modal = null;
    _bumpView();
  }

  void _cancelModal() {
    final modal = _modal;
    final primary = _ctrl.selection.primary;
    if (modal != null && primary != null) {
      _ctrl.previewLocalTransform(
        primary,
        vm.Matrix4.compose(_startT, _startR, _startS),
      );
    }
    _modal = null;
    _bumpView();
  }

  vm.Matrix4 _modalMatrix(_ModalTransform modal) {
    final t = modal.op == _ModalOp.translate
        ? _startT + _modalTranslation(modal)
        : _startT;
    final r = modal.op == _ModalOp.rotate ? _modalRotation(modal) : _startR;
    final s = modal.op == _ModalOp.scale ? _modalScaleVec(modal) : _startS;
    return vm.Matrix4.compose(t, r, s);
  }

  /// Pixels-to-world factor at the modal object's depth (or the orthographic
  /// view scale), for camera-plane translation.
  double _worldPerPixel(_ModalTransform modal) {
    if (_viewSize.height <= 0) return 0;
    // Matches the orbit camera's 45 degree vertical field of view and its
    // orthographic height coupling.
    final scale = 2 * tan(pi / 8) / _viewSize.height;
    if (_camera.orthographic) return _camera.radius * scale;
    final depth = (modal.origin - _camera.position).dot(_camera.forwardVector);
    return max(depth, 0.01) * scale;
  }

  vm.Vector3 _modalTranslation(_ModalTransform modal) {
    final deltaPx = modal.pointer - modal.startPointer;
    final axis = modal.axis;
    if (axis != null) {
      // Project mouse movement onto the axis's screen direction, scaled by
      // how many pixels one world unit of that axis spans.
      final axisDir = vm.Vector3.zero()..[axis] = 1.0;
      final s0 = _camera.camera.worldToScreen(modal.origin, _viewSize);
      final s1 = _camera.camera.worldToScreen(
        modal.origin + axisDir,
        _viewSize,
      );
      if (s0 == null || s1 == null) return vm.Vector3.zero();
      final axisPx = s1 - s0;
      final len2 = axisPx.dx * axisPx.dx + axisPx.dy * axisPx.dy;
      // An axis pointing straight into the screen has no usable projection.
      if (len2 < 1e-3) return vm.Vector3.zero();
      final t = (deltaPx.dx * axisPx.dx + deltaPx.dy * axisPx.dy) / len2;
      return axisDir * t;
    }
    final wpp = _worldPerPixel(modal);
    return _camera.rightVector * (deltaPx.dx * wpp) +
        _camera.upVector * (-deltaPx.dy * wpp);
  }

  vm.Quaternion _modalRotation(_ModalTransform modal) {
    double angleOf(Offset p) =>
        atan2(p.dy - modal.pivotScreen.dy, p.dx - modal.pivotScreen.dx);
    // Positive when the mouse circles clockwise on screen (y grows down).
    final screenAngle = angleOf(modal.pointer) - angleOf(modal.startPointer);
    final axis = modal.axis == null
        ? _camera.forwardVector
        : (vm.Vector3.zero()..[modal.axis!] = 1.0);
    // Make the object follow the mouse regardless of which way the axis
    // faces the camera. The scene-root Z flip mirrors handedness, so the
    // screen-facing branch takes the negated angle.
    final angle = axis.dot(_camera.forwardVector) >= 0
        ? -screenAngle
        : screenAngle;
    return (vm.Quaternion.axisAngle(axis, angle) * _startR)..normalize();
  }

  vm.Vector3 _modalScaleVec(_ModalTransform modal) {
    final base = (modal.startPointer - modal.pivotScreen).distance.clamp(
      5.0,
      double.infinity,
    );
    final factor = (modal.pointer - modal.pivotScreen).distance / base;
    final axis = modal.axis;
    if (axis == null) return _startS * factor;
    return vm.Vector3(
      _startS.x * (axis == 0 ? factor : 1),
      _startS.y * (axis == 1 ? factor : 1),
      _startS.z * (axis == 2 ? factor : 1),
    );
  }

  /// The constrained axis's on-screen direction through the modal pivot, for
  /// the guide line. Null when unconstrained or degenerate.
  Offset? _modalAxisScreenDir(_ModalTransform modal) {
    final axis = modal.axis;
    if (axis == null) return null;
    final axisDir = vm.Vector3.zero()..[axis] = 1.0;
    final s0 = _camera.camera.worldToScreen(modal.origin, _viewSize);
    final s1 = _camera.camera.worldToScreen(modal.origin + axisDir, _viewSize);
    if (s0 == null || s1 == null) return null;
    final d = s1 - s0;
    return d.distance < 1e-2 ? null : d / d.distance;
  }

  String _modalLabel(_ModalTransform modal) {
    final op = switch (modal.op) {
      _ModalOp.translate => 'Move',
      _ModalOp.rotate => 'Rotate',
      _ModalOp.scale => 'Scale',
    };
    final axis = modal.axis;
    return axis == null ? op : '$op ${'XYZ'[axis]}';
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // Ignored with modifiers so app shortcuts still work.
    final keys = HardwareKeyboard.instance;
    if (keys.isMetaPressed || keys.isControlPressed || keys.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final modal = _modal;
    if (modal != null) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.escape:
          _cancelModal();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyX:
        case LogicalKeyboardKey.keyY:
        case LogicalKeyboardKey.keyZ:
          final axis = switch (event.logicalKey) {
            LogicalKeyboardKey.keyX => 0,
            LogicalKeyboardKey.keyY => 1,
            _ => 2,
          };
          // Pressing the active axis again clears the constraint.
          modal.axis = modal.axis == axis ? null : axis;
          _updateModal(modal.pointer);
          return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.keyG:
        _startModal(_ModalOp.translate);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyR:
        _startModal(_ModalOp.rotate);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyS:
        _startModal(_ModalOp.scale);
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
        _viewSize = size;
        return MouseRegion(
          onEnter: (event) {
            _mousePos = event.localPosition;
            // Focus follows the mouse into the viewport so G/R/S work on
            // hover, but never steals focus from a text field mid-edit.
            final focused = FocusManager.instance.primaryFocus;
            if (focused?.context?.widget is! EditableText) {
              _focusNode.requestFocus();
            }
          },
          onHover: (event) {
            _mousePos = event.localPosition;
            if (_modal != null) _updateModal(event.localPosition);
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Viewport and gizmo overlay. Repaints only when viewEpoch bumps.
              RepaintBoundary(
                key: widget.repaintBoundaryKey,
                child: AnimatedBuilder(
                  animation: _viewEpoch,
                  builder: (context, _) {
                    final primary = _ctrl.selection.primary;
                    final live = primary != null
                        ? _ctrl.liveNode(primary)
                        : null;
                    final cam = _camera.camera;
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        Focus(
                          focusNode: _focusNode,
                          onKeyEvent: _onKey,
                          child: OrbitCameraController(
                            camera: _camera,
                            isLocked: () => _draggingGizmo || _modal != null,
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
                        if (_ctrl
                            .scene
                            .renderScene
                            .environmentVolumeComponents
                            .isNotEmpty)
                          IgnorePointer(
                            child: CustomPaint(
                              painter: EnvironmentVolumeComponentPainter(
                                volumes: _ctrl
                                    .scene
                                    .renderScene
                                    .environmentVolumeComponents,
                                camera: cam,
                              ),
                              size: size,
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
                        // Constrained-axis guide line for the modal transform.
                        if (_modal case final modal?)
                          if (_modalAxisScreenDir(modal) case final dir?)
                            IgnorePointer(
                              child: CustomPaint(
                                painter: _AxisGuidePainter(
                                  pivot: modal.pivotScreen,
                                  direction: dir,
                                  color: const [
                                    Color(0xFFE0483E),
                                    Color(0xFF6BB536),
                                    Color(0xFF3E7DE0),
                                  ][modal.axis!],
                                ),
                                size: size,
                              ),
                            ),
                        if (_modal case final modal?)
                          Positioned(
                            bottom: 8,
                            left: 8,
                            child: _InfoBadge(text: _modalLabel(modal)),
                          )
                        else if (primary != null)
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
              // Navigation gizmo, projection toggle, and FPS readout. The
              // gizmo tracks the camera through the same epoch notifier the
              // viewport repaints on.
              Positioned(
                top: 8,
                right: 8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _ViewportSettingsButton(
                      showFps: _showFps,
                      onToggleFps: (value) => setState(() => _showFps = value),
                    ),
                    const SizedBox(height: 4),
                    AnimatedBuilder(
                      animation: _viewEpoch,
                      builder: (context, _) => Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          OrientationGizmo(
                            camera: _camera,
                            onChanged: _bumpView,
                          ),
                          const SizedBox(height: 4),
                          ProjectionToggle(
                            orthographic: _camera.orthographic,
                            onChanged: (value) {
                              _camera.orthographic = value;
                              _bumpView();
                            },
                          ),
                        ],
                      ),
                    ),
                    if (_showFps) ...[
                      const SizedBox(height: 8),
                      ValueListenableBuilder<double>(
                        valueListenable: _fps,
                        builder: (context, fps, _) => RepaintBoundary(
                          child: _InfoBadge(
                            text: 'FPS ${fps.toStringAsFixed(0)}',
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
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
          button(GizmoMode.translate, Icons.open_with, 'Move gizmo'),
          button(GizmoMode.rotate, Icons.threesixty, 'Rotate gizmo'),
          button(GizmoMode.scale, Icons.aspect_ratio, 'Scale gizmo'),
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

/// The kind of keyboard-driven transform in progress.
enum _ModalOp { translate, rotate, scale }

/// State of an in-progress G/R/S transform. The mouse drives the delta from
/// [startPointer]; [axis] constrains it to a world axis when set.
class _ModalTransform {
  _ModalTransform({
    required this.op,
    required this.origin,
    required this.startPointer,
    required this.pivotScreen,
  });

  final _ModalOp op;

  /// The selected node's world-space origin when the transform started.
  final vm.Vector3 origin;

  final Offset startPointer;

  /// The origin's screen position, the pivot for rotate/scale mouse math.
  final Offset pivotScreen;

  /// Constrained world axis (0 = X, 1 = Y, 2 = Z), null when free.
  int? axis;

  Offset pointer = Offset.zero;
}

/// Draws the constrained-axis guide line across the viewport.
class _AxisGuidePainter extends CustomPainter {
  _AxisGuidePainter({
    required this.pivot,
    required this.direction,
    required this.color,
  });

  final Offset pivot;
  final Offset direction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Long enough to cross any viewport from the pivot in both directions.
    final reach = size.longestSide * 2;
    canvas.drawLine(
      pivot - direction * reach,
      pivot + direction * reach,
      Paint()
        ..color = color
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_AxisGuidePainter oldDelegate) =>
      pivot != oldDelegate.pivot ||
      direction != oldDelegate.direction ||
      color != oldDelegate.color;
}

/// Per-viewport settings, popped from the gear button in the corner.
class _ViewportSettingsButton extends StatelessWidget {
  const _ViewportSettingsButton({
    required this.showFps,
    required this.onToggleFps,
  });

  final bool showFps;
  final ValueChanged<bool> onToggleFps;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<VoidCallback>(
      tooltip: 'Viewport settings',
      padding: EdgeInsets.zero,
      onSelected: (action) => action(),
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
          value: () => onToggleFps(!showFps),
          checked: showFps,
          height: 32,
          child: const Text('Show FPS', style: TextStyle(fontSize: 12)),
        ),
      ],
      child: Container(
        width: 28,
        height: 24,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Icon(Icons.settings, size: 15, color: Colors.white),
      ),
    );
  }
}
