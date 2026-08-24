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
  final GlobalKey<_KitStageState> _stageKey = GlobalKey<_KitStageState>();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: _KitStage(
            key: _stageKey,
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
            onFireBurst: () => _stageKey.currentState?.fireProjectileBurst(),
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
    required this.onFireBurst,
    required this.onChanged,
  });

  final _KitScenario scenario;
  final KitDemoSettings settings;
  final VoidCallback onFireBurst;
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
          const SizedBox(height: 6),
          const Text(
            'Drives physical Rayleigh/Mie sky scattering and directional sun shadows smoothly with zero discontinuities.',
            style: TextStyle(color: Colors.white70, fontSize: 11),
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
          const SizedBox(height: 6),
          const Text(
            'Trochoidal Gerstner waves drive real-time surface height, normal orientation, and pitch/roll of floating buoys and crates.',
            style: TextStyle(color: Colors.white70, fontSize: 11),
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
          const SizedBox(height: 6),
          const Text(
            'Autonomous boids steering with seek, separation, cohesion, and alignment behavior towards a moving target.',
            style: TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ];

      case _KitScenario.spawnerPooling:
        return [
          const KitSectionHeader('Zero-GC Projectile Pooling'),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Continuous Auto-Fire',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              Switch(
                value: settings.autoFire,
                onChanged: (v) {
                  settings.autoFire = v;
                  onChanged();
                },
              ),
            ],
          ),
          Center(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.bolt, size: 16),
              label: const Text('Fire Projectile Burst'),
              onPressed: onFireBurst,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Active in Flight: ${settings.activeProjectiles}',
                  style: const TextStyle(
                    color: Colors.amberAccent,
                    fontSize: 11,
                  ),
                ),
                Text(
                  'Pool Buffer Size: ${settings.poolCapacity}',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
                Text(
                  'Total Recycled Spawns: ${settings.totalSpawns}',
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const KitSectionHeader('Poisson-Disc Distribution'),
          KitSliderRow(
            label: 'Min tree spacing',
            value: settings.minDistance,
            min: 2.0,
            max: 7.0,
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
            'Demonstrates immediate-mode DebugDraw wireframes (lines, rays, boxes, spheres, axes) and real-time PerformanceOverlay3D.',
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

class _ActiveProjectile {
  _ActiveProjectile({
    required this.node,
    required this.position,
    required this.velocity,
  });

  final Node node;
  vm.Vector3 position;
  vm.Vector3 velocity;
  double lifeTime = 0.0;
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
  vm.Vector2 _joystickInput = vm.Vector2.zero();

  // Day/Night scenario
  DayNightCycleComponent? _dayNight;

  // Water scenario
  WaterSurfaceComponent? _water;
  final List<Node> _floatingProps = [];

  // Flocking scenario
  final List<Node> _boidNodes = [];
  final List<vm.Vector3> _boidVelocities = [];

  // Pooling scenario
  NodePool? _projectilePool;
  final List<_ActiveProjectile> _activeProjectiles = [];
  final List<Node> _scatteredProps = [];
  double _fireTimer = 0.0;

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
  void didUpdateWidget(covariant _KitStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scenario != widget.scenario) {
      _buildScene();
    } else if (widget.scenario == _KitScenario.spawnerPooling &&
        oldWidget.settings.minDistance != widget.settings.minDistance) {
      _rebuildPoissonFoliage();
    } else if (widget.scenario == _KitScenario.waterBuoyancy &&
        (oldWidget.settings.waveAmplitude != widget.settings.waveAmplitude ||
            oldWidget.settings.waveSpeed != widget.settings.waveSpeed ||
            oldWidget.settings.waveSteepness !=
                widget.settings.waveSteepness)) {
      _rebuildWater();
    }
  }

  void _rebuildWater() {
    if (_water != null) {
      scene.root.removeComponent(_water!);
    }
    _water = WaterSurfaceComponent(
      waves: [
        GerstnerWave(
          direction: vm.Vector2(1.0, 0.2).normalized(),
          amplitude: widget.settings.waveAmplitude,
          wavelength: 12.0,
          speed: widget.settings.waveSpeed,
          steepness: widget.settings.waveSteepness,
        ),
        GerstnerWave(
          direction: vm.Vector2(0.5, 0.8).normalized(),
          amplitude: widget.settings.waveAmplitude * 0.5,
          wavelength: 6.0,
          speed: widget.settings.waveSpeed * 1.3,
          steepness: widget.settings.waveSteepness,
        ),
      ],
    );
    scene.root.addComponent(_water!);
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

    // Reset default directional light
    final keyLight = DirectionalLight()
      ..color = vm.Vector3(1.0, 0.98, 0.92)
      ..intensity = 50000.0;
    final keyLightNode = Node()
      ..addComponent(DirectionalLightComponent(keyLight));
    keyLightNode.localTransform = vm.Matrix4.identity()
      ..setTranslation(vm.Vector3(12, 24, 12));
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
    final groundMesh = PlaneGeometry(width: 48, depth: 48);
    final groundNode = Node(
      mesh: Mesh(
        groundMesh,
        PhysicallyBasedMaterial()
          ..baseColorFactor = vm.Vector4(0.24, 0.26, 0.30, 1.0)
          ..roughnessFactor = 0.8,
      ),
    )..position = vm.Vector3.zero();
    scene.add(groundNode);

    // Obstacle blocks for collision and occlusion testing
    final boxGeo = CuboidGeometry(vm.Vector3(3.5, 2.5, 3.5));
    final wallMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.65, 0.35, 0.22, 1.0)
      ..roughnessFactor = 0.6;
    for (final pos in [
      vm.Vector3(7, 1.25, 7),
      vm.Vector3(-7, 1.25, -7),
      vm.Vector3(-8, 1.25, 5),
      vm.Vector3(0, 1.25, -11),
      vm.Vector3(10, 1.25, -5),
    ]) {
      scene.add(Node(mesh: Mesh(boxGeo, wallMat))..position = pos);
    }

    // Stylized player character with torso, head, and visor
    final charTorsoGeo = CuboidGeometry(vm.Vector3(0.8, 1.0, 0.6));
    final charTorsoMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.18, 0.65, 0.95, 1.0)
      ..roughnessFactor = 0.3;
    _characterNode = Node(mesh: Mesh(charTorsoGeo, charTorsoMat))
      ..position = vm.Vector3(0, 0.9, 0);

    final charHeadGeo = CuboidGeometry(vm.Vector3(0.5, 0.5, 0.5));
    final charHeadMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.95, 0.85, 0.72, 1.0);
    _characterNode!.add(
      Node(mesh: Mesh(charHeadGeo, charHeadMat))
        ..position = vm.Vector3(0, 0.75, 0),
    );

    final charVisorGeo = CuboidGeometry(vm.Vector3(0.42, 0.16, 0.2));
    final charVisorMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.08, 0.08, 0.08, 1.0)
      ..metallicFactor = 0.9
      ..roughnessFactor = 0.1;
    _characterNode!.add(
      Node(mesh: Mesh(charVisorGeo, charVisorMat))
        ..position = vm.Vector3(0, 0.78, 0.22),
    );

    _characterController = ThirdPersonControllerComponent(
      walkSpeed: widget.settings.walkSpeed,
      jumpVelocity: widget.settings.jumpVelocity,
      groundPlaneHeight: 0.0,
    );
    _characterNode!.addComponent(_characterController!);

    _springArm = SpringArmComponent(
      targetLength: widget.settings.armLength,
      targetOffset: vm.Vector3(0, 1.4, 0),
      socketOffset: vm.Vector3(0.0, 0.3, 0),
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
    // Physical atmospheric sky driven by sun direction
    final physicalSky = PhysicalSkySource(
      sunDirection: vm.Vector3(0.5, 0.7, 0.5).normalized(),
      turbidity: 3.0,
      groundColor: vm.Vector3(0.3, 0.32, 0.28),
    );
    scene.skybox = Skybox(physicalSky);
    scene.skyEnvironment = SkyEnvironment(physicalSky);
    scene.sunLight = SunLight(physicalSky, castsShadow: true);

    // Ground plane
    final groundMesh = PlaneGeometry(width: 60, depth: 60);
    scene.add(
      Node(
        mesh: Mesh(
          groundMesh,
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.32, 0.35, 0.30, 1.0)
            ..roughnessFactor = 0.9,
        ),
      ),
    );

    // Monoliths casting dynamic shadows across the landscape
    final pillarGeo = CuboidGeometry(vm.Vector3(1.4, 7.0, 1.4));
    final pillarMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.85, 0.82, 0.78, 1.0)
      ..roughnessFactor = 0.35;

    for (var i = 0; i < 8; i++) {
      final angle = (i / 8.0) * 2 * math.pi;
      final x = math.cos(angle) * 10.0;
      final z = math.sin(angle) * 10.0;
      scene.add(
        Node(mesh: Mesh(pillarGeo, pillarMat))
          ..position = vm.Vector3(x, 3.5, z),
      );
    }

    _dayNight = DayNightCycleComponent(
      timeOfDay: widget.settings.timeOfDay,
      timeSpeed: widget.settings.timeSpeed,
      latitude: widget.settings.latitude,
      skySource: physicalSky,
    );
    scene.root.addComponent(_dayNight!);

    _cameraNode.localTransform = BoundsFraming.computeFramingTransform(
      vm.Aabb3.minMax(vm.Vector3(-14, 0, -14), vm.Vector3(14, 8, 14)),
      PerspectiveCamera(fovRadiansY: 1.0),
      viewDirection: vm.Vector3(0.7, 0.45, 0.7),
      paddingFactor: 1.4,
    );
  }

  void _buildWaterBuoyancy() {
    _rebuildWater();
    _floatingProps.clear();

    // Visible translucent water surface
    final waterGeo = PlaneGeometry(width: 48, depth: 48);
    final waterMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.06, 0.38, 0.68, 0.85)
      ..roughnessFactor = 0.05
      ..metallicFactor = 0.1;
    scene.add(
      Node(mesh: Mesh(waterGeo, waterMat))..position = vm.Vector3.zero(),
    );

    // Floating buoys and crates
    final buoyGeo = CuboidGeometry(vm.Vector3(1.2, 1.2, 1.2));
    final buoyMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(1.0, 0.38, 0.08, 1.0)
      ..roughnessFactor = 0.2;

    final crateGeo = CuboidGeometry(vm.Vector3(1.6, 1.6, 1.6));
    final crateMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.65, 0.45, 0.28, 1.0)
      ..roughnessFactor = 0.7;

    for (var x = -10; x <= 10; x += 5) {
      for (var z = -10; z <= 10; z += 5) {
        final isBuoy = (x + z) % 10 == 0;
        final node = Node(
          mesh: Mesh(isBuoy ? buoyGeo : crateGeo, isBuoy ? buoyMat : crateMat),
        )..position = vm.Vector3(x.toDouble(), 0, z.toDouble());
        _floatingProps.add(node);
        scene.add(node);
      }
    }

    _cameraNode.localTransform = BoundsFraming.computeFramingTransform(
      vm.Aabb3.minMax(vm.Vector3(-14, -2, -14), vm.Vector3(14, 5, 14)),
      PerspectiveCamera(fovRadiansY: 1.0),
      viewDirection: vm.Vector3(0.55, 0.55, 0.75),
      paddingFactor: 1.3,
    );
  }

  void _buildFlocking() {
    _boidNodes.clear();
    _boidVelocities.clear();

    final boidGeo = CuboidGeometry(vm.Vector3(0.4, 0.3, 1.0));
    final boidMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.2, 0.95, 0.6, 1.0)
      ..roughnessFactor = 0.3;

    final rng = math.Random(42);
    for (var i = 0; i < 28; i++) {
      final pos = vm.Vector3(
        (rng.nextDouble() - 0.5) * 18.0,
        rng.nextDouble() * 8.0 + 2.0,
        (rng.nextDouble() - 0.5) * 18.0,
      );
      final node = Node(mesh: Mesh(boidGeo, boidMat))..position = pos;
      _boidNodes.add(node);
      _boidVelocities.add(
        vm.Vector3(
          (rng.nextDouble() - 0.5) * 3.0,
          (rng.nextDouble() - 0.5) * 3.0,
          (rng.nextDouble() - 0.5) * 3.0,
        ),
      );
      scene.add(node);
    }

    _cameraNode.localTransform = BoundsFraming.computeFramingTransform(
      vm.Aabb3.minMax(vm.Vector3(-14, 0, -14), vm.Vector3(14, 12, 14)),
      PerspectiveCamera(fovRadiansY: 1.0),
      viewDirection: vm.Vector3(0.6, 0.55, 0.65),
      paddingFactor: 1.4,
    );
  }

  void _buildSpawnerPooling() {
    _activeProjectiles.clear();
    _scatteredProps.clear();

    // Ground plane
    final groundMesh = PlaneGeometry(width: 36, depth: 36);
    scene.add(
      Node(
        mesh: Mesh(
          groundMesh,
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.22, 0.28, 0.24, 1.0)
            ..roughnessFactor = 0.85,
        ),
      ),
    );

    // Center cannon / turret
    final turretBaseGeo = CuboidGeometry(vm.Vector3(1.8, 0.8, 1.8));
    final turretBaseMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.2, 0.2, 0.25, 1.0)
      ..metallicFactor = 0.8
      ..roughnessFactor = 0.2;
    final turretBarrelGeo = CuboidGeometry(vm.Vector3(0.6, 0.6, 2.2));
    final turretBarrelMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.8, 0.2, 0.2, 1.0)
      ..metallicFactor = 0.5
      ..roughnessFactor = 0.3;

    final turretNode = Node(mesh: Mesh(turretBaseGeo, turretBaseMat))
      ..position = vm.Vector3(0, 0.4, 0);
    turretNode.add(
      Node(mesh: Mesh(turretBarrelGeo, turretBarrelMat))
        ..position = vm.Vector3(0, 0.5, 0.6)
        ..rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), -0.25),
    );
    scene.add(turretNode);

    // 1. Poisson-disc distribution of trees around the perimeter
    _rebuildPoissonFoliage();

    // 2. Zero-GC NodePool for recycled projectiles
    final projGeo = CuboidGeometry(vm.Vector3(0.4, 0.4, 0.4));
    final projMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(1.0, 0.85, 0.15, 1.0)
      ..emissiveFactor = vm.Vector4(1.0, 0.7, 0.1, 1.0)
      ..roughnessFactor = 0.1;

    _projectilePool = NodePool(
      () => Node(mesh: Mesh(projGeo, projMat)),
      initialSize: 16,
      maxSize: widget.settings.poolMaxSize,
    );

    widget.settings.poolCapacity = _projectilePool!.idleCount;

    _cameraNode.localTransform = BoundsFraming.computeFramingTransform(
      vm.Aabb3.minMax(vm.Vector3(-16, 0, -16), vm.Vector3(16, 8, 16)),
      PerspectiveCamera(fovRadiansY: 1.0),
      viewDirection: vm.Vector3(0.65, 0.48, 0.65),
      paddingFactor: 1.35,
    );
  }

  void _rebuildPoissonFoliage() {
    for (final p in _scatteredProps) {
      p.parent?.remove(p);
    }
    _scatteredProps.clear();

    final points = PoissonDiscSampler.sampleRect(
      32.0,
      32.0,
      widget.settings.minDistance,
      seed: 555,
    );

    final trunkGeo = CuboidGeometry(vm.Vector3(0.6, 2.5, 0.6));
    final trunkMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.45, 0.28, 0.16, 1.0)
      ..roughnessFactor = 0.9;
    final foliageGeo = CuboidGeometry(vm.Vector3(2.0, 2.2, 2.0));
    final foliageMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.18, 0.65, 0.28, 1.0)
      ..roughnessFactor = 0.6;

    for (final pt in points) {
      final x = pt.x - 16.0;
      final z = pt.y - 16.0;
      if (math.sqrt(x * x + z * z) < 4.0) {
        continue; // Keep center clear for cannon
      }

      final tree = Node(mesh: Mesh(trunkGeo, trunkMat))
        ..position = vm.Vector3(x, 1.25, z);
      tree.add(
        Node(mesh: Mesh(foliageGeo, foliageMat))
          ..position = vm.Vector3(0, 1.8, 0),
      );
      _scatteredProps.add(tree);
      scene.add(tree);
    }
  }

  void fireProjectileBurst() {
    if (_projectilePool == null) return;
    final rng = math.Random();
    for (var i = 0; i < 5; i++) {
      final node = _projectilePool!.spawn(parent: scene.root);
      final angle = (i - 2) * 0.18 + (rng.nextDouble() - 0.5) * 0.1;
      final speed = 14.0 + rng.nextDouble() * 4.0;
      final dir = vm.Vector3(
        math.sin(angle),
        0.45,
        math.cos(angle),
      ).normalized();

      final proj = _ActiveProjectile(
        node: node,
        position: vm.Vector3(0, 0.9, 1.2),
        velocity: dir * speed,
      );
      node.position = proj.position;
      _activeProjectiles.add(proj);
      widget.settings.totalSpawns++;
    }
  }

  void _buildDebugVisuals() {
    final groundMesh = PlaneGeometry(width: 24, depth: 24);
    scene.add(
      Node(
        mesh: Mesh(
          groundMesh,
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.16, 0.16, 0.20, 1.0)
            ..roughnessFactor = 0.9,
        ),
      ),
    );

    _cameraNode.localTransform = BoundsFraming.computeFramingTransform(
      vm.Aabb3.minMax(vm.Vector3(-9, 0, -9), vm.Vector3(9, 6, 9)),
      PerspectiveCamera(fovRadiansY: 1.0),
      viewDirection: vm.Vector3(0.6, 0.5, 0.8),
      paddingFactor: 1.3,
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

    // Read keyboard movement input
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

    final moveX = mx != 0.0 ? mx : _joystickInput.x;
    final moveY = my != 0.0 ? my : _joystickInput.y;
    final isSprinting = _pressedKeys.contains(LogicalKeyboardKey.shiftLeft);

    _characterController!.setMoveInput(
      vm.Vector2(moveX, moveY),
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

    // Step the scene components (ThirdPersonController + SpringArm)
    scene.update(dt);

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

    if (widget.settings.timeSpeed == 0.0) {
      _dayNight!.timeOfDay = widget.settings.timeOfDay;
    } else {
      widget.settings.timeOfDay = _dayNight!.timeOfDay;
    }

    scene.update(dt);
  }

  void _tickWater(double dt) {
    if (_water == null) return;

    for (final prop in _floatingProps) {
      final surface = _water!.evaluateAt(
        vm.Vector2(prop.position.x, prop.position.z),
      );
      prop.position = vm.Vector3(
        prop.position.x,
        surface.displacement.y,
        prop.position.z,
      );

      final normal = surface.normal;
      final up = vm.Vector3(0, 1, 0);
      final rotAxis = up.cross(normal);
      if (rotAxis.length2 > 1e-4) {
        final rotAngle = math.acos(up.dot(normal).clamp(-1.0, 1.0));
        prop.rotation = vm.Quaternion.axisAngle(rotAxis.normalized(), rotAngle);
      }
    }

    scene.update(dt);
  }

  void _tickFlocking(double dt) {
    if (_boidNodes.isEmpty) return;

    final targetPos = vm.Vector3(
      math.sin(_elapsed * 0.8) * 10.0,
      4.5 + math.cos(_elapsed * 1.2) * 2.5,
      math.cos(_elapsed * 0.8) * 10.0,
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
          seekForce * 1.2 + sepForce * 2.8 + cohForce * 0.6 + aliForce * 0.8;
      vel = (vel + totalForce * dt);
      if (vel.length > widget.settings.maxSteerSpeed) {
        vel = vel.normalized() * widget.settings.maxSteerSpeed;
      }
      _boidVelocities[i] = vel;
      node.position = node.position + vel * dt;

      // Orient boid forward towards velocity direction
      if (vel.length2 > 0.01) {
        final forward = vel.normalized();
        final yaw = math.atan2(forward.x, forward.z);
        final pitch = -math.asin(forward.y.clamp(-1.0, 1.0));
        node.rotation = vm.Quaternion.euler(yaw, pitch, 0.0);
      }
    }

    scene.update(dt);
  }

  void _tickSpawnerPooling(double dt) {
    if (_projectilePool == null) return;

    // Automatic periodic firing
    if (widget.settings.autoFire) {
      _fireTimer += dt;
      if (_fireTimer >= widget.settings.fireInterval) {
        _fireTimer = 0.0;
        fireProjectileBurst();
      }
    }

    // Step active projectiles and recycle when finished
    final expired = <_ActiveProjectile>[];
    for (final proj in _activeProjectiles) {
      proj.lifeTime += dt;
      proj.velocity.y -= 18.0 * dt; // Gravity
      proj.position += proj.velocity * dt;

      // Bounce off ground
      if (proj.position.y <= 0.2) {
        proj.position.y = 0.2;
        proj.velocity.y = -proj.velocity.y * 0.6;
        proj.velocity.x *= 0.85;
        proj.velocity.z *= 0.85;
      }

      proj.node.position = proj.position;

      if (proj.lifeTime >= 3.0) {
        expired.add(proj);
      }
    }

    for (final proj in expired) {
      _activeProjectiles.remove(proj);
      _projectilePool!.despawn(proj.node);
    }

    widget.settings.activeProjectiles = _activeProjectiles.length;
    widget.settings.poolCapacity = _projectilePool!.idleCount;

    scene.update(dt);
  }

  void _tickDebugVisuals(double dt) {
    DebugDraw.clear();

    // Draw coordinate axes
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

    scene.update(dt);
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
                    setState(() {
                      // Joystick emits up as -Y in screen space; invert for 3D forward (+Y)
                      _joystickInput = vm.Vector2(dir.x, -dir.y);
                    });
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
