// The procedural array builders back the wireframe preview, and PrimitiveType
// selects the line topology; neither is part of the curated public API. In-repo
// apps may reach into lib/src, so the implementation_imports lint is waived for
// this file.
// ignore_for_file: implementation_imports
import 'dart:async';
import 'dart:math' as math;

// flutter_scene's physics BoxShape clashes with Flutter's painting BoxShape,
// and flutter_scene's Material clashes with the Flutter Material widget, so
// each conflicting name is hidden from the other import (as in the Physics
// example).
import 'package:flutter/material.dart' hide BoxShape;
import 'package:flutter_scene/scene.dart' hide Material;
import 'package:flutter_scene/src/geometry/primitives.dart' as prim;
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'environment_menu.dart';
import 'example_action_hint.dart';
import 'example_overlay.dart';
import 'example_panel.dart';
import 'example_settings.dart';
import 'quake_camera.dart';

/// A shapes playground. Pick a primitive and tune its dimensions, watch a
/// wireframe preview, then click anywhere to drop one into the scene with a
/// matching physics collision hull. Drag to look and WASD/QE to fly the
/// camera. The bottom-left switches the image-based-lighting environment.
class ExampleShapes extends StatefulWidget {
  const ExampleShapes({super.key});

  @override
  State<ExampleShapes> createState() => _ExampleShapesState();
}

/// The primitives offered for spawning. Only shapes with an analytic
/// collision hull are listed, so every spawn gets a proper physics body.
enum _ShapeKind {
  box('Box'),
  sphere('Sphere'),
  icosphere('Icosphere'),
  cylinder('Cylinder'),
  cone('Cone'),
  capsule('Capsule'),
  torus('Torus'),
  disc('Disc'),
  ring('Ring'),
  wedge('Wedge');

  const _ShapeKind(this.label);
  final String label;
}

/// Mutable dimensions and tessellation for a shape. One instance is kept per
/// [_ShapeKind] so switching shapes preserves each one's settings.
class _ShapeParams {
  double radius = 0.5;
  double height = 1.0;
  double width = 1.0;
  double depth = 1.0;
  double run = 1.0;
  double tubeRadius = 0.2;
  double innerRadius = 0.3;
  double outerRadius = 0.6;
  int subdivisions = 2;
  int segments = 32; // sphere longitude; disc and ring wedges
  int rings = 16; // sphere latitude
  int radialSegments = 24; // cylinder/cone/capsule/torus, around
  int heightSegments = 1; // cylinder/cone, along Y
  int capRings = 8; // capsule hemisphere rings
  int tubularSegments = 16; // torus tube cross-section
}

class _ExampleShapesState extends State<ExampleShapes> {
  final Scene scene = Scene();
  late final PhysicsWorld world;

  final QuakeCamera _quakeCamera = QuakeCamera(
    position: vm.Vector3(0, 4, 11),
    pitch: -0.25,
  )..speed = 8.0;
  // Holds keyboard focus for the camera. Clicking the scene reclaims it from
  // any slider or dropdown that grabbed it, so WASD keeps working.
  final FocusNode _sceneFocus = FocusNode(debugLabel: 'shapes-scene');
  PerspectiveCamera? _camera;
  Size _viewSize = Size.zero;

  _ShapeKind _kind = _ShapeKind.box;
  final Map<_ShapeKind, _ShapeParams> _params = {
    for (final k in _ShapeKind.values) k: _ShapeParams(),
  };

  final EnvironmentSelector _environment = EnvironmentSelector();

  // The spinning wireframe preview lives in its own little scene. The node is
  // retained so a settings change can keep its current rotation.
  final Scene _previewScene = Scene();
  Node? _previewNode;

  // Spawned bodies, retired oldest-first past the cap so the playground
  // stays light.
  static const int _maxBodies = 60;
  final List<Node> _spawned = [];
  final math.Random _rng = math.Random(7);

  // Physics properties applied to the ground (live) and to newly spawned
  // bodies. Existing bodies keep the values they were dropped with.
  double _friction = 0.5;
  double _restitution = 0.2;
  double _density = 1.0;
  double _linearDamping = 0.0;
  double _angularDamping = 0.0;
  Collider? _groundCollider;

  PhysicsMaterial get _physicsMaterial => PhysicsMaterial(
    friction: _friction,
    restitution: _restitution,
    density: _density,
  );

  static final List<vm.Vector4> _palette = [
    vm.Vector4(0.91, 0.30, 0.35, 1),
    vm.Vector4(0.95, 0.61, 0.24, 1),
    vm.Vector4(0.96, 0.82, 0.25, 1),
    vm.Vector4(0.42, 0.74, 0.40, 1),
    vm.Vector4(0.30, 0.62, 0.86, 1),
    vm.Vector4(0.56, 0.42, 0.80, 1),
  ];

  @override
  void initState() {
    super.initState();
    world = PhysicsWorld(RapierWorld(gravity: vm.Vector3(0, -9.81, 0)));
    scene.root.addComponent(world);
    _buildGround();
    _rebuildPreview();
  }

  @override
  void dispose() {
    _sceneFocus.dispose();
    _environment.dispose();
    super.dispose();
  }

  // --- Scene construction ---------------------------------------------------

  void _buildGround() {
    final half = vm.Vector3(20, 0.5, 20);
    final material = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.55, 0.58, 0.62, 1)
      ..roughnessFactor = 0.9
      ..metallicFactor = 0.0;
    final node = Node(
      mesh: Mesh(CuboidGeometry(half * 2.0), material),
      localTransform: vm.Matrix4.translation(vm.Vector3(0, -0.5, 0)),
    );
    final collider = Collider(
      shape: BoxShape(halfExtents: half),
      material: _physicsMaterial,
    );
    node.addComponent(RigidBody(type: BodyType.fixed));
    node.addComponent(collider);
    scene.add(node);
    _groundCollider = collider;
  }

  /// The solid geometry plus its matching collision shape for [kind].
  ({Geometry geometry, Shape collisionShape}) _buildSolid(
    _ShapeKind kind,
    _ShapeParams p,
  ) {
    switch (kind) {
      case _ShapeKind.box:
        final g = CuboidGeometry(vm.Vector3(p.width, p.height, p.depth));
        return (geometry: g, collisionShape: g.collisionShape);
      case _ShapeKind.sphere:
        final g = SphereGeometry(
          radius: p.radius,
          segments: p.segments,
          rings: p.rings,
        );
        return (geometry: g, collisionShape: g.collisionShape);
      case _ShapeKind.icosphere:
        final g = IcosphereGeometry(
          radius: p.radius,
          subdivisions: p.subdivisions,
        );
        return (geometry: g, collisionShape: g.collisionShape);
      case _ShapeKind.cylinder:
        final g = CylinderGeometry(
          bottomRadius: p.radius,
          topRadius: p.radius,
          height: p.height,
          radialSegments: p.radialSegments,
          heightSegments: p.heightSegments,
        );
        return (geometry: g, collisionShape: g.collisionShape);
      case _ShapeKind.cone:
        final g = CylinderGeometry(
          bottomRadius: p.radius,
          topRadius: 0,
          height: p.height,
          radialSegments: p.radialSegments,
          heightSegments: p.heightSegments,
        );
        return (geometry: g, collisionShape: g.collisionShape);
      case _ShapeKind.capsule:
        final g = CapsuleGeometry(
          radius: p.radius,
          height: p.height,
          radialSegments: p.radialSegments,
          capRings: p.capRings,
        );
        return (geometry: g, collisionShape: g.collisionShape);
      case _ShapeKind.torus:
        final g = TorusGeometry(
          radius: p.radius,
          tubeRadius: p.tubeRadius,
          radialSegments: p.radialSegments,
          tubularSegments: p.tubularSegments,
        );
        return (geometry: g, collisionShape: g.collisionShape);
      case _ShapeKind.disc:
        final g = DiscGeometry(radius: p.radius, segments: p.segments);
        return (geometry: g, collisionShape: g.collisionShape);
      case _ShapeKind.ring:
        final g = RingGeometry(
          innerRadius: p.innerRadius,
          outerRadius: p.outerRadius,
          segments: p.segments,
        );
        return (geometry: g, collisionShape: g.collisionShape);
      case _ShapeKind.wedge:
        final g = WedgeGeometry(vm.Vector3(p.width, p.height, p.run));
        return (geometry: g, collisionShape: g.collisionShape);
    }
  }

  /// The procedural arrays for [kind] at the current tessellation, traced as
  /// a wireframe in the preview.
  prim.PrimitiveArrays _buildArrays(_ShapeKind kind, _ShapeParams p) {
    switch (kind) {
      case _ShapeKind.box:
        return prim.buildCuboidArrays(vm.Vector3(p.width, p.height, p.depth));
      case _ShapeKind.sphere:
        return prim.buildSphereArrays(
          radius: p.radius,
          segments: p.segments,
          rings: p.rings,
        );
      case _ShapeKind.icosphere:
        return prim.buildIcosphereArrays(
          radius: p.radius,
          subdivisions: p.subdivisions,
        );
      case _ShapeKind.cylinder:
        return prim.buildCylinderArrays(
          bottomRadius: p.radius,
          topRadius: p.radius,
          height: p.height,
          radialSegments: p.radialSegments,
          heightSegments: p.heightSegments,
          bottomCap: true,
          topCap: true,
        );
      case _ShapeKind.cone:
        return prim.buildCylinderArrays(
          bottomRadius: p.radius,
          topRadius: 0,
          height: p.height,
          radialSegments: p.radialSegments,
          heightSegments: p.heightSegments,
          bottomCap: true,
          topCap: true,
        );
      case _ShapeKind.capsule:
        return prim.buildCapsuleArrays(
          radius: p.radius,
          height: p.height,
          radialSegments: p.radialSegments,
          capRings: p.capRings,
        );
      case _ShapeKind.torus:
        return prim.buildTorusArrays(
          radius: p.radius,
          tubeRadius: p.tubeRadius,
          radialSegments: p.radialSegments,
          tubularSegments: p.tubularSegments,
        );
      case _ShapeKind.disc:
        return prim.buildDiscArrays(radius: p.radius, segments: p.segments);
      case _ShapeKind.ring:
        return prim.buildRingArrays(
          innerRadius: p.innerRadius,
          outerRadius: p.outerRadius,
          segments: p.segments,
        );
      case _ShapeKind.wedge:
        return prim.buildWedgeArrays(vm.Vector3(p.width, p.height, p.run));
    }
  }

  // A line-list geometry tracing every triangle edge, for the preview.
  MeshGeometry _wireframe(prim.PrimitiveArrays a) {
    final edges = <int>[];
    for (var t = 0; t + 2 < a.indices.length; t += 3) {
      final i0 = a.indices[t];
      final i1 = a.indices[t + 1];
      final i2 = a.indices[t + 2];
      edges
        ..addAll([i0, i1])
        ..addAll([i1, i2])
        ..addAll([i2, i0]);
    }
    return MeshGeometry.fromArrays(
      positions: a.positions,
      indices: edges,
      primitiveType: gpu.PrimitiveType.line,
    );
  }

  void _rebuildPreview() {
    // Carry the current rotation across the rebuild so tuning sliders does
    // not snap the preview back to its start pose.
    final previous = _previewNode?.localTransform.clone();
    _previewScene.removeAll();
    final wire = _wireframe(_buildArrays(_kind, _params[_kind]!));
    final material = UnlitMaterial()
      ..baseColorFactor = vm.Vector4(0.55, 0.9, 1.0, 1);
    final node = Node(mesh: Mesh(wire, material), localTransform: previous)
      ..addComponent(_SpinComponent(0.7));
    _previewNode = node;
    _previewScene.add(node);
  }

  // The bounding radius used to frame the preview camera.
  double _previewRadius(_ShapeKind kind, _ShapeParams p) {
    switch (kind) {
      case _ShapeKind.box:
        return vm.Vector3(p.width, p.height, p.depth).length / 2;
      case _ShapeKind.wedge:
        return vm.Vector3(p.width, p.height, p.run).length / 2;
      case _ShapeKind.sphere:
      case _ShapeKind.icosphere:
      case _ShapeKind.disc:
        return p.radius;
      case _ShapeKind.cylinder:
      case _ShapeKind.cone:
        return math.max(p.radius, p.height / 2);
      case _ShapeKind.capsule:
        return p.radius + p.height / 2;
      case _ShapeKind.torus:
        return p.radius + p.tubeRadius;
      case _ShapeKind.ring:
        return p.outerRadius;
    }
  }

  // --- Interaction ----------------------------------------------------------

  void _onTick(Duration elapsed, double deltaSeconds) {
    // Step physics and per-frame components with the clamped ticker delta;
    // render then skips its implicit tick.
    scene.update(deltaSeconds.clamp(0.0, 0.05));
    exampleSettings.applyTo(scene);
  }

  // Drops the selected shape from above wherever the click ray meets the
  // scene (existing geometry or the ground plane).
  void _spawnAt(Offset screenPosition) {
    final camera = _camera;
    if (camera == null || _viewSize.isEmpty) return;
    final ray = camera.screenPointToRay(screenPosition, _viewSize);
    final hit = scene.raycast(ray);
    final target = hit?.worldPoint ?? _intersectGround(ray);
    if (target == null) return;
    _spawn(
      _kind,
      _params[_kind]!,
      vm.Vector3(target.x, target.y + 6.0, target.z),
    );
  }

  // Intersects [ray] with the y = 0 ground plane, or null if it points away.
  vm.Vector3? _intersectGround(vm.Ray ray) {
    final dirY = ray.direction.y;
    if (dirY.abs() < 1e-6) return null;
    final t = -ray.origin.y / dirY;
    if (t < 0) return null;
    return ray.origin + ray.direction.scaled(t);
  }

  // Disc and ring are flat (two-dimensional), so they need double-sided
  // rendering to be visible from below.
  bool _isFlat(_ShapeKind kind) =>
      kind == _ShapeKind.disc || kind == _ShapeKind.ring;

  void _spawn(_ShapeKind kind, _ShapeParams p, vm.Vector3 position) {
    final solid = _buildSolid(kind, p);
    final material = PhysicallyBasedMaterial()
      ..baseColorFactor = _palette[_rng.nextInt(_palette.length)]
      ..roughnessFactor = 0.45
      ..metallicFactor = 0.05
      // Flat shapes have no back, so render both faces to avoid a
      // disappearing underside as they tumble.
      ..doubleSided = _isFlat(kind);
    final rotation = vm.Quaternion.euler(
      _rng.nextDouble() * math.pi * 2,
      _rng.nextDouble() * math.pi * 2,
      _rng.nextDouble() * math.pi * 2,
    );
    final node = Node(
      mesh: Mesh(solid.geometry, material),
      localTransform: vm.Matrix4.compose(
        position,
        rotation,
        vm.Vector3.all(1.0),
      ),
    );
    // No explicit mass, so the material density derives it from the shape.
    node.addComponent(
      RigidBody(
        type: BodyType.dynamic_,
        linearDamping: _linearDamping,
        angularDamping: _angularDamping,
      ),
    );
    node.addComponent(
      Collider(shape: solid.collisionShape, material: _physicsMaterial),
    );
    scene.add(node);
    _spawned.add(node);
    if (_spawned.length > _maxBodies) {
      scene.remove(_spawned.removeAt(0));
    }
    setState(() {});
  }

  void _clear() {
    setState(() {
      for (final node in _spawned) {
        scene.remove(node);
      }
      _spawned.clear();
    });
  }

  Future<void> _selectEnvironment(ExampleEnvironment environment) async {
    try {
      await _environment.select(environment, scene);
    } catch (_) {
      // Ignore download/decode failures in the demo; the previous
      // environment stays active.
    }
  }

  // --- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    return Stack(
      children: [
        Positioned.fill(
          child: Focus(
            focusNode: _sceneFocus,
            autofocus: true,
            onKeyEvent: _quakeCamera.onKeyEvent,
            child: Listener(
              // Any press on the scene reclaims keyboard focus from a slider
              // or dropdown so the camera keys keep working.
              onPointerDown: (_) => _sceneFocus.requestFocus(),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // A tap (press and release without a drag) drops a shape; the
                // gesture arena routes a drag to the camera look instead.
                onTapUp: (details) => _spawnAt(details.localPosition),
                onPanUpdate: (details) => _quakeCamera.look(details.delta),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    _viewSize = constraints.biggest;
                    return SceneView(
                      scene,
                      cameraBuilder: (elapsed) {
                        _quakeCamera.move(elapsed.inMicroseconds / 1e6);
                        return _camera = _quakeCamera.camera;
                      },
                      onTick: _onTick,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        // On wide screens the preview gets the free bottom-center slot. On
        // narrow ones that slot is covered by the paired side panels, so the
        // preview stacks under the hint row in the top slot instead.
        ExampleOverlay.topCenterAction(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ExampleActionHint(
                    message: 'Tap: drop  ·  Drag: look  ·  WASD/QE: move',
                  ),
                  const SizedBox(width: 8),
                  ExampleActionButton(
                    tooltip: 'Clear dropped shapes',
                    onPressed: _spawned.isEmpty ? null : _clear,
                    icon: Icons.delete_outline,
                  ),
                ],
              ),
              if (!wide) ...[const SizedBox(height: 8), _previewPanel()],
            ],
          ),
        ),
        if (wide) ExampleOverlay.bottomCenter(child: _previewPanel()),
        ExampleOverlay.bottomRightPanel(
          paired: true,
          child: SizedBox(width: double.infinity, child: _controlPanel()),
        ),
        ExampleOverlay.bottomLeftPanel(
          paired: true,
          child: SizedBox(
            width: double.infinity,
            child: _physicsEnvironmentControls(),
          ),
        ),
      ],
    );
  }

  Widget _physicsEnvironmentControls() {
    return ExamplePanelCard(
      icon: Icons.tune,
      title: 'Physics & environment',
      width: double.infinity,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _physicsPanel(),
          const Divider(height: 20, color: Colors.white24),
          _environmentPanel(),
        ],
      ),
    );
  }

  Widget _controlPanel() {
    return ExamplePanelCard(
      icon: Icons.category_outlined,
      title: 'Shape',
      width: double.infinity,
      maxBodyHeight: 280,
      trailing: ExampleDropdown<_ShapeKind>(
        value: _kind,
        triggerColor: Colors.white12,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        isDense: true,
        onChanged: (kind) {
          if (kind != null) {
            setState(() {
              _kind = kind;
              _rebuildPreview();
            });
          }
        },
        items: [
          for (final kind in _ShapeKind.values)
            DropdownMenuItem(value: kind, child: Text(kind.label)),
        ],
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [..._buildSliders()],
      ),
    );
  }

  List<Widget> _buildSliders() {
    final p = _params[_kind]!;
    ValueChanged<double> set(void Function(double) apply) => (v) {
      setState(() {
        apply(v);
        _rebuildPreview();
      });
    };
    Widget dim(
      String label,
      double value,
      double min,
      double max,
      void Function(double) apply,
    ) => _slider(label, value, min, max, set(apply));
    Widget count(
      String label,
      int value,
      int min,
      int max,
      void Function(int) apply,
    ) => _slider(
      label,
      value.toDouble(),
      min.toDouble(),
      max.toDouble(),
      set((v) => apply(v.round())),
      divisions: max - min,
    );

    switch (_kind) {
      case _ShapeKind.box:
        return [
          dim('Width', p.width, 0.3, 3, (v) => p.width = v),
          dim('Height', p.height, 0.3, 3, (v) => p.height = v),
          dim('Depth', p.depth, 0.3, 3, (v) => p.depth = v),
        ];
      case _ShapeKind.sphere:
        return [
          dim('Radius', p.radius, 0.25, 2, (v) => p.radius = v),
          count('Segments', p.segments, 3, 48, (v) => p.segments = v),
          count('Rings', p.rings, 2, 32, (v) => p.rings = v),
        ];
      case _ShapeKind.icosphere:
        return [
          dim('Radius', p.radius, 0.25, 2, (v) => p.radius = v),
          count('Subdiv', p.subdivisions, 0, 4, (v) => p.subdivisions = v),
        ];
      case _ShapeKind.cylinder:
      case _ShapeKind.cone:
        return [
          dim('Radius', p.radius, 0.25, 2, (v) => p.radius = v),
          dim('Height', p.height, 0.3, 3, (v) => p.height = v),
          count('Radial', p.radialSegments, 3, 48, (v) => p.radialSegments = v),
          count(
            'Height seg',
            p.heightSegments,
            1,
            6,
            (v) => p.heightSegments = v,
          ),
        ];
      case _ShapeKind.capsule:
        return [
          dim('Radius', p.radius, 0.25, 1.2, (v) => p.radius = v),
          dim('Height', p.height, 0.2, 3, (v) => p.height = v),
          count('Radial', p.radialSegments, 3, 48, (v) => p.radialSegments = v),
          count('Cap rings', p.capRings, 1, 16, (v) => p.capRings = v),
        ];
      case _ShapeKind.torus:
        return [
          dim('Radius', p.radius, 0.3, 2, (v) => p.radius = v),
          dim('Tube', p.tubeRadius, 0.05, 0.8, (v) => p.tubeRadius = v),
          count('Radial', p.radialSegments, 3, 48, (v) => p.radialSegments = v),
          count(
            'Tubular',
            p.tubularSegments,
            3,
            24,
            (v) => p.tubularSegments = v,
          ),
        ];
      case _ShapeKind.disc:
        return [
          dim('Radius', p.radius, 0.25, 2, (v) => p.radius = v),
          count('Segments', p.segments, 3, 64, (v) => p.segments = v),
        ];
      case _ShapeKind.ring:
        return [
          dim(
            'Inner',
            p.innerRadius,
            0.05,
            1.4,
            (v) => p.innerRadius = math.min(v, p.outerRadius - 0.05),
          ),
          dim(
            'Outer',
            p.outerRadius,
            0.1,
            1.5,
            (v) => p.outerRadius = math.max(v, p.innerRadius + 0.05),
          ),
          count('Segments', p.segments, 3, 64, (v) => p.segments = v),
        ];
      case _ShapeKind.wedge:
        return [
          dim('Width', p.width, 0.3, 3, (v) => p.width = v),
          dim('Height', p.height, 0.3, 3, (v) => p.height = v),
          dim('Run', p.run, 0.3, 3, (v) => p.run = v),
        ];
    }
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged, {
    int? divisions,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 32,
          child: Text(
            value.toStringAsFixed(divisions == null ? 2 : 0),
            style: const TextStyle(color: Colors.white70, fontSize: 11),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _physicsPanel() {
    // Changing a property updates the ground collider live; new spawns pick
    // up the values at drop time.
    ValueChanged<double> set(void Function(double) apply) => (v) {
      setState(() {
        apply(v);
        _groundCollider?.material = _physicsMaterial;
      });
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Physics',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 4),
        _slider('Friction', _friction, 0, 1, set((v) => _friction = v)),
        _slider('Bounce', _restitution, 0, 1, set((v) => _restitution = v)),
        _slider('Density', _density, 0.1, 5, set((v) => _density = v)),
        _slider(
          'Lin damp',
          _linearDamping,
          0,
          2,
          set((v) => _linearDamping = v),
        ),
        _slider(
          'Ang damp',
          _angularDamping,
          0,
          2,
          set((v) => _angularDamping = v),
        ),
      ],
    );
  }

  Widget _environmentPanel() {
    return AnimatedBuilder(
      animation: _environment,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Environment',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 4),
          EnvironmentMenu(
            active: _environment.active,
            loading: _environment.loading,
            onSelected: (env) => unawaited(_selectEnvironment(env)),
          ),
        ],
      ),
    );
  }

  Widget _previewPanel() {
    return Card(
      color: Colors.black54,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Preview',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 2),
            SizedBox(
              width: 118,
              height: 118,
              child: SceneView(
                _previewScene,
                cameraBuilder: (elapsed) {
                  final r = _previewRadius(_kind, _params[_kind]!);
                  final distance = r * 3.4 + 0.6;
                  return PerspectiveCamera(
                    position: vm.Vector3(0, r * 0.4, distance),
                    target: vm.Vector3(0, 0, 0),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Spins the preview node around Y so every face is visible.
class _SpinComponent extends Component {
  _SpinComponent(this.radiansPerSecond);

  final double radiansPerSecond;

  @override
  void update(double deltaSeconds) {
    node.localTransform =
        node.localTransform *
        vm.Matrix4.rotationY(radiansPerSecond * deltaSeconds);
  }
}
