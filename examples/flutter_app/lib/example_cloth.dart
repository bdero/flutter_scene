// Cloth example: a CPU cloth solver driving updatable MeshGeometry, shaded by
// the ClothFabric material.
//
// Three scenes exercise different parts of the solver. Flag runs on
// aerodynamics (pressure drag and lift across each triangle, which is what
// makes it snap instead of swing). Drape runs on self-collision and friction,
// so folds stack on the floor instead of sinking through each other. Curtain
// runs on moving contacts, sweeping a ball through a pinned sheet.
//
// The Physics example hangs the same cloth in a corridor you walk a character
// through.

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart' hide Material;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'cloth/cloth_controls.dart';
import 'cloth/cloth_settings.dart';
import 'cloth/cloth_sheet.dart';
import 'cloth/cloth_solver.dart';
import 'example_action_hint.dart';
import 'example_overlay.dart';
import 'example_panel.dart';
import 'example_settings.dart';
import 'quake_camera.dart';

enum _Demo {
  flag('Flag'),
  drape('Drape'),
  curtain('Curtain');

  const _Demo(this.label);
  final String label;
}

/// Each scene's tuned starting point, as deltas from the stock defaults.
///
/// The flag runs on the stock values; the drape wants a softer, slacker sheet
/// that settles, and the curtain a stiffer one in a gustier wind.
ClothSettings _presetFor(_Demo demo) {
  final settings = ClothSettings();
  switch (demo) {
    case _Demo.flag:
      return settings;
    case _Demo.drape:
      return settings
        ..stretchCompliance = 2.18e-6
        ..bending = 0.25
        ..friction = 0.25
        ..wind.speed = 5.10
        ..wind.gust = 0.33;
    case _Demo.curtain:
      return settings
        ..stretchCompliance = 2.18e-6
        ..bending = 0.18
        ..friction = 0.39
        ..wind.speed = 5.10
        ..wind.gust = 0.57;
  }
}

class ExampleCloth extends StatefulWidget {
  const ExampleCloth({super.key});

  @override
  State<ExampleCloth> createState() => _ExampleClothState();
}

class _ExampleClothState extends State<ExampleCloth> {
  final ClothSettings _settings = _presetFor(_Demo.flag);
  _Demo _demo = _Demo.flag;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: _body()),
        ExampleOverlay.topLeft(
          child: SizedBox(
            width: 156,
            child: ExampleDropdown<_Demo>(
              value: _demo,
              items: [
                for (final demo in _Demo.values)
                  DropdownMenuItem(value: demo, child: Text(demo.label)),
              ],
              onChanged: (demo) {
                if (demo == null || demo == _demo) return;
                setState(() {
                  _demo = demo;
                  _settings.copyFrom(_presetFor(demo));
                });
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _body() => _ClothStage(
    // The scene owns its Scene and SceneView; the key rebuilds it (and
    // disposes the old scene) when the selection or the tessellation changes.
    // The hem height and the tessellation are both cut into the sheet, so a
    // change to either has to rebuild the scene.
    key: ValueKey(
      '${_demo.name}-${_settings.quality.name}-'
      '${_settings.groundOffset.toStringAsFixed(2)}',
    ),
    demo: _demo,
    settings: _settings,
    onSettingsChanged: () => setState(() {}),
  );
}

// ---------------------------------------------------------------------------
// The stage scenes: one sheet, an orbit camera, and a pointer you can grab it
// with.
// ---------------------------------------------------------------------------

class _ClothStage extends StatefulWidget {
  const _ClothStage({
    super.key,
    required this.demo,
    required this.settings,
    required this.onSettingsChanged,
  });

  final _Demo demo;
  final ClothSettings settings;
  final VoidCallback onSettingsChanged;

  @override
  State<_ClothStage> createState() => _ClothStageState();
}

class _ClothStageState extends State<_ClothStage> {
  final Scene scene = Scene();
  final Node _props = Node();

  PreprocessedMaterial? _fabric;
  String? _failure;

  ClothSheet? _sheet;
  ClothSolver? _solver;

  // A free-flying camera. Each scene names the pose it starts at, as an orbit
  // around the sheet, which the camera is synced to on load and on reset.
  final QuakeCamera _camera = QuakeCamera()..speed = 3.2;
  double _spawnYaw = -0.9;
  double _spawnPitch = 0.16;
  double _spawnDistance = 4.4;
  vm.Vector3 _spawnTarget = vm.Vector3(1.1, 1.9, 0.0);

  ClothSphere? _ball;
  Node? _ballNode;

  final ValueNotifier<String> _stats = ValueNotifier<String>('');

  Size _viewSize = Size.zero;
  int _grabPointer = -1;
  double _grabDistance = 0.0;
  double _elapsed = 0.0;

  @override
  void initState() {
    super.initState();
    // Read the keyboard directly rather than through focus, so opening a
    // dropdown (which takes focus and never hands it back) cannot strand the
    // camera. Nothing in this example accepts typed text.
    HardwareKeyboard.instance.addHandler(_camera.handleKey);
    _load();
  }

  Future<void> _load() async {
    try {
      _fabric = await loadFmatMaterial('assets/cloth_fabric.fmat');
    } catch (error) {
      if (mounted) setState(() => _failure = '$error');
      return;
    }
    if (!mounted) return;
    scene.add(_props);
    _build();
    setState(() {});
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_camera.handleKey);
    scene.removeAll();
    _stats.dispose();
    super.dispose();
  }

  // --- Scene construction ------------------------------------------------

  void _build() {
    _props.add(
      Node(
        mesh: Mesh(
          PlaneGeometry(width: 24, depth: 24),
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.20, 0.21, 0.23, 1.0)
            ..metallicFactor = 0.0
            ..roughnessFactor = 0.92,
        ),
      ),
    );

    switch (widget.demo) {
      case _Demo.flag:
        _buildFlag();
      case _Demo.drape:
        _buildDrape();
      case _Demo.curtain:
        _buildCurtain();
    }

    _camera.syncTo(_spawnCamera());

    final solver = _solver!;
    _sheet = ClothSheet(
      solver: solver,
      material: _fabric!,
      colors: clothColors(solver, _pattern),
    );
    scene.add(_sheet!.node);
  }

  int _grid(int base) => widget.settings.quality.gridSize(base);

  void _buildFlag() {
    const width = 2.3;
    const height = 1.5;
    const top = 2.55;
    final columns = _grid(56);
    final rows = _grid(36);

    // A shallow bow across the sheet: a perfectly flat flag in a headwind is
    // a balanced state the wind cannot break out of on its own.
    final solver = ClothSolver(
      columns: columns,
      rows: rows,
      layout: (c, r) {
        final u = c / (columns - 1);
        final v = r / (rows - 1);
        return vm.Vector3(
          0.06 + u * width,
          top - v * height,
          math.sin(u * math.pi) * 0.06,
        );
      },
    );
    for (var r = 0; r < rows; r++) {
      solver.setPinned(r * columns, true);
    }
    solver.groundHeight = 0.0;
    _solver = solver;

    _props.add(
      Node(
        mesh: Mesh(
          CylinderGeometry(
            bottomRadius: 0.045,
            topRadius: 0.045,
            height: 3.1,
            radialSegments: 16,
          ),
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.42, 0.44, 0.47, 1.0)
            ..metallicFactor = 0.9
            ..roughnessFactor = 0.35,
        ),
      )..localTransform = vm.Matrix4.translation(vm.Vector3(0.0, 1.55, 0.0)),
    );

    _spawnTarget = vm.Vector3(1.1, 1.9, 0.0);
    _spawnDistance = 4.4;
    _spawnYaw = -0.9;
    _spawnPitch = 0.16;
  }

  void _buildDrape() {
    const size = 2.7;
    final columns = _grid(48);
    final rows = columns;

    final solver = ClothSolver(
      columns: columns,
      rows: rows,
      layout: (c, r) => vm.Vector3(
        (c / (columns - 1) - 0.5) * size,
        2.05,
        (r / (rows - 1) - 0.5) * size,
      ),
    );
    solver.groundHeight = 0.0;
    solver.colliders.add(
      ClothSphere(center: vm.Vector3(0.0, 0.72, 0.0), radius: 0.68),
    );
    _solver = solver;

    _props.add(
      Node(
        mesh: Mesh(
          SphereGeometry(radius: 0.68, segments: 48, rings: 24),
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.30, 0.32, 0.36, 1.0)
            ..metallicFactor = 0.1
            ..roughnessFactor = 0.5,
        ),
      )..localTransform = vm.Matrix4.translation(vm.Vector3(0.0, 0.72, 0.0)),
    );

    _spawnTarget = vm.Vector3(0.0, 0.75, 0.0);
    _spawnDistance = 3.9;
    _spawnYaw = -0.7;
    _spawnPitch = 0.28;
  }

  void _buildCurtain() {
    const width = 2.8;
    const top = 2.7;
    final height = math.max(top - widget.settings.groundOffset, 0.5);
    final columns = _grid(52);
    final rows = _grid(44);

    final solver = ClothSolver(
      columns: columns,
      rows: rows,
      layout: (c, r) => vm.Vector3(
        (c / (columns - 1) - 0.5) * width,
        top - (r / (rows - 1)) * height,
        0.0,
      ),
    );
    solver.pinTopEdge();
    solver.groundHeight = 0.0;

    final ball = ClothSphere(center: vm.Vector3(0.0, 1.5, 1.6), radius: 0.42);
    solver.colliders.add(ball);
    _ball = ball;
    _solver = solver;

    _props.add(
      Node(
          mesh: Mesh(
            CylinderGeometry(
              bottomRadius: 0.05,
              topRadius: 0.05,
              height: width + 0.5,
              radialSegments: 16,
            ),
            PhysicallyBasedMaterial()
              ..baseColorFactor = vm.Vector4(0.35, 0.28, 0.22, 1.0)
              ..metallicFactor = 0.0
              ..roughnessFactor = 0.6,
          ),
        )
        ..localTransform = (vm.Matrix4.translation(
          vm.Vector3(0.0, top + 0.06, 0.0),
        )..rotateZ(math.pi / 2)),
    );

    _ballNode = Node(
      mesh: Mesh(
        SphereGeometry(radius: 0.42, segments: 40, rings: 20),
        PhysicallyBasedMaterial()
          ..baseColorFactor = vm.Vector4(0.16, 0.17, 0.19, 1.0)
          ..metallicFactor = 0.85
          ..roughnessFactor = 0.3,
      ),
    );
    _props.add(_ballNode!);

    _spawnTarget = vm.Vector3(0.0, 1.4, 0.0);
    _spawnDistance = 5.0;
    _spawnYaw = -0.35;
    _spawnPitch = 0.12;
  }

  /// The sheet's pattern, carried in the vertex colors.
  vm.Vector3 _pattern(int column, int row) {
    final solver = _solver!;
    switch (widget.demo) {
      case _Demo.flag:
        return (row * 7 ~/ solver.rows).isEven
            ? vm.Vector3(0.62, 0.07, 0.11)
            : vm.Vector3(0.93, 0.90, 0.84);
      case _Demo.drape:
        final check =
            ((column * 8 ~/ solver.columns) + (row * 8 ~/ solver.rows)).isEven;
        return check
            ? vm.Vector3(0.72, 0.24, 0.20)
            : vm.Vector3(0.94, 0.92, 0.86);
      case _Demo.curtain:
        final t = row / (solver.rows - 1);
        return vm.Vector3(0.10, 0.34, 0.36) * (0.6 + 0.4 * t);
    }
  }

  // --- Frame -------------------------------------------------------------

  void _tick(Duration elapsed, double deltaSeconds) {
    final sheet = _sheet;
    final fabric = _fabric;
    if (sheet == null || fabric == null) return;
    _elapsed = elapsed.inMicroseconds / 1e6;

    _camera.move(_elapsed);
    _animate();
    // Re-applied every frame, so a slider takes effect with no wiring.
    widget.settings.applyTo(sheet.solver);
    widget.settings.wind.applyTo(sheet.solver, _elapsed);
    sheet.solver.advance(deltaSeconds);
    sheet.sync();

    applyFabricLight(fabric);
    exampleSettings.applyTo(scene);

    final solver = sheet.solver;
    _stats.value =
        '${solver.particleCount} particles, '
        '${solver.constraintCount} constraints, '
        '${solver.lastStepMilliseconds.toStringAsFixed(1)} ms';
  }

  void _animate() {
    final ball = _ball;
    if (widget.demo != _Demo.curtain || ball == null) return;
    ball.moveTo(
      vm.Vector3(
        math.sin(_elapsed * 0.47) * 0.9,
        1.35 + math.sin(_elapsed * 0.94).abs() * 0.25,
        math.cos(_elapsed * 0.72) * 1.7,
      ),
    );
    _ballNode?.localTransform = vm.Matrix4.translation(ball.center);
  }

  /// The pose a scene starts (and resets) at, as a look at its sheet.
  PerspectiveCamera _spawnCamera() {
    final horizontal = math.cos(_spawnPitch) * _spawnDistance;
    return PerspectiveCamera(
      position:
          _spawnTarget +
          vm.Vector3(
            math.sin(_spawnYaw) * horizontal,
            math.sin(_spawnPitch) * _spawnDistance,
            math.cos(_spawnYaw) * horizontal,
          ),
      target: _spawnTarget,
    );
  }

  /// Puts the sheet back where it started and the camera back with it.
  void _respawn() {
    _sheet?.solver.reset();
    _sheet?.sync();
    _camera.syncTo(_spawnCamera());
  }

  // --- Interaction -------------------------------------------------------

  void _onPointerDown(PointerDownEvent event) {
    final sheet = _sheet;
    if (sheet == null || _viewSize.isEmpty) return;
    final ray = _camera.camera.screenPointToRay(event.localPosition, _viewSize);
    final hit = raycastNode(sheet.node, ray);
    if (hit == null) return;
    final particle = sheet.solver.nearestParticle(hit.worldPoint);
    // Dragging a pinned particle would tear it off its mount for good, so
    // those fall through to the orbit gesture.
    if (sheet.solver.isPinned(particle)) return;
    _grabPointer = event.pointer;
    _grabDistance = hit.distance;
    sheet.solver.grab(particle);
  }

  void _onPointerMove(PointerMoveEvent event) {
    final sheet = _sheet;
    if (sheet == null) return;
    if (event.pointer == _grabPointer) {
      if (_viewSize.isEmpty) return;
      final ray = _camera.camera.screenPointToRay(
        event.localPosition,
        _viewSize,
      );
      sheet.solver.moveGrab(
        ray.origin + ray.direction.normalized() * _grabDistance,
      );
      return;
    }
    _camera.look(event.delta);
  }

  void _endGrab(PointerEvent event) {
    if (event.pointer != _grabPointer) return;
    _grabPointer = -1;
    _sheet?.solver.releaseGrab();
  }

  // --- UI ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final failure = _failure;
    if (failure != null) {
      return Center(
        child: ExampleLoadFailureCard(
          title: 'Could not load the fabric material',
          detail: failure,
        ),
      );
    }
    final sheet = _sheet;
    if (sheet == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: [
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              _viewSize = constraints.biggest;
              return Listener(
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _endGrab,
                onPointerCancel: _endGrab,
                onPointerSignal: (signal) {
                  if (signal is! PointerScrollEvent) return;
                  // Scroll rides along the view direction, the same axis W
                  // and S walk.
                  _camera.position.addScaled(
                    _camera.forward,
                    -signal.scrollDelta.dy * 0.01,
                  );
                },
                child: SceneView(
                  scene,
                  cameraBuilder: (elapsed) => _camera.camera,
                  onTick: _tick,
                ),
              );
            },
          ),
        ),
        ExampleOverlay.topCenterAction(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Flexible(
                child: ExampleActionHint(
                  message:
                      'WASD to fly, Q and E for down and up, drag to look, '
                      'drag the cloth to grab it',
                ),
              ),
              const SizedBox(width: 8),
              ExampleActionButton(
                tooltip: 'Respawn the cloth and camera',
                icon: Icons.restart_alt,
                onPressed: () => setState(_respawn),
              ),
            ],
          ),
        ),
        ExampleOverlay.bottomLeftPanel(child: _controls()),
      ],
    );
  }

  Widget _controls() {
    return ClothControlPanel(
      settings: widget.settings,
      stats: _stats,
      onChanged: () => setState(() {}),
      onRebuild: widget.onSettingsChanged,
      showGroundOffset: widget.demo == _Demo.curtain,
      onReset: () => setState(_respawn),
    );
  }
}
