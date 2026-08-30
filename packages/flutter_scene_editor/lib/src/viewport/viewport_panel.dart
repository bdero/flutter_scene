import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// The editor's own OrbitCameraController (a viewport widget) predates the
// engine's; hide the engine one here to keep using the local widget.
import 'package:flutter_scene/scene.dart' hide OrbitCameraController;
import 'package:native_mouse_cursor/native_mouse_cursor.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../controller/editor_controller.dart';
import '../render_graph/debug_shaders.dart' show loadEditorDebugShaders;
import '../shell/editor_theme.dart';
import 'component_gizmos.dart';
import 'debug_visualize.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/realize/resource_origin.dart'
    show resourceOrigin;
import 'package:scene/scene.dart' show LocalId;
import 'free_look_camera.dart';
import 'orbit_camera.dart';
import 'orientation_gizmo.dart';
import 'scene_overlay.dart';
import 'scatter_tool.dart';
import 'terrain_tool.dart';
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
    this.gizmoPreferences,
  });

  final EditorController controller;

  /// Optional key on the viewport's [RepaintBoundary], so a host can capture
  /// the rendered viewport as an image (the MCP screenshot perception tool).
  final GlobalKey? repaintBoundaryKey;

  /// Optional remote control this viewport attaches its camera to (the MCP
  /// camera tools).
  final ViewportCameraHandle? cameraHandle;

  /// Shared component-gizmo visibility preferences; null uses a private
  /// per-viewport default (everything visible).
  final GizmoPreferences? gizmoPreferences;

  @override
  State<ViewportPanel> createState() => _ViewportPanelState();
}

class _ViewportPanelState extends State<ViewportPanel> {
  static const double _primaryDragThreshold = 4;

  final _camera = OrbitCamera(radius: 10.0, elevation: 0.3);
  final _freeLook = FreeLookCamera();
  final _freeLookPointer = InfiniteDragController(
    axis: InfiniteDragAxis.both,
    edgeMargin: 24,
  );
  final _gizmo = GizmoController();
  final _componentGizmoHits = ComponentGizmoHitCache();
  final _componentGizmoCache = ComponentGizmoRenderCache();
  final _fallbackGizmoPrefs = GizmoPreferences();
  final _viewEpoch = ValueNotifier<int>(0);
  final _fps = ValueNotifier<double>(0);
  // Holds keyboard focus while the viewport is the active surface, so the
  // app-level shortcuts (undo, delete) fire after the viewport is clicked.
  final _focusNode = FocusNode(debugLabel: 'editorViewport');

  bool _draggingGizmo = false;
  bool _freeLookActive = false;
  bool _showFps = false;
  TransformSpace _transformSpace = TransformSpace.global;
  _PendingSelection? _pendingSelection;

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
  final vm.Matrix4 _startLocal = vm.Matrix4.identity();
  final vm.Matrix4 _startGlobal = vm.Matrix4.identity();
  final vm.Matrix4 _parentGlobalInverse = vm.Matrix4.identity();
  List<vm.Vector3> _activeTransformAxes = transformSpaceAxes(
    TransformSpace.global,
    vm.Matrix4.identity(),
  );

  Size _viewSize = Size.zero;

  EditorController get _ctrl => widget.controller;

  GizmoPreferences get _gizmoPrefs =>
      widget.gizmoPreferences ?? _fallbackGizmoPrefs;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onControllerChanged);
    // Repaint overlays while a drag in any viewport previews a transform.
    _ctrl.previewEpoch.addListener(_onControllerChanged);
    _gizmoPrefs.addListener(_onControllerChanged);
    // The armed tool is chosen in the inspector, so a change to it has to
    // reach the viewport that applies it -- and gates the mouse on it.
    _ctrl.terrainTool.addListener(_onControllerChanged);
    widget.cameraHandle?.attach(_camera, _bumpView);
  }

  @override
  void didUpdateWidget(ViewportPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      oldWidget.controller.previewEpoch.removeListener(_onControllerChanged);
      oldWidget.controller.terrainTool.removeListener(_onControllerChanged);
      _ctrl.addListener(_onControllerChanged);
      _ctrl.previewEpoch.addListener(_onControllerChanged);
      _ctrl.terrainTool.addListener(_onControllerChanged);
      _bumpView();
    }
    if (oldWidget.gizmoPreferences != widget.gizmoPreferences) {
      (oldWidget.gizmoPreferences ?? _fallbackGizmoPrefs).removeListener(
        _onControllerChanged,
      );
      _gizmoPrefs.addListener(_onControllerChanged);
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
    _ctrl.terrainTool.removeListener(_onControllerChanged);
    _gizmoPrefs.removeListener(_onControllerChanged);
    _viewEpoch.dispose();
    _fps.dispose();
    _focusNode.dispose();
    _freeLookPointer.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    // Document commits and previews can change gizmo-bound component
    // properties; camera movement alone does not reach this handler, so the
    // gizmo snapshot cache survives orbit drags.
    _componentGizmoCache.invalidate();
    _groundFieldCached = false;
    _bumpView();
  }

  void _bumpView() => _viewEpoch.value++;

  void _onTick(Duration elapsed, double deltaSeconds) {
    if (deltaSeconds > 0) {
      final inst = 1.0 / deltaSeconds;
      final prev = _fps.value;
      _fps.value = prev == 0 ? inst : prev * 0.9 + inst * 0.1;
    }
    if (_freeLookActive && _freeLook.move(deltaSeconds)) {
      _syncOrbitToFreeLook();
      _bumpView();
    }
  }

  // --- pointer handling ----------------------------------------------------

  /// The terrain tools, owned by the controller so the inspector's tool
  /// buttons and this viewport are looking at the same armed tool.
  TerrainToolController get _terrainTool => _ctrl.terrainTool;
  final ScatterToolController _scatterTool = ScatterToolController();
  ScatterStroke? _scatterStroke;

  TerrainStroke? _stroke;
  TerrainPaintStroke? _paintStroke;

  /// The terrain a paint stroke is running on, for the ground query the dab
  /// needs. The stroke itself holds only the control map.
  ({TerrainGeometry geometry, LocalId resourceId})? _paintTarget;

  /// Whether the stroke in progress is the one that minted the control map,
  /// and so the one that has to give the terrain a material to show it.
  bool _paintCreatedMap = false;

  /// Whether this stroke has already pressed its stamp in.
  bool _stamped = false;
  final Stopwatch _strokeClock = Stopwatch();

  /// Where the brush would land, for the cursor ring. Null when the pointer
  /// is not over terrain.
  vm.Vector3? _brushPoint;

  /// The sculpting target for the current selection, or null when the
  /// selected node is not terrain realized from a document.
  ({TerrainGeometry geometry, LocalId resourceId})? _terrainTarget() {
    final primary = _ctrl.selection.primary;
    if (primary == null) return null;
    return terrainTargetOf(
      _ctrl.liveNode(primary),
      (geometry) => resourceOrigin(geometry)?.resourceId,
    );
  }

  /// The scatter layer on the selection, or null when there is none.
  ScatterLayer? _scatterTarget() {
    final primary = _ctrl.selection.primary;
    if (primary == null) return null;
    return scatterLayerOf(_ctrl.liveNode(primary));
  }

  // Finding the ground walks the whole document, and the answer is asked for
  // once per build while a brush is armed. It only changes when the document
  // does, so it is found once and kept until then. Sculpting mutates the
  // field in place rather than replacing it, so a stroke does not invalidate
  // this.
  HeightField? _groundFieldValue;
  bool _groundFieldCached = false;

  /// The height field anything painted should sit on: the first terrain in
  /// the scene. Painting onto a scene with no terrain drops instances on the
  /// plane, which is the sensible fallback rather than a refusal.
  HeightField? _groundField() {
    if (_groundFieldCached) return _groundFieldValue;
    _groundFieldCached = true;
    _groundFieldValue = _findGroundField();
    return _groundFieldValue;
  }

  HeightField? _findGroundField() {
    for (final id in _ctrl.document.nodes.keys) {
      final node = _ctrl.liveNode(id);
      final target = terrainTargetOf(node, (geometry) => null);
      if (target != null) return target.geometry.field;
      final primitives = node?.mesh?.primitives;
      if (primitives == null) continue;
      for (final primitive in primitives) {
        final geometry = primitive.geometry;
        if (geometry is TerrainGeometry) return geometry.field;
      }
    }
    return null;
  }

  /// Starts a painting stroke when the tool is armed over a scatter layer.
  bool _beginScatter(Offset position, Size viewSize) {
    final layer = _scatterTarget();
    final primary = _ctrl.selection.primary;
    if (layer == null || primary == null) return false;
    _scatterStroke = ScatterStroke(layer: layer, nodeId: primary);
    _strokeClock
      ..reset()
      ..start();
    _scatterAt(position, viewSize, 1 / 60);
    return true;
  }

  void _scatterAt(Offset position, Size viewSize, double deltaSeconds) {
    final stroke = _scatterStroke;
    if (stroke == null) return;
    final field = _groundField();
    final point = field == null
        ? _pointOnGroundPlane(position, viewSize)
        : _groundUnder(position, viewSize, field);
    if (point == null) return;
    _brushPoint = point;
    stroke.dab(
      _scatterTool.brush,
      _scatterTool.action,
      point,
      deltaSeconds,
      heightAt: field?.heightAtWorld,
    );
    setState(() {});
  }

  /// Where the pointer crosses y = 0, for a scene with no terrain to land on.
  vm.Vector3? _pointOnGroundPlane(Offset position, Size viewSize) {
    final ray = _camera.camera.screenPointToRay(position, viewSize);
    final direction = ray.direction.normalized();
    if (direction.y.abs() < 1e-6) return null;
    final t = -ray.origin.y / direction.y;
    if (t < 0) return null;
    return ray.origin + direction * t;
  }

  /// Ends the painting stroke, writing the placements as one undoable step.
  void _endScatter() {
    final stroke = _scatterStroke;
    _scatterStroke = null;
    _strokeClock.stop();
    if (stroke == null || !stroke.changed) return;
    unawaited(
      _ctrl.setComponentPropertyRouted(
        _ctrl.selection.primary!,
        'scatterLayer',
        'placements',
        stroke.encodedPlacements(),
      ),
    );
  }

  /// Where the pointer meets the ground, or null when it misses.
  vm.Vector3? _groundUnder(Offset position, Size viewSize, HeightField field) {
    final ray = _camera.camera.screenPointToRay(position, viewSize);
    return field.raycast(ray.origin, ray.direction);
  }

  /// The plane under the selection that could become terrain, if any.
  LocalId? _sculptablePlane() {
    final primary = _ctrl.selection.primary;
    if (primary == null) return null;
    return sculptablePlaneOf(
      _ctrl.liveNode(primary),
      (geometry) => resourceOrigin(geometry)?.resourceId,
    )?.resourceId;
  }

  /// Starts a stroke when the tool is armed and the pointer is over terrain.
  bool _beginSculpt(Offset position, Size viewSize) {
    final target = _terrainTarget();
    if (target == null) {
      // A plane is not sculptable until it has a grid to push around. Convert
      // it as its own undoable step, so it shows in history as the moment the
      // sheet became ground, and sculpt from the next press.
      final plane = _sculptablePlane();
      if (plane == null) return false;
      unawaited(
        _ctrl
            .run('makeTerrainSculptable', {'resourceId': plane.toToken()})
            .then((_) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Plane is now sculptable. Drag to shape it.'),
                  ),
                );
              }
            }),
      );
      return true;
    }
    if (_groundUnder(position, viewSize, target.geometry.field) == null) {
      return false;
    }
    if (_terrainTool.painting) {
      _paintCreatedMap = target.geometry.splat == null;
      _paintStroke = TerrainPaintStroke.on(
        target.geometry,
        resourceId: target.resourceId,
      );
      _paintTarget = target;
    } else {
      _stroke = TerrainStroke(
        geometry: target.geometry,
        resourceId: target.resourceId,
      );
    }
    _stamped = false;
    _strokeClock
      ..reset()
      ..start();
    // The first dab has no elapsed time to measure, so it gets a frame's
    // worth rather than zero, which would make a click do nothing.
    _sculptAt(position, viewSize, 1 / 60);
    return true;
  }

  void _sculptAt(Offset position, Size viewSize, double deltaSeconds) {
    final geometry = _stroke?.geometry ?? _paintTarget?.geometry;
    if (geometry == null) return;
    final point = _groundUnder(position, viewSize, geometry.field);
    // A pointer dragged off the terrain pauses the stroke rather than ending
    // it, so crossing a gap and coming back is still one stroke.
    if (point == null) return;
    _brushPoint = point;
    // A stamp is one press of a shape, not a rate: pressing it again every
    // frame the button is held would drive the ground up without limit, and
    // the depth of a stamp would depend on how long you rested there.
    final stamping = _terrainTool.paintMode == TerrainPaintMode.stamp;
    if (stamping && _stamped) return;
    if (stamping) _stamped = true;
    _stroke?.dab(_strokeBrush(), point, stamping ? 1.0 : deltaSeconds);
    _paintStroke?.dab(
      _terrainTool.brush,
      _terrainTool.paintLayer,
      _terrainTool.targetStrength,
      point,
      deltaSeconds,
    );
    setState(() {});
  }

  /// The brush this stroke applies, with Shift inverting it.
  ///
  /// Shift lowers rather than raises, which is what Unity's terrain tools do
  /// and therefore what people try first. Alt does the same, because that is
  /// what this editor used before and muscle memory outlives a convention
  /// change.
  TerrainBrush _strokeBrush() {
    final keyboard = HardwareKeyboard.instance;
    return _terrainTool.strokeBrush(
      lower: keyboard.isShiftPressed || keyboard.isAltPressed,
    );
  }

  /// The elapsed time since the previous dab, so a slow drag moves the ground
  /// as far as a fast one over the same distance.
  double _dabSeconds() {
    final elapsed = _strokeClock.elapsedMicroseconds / 1000000;
    _strokeClock
      ..reset()
      ..start();
    // A stall should not land a single enormous dab.
    return elapsed.clamp(0.0, 1 / 20);
  }

  /// Ends the stroke, writing it to the document as one undoable step.
  void _endSculpt() {
    final stroke = _stroke;
    final paint = _paintStroke;
    final firstPaint = _paintCreatedMap;
    _paintCreatedMap = false;
    _stroke = null;
    _paintStroke = null;
    _paintTarget = null;
    _strokeClock.stop();
    if (stroke != null && stroke.touched) {
      unawaited(
        _ctrl.run('setTerrainHeights', {
          'resourceId': stroke.resourceId.toToken(),
          'heights': stroke.encodedHeights(),
        }),
      );
    }
    if (paint != null && paint.touched) {
      final node = _ctrl.selection.primary;
      final needsLayers = firstPaint && node != null;
      unawaited(
        _ctrl
            .run('setTerrainSplat', {
              'resourceId': paint.resourceId.toToken(),
              'splat': paint.encodedSplat(),
              'columns': paint.map.columns,
              'rows': paint.map.rows,
            })
            .then((_) async {
              // The control map exists now but nothing draws it until the
              // terrain is using the material that blends by it. Do that once,
              // on the stroke that created the map, as its own undoable step:
              // a first stroke that changed nothing on screen would read as a
              // broken tool.
              if (needsLayers) {
                await _ctrl.run('addTerrainLayers', {'nodeId': node.toToken()});
              }
            })
            .then((_) {
              if (needsLayers && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Terrain layers added. Assign textures to the layers in '
                      'the material.',
                    ),
                  ),
                );
              }
            }),
      );
    }
  }

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
    if (event.buttons & kSecondaryMouseButton != 0) {
      _startFreeLook(event);
      return;
    }
    if (event.buttons & kPrimaryMouseButton == 0) return;
    // Sculpting takes the primary button ahead of the gizmo: the tool is
    // explicitly armed, and a brush that fought the move handles would be
    // unusable over a selected terrain.
    if (_terrainTool.active && _beginSculpt(event.localPosition, viewSize)) {
      return;
    }
    if (_scatterTool.active && _beginScatter(event.localPosition, viewSize)) {
      return;
    }
    final primary = _ctrl.selection.primary;
    if (primary != null) {
      final live = _ctrl.liveNode(primary);
      if (live != null) {
        final grabbed = _gizmo.grab(
          event.localPosition,
          live.globalTransform.getTranslation(),
          _axesFor(live),
          _camera.camera,
          viewSize,
        );
        if (grabbed) {
          _draggingGizmo = true;
          _captureTransformStart(live);
          return;
        }
      }
    }
    _pendingSelection = _PendingSelection(
      pointer: event.pointer,
      origin: event.localPosition,
      viewSize: viewSize,
    );
  }

  /// Follows the pointer with the brush ring while the tool is armed.
  void _onPointerHover(PointerHoverEvent event, Size viewSize) {
    if (!_terrainTool.active && !_scatterTool.active) return;
    _viewSize = viewSize;
    final field = _terrainTool.active
        ? _terrainTarget()?.geometry.field
        : _groundField();
    final point = field == null
        ? (_scatterTool.active
              ? _pointOnGroundPlane(event.localPosition, viewSize)
              : null)
        : _groundUnder(event.localPosition, viewSize, field);
    if (point == _brushPoint) return;
    setState(() => _brushPoint = point);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_stroke != null || _paintStroke != null) {
      _sculptAt(event.localPosition, _viewSize, _dabSeconds());
      return;
    }
    if (_scatterStroke != null) {
      _scatterAt(event.localPosition, _viewSize, _dabSeconds());
      return;
    }
    if (_freeLookActive) {
      unawaited(
        _freeLookPointer
            .updateOffset(
              globalPosition: event.position,
              delta: event.delta,
              viewportSize: MediaQuery.sizeOf(context),
            )
            .then(_applyFreeLookDelta),
      );
      return;
    }
    final pending = _pendingSelection;
    if (pending != null &&
        pending.pointer == event.pointer &&
        (event.localPosition - pending.origin).distance >=
            _primaryDragThreshold) {
      _pendingSelection = null;
    }
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
    if (_stroke != null || _paintStroke != null) {
      _endSculpt();
      return;
    }
    if (_scatterStroke != null) {
      _endScatter();
      return;
    }
    if (_freeLookActive && event.buttons & kSecondaryMouseButton == 0) {
      _endFreeLook();
      return;
    }
    if (!_draggingGizmo) {
      final pending = _pendingSelection;
      _pendingSelection = null;
      if (pending != null && pending.pointer == event.pointer) {
        _performRaycast(event.localPosition, pending.viewSize);
      }
      return;
    }
    final primary = _ctrl.selection.primary;
    if (primary != null) {
      final local = _previewMatrix();
      final translation = vm.Vector3.zero();
      final rotation = vm.Quaternion.identity();
      final scale = vm.Vector3.zero();
      local.decompose(translation, rotation, scale);
      switch (_gizmo.mode) {
        case GizmoMode.translate:
          if (_gizmo.translation.length2 > 1e-10) {
            _ctrl.setNodeTransformRouted(
              primary,
              translation: _vectorMap(translation),
            );
          }
        case GizmoMode.rotate:
          if (_gizmo.angle.abs() > 1e-5) {
            _ctrl.setNodeTransformRouted(
              primary,
              rotation: _quaternionMap(rotation),
              scale: _transformSpace == TransformSpace.global
                  ? _vectorMap(scale)
                  : null,
            );
          }
        case GizmoMode.scale:
          if ((scale - _startS).length2 > 1e-10) {
            _ctrl.setNodeTransformRouted(
              primary,
              scale: _vectorMap(scale),
              rotation:
                  _transformSpace == TransformSpace.global &&
                      _gizmo.activeAxis != axisUniform
                  ? _quaternionMap(rotation)
                  : null,
            );
          }
      }
    }
    _gizmo.end();
    _draggingGizmo = false;
  }

  void _onPointerCancel(PointerCancelEvent event) {
    // A cancelled stroke still keeps what it drew: the ground has already
    // moved on screen, and silently reverting it would look like the edit
    // was lost rather than cancelled.
    if (_stroke != null || _paintStroke != null) _endSculpt();
    if (_scatterStroke != null) _endScatter();
    if (_freeLookActive) _endFreeLook();
    if (_pendingSelection?.pointer == event.pointer) _pendingSelection = null;
    if (_draggingGizmo) {
      final primary = _ctrl.selection.primary;
      if (primary != null) {
        _ctrl.previewLocalTransform(primary, _startLocal.clone());
      }
      _gizmo.end();
      _draggingGizmo = false;
      _bumpView();
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (!_freeLookActive || event is! PointerScrollEvent) return;
    _freeLook.adjustSpeed(event.scrollDelta.dy);
    _bumpView();
  }

  void _startFreeLook(PointerDownEvent event) {
    if (_freeLookActive) return;
    _pendingSelection = null;
    _freeLook.syncTo(_camera.camera);
    _camera.orthographic = false;
    setState(() => _freeLookActive = true);
    unawaited(
      _freeLookPointer.start(
        event.position,
        viewportSize: MediaQuery.sizeOf(context),
        onLockedDelta: _applyFreeLookDelta,
      ),
    );
    _bumpView();
  }

  void _applyFreeLookDelta(Offset delta) {
    if (!_freeLookActive || delta == Offset.zero) return;
    _freeLook.look(delta);
    _syncOrbitToFreeLook();
    _bumpView();
  }

  void _syncOrbitToFreeLook() {
    _camera.azimuth = _freeLook.yaw;
    _camera.elevation = -_freeLook.pitch;
    _camera.target = _freeLook.position + _freeLook.forward * _camera.radius;
    _camera.orthographic = false;
  }

  void _endFreeLook() {
    if (!_freeLookActive) return;
    _freeLook.releaseKeys();
    _syncOrbitToFreeLook();
    unawaited(_freeLookPointer.end());
    if (mounted) setState(() => _freeLookActive = false);
    _bumpView();
  }

  List<vm.Vector3> _axesFor(Node live) =>
      transformSpaceAxes(_transformSpace, live.globalTransform);

  void _captureTransformStart(Node live) {
    _startLocal.setFrom(live.localTransform);
    _startGlobal.setFrom(live.globalTransform);
    live.localTransform.decompose(_startT, _startR, _startS);
    final parent = live.parent;
    if (parent == null) {
      _parentGlobalInverse.setIdentity();
    } else {
      _parentGlobalInverse.copyInverse(parent.globalTransform);
    }
    _activeTransformAxes = transformSpaceAxes(_transformSpace, _startGlobal);
  }

  vm.Matrix4 _globalToLocal(vm.Matrix4 global) =>
      globalToLocalTransform(global, _parentGlobalInverse);

  vm.Matrix4 _translatedLocal(vm.Vector3 globalDelta) {
    final global = _startGlobal.clone();
    global.setTranslation(_startGlobal.getTranslation() + globalDelta);
    return _globalToLocal(global);
  }

  vm.Matrix4 _rotatedLocal(vm.Vector3 globalAxis, double angle) {
    final origin = _startGlobal.getTranslation();
    final rotation = vm.Matrix4.compose(
      vm.Vector3.zero(),
      vm.Quaternion.axisAngle(globalAxis, angle),
      vm.Vector3.all(1),
    );
    final global =
        vm.Matrix4.translation(origin) *
        rotation *
        vm.Matrix4.translation(-origin) *
        _startGlobal;
    return _globalToLocal(global);
  }

  vm.Matrix4 _rotatedInLocalSpace(int axis, double angle) {
    final localAngle = localAxisRotationAngle(angle, _startGlobal);
    final rotation =
        _startR *
        vm.Quaternion.axisAngle(vm.Vector3.zero()..[axis] = 1, localAngle);
    rotation.normalize();
    return vm.Matrix4.compose(_startT, rotation, _startS);
  }

  vm.Matrix4 _scaledGlobalLocal(vm.Vector3 globalAxis, double factor) {
    final scale = vm.Matrix4.identity();
    for (var row = 0; row < 3; row++) {
      for (var column = 0; column < 3; column++) {
        scale.setEntry(
          row,
          column,
          (row == column ? 1.0 : 0.0) +
              (factor - 1) * globalAxis[row] * globalAxis[column],
        );
      }
    }
    final origin = _startGlobal.getTranslation();
    final global =
        vm.Matrix4.translation(origin) *
        scale *
        vm.Matrix4.translation(-origin) *
        _startGlobal;
    return _globalToLocal(global);
  }

  vm.Matrix4 _scaledLocal(vm.Vector3 scale) => vm.Matrix4.compose(
    _startT,
    _startR,
    vm.Vector3(_startS.x * scale.x, _startS.y * scale.y, _startS.z * scale.z),
  );

  vm.Matrix4 _previewMatrix() {
    switch (_gizmo.mode) {
      case GizmoMode.translate:
        return _translatedLocal(_gizmo.translation);
      case GizmoMode.rotate:
        if (_transformSpace == TransformSpace.local) {
          return _rotatedInLocalSpace(_gizmo.activeAxis!, _gizmo.angle);
        }
        return _rotatedLocal(_gizmo.axisVec, _gizmo.angle);
      case GizmoMode.scale:
        final axis = _gizmo.activeAxis;
        if (_transformSpace == TransformSpace.local || axis == axisUniform) {
          return _scaledLocal(_gizmo.scale);
        }
        return _scaledGlobalLocal(_gizmo.axisVec, _gizmo.scale[axis!]);
    }
  }

  void _setMode(GizmoMode mode) {
    if (_gizmo.mode == mode) return;
    _gizmo.mode = mode;
    _bumpView();
  }

  void _setTransformSpace(TransformSpace space) {
    if (_transformSpace == space) return;
    setState(() => _transformSpace = space);
    _bumpView();
  }

  // --- modal transforms (G/R/S) --------------------------------------------

  void _startModal(_ModalOp op) {
    final primary = _ctrl.selection.primary;
    if (primary == null) return;
    final live = _ctrl.liveNode(primary);
    if (live == null) return;
    _captureTransformStart(live);
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
        final local = _modalMatrix(modal);
        final t = local.getTranslation();
        _ctrl.setNodeTransformRouted(primary, translation: _vectorMap(t));
      case _ModalOp.rotate:
        final local = _modalMatrix(modal);
        final t = vm.Vector3.zero();
        final r = vm.Quaternion.identity();
        final s = vm.Vector3.zero();
        local.decompose(t, r, s);
        _ctrl.setNodeTransformRouted(
          primary,
          rotation: _quaternionMap(r),
          scale: _transformSpace == TransformSpace.global
              ? _vectorMap(s)
              : null,
        );
      case _ModalOp.scale:
        final local = _modalMatrix(modal);
        final t = vm.Vector3.zero();
        final r = vm.Quaternion.identity();
        final s = vm.Vector3.zero();
        local.decompose(t, r, s);
        _ctrl.setNodeTransformRouted(
          primary,
          scale: _vectorMap(s),
          rotation:
              _transformSpace == TransformSpace.global && modal.axis != null
              ? _quaternionMap(r)
              : null,
        );
    }
    _modal = null;
    _bumpView();
  }

  void _cancelModal() {
    final modal = _modal;
    final primary = _ctrl.selection.primary;
    if (modal != null && primary != null) {
      _ctrl.previewLocalTransform(primary, _startLocal.clone());
    }
    _modal = null;
    _bumpView();
  }

  vm.Matrix4 _modalMatrix(_ModalTransform modal) {
    switch (modal.op) {
      case _ModalOp.translate:
        return _translatedLocal(_modalTranslation(modal));
      case _ModalOp.rotate:
        if (_transformSpace == TransformSpace.local && modal.axis != null) {
          return _rotatedInLocalSpace(modal.axis!, _modalRotationAngle(modal));
        }
        return _rotatedLocal(
          _modalRotationAxis(modal),
          _modalRotationAngle(modal),
        );
      case _ModalOp.scale:
        final factors = _modalScaleFactors(modal);
        final axis = modal.axis;
        if (_transformSpace == TransformSpace.local || axis == null) {
          return _scaledLocal(factors);
        }
        return _scaledGlobalLocal(_activeTransformAxes[axis], factors[axis]);
    }
  }

  Map<String, Object> _vectorMap(vm.Vector3 value) => {
    'x': value.x,
    'y': value.y,
    'z': value.z,
  };

  Map<String, Object> _quaternionMap(vm.Quaternion value) => {
    'x': value.x,
    'y': value.y,
    'z': value.z,
    'w': value.w,
  };

  /// Pixels-to-global-units factor at the modal object's depth (or orthographic
  /// view scale), for camera-plane translation.
  double _globalUnitsPerPixel(_ModalTransform modal) {
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
      // how many pixels one global unit of that axis spans.
      final axisDir = _activeTransformAxes[axis];
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
    final unitsPerPixel = _globalUnitsPerPixel(modal);
    return _camera.rightVector * (deltaPx.dx * unitsPerPixel) +
        _camera.upVector * (-deltaPx.dy * unitsPerPixel);
  }

  double _modalRotationAngle(_ModalTransform modal) {
    double angleOf(Offset p) =>
        atan2(p.dy - modal.pivotScreen.dy, p.dx - modal.pivotScreen.dx);
    // Positive when the mouse circles clockwise on screen (y grows down).
    final screenAngle = angleOf(modal.pointer) - angleOf(modal.startPointer);
    final axis = _modalRotationAxis(modal);
    // Make the object follow the mouse regardless of which way the axis faces.
    return axis.dot(_camera.forwardVector) >= 0 ? -screenAngle : screenAngle;
  }

  vm.Vector3 _modalRotationAxis(_ModalTransform modal) => modal.axis == null
      ? _camera.forwardVector
      : _activeTransformAxes[modal.axis!];

  vm.Vector3 _modalScaleFactors(_ModalTransform modal) {
    final base = (modal.startPointer - modal.pivotScreen).distance.clamp(
      5.0,
      double.infinity,
    );
    final factor = (modal.pointer - modal.pivotScreen).distance / base;
    final axis = modal.axis;
    if (axis == null) return vm.Vector3.all(factor);
    return vm.Vector3(
      axis == 0 ? factor : 1,
      axis == 1 ? factor : 1,
      axis == 2 ? factor : 1,
    );
  }

  /// The constrained axis's on-screen direction through the modal pivot, for
  /// the guide line. Null when unconstrained or degenerate.
  Offset? _modalAxisScreenDir(_ModalTransform modal) {
    final axis = modal.axis;
    if (axis == null) return null;
    final axisDir = _activeTransformAxes[axis];
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
    final label = axis == null ? op : '$op ${'XYZ'[axis]}';
    final space = _transformSpace == TransformSpace.global ? 'Global' : 'Local';
    return '$label  $space';
  }

  bool _frameSelection() {
    vm.Aabb3? selectionBounds;
    for (final id in _ctrl.selection.ids) {
      final node = _ctrl.liveNode(id);
      if (node == null) continue;
      final bounds = node.combinedWorldBounds ?? _translationHull(node);
      if (bounds == null) continue;
      if (selectionBounds == null) {
        selectionBounds = vm.Aabb3.copy(bounds);
      } else {
        selectionBounds.hull(bounds);
      }
    }
    if (selectionBounds == null) return false;
    final aspect = _viewSize.height > 0
        ? _viewSize.width / _viewSize.height
        : 1.0;
    _camera.frame(selectionBounds, aspectRatio: aspect);
    _bumpView();
    return true;
  }

  vm.Aabb3? _translationHull(Node root) {
    // TODO(frame-selection): use posed bounds when skinned nodes expose them.
    vm.Aabb3? result;
    for (final node in root.meshNodes) {
      final point = node.globalTransform.getTranslation();
      if (result == null) {
        result = vm.Aabb3.minMax(point.clone(), point.clone());
      } else {
        result.hullPoint(point);
      }
    }
    if (result != null) return result;
    final point = root.globalTransform.getTranslation();
    return vm.Aabb3.minMax(point.clone(), point.clone());
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (_freeLookActive) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        _endFreeLook();
        return KeyEventResult.handled;
      }
      final result = _freeLook.onKeyEvent(event);
      return result == KeyEventResult.ignored ? KeyEventResult.handled : result;
    }
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
    // Brush size and opacity, on the keys Unity uses. Only while a tool is
    // armed: the brackets belong to whoever has the mouse, and with no tool
    // armed that is not the brush.
    if (_terrainTool.active) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.bracketLeft:
          _terrainTool.nudgeRadius(1 / 1.25);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.bracketRight:
          _terrainTool.nudgeRadius(1.25);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.minus:
          _terrainTool.nudgeStrength(-0.25);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.equal:
          _terrainTool.nudgeStrength(0.25);
          return KeyEventResult.handled;
      }
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.keyF:
        return _frameSelection()
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
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
    // Component gizmos win over the scene raycast: a gizmo is often a
    // meshless node's only clickable presence, and screen-space slop is what
    // users expect when clicking thin lines.
    final gizmoHit = _componentGizmoHits.hitTest(position);
    if (gizmoHit != null) {
      _ctrl.selection.selectOnly(gizmoHit);
      _bumpView();
      return;
    }
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
          cursor: _freeLookActive ? SystemMouseCursors.none : MouseCursor.defer,
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
                    final cam = _freeLookActive
                        ? _freeLook.camera
                        : _camera.camera;
                    // Picture-in-picture preview of the selected node's camera
                    // component, rendered by the same SceneView as a second
                    // view into a bottom-left sub-rect. Hidden when the panel
                    // is too small to fit it alongside the badges.
                    final cameraComponents = live
                        ?.getComponents<CameraComponent>();
                    final pipCamera =
                        (cameraComponents == null || cameraComponents.isEmpty)
                        ? null
                        : cameraComponents.first.toCamera();
                    Rect? pipRect;
                    if (pipCamera != null) {
                      final pipWidth = (size.width * 0.3).clamp(160.0, 420.0);
                      final pipHeight = pipWidth * 9 / 16;
                      if (size.width >= pipWidth * 2 &&
                          size.height >= pipHeight * 2) {
                        pipRect = Rect.fromLTWH(
                          12,
                          size.height - pipHeight - 40,
                          pipWidth,
                          pipHeight,
                        );
                      }
                    }
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        Focus(
                          focusNode: _focusNode,
                          onKeyEvent: _onKey,
                          onFocusChange: (focused) {
                            if (!focused) {
                              if (_freeLookActive) _endFreeLook();
                              _freeLook.releaseKeys();
                            }
                          },
                          child: OrbitCameraController(
                            camera: _camera,
                            isLocked: () =>
                                _draggingGizmo ||
                                _modal != null ||
                                _freeLookActive,
                            onChanged: _bumpView,
                            child: Listener(
                              behavior: HitTestBehavior.opaque,
                              onPointerDown: (e) => _onPointerDown(e, size),
                              onPointerMove: _onPointerMove,
                              onPointerHover: (event) =>
                                  _onPointerHover(event, size),
                              onPointerUp: _onPointerUp,
                              onPointerCancel: _onPointerCancel,
                              onPointerSignal: _onPointerSignal,
                              child: SceneView(
                                _ctrl.scene,
                                viewsBuilder: (_) => [
                                  RenderView(
                                    camera: cam,
                                    // The editor's own quality. Null leaves
                                    // the scene's setting alone, so the
                                    // default view is what the game sees.
                                    renderScale:
                                        _gizmoPrefs.viewportRenderScale == 1.0
                                        ? null
                                        : _gizmoPrefs.viewportRenderScale,
                                  ),
                                  if (pipCamera != null && pipRect != null)
                                    RenderView(
                                      camera: pipCamera,
                                      viewport: Rect.fromLTWH(
                                        pipRect.left / size.width,
                                        pipRect.top / size.height,
                                        pipRect.width / size.width,
                                        pipRect.height / size.height,
                                      ),
                                      order: 1,
                                    ),
                                ],
                                onTick: _onTick,
                              ),
                            ),
                          ),
                        ),
                        IgnorePointer(
                          child: CustomPaint(
                            painter: ComponentGizmoPainter(
                              controller: _ctrl,
                              camera: cam,
                              preferences: _gizmoPrefs,
                              hits: _componentGizmoHits,
                              cache: _componentGizmoCache,
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
                                axes: _draggingGizmo || _modal != null
                                    ? _activeTransformAxes
                                    : _axesFor(live),
                                camera: cam,
                                activeAxis: _gizmo.activeAxis,
                              ),
                              size: size,
                            ),
                          ),
                        if (pipRect != null)
                          Positioned.fromRect(
                            rect: pipRect,
                            child: IgnorePointer(
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.white70),
                                    ),
                                    child: const SizedBox.expand(),
                                  ),
                                  Positioned(
                                    top: -24,
                                    left: 0,
                                    child: _InfoBadge(
                                      text: () {
                                        final name = live?.name ?? '';
                                        return name.isEmpty
                                            ? 'Camera preview'
                                            : name;
                                      }(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: SceneOverlay(
                            label: 'Tool settings',
                            child: OverlaySegments<TransformSpace>(
                              options: const {
                                TransformSpace.global: 'Global',
                                TransformSpace.local: 'Local',
                              },
                              value: _transformSpace,
                              onChanged: _setTransformSpace,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          left: 8,
                          child: _GizmoModeBar(
                            mode: _gizmo.mode,
                            onChanged: _setMode,
                            sculpting: _terrainTool.active,
                            canSculpt:
                                _terrainTarget() != null ||
                                _sculptablePlane() != null,
                            onSculptingChanged: (value) => setState(() {
                              _terrainTool.tool = value
                                  ? TerrainTool.paint
                                  : null;
                              // The two brushes both want the primary button,
                              // so arming one disarms the other.
                              if (value) _scatterTool.active = false;
                            }),
                            painting: _scatterTool.active,
                            canPaint: _scatterTarget() != null,
                            onPaintingChanged: (value) => setState(() {
                              _scatterTool.active = value;
                              if (value) _terrainTool.tool = null;
                            }),
                          ),
                        ),
                        if (_scatterTool.active)
                          if (_brushPoint case final point?)
                            if (_groundField() case final field?)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: CustomPaint(
                                    painter: TerrainBrushCursorPainter(
                                      center: point,
                                      // The scatter brush has the same
                                      // footprint as a sculpting one, so it
                                      // borrows the ring rather than drawing
                                      // a second kind of circle.
                                      brush: TerrainBrush(
                                        radius: _scatterTool.brush.radius,
                                        falloff: 1,
                                      ),
                                      field: field,
                                      color: editorAccentColor,
                                      project: (world) => projectToScreen(
                                        world,
                                        _camera.camera,
                                        _viewSize,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                        if (_terrainTool.active)
                          if (_brushPoint case final point?)
                            if (_terrainTarget() case final target?)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: CustomPaint(
                                    painter: TerrainBrushCursorPainter(
                                      center: point,
                                      brush: _terrainTool.brush,
                                      field: target.geometry.field,
                                      color: editorAccentColor,
                                      project: (world) => projectToScreen(
                                        world,
                                        _camera.camera,
                                        _viewSize,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                        if (_scatterTool.active)
                          Positioned(
                            top: 40,
                            left: 8,
                            child: ListenableBuilder(
                              listenable: _scatterTool,
                              builder: (context, _) =>
                                  ScatterBrushPalette(tool: _scatterTool),
                            ),
                          ),
                        if (_terrainTool.active)
                          Positioned(
                            top: 40,
                            left: 8,
                            child: ListenableBuilder(
                              listenable: _terrainTool,
                              builder: (context, _) =>
                                  TerrainBrushPalette(tool: _terrainTool),
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
                        if (_freeLookActive)
                          Positioned(
                            top: 8,
                            left: 0,
                            right: 0,
                            child: IgnorePointer(
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    'FLY  ${_freeLook.speed.toStringAsFixed(2)}  '
                                    'WASD/QE  Shift boost  Release RMB',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ),
                              ),
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
                    _GizmoMenuButton(
                      controller: _ctrl,
                      preferences: _gizmoPrefs,
                    ),
                    const SizedBox(height: 4),
                    _DebugOutputButton(controller: _ctrl, onChanged: _bumpView),
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

/// Translate/rotate/scale mode selector, plus the sculpting tool.
///
/// Sculpting sits with the gizmo modes because it is one: while it is armed
/// the primary button belongs to the brush rather than the move handles, so
/// showing it anywhere else would hide that they are exclusive.
class _GizmoModeBar extends StatelessWidget {
  const _GizmoModeBar({
    required this.mode,
    required this.onChanged,
    required this.sculpting,
    required this.onSculptingChanged,
    required this.canSculpt,
    required this.painting,
    required this.onPaintingChanged,
    required this.canPaint,
  });
  final GizmoMode mode;
  final void Function(GizmoMode) onChanged;

  /// Whether the terrain brush has the primary button.
  final bool sculpting;
  final ValueChanged<bool> onSculptingChanged;

  /// Whether the selection is terrain the brush could reach.
  final bool canSculpt;

  /// Whether the scatter brush has the primary button.
  final bool painting;
  final ValueChanged<bool> onPaintingChanged;

  /// Whether the selection carries a scatter layer to paint into.
  final bool canPaint;

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
              size: 16,
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
          Tooltip(
            message: canSculpt
                ? 'Sculpt terrain'
                : 'Select a terrain to sculpt it',
            child: InkWell(
              onTap: canSculpt ? () => onSculptingChanged(!sculpting) : null,
              child: Container(
                width: 28,
                height: 24,
                color: sculpting
                    ? Theme.of(context).colorScheme.primary
                    : Colors.black.withValues(alpha: 0.55),
                child: Icon(
                  Icons.terrain,
                  size: 16,
                  color: !canSculpt
                      ? editorMutedTextColor
                      : sculpting
                      ? Colors.black
                      : Colors.white,
                ),
              ),
            ),
          ),
          Tooltip(
            message: canPaint
                ? 'Paint objects'
                : 'Select a node with a scatter layer to paint into',
            child: InkWell(
              onTap: canPaint ? () => onPaintingChanged(!painting) : null,
              child: Container(
                width: 28,
                height: 24,
                color: painting
                    ? Theme.of(context).colorScheme.primary
                    : Colors.black.withValues(alpha: 0.55),
                child: Icon(
                  Icons.forest_outlined,
                  size: editorIconSizeLarge,
                  color: !canPaint
                      ? editorMutedTextColor
                      : painting
                      ? Colors.black
                      : Colors.white,
                ),
              ),
            ),
          ),
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

class _PendingSelection {
  const _PendingSelection({
    required this.pointer,
    required this.origin,
    required this.viewSize,
  });

  final int pointer;
  final Offset origin;
  final Size viewSize;
}

/// The kind of keyboard-driven transform in progress.
enum _ModalOp { translate, rotate, scale }

/// State of an in-progress G/R/S transform. The mouse drives the delta from
/// [startPointer]; [axis] constrains it to a transform-space axis when set.
class _ModalTransform {
  _ModalTransform({
    required this.op,
    required this.origin,
    required this.startPointer,
    required this.pivotScreen,
  });

  final _ModalOp op;

  /// The selected node's global-space origin when the transform started.
  final vm.Vector3 origin;

  final Offset startPointer;

  /// The origin's screen position, the pivot for rotate/scale mouse math.
  final Offset pivotScreen;

  /// Constrained transform-space axis, null when free.
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

/// Component-gizmo visibility menu: the master toggle plus one checkbox per
/// component type that declares a gizmo. Preferences are shared across
/// viewports and persisted with the editor settings.
class _GizmoMenuButton extends StatelessWidget {
  const _GizmoMenuButton({required this.controller, required this.preferences});

  final EditorController controller;
  final GizmoPreferences preferences;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: preferences,
      builder: (context, _) {
        final schemas = controller.gizmoComponentSchemas();
        return PopupMenuButton<VoidCallback>(
          tooltip: 'Gizmos',
          padding: EdgeInsets.zero,
          onSelected: (action) => action(),
          itemBuilder: (_) => [
            _checkedItem(
              label: 'Show gizmos',
              checked: preferences.enabled,
              action: () => preferences.enabled = !preferences.enabled,
            ),
            const PopupMenuDivider(height: 8),
            // Editor-only resolution. The scene's own renderScale is a
            // document property and would follow the game out of the editor;
            // this does not.
            for (final scale in const [1.0, 0.75, 0.5, 0.25])
              _checkedItem(
                label: scale == 1.0
                    ? 'Viewport resolution: full'
                    : 'Viewport resolution: ${(scale * 100).round()}%',
                checked: preferences.viewportRenderScale == scale,
                action: () => preferences.viewportRenderScale = scale,
              ),
            if (schemas.isNotEmpty) const PopupMenuDivider(height: 8),
            for (final schema in schemas)
              _checkedItem(
                label: schema.type,
                checked: !preferences.hiddenTypes.contains(schema.type),
                enabled: preferences.enabled,
                action: () => preferences.setTypeHidden(
                  schema.type,
                  !preferences.hiddenTypes.contains(schema.type),
                ),
              ),
          ],
          child: Container(
            width: 28,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              Icons.place_outlined,
              size: 16,
              color: preferences.enabled ? Colors.white : Colors.white38,
            ),
          ),
        );
      },
    );
  }

  PopupMenuItem<VoidCallback> _checkedItem({
    required String label,
    required bool checked,
    required VoidCallback action,
    bool enabled = true,
  }) {
    return PopupMenuItem<VoidCallback>(
      value: action,
      enabled: enabled,
      height: editorMenuItemHeight,
      child: Row(
        children: [
          editorMenuCheckmark(checked),
          const SizedBox(width: 4),
          Text(label),
        ],
      ),
    );
  }
}

/// Debug-output selector: renders one of the engine's intermediate buffers
/// (depth, normals, AO, shadow atlas...) full-viewport instead of the final
/// image. Mode state lives on the scene's shared debug pass, so every
/// viewport of that scene shows the same output.
class _DebugOutputButton extends StatefulWidget {
  const _DebugOutputButton({required this.controller, required this.onChanged});

  final EditorController controller;
  final VoidCallback onChanged;

  @override
  State<_DebugOutputButton> createState() => _DebugOutputButtonState();
}

class _DebugOutputButtonState extends State<_DebugOutputButton> {
  @override
  Widget build(BuildContext context) {
    final pass = debugVisualizePassFor(widget.controller.scene);
    final active = pass.mode.resolve != null;
    return PopupMenuButton<ViewportDebugMode>(
      tooltip: 'Debug output',
      padding: EdgeInsets.zero,
      onSelected: (mode) async {
        // The remap shader loads lazily on the first non-passthrough use.
        if (mode.resolve != null) await loadEditorDebugShaders();
        pass.mode = mode;
        if (mounted) setState(() {});
        widget.onChanged();
      },
      itemBuilder: (_) => [
        for (final mode in viewportDebugModes)
          PopupMenuItem<ViewportDebugMode>(
            value: mode,
            height: editorMenuItemHeight,
            child: Row(
              children: [
                editorMenuCheckmark(pass.mode.id == mode.id),
                const SizedBox(width: 4),
                Text(mode.label),
              ],
            ),
          ),
      ],
      child: Container(
        width: 28,
        height: 24,
        decoration: BoxDecoration(
          color: active
              ? Theme.of(context).colorScheme.primary
              : Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          Icons.layers_outlined,
          size: 16,
          color: active ? Colors.black : Colors.white,
        ),
      ),
    );
  }
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
        // Transform space moved onto the scene as a Tool settings overlay:
        // it changes what a drag does, so it belongs where you can see which
        // one you are in without opening anything.
        _checkedItem(
          label: 'Show FPS',
          checked: showFps,
          action: () => onToggleFps(!showFps),
        ),
      ],
      child: Container(
        width: 28,
        height: 24,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Icon(Icons.settings, size: 16, color: Colors.white),
      ),
    );
  }

  PopupMenuItem<VoidCallback> _checkedItem({
    required String label,
    required bool checked,
    required VoidCallback action,
  }) {
    return PopupMenuItem<VoidCallback>(
      value: action,
      height: editorMenuItemHeight,
      child: Row(
        children: [
          editorMenuCheckmark(checked),
          const SizedBox(width: 4),
          Text(label),
        ],
      ),
    );
  }
}
