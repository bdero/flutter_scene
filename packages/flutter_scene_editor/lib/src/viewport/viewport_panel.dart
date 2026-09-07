import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// The editor's own OrbitCameraController (a viewport widget) predates the
// engine's; hide the engine one here to keep using the local widget.
import 'package:flutter_scene/scene.dart' hide OrbitCameraController;
import 'package:scene/scene.dart' show LocalId, TrsTransform;
import 'package:native_mouse_cursor/native_mouse_cursor.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../controller/editor_controller.dart';
import '../render_graph/debug_shaders.dart' show loadEditorDebugShaders;
import '../shell/editor_theme.dart';
import 'canvas_overlay.dart';
import 'component_gizmos.dart';
import 'debug_visualize.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/realize/resource_origin.dart'
    show resourceOrigin;
import 'free_look_camera.dart';
import 'orbit_camera.dart';
import 'orientation_gizmo.dart';
import 'scene_overlay.dart';
import 'scatter_tool.dart';
import 'terrain_tool.dart';
import 'transform_gizmo.dart';
import 'viewport_tools.dart';
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
    this.tools,
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

  /// The tool state the rail drives. Attached, the rail owns which handle is
  /// showing and what frame it works in, and this viewport stops drawing its
  /// own controls for them: one tool, one place it is chosen. Null leaves the
  /// viewport self-contained, which is what a host embedding one on its own
  /// gets.
  final ViewportToolState? tools;

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
  // Items that dropped punctual lights last frame (over the per-object cap);
  // nonzero shows the lighting warning badge.
  final _lightOverflow = ValueNotifier<int>(0);
  final _shadowOverflow = ValueNotifier<int>(0);
  // Holds keyboard focus while the viewport is the active surface, so the
  // app-level shortcuts (undo, delete) fire after the viewport is clicked.
  final _focusNode = FocusNode(debugLabel: 'editorViewport');

  bool _draggingGizmo = false;
  bool _freeLookActive = false;
  bool _showFps = false;

  /// The frame used when no rail is attached.
  TransformSpace _ownSpace = TransformSpace.global;

  ViewportToolState? get _tools => widget.tools;

  TransformSpace get _transformSpace => _tools?.space ?? _ownSpace;

  /// The pivot used when no rail is attached.
  PivotMode _ownPivot = PivotMode.medianPoint;

  PivotMode get _pivotMode => _tools?.pivot ?? _ownPivot;
  _PendingSelection? _pendingSelection;

  // The pointer's last position over this viewport, kept for starting a
  // modal transform at the right anchor.
  Offset _mousePos = Offset.zero;

  // The active keyboard-driven transform (G/R/S), if any.
  _ModalTransform? _modal;

  // The selected node's local transform components at the start of a gizmo
  // drag, decomposed so each mode can rebuild the preview.
  // Per-node start state for the active drag (primary first), and the shared
  // pivot (the selection median under PivotMode.medianPoint, else the
  // primary's start origin; individual-origin transforms ignore it).
  List<_TransformTarget> _dragTargets = const [];
  final vm.Vector3 _dragPivot = vm.Vector3.zero();
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
    final tools = _tools;
    if (tools != null) {
      tools.addListener(_onToolsChanged);
      _gizmo.mode = tools.mode;
      _lastFrameSignal = tools.frameSignal;
      _applySnap(tools);
    }
    widget.cameraHandle?.attach(_camera, _bumpView);
  }

  /// The rail changed something the viewport draws or drags with.
  void _onToolsChanged() {
    final tools = _tools;
    if (tools == null || !mounted) return;
    setState(() {
      _gizmo.mode = tools.mode;
      _applySnap(tools);
      // The brushes are armed from the rail now; the primary button belongs
      // to whichever one is holding it.
      _terrainTool.tool = tools.brush == ViewportBrush.terrain
          ? TerrainTool.paint
          : null;
      _scatterTool.active = tools.brush == ViewportBrush.scatter;
    });
    if (tools.frameSignal != _lastFrameSignal) {
      _lastFrameSignal = tools.frameSignal;
      _frameSelection();
    }
    _bumpView();
  }

  /// The last framing request this view answered.
  int _lastFrameSignal = 0;

  /// Snapping is off unless the rail says otherwise, and the steps are the
  /// rail's, so two scene views cannot disagree about where a drag lands.
  void _applySnap(ViewportToolState tools) {
    _gizmo
      ..translateSnap = tools.snap ? tools.translateStep : 0
      ..rotateSnap = tools.snap ? tools.rotateStepDegrees * (pi / 180) : 0
      ..scaleSnap = tools.snap ? tools.scaleStep : 0;
  }

  /// Tells the rail what the brushes could reach, so it can disable one with a
  /// reason rather than arming a brush with nothing under it.
  void _publishBrushTargets() {
    final tools = _tools;
    if (tools == null) return;
    tools.publishBrushTargets(
      sculpt: _terrainTarget() != null || _sculptablePlane() != null,
      scatter: _scatterTarget() != null,
    );
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
    if (oldWidget.tools != widget.tools) {
      oldWidget.tools?.removeListener(_onToolsChanged);
      final tools = _tools;
      if (tools != null) {
        tools.addListener(_onToolsChanged);
        _gizmo.mode = tools.mode;
      }
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
    _tools?.removeListener(_onToolsChanged);
    _viewEpoch.dispose();
    _fps.dispose();
    _lightOverflow.dispose();
    _shadowOverflow.dispose();
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
    // What the brushes can reach depends on the selection, which is what
    // just changed.
    _publishBrushTargets();
    _bumpView();
  }

  void _bumpView() => _viewEpoch.value++;

  void _onTick(Duration elapsed, double deltaSeconds) {
    if (deltaSeconds > 0) {
      final inst = 1.0 / deltaSeconds;
      final prev = _fps.value;
      _fps.value = prev == 0 ? inst : prev * 0.9 + inst * 0.1;
    }
    final overflow = _ctrl.scene.punctualLightOverflowCount;
    if (overflow != _lightOverflow.value) _lightOverflow.value = overflow;
    final shadows = _ctrl.scene.shadowCasterOverflowCount;
    if (shadows != _shadowOverflow.value) _shadowOverflow.value = shadows;
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
  /// Shift lowers rather than raises, which is what people try first because
  /// it is what sculpting tools generally do. Alt does the same, because that
  /// is what this editor used before and muscle memory outlives a convention
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
          _gizmoAnchor(live),
          _axesFor(live),
          _camera.camera,
          viewSize,
        );
        if (grabbed) {
          _draggingGizmo = true;
          _captureTransformStarts(live);
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
    if (_dragTargets.isEmpty) return;
    _gizmo.update(
      event.localPosition,
      _pivotMode == PivotMode.medianPoint
          ? _dragPivot + _gizmo.translation
          : _dragTargets.first.live.globalTransform.getTranslation(),
      _camera.camera,
      _viewSize,
    );
    for (final target in _dragTargets) {
      _ctrl.previewLocalTransform(target.id, _previewMatrixFor(target));
    }
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
    if (_dragTargets.isNotEmpty) {
      switch (_gizmo.mode) {
        case GizmoMode.translate:
          if (_gizmo.translation.length2 > 1e-10) {
            _commitTransformDrag(_previewMatrixFor, translation: true);
          }
        case GizmoMode.rotate:
          if (_gizmo.angle.abs() > 1e-5) {
            _commitTransformDrag(
              _previewMatrixFor,
              rotation: true,
              translation: _dragTargets.length > 1,
              scale: _transformSpace == TransformSpace.global,
            );
          }
        case GizmoMode.scale:
          if ((_gizmo.scale - vm.Vector3.all(1)).length2 > 1e-12) {
            _commitTransformDrag(
              _previewMatrixFor,
              scale: true,
              translation: _dragTargets.length > 1,
              rotation:
                  _transformSpace == TransformSpace.global &&
                  _gizmo.activeAxis != axisUniform,
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
      for (final target in _dragTargets) {
        _ctrl.previewLocalTransform(target.id, target.startLocal.clone());
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

  /// The median of the selected top-level editable nodes' world origins, or
  /// null when nothing editable is selected.
  vm.Vector3? _selectionMedian() {
    var count = 0;
    final sum = vm.Vector3.zero();
    for (final id in _ctrl.topLevelSelection()) {
      if (!_ctrl.isEditableNode(id)) continue;
      final live = _ctrl.liveNode(id);
      if (live == null) continue;
      sum.add(live.globalTransform.getTranslation());
      count++;
    }
    if (count == 0) return null;
    return sum..scale(1 / count);
  }

  /// Where the transform gizmo anchors for [primaryLive]: the selection
  /// median under [PivotMode.medianPoint], the primary's origin otherwise.
  vm.Vector3 _gizmoAnchor(Node primaryLive) {
    if (_pivotMode == PivotMode.medianPoint) {
      final median = _selectionMedian();
      if (median != null) return median;
    }
    return primaryLive.globalTransform.getTranslation();
  }

  /// The pivot [target]'s rotate/scale applies about for the current mode.
  vm.Vector3 _pivotFor(_TransformTarget target) =>
      _pivotMode == PivotMode.individualOrigins
      ? target.startGlobal.getTranslation()
      : _dragPivot;

  // Captures start state for every selected top-level editable node, primary
  // first (the pivot and gizmo axes derive from it). A single selection
  // behaves exactly as before; extra nodes ride along about the same pivot.
  void _captureTransformStarts(Node primaryLive) {
    final primaryId = _ctrl.selection.primary;
    final targets = <_TransformTarget>[];
    for (final id in _ctrl.topLevelSelection()) {
      if (!_ctrl.isEditableNode(id)) continue;
      final live = _ctrl.liveNode(id);
      if (live == null) continue;
      final target = _TransformTarget(id, live);
      if (id == primaryId) {
        targets.insert(0, target);
      } else {
        targets.add(target);
      }
    }
    if (targets.isEmpty && primaryId != null) {
      targets.add(_TransformTarget(primaryId, primaryLive));
    }
    _dragTargets = targets;
    if (_pivotMode == PivotMode.medianPoint && targets.isNotEmpty) {
      _dragPivot.setZero();
      for (final target in targets) {
        _dragPivot.add(target.startGlobal.getTranslation());
      }
      _dragPivot.scale(1 / targets.length);
    } else {
      _dragPivot.setFrom(primaryLive.globalTransform.getTranslation());
    }
    _activeTransformAxes = transformSpaceAxes(
      _transformSpace,
      primaryLive.globalTransform,
    );
  }

  vm.Matrix4 _translatedLocal(_TransformTarget target, vm.Vector3 globalDelta) {
    final global = target.startGlobal.clone();
    global.setTranslation(target.startGlobal.getTranslation() + globalDelta);
    return globalToLocalTransform(global, target.parentGlobalInverse);
  }

  vm.Matrix4 _rotatedLocal(
    _TransformTarget target,
    vm.Vector3 globalAxis,
    double angle,
  ) {
    final rotation = vm.Matrix4.compose(
      vm.Vector3.zero(),
      vm.Quaternion.axisAngle(globalAxis, angle),
      vm.Vector3.all(1),
    );
    final pivot = _pivotFor(target);
    final global =
        vm.Matrix4.translation(pivot) *
        rotation *
        vm.Matrix4.translation(-pivot) *
        target.startGlobal;
    return globalToLocalTransform(global, target.parentGlobalInverse);
  }

  vm.Matrix4 _rotatedInLocalSpace(
    _TransformTarget target,
    int axis,
    double angle,
  ) {
    final localAngle = localAxisRotationAngle(angle, target.startGlobal);
    final rotation =
        target.startR *
        vm.Quaternion.axisAngle(vm.Vector3.zero()..[axis] = 1, localAngle);
    rotation.normalize();
    return vm.Matrix4.compose(target.startT, rotation, target.startS);
  }

  vm.Matrix4 _scaledGlobalLocal(
    _TransformTarget target,
    vm.Vector3 globalAxis,
    double factor,
  ) {
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
    final pivot = _pivotFor(target);
    final global =
        vm.Matrix4.translation(pivot) *
        scale *
        vm.Matrix4.translation(-pivot) *
        target.startGlobal;
    return globalToLocalTransform(global, target.parentGlobalInverse);
  }

  // Scales [target] in its own local frame while pulling its position toward
  // the shared pivot by [uniform], so a median-point uniform or local-space
  // scale moves the selection together the way a rotation about the median
  // does.
  vm.Matrix4 _scaledLocalAboutPivot(
    _TransformTarget target,
    vm.Vector3 scale,
    double uniform,
  ) {
    final local = _scaledLocal(target, scale);
    final global = target.parentGlobalInverse.clone()
      ..invert()
      ..multiply(local);
    final position = target.startGlobal.getTranslation();
    global.setTranslation(_dragPivot + (position - _dragPivot) * uniform);
    return globalToLocalTransform(global, target.parentGlobalInverse);
  }

  vm.Matrix4 _scaledLocal(_TransformTarget target, vm.Vector3 scale) =>
      vm.Matrix4.compose(
        target.startT,
        target.startR,
        vm.Vector3(
          target.startS.x * scale.x,
          target.startS.y * scale.y,
          target.startS.z * scale.z,
        ),
      );

  vm.Matrix4 _previewMatrixFor(_TransformTarget target) {
    final individual = _pivotMode == PivotMode.individualOrigins;
    switch (_gizmo.mode) {
      case GizmoMode.translate:
        return _translatedLocal(target, _gizmo.translation);
      case GizmoMode.rotate:
        if (_transformSpace == TransformSpace.local && individual) {
          return _rotatedInLocalSpace(target, _gizmo.activeAxis!, _gizmo.angle);
        }
        return _rotatedLocal(target, _gizmo.axisVec, _gizmo.angle);
      case GizmoMode.scale:
        final axis = _gizmo.activeAxis;
        if (_transformSpace == TransformSpace.local || axis == axisUniform) {
          if (individual) return _scaledLocal(target, _gizmo.scale);
          final uniform = axis == axisUniform
              ? _gizmo.scale.x
              : _gizmo.scale[axis!];
          return _scaledLocalAboutPivot(target, _gizmo.scale, uniform);
        }
        return _scaledGlobalLocal(target, _gizmo.axisVec, _gizmo.scale[axis!]);
    }
  }

  // Decomposes each drag target's final matrix and commits everything as one
  // undoable edit. Fields outside the drag's mode keep their current values.
  // Prefab-member nodes route through the override path individually.
  void _commitTransformDrag(
    vm.Matrix4 Function(_TransformTarget) matrixFor, {
    bool translation = false,
    bool rotation = false,
    bool scale = false,
  }) {
    final batch = <LocalId, TrsTransform>{};
    for (final target in _dragTargets) {
      final local = matrixFor(target);
      final t = vm.Vector3.zero();
      final r = vm.Quaternion.identity();
      final sc = vm.Vector3.zero();
      local.decompose(t, r, sc);
      final source = _ctrl.document.nodes[target.id];
      if (source == null) {
        _ctrl.setNodeTransformRouted(
          target.id,
          translation: translation ? _vectorMap(t) : null,
          rotation: rotation ? _quaternionMap(r) : null,
          scale: scale ? _vectorMap(sc) : null,
        );
        continue;
      }
      final current = source.transform;
      final trs = current is TrsTransform ? current : null;
      batch[target.id] = TrsTransform(
        translation: translation ? t : (trs?.translation ?? target.startT),
        rotation: rotation ? r : (trs?.rotation ?? target.startR),
        scale: scale ? sc : (trs?.scale ?? target.startS),
      );
    }
    if (batch.isNotEmpty) unawaited(_ctrl.setNodeTransformsBatch(batch));
  }

  void _setMode(GizmoMode mode) {
    if (_gizmo.mode == mode) return;
    final tools = _tools;
    if (tools != null) {
      // Through the shared state, so the rail and every other scene view move
      // with it rather than disagreeing about which tool is held.
      tools.mode = mode;
      return;
    }
    _gizmo.mode = mode;
    _bumpView();
  }

  void _setTransformSpace(TransformSpace space) {
    if (_transformSpace == space) return;
    final tools = _tools;
    if (tools != null) {
      tools.space = space;
      return;
    }
    setState(() => _ownSpace = space);
    _bumpView();
  }

  void _setPivotMode(PivotMode mode) {
    if (_pivotMode == mode) return;
    final tools = _tools;
    if (tools != null) {
      tools.pivot = mode;
      return;
    }
    setState(() => _ownPivot = mode);
    _bumpView();
  }

  // --- modal transforms (G/R/S) --------------------------------------------

  void _startModal(_ModalOp op) {
    final primary = _ctrl.selection.primary;
    if (primary == null) return;
    final live = _ctrl.liveNode(primary);
    if (live == null) return;
    _captureTransformStarts(live);
    final origin = _pivotMode == PivotMode.medianPoint
        ? _dragPivot.clone()
        : live.globalTransform.getTranslation();
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
    if (modal == null || _dragTargets.isEmpty) return;
    modal.pointer = pointer;
    for (final target in _dragTargets) {
      _ctrl.previewLocalTransform(target.id, _modalMatrixFor(target, modal));
    }
    _bumpView();
  }

  void _commitModal() {
    final modal = _modal;
    if (modal == null || _dragTargets.isEmpty) {
      _modal = null;
      return;
    }
    vm.Matrix4 matrixFor(_TransformTarget target) =>
        _modalMatrixFor(target, modal);
    switch (modal.op) {
      case _ModalOp.translate:
        _commitTransformDrag(matrixFor, translation: true);
      case _ModalOp.rotate:
        _commitTransformDrag(
          matrixFor,
          rotation: true,
          translation: _dragTargets.length > 1,
          scale: _transformSpace == TransformSpace.global,
        );
      case _ModalOp.scale:
        _commitTransformDrag(
          matrixFor,
          scale: true,
          translation: _dragTargets.length > 1,
          rotation:
              _transformSpace == TransformSpace.global && modal.axis != null,
        );
    }
    _modal = null;
    _bumpView();
  }

  void _cancelModal() {
    if (_modal != null) {
      for (final target in _dragTargets) {
        _ctrl.previewLocalTransform(target.id, target.startLocal.clone());
      }
    }
    _modal = null;
    _bumpView();
  }

  vm.Matrix4 _modalMatrixFor(_TransformTarget target, _ModalTransform modal) {
    final individual = _pivotMode == PivotMode.individualOrigins;
    switch (modal.op) {
      case _ModalOp.translate:
        return _translatedLocal(target, _modalTranslation(modal));
      case _ModalOp.rotate:
        if (_transformSpace == TransformSpace.local &&
            modal.axis != null &&
            individual) {
          return _rotatedInLocalSpace(
            target,
            modal.axis!,
            _modalRotationAngle(modal),
          );
        }
        return _rotatedLocal(
          target,
          _modalRotationAxis(modal),
          _modalRotationAngle(modal),
        );
      case _ModalOp.scale:
        final factors = _modalScaleFactors(modal);
        final axis = modal.axis;
        if (_transformSpace == TransformSpace.local || axis == null) {
          if (individual) return _scaledLocal(target, factors);
          final uniform = axis == null ? factors.x : factors[axis];
          return _scaledLocalAboutPivot(target, factors, uniform);
        }
        return _scaledGlobalLocal(
          target,
          _activeTransformAxes[axis],
          factors[axis],
        );
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
    // A meshless node hulls to a point; frame it like a small object instead
    // of slamming the camera to point-blank range on its origin.
    if ((selectionBounds.max - selectionBounds.min).length < 1e-4) {
      const halfExtent = 0.75;
      final center = selectionBounds.center;
      selectionBounds = vm.Aabb3.minMax(
        center - vm.Vector3.all(halfExtent),
        center + vm.Vector3.all(halfExtent),
      );
    }
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
    // Brush size and opacity, on the conventional keys. Only while a tool is
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
    // Ctrl/Cmd-click toggles the hit node in and out of the selection
    // instead of replacing it (and a toggle click on empty space keeps the
    // selection).
    final keys = HardwareKeyboard.instance;
    final toggle = keys.isMetaPressed || keys.isControlPressed;
    void apply(LocalId? id) {
      if (id == null) {
        if (!toggle) _ctrl.selection.clear();
        return;
      }
      if (toggle) {
        _ctrl.selection.toggle(id);
      } else {
        _ctrl.selection.selectOnly(id);
      }
    }

    // Component gizmos win over the scene raycast: a gizmo is often a
    // meshless node's only clickable presence, and screen-space slop is what
    // users expect when clicking thin lines.
    final gizmoHit = _componentGizmoHits.hitTest(position);
    if (gizmoHit != null) {
      apply(gizmoHit);
      _bumpView();
      return;
    }
    final ray = _camera.camera.screenPointToRay(position, viewSize);
    final hit = _ctrl.scene.raycast(ray);
    // Resolve the hit to the source node the editor can act on (the node
    // itself, or the enclosing prefab instance for prefab-internal geometry).
    apply(hit == null ? null : _ctrl.sourceIdForLiveNode(hit.node));
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
                        // Above the component gizmos: a UI layout is what you
                        // are working on while you build one, and a light
                        // icon behind it is easier to lose than a rectangle.
                        IgnorePointer(
                          child: CustomPaint(
                            painter: CanvasOverlayPainter(
                              controller: _ctrl,
                              camera: cam,
                              preferences: _gizmoPrefs,
                            ),
                            size: size,
                          ),
                        ),
                        if (live != null)
                          IgnorePointer(
                            child: CustomPaint(
                              painter: TransformGizmoPainter(
                                origin: _draggingGizmo || _modal != null
                                    ? (_pivotMode == PivotMode.medianPoint
                                          ? _dragPivot + _gizmo.translation
                                          : live.globalTransform
                                                .getTranslation())
                                    : _gizmoAnchor(live),
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
                        if (_tools == null)
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
                        // The rail owns the tools when one is attached; a
                        // second copy floating over the scene is a second
                        // place for them to disagree.
                        if (_tools == null)
                          Positioned(
                            top: 8,
                            left: 8,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _GizmoModeBar(
                                  showModes: _tools == null,
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
                                    // The two brushes both want the primary
                                    // button, so arming one disarms the other.
                                    if (value) _scatterTool.active = false;
                                  }),
                                  painting: _scatterTool.active,
                                  canPaint: _scatterTarget() != null,
                                  onPaintingChanged: (value) => setState(() {
                                    _scatterTool.active = value;
                                    if (value) _terrainTool.tool = null;
                                  }),
                                ),
                                const SizedBox(width: 8),
                                _PivotModeBar(
                                  mode: _pivotMode,
                                  onChanged: _setPivotMode,
                                ),
                              ],
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
                    ValueListenableBuilder<int>(
                      valueListenable: _lightOverflow,
                      builder: (context, overflow, _) => overflow == 0
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Tooltip(
                                message:
                                    'More punctual lights reach these '
                                    'objects (or screen regions, under '
                                    'clustered lighting) than the budget '
                                    'shades; the farthest are dropped. Give '
                                    'lights a range, or thin dense light '
                                    'clusters.',
                                child: _InfoBadge(
                                  text: overflow == 1
                                      ? '1 light-budget overflow'
                                      : '$overflow light-budget overflows',
                                  color: const Color(0xCC8A6D1F),
                                ),
                              ),
                            ),
                    ),
                    // Lights whose authored shadow is not being drawn. Silent
                    // otherwise: the light still lights, so the missing shadow
                    // reads as a lighting bug rather than a budget.
                    ValueListenableBuilder<int>(
                      valueListenable: _shadowOverflow,
                      builder: (context, dropped, _) => dropped <= 0
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Tooltip(
                                message:
                                    'More lights ask to cast a shadow than '
                                    'the shared shadow atlas holds, so these '
                                    'lights light the scene but throw no '
                                    'shadow. Turn off Casts shadow on the '
                                    'lights that do not need one; the ones '
                                    'that keep their slot are highlighted in '
                                    'the viewport.',
                                child: _InfoBadge(
                                  text: dropped == 1
                                      ? '1 shadow over budget'
                                      : '$dropped shadows over budget',
                                  color: const Color(0xCC8A6D1F),
                                ),
                              ),
                            ),
                    ),
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

/// Blender-style pivot-point selector for multi-selection transforms.
class _PivotModeBar extends StatelessWidget {
  const _PivotModeBar({required this.mode, required this.onChanged});
  final PivotMode mode;
  final void Function(PivotMode) onChanged;

  @override
  Widget build(BuildContext context) {
    Widget button(PivotMode m, IconData icon, String tip) {
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
          button(
            PivotMode.medianPoint,
            Icons.adjust,
            'Pivot around the median point',
          ),
          button(
            PivotMode.individualOrigins,
            Icons.scatter_plot,
            'Pivot around individual origins',
          ),
        ],
      ),
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
    this.showModes = true,
    required this.mode,
    required this.onChanged,
    required this.sculpting,
    required this.onSculptingChanged,
    required this.canSculpt,
    required this.painting,
    required this.onPaintingChanged,
    required this.canPaint,
  });

  /// Whether the transform handles are chosen here.
  ///
  /// False once a rail is attached: it holds those three, and the bar keeps
  /// the two brushes, which are gated on what the selection is and so belong
  /// next to the scene rather than in a rail that cannot see it.
  final bool showModes;

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
          if (showModes) ...[
            button(GizmoMode.translate, Icons.open_with, 'Move gizmo'),
            button(GizmoMode.rotate, Icons.threesixty, 'Rotate gizmo'),
            button(GizmoMode.scale, Icons.aspect_ratio, 'Scale gizmo'),
          ],
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
  const _InfoBadge({required this.text, this.color});
  final String text;

  /// Background override (a warning tint); null is the neutral scrim.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? Colors.black.withValues(alpha: 0.55),
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
            // The probe lattice is engine data rather than a component gizmo,
            // so it sits outside the per-type list and past the master toggle.
            _checkedItem(
              label: 'Show GI probes',
              checked: preferences.showGiProbes,
              enabled: preferences.enabled,
              action: () =>
                  preferences.showGiProbes = !preferences.showGiProbes,
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

/// Per-node start state captured when a transform drag begins.
class _TransformTarget {
  _TransformTarget(this.id, this.live)
    : startLocal = live.localTransform.clone(),
      startGlobal = live.globalTransform.clone(),
      parentGlobalInverse = vm.Matrix4.identity(),
      startT = vm.Vector3.zero(),
      startR = vm.Quaternion.identity(),
      startS = vm.Vector3(1, 1, 1) {
    live.localTransform.decompose(startT, startR, startS);
    final parent = live.parent;
    if (parent != null) {
      parentGlobalInverse.copyInverse(parent.globalTransform);
    }
  }

  final LocalId id;
  final Node live;
  final vm.Matrix4 startLocal;
  final vm.Matrix4 startGlobal;
  final vm.Matrix4 parentGlobalInverse;
  final vm.Vector3 startT;
  final vm.Quaternion startR;
  final vm.Vector3 startS;
}
