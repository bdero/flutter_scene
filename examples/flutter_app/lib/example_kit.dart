import 'dart:math' as math;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter/services.dart';
import 'package:flutter_scene/kit.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_action_hint.dart';
import 'example_overlay.dart';
import 'example_panel.dart';
import 'kit/kit_controls.dart';

enum _KitScenario {
  characterCamera('Character & Camera'),
  dayNight('Day & Night'),
  waterBuoyancy('Water & Buoyancy'),
  flocking('NPC Flocking'),
  spawnerPooling('Spawner & Pooling'),
  debugVisuals('Debug Visualizer');

  const _KitScenario(this.label);
  final String label;
}

class ExampleKit extends StatefulWidget {
  const ExampleKit({super.key});

  @override
  State<ExampleKit> createState() => _ExampleKitState();
}

class _ExampleKitState extends State<ExampleKit> {
  _KitScenario _scenario = _KitScenario.characterCamera;
  final KitDemoSettings _settings = KitDemoSettings();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: _KitStage(
            key: ValueKey(_scenario),
            scenario: _scenario,
            settings: _settings,
            onSettingsChanged: () => setState(() {}),
          ),
        ),
        ExampleOverlay.topLeft(
          child: SizedBox(
            width: 200,
            child: ExampleDropdown<_KitScenario>(
              value: _scenario,
              items: [
                for (final s in _KitScenario.values)
                  DropdownMenuItem(value: s, child: Text(s.label)),
              ],
              onChanged: (scenario) {
                if (scenario == null || scenario == _scenario) return;
                setState(() {
                  _scenario = scenario;
                });
              },
            ),
          ),
        ),
        ExampleOverlay.bottomLeftPanel(
          child: _KitScenarioPanel(
            scenario: _scenario,
            settings: _settings,
            onChanged: () => setState(() {}),
          ),
        ),
      ],
    );
  }
}

class _KitScenarioPanel extends StatelessWidget {
  const _KitScenarioPanel({
    required this.scenario,
    required this.settings,
    required this.onChanged,
  });

  final _KitScenario scenario;
  final KitDemoSettings settings;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return ExamplePanelCard(
      icon: Icons.sports_esports,
      title: scenario.label,
      maxBodyHeight: 400,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [..._buildControls(context)],
      ),
    );
  }

  List<Widget> _buildControls(BuildContext context) {
    switch (scenario) {
      case _KitScenario.characterCamera:
        return [
          const KitSectionHeader('Character'),
          KitSliderRow(
            label: 'Walk speed',
            value: settings.walkSpeed,
            min: 2.0,
            max: 12.0,
            onChanged: (v) {
              settings.walkSpeed = v;
              onChanged();
            },
          ),
          KitSliderRow(
            label: 'Jump power',
            value: settings.jumpVelocity,
            min: 3.0,
            max: 15.0,
            onChanged: (v) {
              settings.jumpVelocity = v;
              onChanged();
            },
          ),
          const KitSectionHeader('Camera Boom'),
          KitSliderRow(
            label: 'Arm length',
            value: settings.armLength,
            min: 2.0,
            max: 10.0,
            onChanged: (v) {
              settings.armLength = v;
              onChanged();
            },
          ),
          KitSliderRow(
            label: 'Lag speed',
            value: settings.lagSpeed,
            min: 1.0,
            max: 20.0,
            onChanged: (v) {
              settings.lagSpeed = v;
              onChanged();
            },
          ),
          const SizedBox(height: 8),
          const Text(
            'Use WASD / Arrow keys and Space to jump, or the on-screen joystick.',
            style: TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ];

      case _KitScenario.dayNight:
        return [
          const KitSectionHeader('Time of Day'),
          KitSliderRow(
            label: 'Time',
            value: settings.timeOfDay,
            min: 0.0,
            max: 24.0,
            suffix: 'h',
            onChanged: (v) {
              settings.timeOfDay = v;
              onChanged();
            },
          ),
          KitSliderRow(
            label: 'Cycle speed',
            value: settings.timeSpeed,
            min: 0.0,
            max: 4.0,
            onChanged: (v) {
              settings.timeSpeed = v;
              onChanged();
            },
          ),
          KitSliderRow(
            label: 'Latitude',
            value: settings.latitude,
            min: -90.0,
            max: 90.0,
            suffix: '°',
            onChanged: (v) {
              settings.latitude = v;
              onChanged();
            },
          ),
        ];

      case _KitScenario.waterBuoyancy:
        return [
          const KitSectionHeader('Wave Simulation'),
          KitSliderRow(
            label: 'Amplitude',
            value: settings.waveAmplitude,
            min: 0.1,
            max: 1.2,
            onChanged: (v) {
              settings.waveAmplitude = v;
              onChanged();
            },
          ),
          KitSliderRow(
            label: 'Speed',
            value: settings.waveSpeed,
            min: 0.2,
            max: 3.0,
            onChanged: (v) {
              settings.waveSpeed = v;
              onChanged();
            },
          ),
          KitSliderRow(
            label: 'Steepness',
            value: settings.waveSteepness,
            min: 0.1,
            max: 1.0,
            onChanged: (v) {
              settings.waveSteepness = v;
              onChanged();
            },
          ),
        ];

      case _KitScenario.flocking:
        return [
          const KitSectionHeader('Flock Parameters'),
          KitSliderRow(
            label: 'Separation',
            value: settings.separationDistance,
            min: 0.5,
            max: 4.0,
            onChanged: (v) {
              settings.separationDistance = v;
              onChanged();
            },
          ),
          KitSliderRow(
            label: 'Max speed',
            value: settings.maxSteerSpeed,
            min: 2.0,
            max: 12.0,
            onChanged: (v) {
              settings.maxSteerSpeed = v;
              onChanged();
            },
          ),
        ];

      case _KitScenario.spawnerPooling:
        return [
          const KitSectionHeader('Poisson-Disc Distribution'),
          KitSliderRow(
            label: 'Min distance',
            value: settings.minDistance,
            min: 1.0,
            max: 6.0,
            onChanged: (v) {
              settings.minDistance = v;
              onChanged();
            },
          ),
        ];

      case _KitScenario.debugVisuals:
        return [
          const KitSectionHeader('Debug Shapes'),
          const Text(
            'Demonstrates immediate-mode DebugDraw wireframes (lines, rays, boxes, spheres, axes) and real-time PerformanceOverlay3d.',
            style: TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ];
    }
  }
}

class _KitStage extends StatefulWidget {
  const _KitStage({
    super.key,
    required this.scenario,
    required this.settings,
    required this.onSettingsChanged,
  });

  final _KitScenario scenario;
  final KitDemoSettings settings;
  final VoidCallback onSettingsChanged;

  @override
  State<_KitStage> createState() => _KitStageState();
}

class _KitStageState extends State<_KitStage> {
  final Scene scene = Scene();
  final Node _cameraNode = Node();
  late final NodeCamera _nodeCamera;
  final Node _debugMeshNode = Node();

  // Character scenario
  Node? _characterNode;
  ThirdPersonControllerComponent? _characterController;
  SpringArmComponent? _springArm;
  final CameraShake _shake = CameraShake();

  // Day/Night scenario
  Node? _sunLightNode;
  DayNightCycleComponent? _dayNight;

  // Water scenario
  WaterSurfaceComponent? _water;
  final List<Node> _floatingProps = [];

  // Flocking scenario
  final List<Node> _boidNodes = [];
  final List<vm.Vector3> _boidVelocities = [];

  // Pooling scenario
  NodePool? _bulletPool;
  final List<Node> _scatteredProps = [];

  double _elapsed = 0.0;
  final Set<LogicalKeyboardKey> _pressedKeys = {};

  @override
  void initState() {
    super.initState();
    _nodeCamera = NodeCamera(
      _cameraNode,
      PerspectiveCamera(fovRadiansY: 1.0).projection,
    );
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _buildScene();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    scene.removeAll();
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      _pressedKeys.add(event.logicalKey);
    } else if (event is KeyUpEvent) {
      _pressedKeys.remove(event.logicalKey);
    }
    return false;
  }

  void _buildScene() {
    scene.removeAll();
    scene.add(_cameraNode);
    scene.add(_debugMeshNode);

    // Add ambient default lighting
    final keyLight = DirectionalLight()
      ..color = vm.Vector3(1.0, 0.98, 0.95)
      ..intensity = 40000.0;
    final keyLightNode = Node()
      ..addComponent(DirectionalLightComponent(keyLight));
    keyLightNode.localTransform = vm.Matrix4.identity()
      ..setTranslation(vm.Vector3(10, 20, 10));
    scene.add(keyLightNode);

    switch (widget.scenario) {
      case _KitScenario.characterCamera:
        _buildCharacterCamera();
      case _KitScenario.dayNight:
        _buildDayNight();
      case _KitScenario.waterBuoyancy:
        _buildWaterBuoyancy();
      case _KitScenario.flocking:
        _buildFlocking();
      case _KitScenario.spawnerPooling:
        _buildSpawnerPooling();
      case _KitScenario.debugVisuals:
        _buildDebugVisuals();
    }
  }

  void _buildCharacterCamera() {
    // Ground plane
    final groundMesh = PlaneGeometry(width: 40, depth: 40);
    final groundNode = Node(
      mesh: Mesh(
        groundMesh,
        PhysicallyBasedMaterial()
          ..baseColorFactor = vm.Vector4(0.25, 0.28, 0.32, 1.0)
          ..roughnessFactor = 0.8,
      ),
    )..position = vm.Vector3.zero();
    scene.add(groundNode);

    // Obstacle blocks for collision and occlusion testing
    final boxGeo = CuboidGeometry(vm.Vector3(3, 2.5, 3));
    final wallMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.6, 0.3, 0.2, 1.0)
      ..roughnessFactor = 0.6;
    for (final pos in [
      vm.Vector3(6, 1.25, 6),
      vm.Vector3(-6, 1.25, -6),
      vm.Vector3(-8, 1.25, 4),
      vm.Vector3(0, 1.25, -10),
    ]) {
      scene.add(Node(mesh: Mesh(boxGeo, wallMat))..position = pos);
    }

    // Player character
    final charGeo = CuboidGeometry(vm.Vector3(0.8, 1.8, 0.8));
    final charMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.2, 0.7, 0.9, 1.0)
      ..roughnessFactor = 0.3;
    _characterNode = Node(mesh: Mesh(charGeo, charMat))
      ..position = vm.Vector3(0, 0.9, 0);

    _characterController = ThirdPersonControllerComponent(
      walkSpeed: widget.settings.walkSpeed,
      jumpVelocity: widget.settings.jumpVelocity,
      groundPlaneHeight: 0.0,
    );
    _characterNode!.addComponent(_characterController!);

    _springArm = SpringArmComponent(
      targetLength: widget.settings.armLength,
      targetOffset: vm.Vector3(0, 1.4, 0),
      socketOffset: vm.Vector3(0.4, 0, 0),
      enablePositionLag: widget.settings.enableLag,
      positionLagSpeed: widget.settings.lagSpeed,
      enableRotationLag: widget.settings.enableLag,
      rotationLagSpeed: widget.settings.lagSpeed,
      cameraNode: _cameraNode,
    );
    _characterNode!.addComponent(_springArm!);

    scene.add(_characterNode!);
  }

  void _buildDayNight() {
    // Ground plane
    final groundMesh = PlaneGeometry(width: 50, depth: 50);
    scene.add(
      Node(
        mesh: Mesh(
          groundMesh,
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.3, 0.32, 0.28, 1.0)
            ..roughnessFactor = 0.9,
        ),
      ),
    );

    // Monoliths casting shadows
    final pillarGeo = CuboidGeometry(vm.Vector3(1.2, 6.0, 1.2));
    final pillarMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.8, 0.78, 0.72, 1.0)
      ..roughnessFactor = 0.4;

    for (var i = 0; i < 6; i++) {
      final angle = (i / 6.0) * 2 * math.pi;
      final x = math.cos(angle) * 8.0;
      final z = math.sin(angle) * 8.0;
      scene.add(
        Node(mesh: Mesh(pillarGeo, pillarMat))
          ..position = vm.Vector3(x, 3.0, z),
      );
    }

    final sunLight = DirectionalLight();
    _sunLightNode = Node()..addComponent(DirectionalLightComponent(sunLight));
    scene.add(_sunLightNode!);

    _dayNight = DayNightCycleComponent(
      timeOfDay: widget.settings.timeOfDay,
      timeSpeed: widget.settings.timeSpeed,
      latitude: widget.settings.latitude,
      sunLightNode: _sunLightNode,
    );
    scene.root.addComponent(_dayNight!);

    _cameraNode.localTransform = BoundsFraming.computeFramingTransform(
      vm.Aabb3.minMax(vm.Vector3(-12, 0, -12), vm.Vector3(12, 6, 12)),
      PerspectiveCamera(fovRadiansY: 1.0),
      viewDirection: vm.Vector3(0.7, 0.5, 0.7),
      paddingFactor: 1.4,
    );
  }

  void _buildWaterBuoyancy() {
    _water = WaterSurfaceComponent();
    _floatingProps.clear();

    final buoyGeo = CuboidGeometry(vm.Vector3(1.2, 1.2, 1.2));
    final buoyMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(1.0, 0.4, 0.1, 1.0)
      ..roughnessFactor = 0.2;

    for (var x = -8; x <= 8; x += 4) {
      for (var z = -8; z <= 8; z += 4) {
        final node = Node(mesh: Mesh(buoyGeo, buoyMat))
          ..position = vm.Vector3(x.toDouble(), 0, z.toDouble())
          ..addComponent(
            FloatingMotionComponent(
              hoverAmplitude: 0.3,
              hoverFrequency: 0.8,
              spinSpeed: 0.5,
            ),
          );
        _floatingProps.add(node);
        scene.add(node);
      }
    }

    _cameraNode.localTransform = BoundsFraming.computeFramingTransform(
      vm.Aabb3.minMax(vm.Vector3(-10, -2, -10), vm.Vector3(10, 4, 10)),
      PerspectiveCamera(fovRadiansY: 1.0),
      viewDirection: vm.Vector3(0.5, 0.6, 0.8),
    );
  }

  void _buildFlocking() {
    _boidNodes.clear();
    _boidVelocities.clear();

    final boidGeo = CuboidGeometry(vm.Vector3(0.4, 0.4, 1.0));
    final boidMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.3, 0.9, 0.5, 1.0)
      ..roughnessFactor = 0.4;

    final rng = math.Random(42);
    for (var i = 0; i < 24; i++) {
      final pos = vm.Vector3(
        (rng.nextDouble() - 0.5) * 16.0,
        rng.nextDouble() * 8.0 + 2.0,
        (rng.nextDouble() - 0.5) * 16.0,
      );
      final node = Node(mesh: Mesh(boidGeo, boidMat))..position = pos;
      _boidNodes.add(node);
      _boidVelocities.add(
        vm.Vector3(
          (rng.nextDouble() - 0.5) * 2.0,
          (rng.nextDouble() - 0.5) * 2.0,
          (rng.nextDouble() - 0.5) * 2.0,
        ),
      );
      scene.add(node);
    }

    _cameraNode.localTransform = BoundsFraming.computeFramingTransform(
      vm.Aabb3.minMax(vm.Vector3(-12, 0, -12), vm.Vector3(12, 10, 12)),
      PerspectiveCamera(fovRadiansY: 1.0),
      viewDirection: vm.Vector3(0.6, 0.6, 0.6),
    );
  }

  void _buildSpawnerPooling() {
    _scatteredProps.clear();

    // 1. Procedural tree/rock scattering using PoissonDiscSampler
    final groundMesh = PlaneGeometry(width: 30, depth: 30);
    scene.add(
      Node(
        mesh: Mesh(
          groundMesh,
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.2, 0.3, 0.22, 1.0)
            ..roughnessFactor = 0.9,
        ),
      ),
    );

    final points = PoissonDiscSampler.sampleRect(
      28.0,
      28.0,
      widget.settings.minDistance,
      seed: 777,
    );
    final treeGeo = CuboidGeometry(vm.Vector3(0.8, 3.5, 0.8));
    final treeMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.15, 0.6, 0.25, 1.0)
      ..roughnessFactor = 0.5;

    for (final pt in points) {
      final x = pt.x - 14.0;
      final z = pt.y - 14.0;
      final prop = Node(mesh: Mesh(treeGeo, treeMat))
        ..position = vm.Vector3(x, 1.75, z);
      _scatteredProps.add(prop);
      scene.add(prop);
    }

    // 2. NodePool for zero-GC particles/bullets
    final bulletGeo = CuboidGeometry(vm.Vector3(0.3, 0.3, 0.3));
    final bulletMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(1.0, 0.9, 0.2, 1.0)
      ..roughnessFactor = 0.1;

    _bulletPool = NodePool(
      () => Node(mesh: Mesh(bulletGeo, bulletMat)),
      initialSize: 16,
      maxSize: widget.settings.poolMaxSize,
    );

    _cameraNode.localTransform = BoundsFraming.computeFramingTransform(
      vm.Aabb3.minMax(vm.Vector3(-14, 0, -14), vm.Vector3(14, 6, 14)),
      PerspectiveCamera(fovRadiansY: 1.0),
      viewDirection: vm.Vector3(0.7, 0.5, 0.7),
      paddingFactor: 1.3,
    );
  }

  void _buildDebugVisuals() {
    final groundMesh = PlaneGeometry(width: 20, depth: 20);
    scene.add(
      Node(
        mesh: Mesh(
          groundMesh,
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.15, 0.15, 0.18, 1.0)
            ..roughnessFactor = 0.9,
        ),
      ),
    );

    _cameraNode.localTransform = BoundsFraming.computeFramingTransform(
      vm.Aabb3.minMax(vm.Vector3(-8, 0, -8), vm.Vector3(8, 6, 8)),
      PerspectiveCamera(fovRadiansY: 1.0),
      viewDirection: vm.Vector3(0.6, 0.5, 0.8),
    );
  }

  void _tick(Duration elapsedDuration, double dt) {
    _elapsed += dt;

    switch (widget.scenario) {
      case _KitScenario.characterCamera:
        _tickCharacter(dt);
      case _KitScenario.dayNight:
        _tickDayNight(dt);
      case _KitScenario.waterBuoyancy:
        _tickWater(dt);
      case _KitScenario.flocking:
        _tickFlocking(dt);
      case _KitScenario.spawnerPooling:
        _tickSpawnerPooling(dt);
      case _KitScenario.debugVisuals:
        _tickDebugVisuals(dt);
    }
  }

  void _tickCharacter(double dt) {
    if (_characterController == null || _characterNode == null) return;

    // Keyboard movement input
    var mx = 0.0;
    var my = 0.0;
    if (_pressedKeys.contains(LogicalKeyboardKey.keyW) ||
        _pressedKeys.contains(LogicalKeyboardKey.arrowUp)) {
      my += 1.0;
    }
    if (_pressedKeys.contains(LogicalKeyboardKey.keyS) ||
        _pressedKeys.contains(LogicalKeyboardKey.arrowDown)) {
      my -= 1.0;
    }
    if (_pressedKeys.contains(LogicalKeyboardKey.keyD) ||
        _pressedKeys.contains(LogicalKeyboardKey.arrowRight)) {
      mx += 1.0;
    }
    if (_pressedKeys.contains(LogicalKeyboardKey.keyA) ||
        _pressedKeys.contains(LogicalKeyboardKey.arrowLeft)) {
      mx -= 1.0;
    }

    final isSprinting = _pressedKeys.contains(LogicalKeyboardKey.shiftLeft);
    _characterController!.setMoveInput(
      vm.Vector2(mx, my),
      isRunning: isSprinting,
    );

    if (_pressedKeys.contains(LogicalKeyboardKey.space)) {
      _characterController!.jump();
    }

    _characterController!.walkSpeed = widget.settings.walkSpeed;
    _characterController!.jumpVelocity = widget.settings.jumpVelocity;

    if (_springArm != null) {
      _springArm!.targetLength = widget.settings.armLength;
      _springArm!.enablePositionLag = widget.settings.enableLag;
      _springArm!.positionLagSpeed = widget.settings.lagSpeed;
      _springArm!.enableRotationLag = widget.settings.enableLag;
      _springArm!.rotationLagSpeed = widget.settings.lagSpeed;
    }

    // Apply trauma shake offset to camera
    final shakeOffset = _shake.update(dt);
    if (shakeOffset.translation.length2 > 0) {
      _cameraNode.localTransform =
          _cameraNode.localTransform * shakeOffset.toMatrix4();
    }
  }

  void _tickDayNight(double dt) {
    if (_dayNight == null) return;
    _dayNight!.timeSpeed = widget.settings.timeSpeed;
    _dayNight!.latitude = widget.settings.latitude;
    _dayNight!.timeOfDay = widget.settings.timeOfDay;
  }

  void _tickWater(double dt) {
    if (_water == null) return;
    for (final prop in _floatingProps) {
      final surface = _water!.evaluateAt(
        vm.Vector2(prop.position.x, prop.position.z),
      );
      prop.position.y = surface.displacement.y;
    }
  }

  void _tickFlocking(double dt) {
    if (_boidNodes.isEmpty) return;

    final targetPos = vm.Vector3(
      math.sin(_elapsed * 0.8) * 8.0,
      4.0 + math.cos(_elapsed * 1.2) * 2.0,
      math.cos(_elapsed * 0.8) * 8.0,
    );

    final positions = _boidNodes.map((n) => n.position).toList();

    for (var i = 0; i < _boidNodes.length; i++) {
      final node = _boidNodes[i];
      var vel = _boidVelocities[i];

      final seekForce = Steering.seek(
        node.position,
        vel,
        targetPos,
        maxSpeed: widget.settings.maxSteerSpeed,
      );
      final sepForce = Steering.separation(
        node.position,
        vel,
        positions,
        desiredDistance: widget.settings.separationDistance,
      );
      final cohForce = Steering.cohesion(node.position, vel, positions);
      final aliForce = Steering.alignment(vel, _boidVelocities);

      final totalForce =
          seekForce * 1.0 + sepForce * 2.5 + cohForce * 0.6 + aliForce * 0.8;
      vel = (vel + totalForce * dt);
      if (vel.length > widget.settings.maxSteerSpeed) {
        vel = vel.normalized() * widget.settings.maxSteerSpeed;
      }
      _boidVelocities[i] = vel;

      node.position += vel * dt;
      if (vel.length2 > 0.01) {
        final yaw = math.atan2(vel.x, vel.z);
        node.localTransform = vm.Matrix4.compose(
          node.position,
          vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), yaw),
          vm.Vector3.all(1.0),
        );
      }
    }
  }

  void _tickSpawnerPooling(double dt) {
    if (_bulletPool == null) return;
    // Auto-fire periodic bursts for visualization
    if ((_elapsed * 10).floor() % 12 == 0 && _bulletPool!.activeCount < 40) {
      final rng = math.Random();
      final node = _bulletPool!.spawn(
        parent: scene.root,
        transform: vm.Matrix4.translation(
          vm.Vector3(
            (rng.nextDouble() - 0.5) * 10.0,
            0.5,
            (rng.nextDouble() - 0.5) * 10.0,
          ),
        ),
      );
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) _bulletPool?.despawn(node);
      });
    }
  }

  void _tickDebugVisuals(double dt) {
    DebugDraw.clear();

    // Draw animated axes
    final centerMat = vm.Matrix4.identity()
      ..setTranslation(vm.Vector3(0, 2.0, 0))
      ..rotateY(_elapsed);
    DebugDraw.axes(centerMat, size: 2.5);

    // Draw wireframe bounds
    DebugDraw.box(
      vm.Aabb3.minMax(vm.Vector3(-4, 0, -4), vm.Vector3(4, 3.5, 4)),
      color: vm.Vector4(0.2, 0.8, 1.0, 0.8),
    );

    // Draw pulsating sphere
    final radius = 1.5 + math.sin(_elapsed * 2.0) * 0.4;
    DebugDraw.sphere(
      vm.Vector3(0, 2.0, 0),
      radius,
      color: vm.Vector4(1.0, 0.8, 0.2, 0.7),
    );

    // Flush to mesh
    final mesh = DebugDraw.flushMesh();
    if (mesh != null) {
      _debugMeshNode.mesh = Mesh(mesh, UnlitMaterial());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: SceneView(scene, camera: _nodeCamera, onTick: _tick),
        ),
        if (widget.scenario == _KitScenario.characterCamera)
          Positioned(
            right: 24,
            bottom: 24,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton.filled(
                  tooltip: 'Trigger Impact Camera Shake',
                  icon: const Icon(Icons.vibration),
                  onPressed: () => _shake.addTrauma(0.75),
                ),
                const SizedBox(width: 16),
                VirtualJoystick(
                  onChanged: (dir) {
                    // Joystick emits up as -Y in screen space; invert for 3D forward (+Y)
                    _characterController?.setMoveInput(
                      vm.Vector2(dir.x, -dir.y),
                    );
                  },
                ),
              ],
            ),
          ),
        if (widget.scenario == _KitScenario.debugVisuals)
          const Positioned(top: 64, right: 16, child: PerformanceOverlay3D()),
      ],
    );
  }
}
