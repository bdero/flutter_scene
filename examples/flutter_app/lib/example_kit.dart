import 'dart:async';
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
            onScatterFlock: () => _stageKey.currentState?.scatterFlock(),
            onChanged: () => setState(() {}),
          ),
        ),
      ],
    );
  }
}

class _KitScenarioPanel extends StatefulWidget {
  const _KitScenarioPanel({
    required this.scenario,
    required this.settings,
    required this.onFireBurst,
    required this.onScatterFlock,
    required this.onChanged,
  });

  final _KitScenario scenario;
  final KitDemoSettings settings;
  final VoidCallback onFireBurst;
  final VoidCallback onScatterFlock;
  final VoidCallback onChanged;

  @override
  State<_KitScenarioPanel> createState() => _KitScenarioPanelState();
}

class _KitScenarioPanelState extends State<_KitScenarioPanel> {
  Timer? _uiTimer;

  @override
  void initState() {
    super.initState();
    _uiTimer = Timer.periodic(const Duration(milliseconds: 60), (_) {
      if (mounted &&
          widget.scenario == _KitScenario.dayNight &&
          widget.settings.isTimePlaying) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExamplePanelCard(
      icon: Icons.sports_esports,
      title: widget.scenario.label,
      maxBodyHeight: 440,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [..._buildControls(context)],
      ),
    );
  }

  List<Widget> _buildControls(BuildContext context) {
    final settings = widget.settings;
    final onChanged = widget.onChanged;

    switch (widget.scenario) {
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
            max: 12.0,
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
            'Drag on screen to orbit camera freely. WASD / Arrow keys run relative to camera view.',
            style: TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ];

      case _KitScenario.dayNight:
        final hours = settings.timeOfDay.floor();
        final minutes = ((settings.timeOfDay - hours) * 60).round();
        final timeStr =
            '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';

        return [
          const KitSectionHeader('Time of Day'),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Clock: $timeStr',
                  style: const TextStyle(
                    color: Colors.amberAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  backgroundColor: settings.isTimePlaying
                      ? Colors.amber.shade800
                      : Colors.blueGrey.shade700,
                ),
                icon: Icon(
                  settings.isTimePlaying ? Icons.pause : Icons.play_arrow,
                  size: 16,
                ),
                label: Text(
                  settings.isTimePlaying ? 'Pause' : 'Play',
                  style: const TextStyle(fontSize: 11),
                ),
                onPressed: () {
                  setState(() {
                    settings.isTimePlaying = !settings.isTimePlaying;
                  });
                  onChanged();
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          KitSliderRow(
            label: 'Time',
            value: settings.timeOfDay,
            min: 0.0,
            max: 24.0,
            suffix: 'h',
            onChanged: (v) {
              settings.timeOfDay = v;
              setState(() {});
              onChanged();
            },
          ),
          KitSliderRow(
            label: 'Cycle speed',
            value: settings.timeSpeed,
            min: 0.1,
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
            'Drives physical Rayleigh/Mie atmospheric scattering and cascaded directional sun shadows.',
            style: TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ];

      case _KitScenario.waterBuoyancy:
        return [
          const KitSectionHeader('Gerstner Wave Simulation'),
          KitSliderRow(
            label: 'Amplitude',
            value: settings.waveAmplitude,
            min: 0.1,
            max: 2.0,
            onChanged: (v) {
              settings.waveAmplitude = v;
              onChanged();
            },
          ),
          KitSliderRow(
            label: 'Speed',
            value: settings.waveSpeed,
            min: 0.2,
            max: 4.0,
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
            'Trochoidal Gerstner waves compute height and surface normal dynamically, pitching and rolling floating props.',
            style: TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ];

      case _KitScenario.flocking:
        return [
          const KitSectionHeader('Interactive Swarm'),
          Center(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.waves, size: 16),
              label: const Text('Scatter Flock Impulse'),
              onPressed: widget.onScatterFlock,
            ),
          ),
          const SizedBox(height: 6),
          KitSliderRow(
            label: 'Boid count',
            value: settings.boidCount,
            min: 8.0,
            max: 60.0,
            fractionDigits: 0,
            onChanged: (v) {
              settings.boidCount = v;
              onChanged();
            },
          ),
          KitSliderRow(
            label: 'Max speed',
            value: settings.maxSteerSpeed,
            min: 2.0,
            max: 14.0,
            onChanged: (v) {
              settings.maxSteerSpeed = v;
              onChanged();
            },
          ),
          KitSliderRow(
            label: 'Separation dist',
            value: settings.separationDistance,
            min: 0.5,
            max: 4.0,
            onChanged: (v) {
              settings.separationDistance = v;
              onChanged();
            },
          ),
          KitSliderRow(
            label: 'Separation wt',
            value: settings.separationWeight,
            min: 0.5,
            max: 5.0,
            onChanged: (v) {
              settings.separationWeight = v;
              onChanged();
            },
          ),
          KitSliderRow(
            label: 'Cohesion wt',
            value: settings.cohesionWeight,
            min: 0.1,
            max: 3.0,
            onChanged: (v) {
              settings.cohesionWeight = v;
              onChanged();
            },
          ),
          KitSliderRow(
            label: 'Alignment wt',
            value: settings.alignmentWeight,
            min: 0.1,
            max: 3.0,
            onChanged: (v) {
              settings.alignmentWeight = v;
              onChanged();
            },
          ),
          const SizedBox(height: 6),
          const Text(
            'Click / drag on the 3D scene to guide the boid swarm to your cursor!',
            style: TextStyle(color: Colors.amberAccent, fontSize: 11),
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
              onPressed: widget.onFireBurst,
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
                  'Pool Idle Available: ${settings.poolCapacity}',
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
  Scene scene = Scene();
  Node _cameraNode = Node();
  late NodeCamera _nodeCamera;
  Node _debugMeshNode = Node();

  // Character scenario
  Node? _characterNode;
  ThirdPersonControllerComponent? _characterController;
  SpringArmComponent? _springArm;
  Map<String, AnimationClip> _dashClips = {};
  int _dashJumpState = 0;
  double _dashLandingCooldown = 0.0;
  double _dashAirborneBlend = 0.0;
  bool _prevGrounded = true;
  final CameraShake _shake = CameraShake();
  vm.Vector2 _joystickInput = vm.Vector2.zero();

  // Day/Night scenario
  DayNightCycleComponent? _dayNight;

  // Water scenario
  WaterSurfaceComponent? _water;
  final List<Node> _floatingProps = [];
  double _cachedWaveAmplitude = -1.0;
  double _cachedWaveSpeed = -1.0;
  double _cachedWaveSteepness = -1.0;

  // Flocking scenario
  final List<Node> _boidNodes = [];
  final List<vm.Vector3> _boidVelocities = [];
  Node _targetMarkerNode = Node();
  vm.Vector3? _userAttractorPos;
  bool _isUserAttracting = false;
  double _cachedBoidCount = -1.0;

  // Pooling scenario
  NodePool? _projectilePool;
  final List<_ActiveProjectile> _activeProjectiles = [];
  final List<Node> _scatteredProps = [];
  double _fireTimer = 0.0;
  double _cachedMinDistance = -1.0;

  double _elapsed = 0.0;
  final Set<LogicalKeyboardKey> _pressedKeys = {};

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _buildScene();
  }

  @override
  void didUpdateWidget(covariant _KitStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scenario != widget.scenario) {
      _buildScene();
      setState(() {});
    }
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
    scene = Scene();
    _cameraNode = Node();
    _nodeCamera = NodeCamera(
      _cameraNode,
      PerspectiveCamera(fovRadiansY: 1.0).projection,
    );
    _debugMeshNode = Node();
    _characterNode = null;
    _characterController = null;
    _springArm = null;
    _dayNight = null;
    _water = null;
    _dashClips.clear();
    _dashJumpState = 0;
    _dashLandingCooldown = 0.0;
    _dashAirborneBlend = 0.0;
    _prevGrounded = true;
    _floatingProps.clear();
    _boidNodes.clear();
    _boidVelocities.clear();
    _targetMarkerNode = Node();
    _projectilePool = null;
    _activeProjectiles.clear();
    _scatteredProps.clear();
    DebugDraw.clear();

    scene.add(_cameraNode);

    if (widget.scenario != _KitScenario.dayNight) {
      // Natural balanced directional sun/key light
      scene.directionalLight = DirectionalLight(
        direction: vm.Vector3(-0.6, -1.0, -0.45).normalized(),
        intensity: 2.8,
        castsShadow: true,
        shadowMaxDistance: 60.0,
        shadowAmbientStrength: 0.35,
      );
      scene.environmentIntensity = 0.5;
    }

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

    // Playable animated Dash character
    final dashNode = Node()..position = vm.Vector3(0, 0.9, 0);
    _characterNode = dashNode;

    final clips = <String, AnimationClip>{};
    loadScene('assets_src/dash.glb').then((model) {
      if (!mounted || _characterNode != dashNode) return;
      final pivot = Node()
        ..localTransform = (vm.Matrix4.identity()
          ..rotateY(math.pi)
          ..translateByVector3(vm.Vector3(0.0, -0.9, 0.0)));
      pivot.add(model);
      dashNode.add(pivot);

      for (final name in const [
        'Idle',
        'Walk',
        'Run',
        'JumpStart',
        'JumpLand',
      ]) {
        final anim = model.findAnimationByName(name);
        if (anim == null) continue;
        final loop = name != 'JumpStart' && name != 'JumpLand';
        final clip = model.createAnimationClip(anim)
          ..loop = loop
          ..playing = loop
          ..weight = name == 'Idle' ? 1.0 : 0.0;
        clips[name] = clip;
      }
      _dashClips = clips;
    });

    _characterController = ThirdPersonControllerComponent(
      walkSpeed: widget.settings.walkSpeed,
      jumpVelocity: widget.settings.jumpVelocity,
      groundPlaneHeight: 0.0,
      footOffset: 0.9,
      obstacleRadius: 0.85,
      obstacleHeight: 1.8,
    );
    _characterNode!.addComponent(_characterController!);

    _springArm = SpringArmComponent(
      targetLength: widget.settings.armLength,
      targetOffset: vm.Vector3(0, 0.6, 0),
      socketOffset: vm.Vector3(0.0, 0.3, 0),
      enablePositionLag: widget.settings.enableLag,
      positionLagSpeed: widget.settings.lagSpeed,
      enableRotationLag: false,
      rotationLagSpeed: widget.settings.lagSpeed,
      cameraNode: _cameraNode,
      inheritYaw: false,
      inheritPitch: false,
      inheritRoll: false,
      yaw: widget.settings.cameraOrbitYaw,
      pitch: widget.settings.cameraOrbitPitch,
    );
    _characterNode!.addComponent(_springArm!);

    scene.add(_characterNode!);
  }

  void _buildDayNight() {
    // Physical atmospheric sky driven by sun direction
    final physicalSky = PhysicalSkySource(
      sunDirection: vm.Vector3(0.5, 0.7, 0.5).normalized(),
      turbidity: 4.0,
      groundColor: vm.Vector3(0.2, 0.22, 0.2),
    );
    scene.skybox = Skybox(physicalSky);
    scene.skyEnvironment = SkyEnvironment(physicalSky);
    // Directional light contributes pure shadow mapping without adding direct illuminance
    scene.sunLight = SunLight(
      physicalSky,
      intensity: 0.0,
      castsShadow: true,
      shadowAmbientStrength: 0.75,
      shadowMaxDistance: 80.0,
    );

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
      timeSpeed: widget.settings.isTimePlaying
          ? widget.settings.timeSpeed
          : 0.0,
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

  void _rebuildWater() {
    if (_water != null) {
      scene.root.removeComponent(_water!);
    }
    _water = WaterSurfaceComponent(
      waves: [
        GerstnerWave(
          direction: vm.Vector2(1.0, 0.2).normalized(),
          amplitude: widget.settings.waveAmplitude,
          wavelength: 10.0,
          speed: widget.settings.waveSpeed,
          steepness: widget.settings.waveSteepness,
        ),
        GerstnerWave(
          direction: vm.Vector2(0.5, 0.8).normalized(),
          amplitude: widget.settings.waveAmplitude * 0.6,
          wavelength: 6.0,
          speed: widget.settings.waveSpeed * 1.3,
          steepness: widget.settings.waveSteepness,
        ),
      ],
    );
    scene.root.addComponent(_water!);
  }

  void _buildWaterBuoyancy() {
    _cachedWaveAmplitude = widget.settings.waveAmplitude;
    _cachedWaveSpeed = widget.settings.waveSpeed;
    _cachedWaveSteepness = widget.settings.waveSteepness;
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
      paddingFactor: 1.35,
    );
  }

  void _rebuildFlock() {
    for (final n in _boidNodes) {
      n.parent?.remove(n);
    }
    _boidNodes.clear();
    _boidVelocities.clear();

    final boidCount = widget.settings.boidCount.round();
    final boidGeo = CuboidGeometry(vm.Vector3(0.4, 0.25, 1.1));
    final boidMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.2, 0.95, 0.6, 1.0)
      ..roughnessFactor = 0.25;

    final rng = math.Random(42);
    for (var i = 0; i < boidCount; i++) {
      final pos = vm.Vector3(
        (rng.nextDouble() - 0.5) * 16.0,
        rng.nextDouble() * 6.0 + 2.0,
        (rng.nextDouble() - 0.5) * 16.0,
      );
      final node = Node(mesh: Mesh(boidGeo, boidMat))..position = pos;
      _boidNodes.add(node);
      _boidVelocities.add(
        vm.Vector3(
          (rng.nextDouble() - 0.5) * 4.0,
          (rng.nextDouble() - 0.5) * 2.0,
          (rng.nextDouble() - 0.5) * 4.0,
        ),
      );
      scene.add(node);
    }
  }

  void scatterFlock() {
    final rng = math.Random();
    for (var i = 0; i < _boidVelocities.length; i++) {
      final angle = rng.nextDouble() * 2 * math.pi;
      final speed =
          widget.settings.maxSteerSpeed * (1.8 + rng.nextDouble() * 0.8);
      _boidVelocities[i] = vm.Vector3(
        math.cos(angle) * speed,
        (rng.nextDouble() - 0.3) * speed * 0.5,
        math.sin(angle) * speed,
      );
    }
  }

  void _buildFlocking() {
    _cachedBoidCount = widget.settings.boidCount;
    _rebuildFlock();

    // Target attractor marker beacon
    final targetGeo = CuboidGeometry(vm.Vector3(0.8, 0.8, 0.8));
    final targetMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(1.0, 0.25, 0.25, 1.0)
      ..emissiveFactor = vm.Vector4(1.0, 0.3, 0.3, 1.0);
    _targetMarkerNode.mesh = Mesh(targetGeo, targetMat);
    scene.add(_targetMarkerNode);

    _cameraNode.localTransform = BoundsFraming.computeFramingTransform(
      vm.Aabb3.minMax(vm.Vector3(-14, 0, -14), vm.Vector3(14, 10, 14)),
      PerspectiveCamera(fovRadiansY: 1.0),
      viewDirection: vm.Vector3(0.65, 0.5, 0.65),
      paddingFactor: 1.35,
    );
  }

  void _buildSpawnerPooling() {
    _activeProjectiles.clear();
    _fireTimer = 0.0;
    _cachedMinDistance = widget.settings.minDistance;

    // Cannon turret base
    final turretBaseGeo = CuboidGeometry(vm.Vector3(2.0, 0.8, 2.0));
    final turretBaseMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.3, 0.32, 0.35, 1.0)
      ..metallicFactor = 0.8
      ..roughnessFactor = 0.2;
    scene.add(
      Node(mesh: Mesh(turretBaseGeo, turretBaseMat))
        ..position = vm.Vector3(0, 0.4, 0),
    );

    final barrelGeo = CuboidGeometry(vm.Vector3(0.5, 0.5, 1.8));
    final barrelMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.15, 0.15, 0.18, 1.0)
      ..metallicFactor = 0.9
      ..roughnessFactor = 0.15;
    scene.add(
      Node(mesh: Mesh(barrelGeo, barrelMat))
        ..position = vm.Vector3(0, 0.9, 0.8),
    );

    // 1. Procedural Poisson-disc forest distribution
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
    scene.add(_debugMeshNode);
    final groundMesh = PlaneGeometry(width: 24, depth: 24);
    final groundMat = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.25, 0.25, 0.28, 1.0);
    scene.add(
      Node(mesh: Mesh(groundMesh, groundMat))..position = vm.Vector3.zero(),
    );

    _cameraNode.localTransform = BoundsFraming.computeFramingTransform(
      vm.Aabb3.minMax(vm.Vector3(-8, 0, -8), vm.Vector3(8, 6, 8)),
      PerspectiveCamera(fovRadiansY: 1.0),
      viewDirection: vm.Vector3(0.65, 0.5, 0.65),
      paddingFactor: 1.4,
    );
  }

  void _handlePointerDown(Offset localPos, Size? size) {
    if (widget.scenario == _KitScenario.flocking) {
      _updateAttractorFromScreen(localPos, size);
    }
  }

  void _handlePointerMove(Offset delta, Offset localPos, Size? size) {
    if (widget.scenario == _KitScenario.characterCamera) {
      widget.settings.cameraOrbitYaw += delta.dx * 0.005;
      widget.settings.cameraOrbitPitch =
          (widget.settings.cameraOrbitPitch + delta.dy * 0.005).clamp(
            -0.35,
            1.15,
          );
    } else if (widget.scenario == _KitScenario.flocking) {
      _updateAttractorFromScreen(localPos, size);
    }
  }

  void _handlePointerUp() {
    // Keep user attractor active at the dragged location so boids gather there
  }

  void _updateAttractorFromScreen(Offset pos, Size? size) {
    if (size == null || size.width == 0 || size.height == 0) return;
    final ndcX = (pos.dx / size.width) * 2.0 - 1.0;
    final ndcY = 1.0 - (pos.dy / size.height) * 2.0;

    final tanFov = math.tan(0.5);
    final aspect = size.width / size.height;

    final camPos = _cameraNode.globalTransform.getTranslation();
    final camForward = (_cameraNode.globalTransform * vm.Vector4(0, 0, 1, 0))
        .xyz
        .normalized();
    final camRight = (_cameraNode.globalTransform * vm.Vector4(1, 0, 0, 0)).xyz
        .normalized();
    final camUp = (_cameraNode.globalTransform * vm.Vector4(0, 1, 0, 0)).xyz
        .normalized();

    final worldRayDir =
        (camForward +
                camRight * (ndcX * tanFov * aspect) +
                camUp * (ndcY * tanFov))
            .normalized();
    if (worldRayDir.y.abs() > 1e-4) {
      final t = (3.5 - camPos.y) / worldRayDir.y;
      if (t > 0) {
        final hitPos = camPos + worldRayDir * t;
        _userAttractorPos = hitPos;
        _isUserAttracting = true;
        _targetMarkerNode.position = hitPos;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) => _handlePointerDown(
                  event.localPosition,
                  constraints.biggest,
                ),
                onPointerMove: (event) => _handlePointerMove(
                  event.delta,
                  event.localPosition,
                  constraints.biggest,
                ),
                onPointerUp: (_) => _handlePointerUp(),
                onPointerCancel: (_) => _handlePointerUp(),
                child: SceneView(
                  scene,
                  camera: _nodeCamera,
                  onTick: (elapsedDuration, dt) => _tick(dt),
                ),
              );
            },
          ),
        ),
        if (widget.scenario == _KitScenario.characterCamera) ...[
          Positioned(
            bottom: 24,
            right: 24,
            child: _VirtualJoystick(
              onChanged: (v) {
                _joystickInput = v;
              },
            ),
          ),
          Positioned(
            bottom: 24,
            right: 150,
            child: FloatingActionButton.small(
              backgroundColor: Colors.blueAccent.withValues(alpha: 0.8),
              onPressed: () {
                _characterController?.jump();
                _shake.addTrauma(0.2);
              },
              child: const Icon(Icons.arrow_upward, color: Colors.white),
            ),
          ),
        ],
        if (widget.scenario == _KitScenario.debugVisuals)
          const Positioned(top: 64, right: 16, child: PerformanceOverlay3D()),
      ],
    );
  }

  void _tick(double dt) {
    _elapsed += dt;

    if (widget.scenario == _KitScenario.waterBuoyancy) {
      if (_cachedWaveAmplitude != widget.settings.waveAmplitude ||
          _cachedWaveSpeed != widget.settings.waveSpeed ||
          _cachedWaveSteepness != widget.settings.waveSteepness) {
        _cachedWaveAmplitude = widget.settings.waveAmplitude;
        _cachedWaveSpeed = widget.settings.waveSpeed;
        _cachedWaveSteepness = widget.settings.waveSteepness;
        _rebuildWater();
      }
    } else if (widget.scenario == _KitScenario.spawnerPooling) {
      if (_cachedMinDistance != widget.settings.minDistance) {
        _cachedMinDistance = widget.settings.minDistance;
        _rebuildPoissonFoliage();
      }
    } else if (widget.scenario == _KitScenario.flocking) {
      if (_cachedBoidCount != widget.settings.boidCount) {
        _cachedBoidCount = widget.settings.boidCount;
        _rebuildFlock();
      }
    }

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
    if (_characterController == null) return;

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

    // Pass camera heading yaw so movement aligns with the third-person camera view
    _characterController!.setMoveInput(
      vm.Vector2(moveX, moveY),
      isRunning: isSprinting,
      cameraHeadingYaw: widget.settings.cameraOrbitYaw,
    );

    if (_pressedKeys.contains(LogicalKeyboardKey.space)) {
      _characterController!.jump();
    }

    _characterController!.walkSpeed = widget.settings.walkSpeed;
    _characterController!.jumpVelocity = widget.settings.jumpVelocity;

    if (_springArm != null) {
      _springArm!.yaw = widget.settings.cameraOrbitYaw;
      _springArm!.pitch = widget.settings.cameraOrbitPitch;
      _springArm!.targetLength = widget.settings.armLength;
      _springArm!.enablePositionLag = widget.settings.enableLag;
      _springArm!.positionLagSpeed = widget.settings.lagSpeed;
      _springArm!.enableRotationLag = false;
      _springArm!.rotationLagSpeed = widget.settings.lagSpeed;
    }

    // Step the scene components (ThirdPersonController + SpringArm)
    scene.update(dt);

    final horizSpeed = vm.Vector2(
      _characterController!.velocity.x,
      _characterController!.velocity.z,
    ).length;
    final isGrounded = _characterController!.isGrounded;
    final vertVel = _characterController!.velocity.y;

    if (!isGrounded) {
      _dashLandingCooldown = 0.0;
      final landClip = _dashClips['JumpLand'];
      if (landClip != null) {
        landClip.playing = false;
        landClip.weight = 0.0;
      }

      if (vertVel >= 0.0) {
        if (_dashJumpState != 1) {
          _dashJumpState = 1;
          _dashClips['JumpStart']?.seek(0.0);
        }
      } else {
        _dashJumpState = 2;
      }
    } else {
      if (!_prevGrounded && _dashJumpState != 0) {
        // Touchdown: trigger JumpLand overlay
        _dashJumpState = 3;
        _dashLandingCooldown = 0.4;
        _dashClips['JumpLand']?.seek(0.0);
      }
    }
    _prevGrounded = isGrounded;

    if (isGrounded && _dashLandingCooldown > 0.0) {
      _dashLandingCooldown = math.max(0.0, _dashLandingCooldown - dt);
      if (_dashLandingCooldown == 0.0) {
        _dashJumpState = 0;
      }
    }

    final airborne = _dashJumpState == 1 || _dashJumpState == 2;
    final landing = _dashJumpState == 3;

    // Smoothly ease the airborne takeoff/falling pose in and out
    _dashAirborneBlend +=
        ((airborne ? 1.0 : 0.0) - _dashAirborneBlend) *
        (1.0 - math.exp(-12.0 * dt));

    if (_dashClips.isNotEmpty) {
      final groundedWeight = math.max(
        _dashJumpState == 0 ? 1.0 : 0.0,
        math.min(1.0, 1.0 - _dashLandingCooldown * 6.0),
      );
      final landingWeight =
          (landing ? 1.0 : 0.0) * math.min(1.0, _dashLandingCooldown * 4.0);

      final speedFraction = (horizSpeed / widget.settings.walkSpeed).clamp(
        0.0,
        1.0,
      );
      final double idle, walk, run;
      if (speedFraction < 0.5) {
        idle = 1.0 - speedFraction * 2.0;
        walk = speedFraction * 2.0;
        run = 0.0;
      } else {
        idle = 0.0;
        walk = (1.0 - speedFraction) * 2.0;
        run = speedFraction * 2.0 - 1.0;
      }

      _dashClips['Idle']?.weight = groundedWeight * idle;
      _dashClips['Walk']?.weight = groundedWeight * walk;
      _dashClips['Run']?.weight = groundedWeight * run;

      final startClip = _dashClips['JumpStart'];
      if (startClip != null) {
        startClip.weight = _dashAirborneBlend;
        startClip.playing = airborne || _dashAirborneBlend > 0.01;
      }

      final landClip = _dashClips['JumpLand'];
      if (landClip != null) {
        landClip.weight = landingWeight;
        landClip.playing = landing;
      }
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
    if (widget.settings.isTimePlaying) {
      _dayNight!.timeSpeed = widget.settings.timeSpeed;
      widget.settings.timeOfDay = _dayNight!.timeOfDay;
    } else {
      _dayNight!.timeSpeed = 0.0;
      _dayNight!.timeOfDay = widget.settings.timeOfDay;
    }
    _dayNight!.latitude = widget.settings.latitude;

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

    final vm.Vector3 targetPos;
    if (_isUserAttracting && _userAttractorPos != null) {
      targetPos = _userAttractorPos!;
      _targetMarkerNode.position = targetPos;
    } else {
      targetPos = vm.Vector3(
        math.sin(_elapsed * 0.7) * 11.0,
        4.0 + math.cos(_elapsed * 1.1) * 2.5,
        math.cos(_elapsed * 0.7) * 11.0,
      );
      _targetMarkerNode.position = targetPos;
    }

    final positions = _boidNodes.map((n) => n.position).toList();

    for (var i = 0; i < _boidNodes.length; i++) {
      final node = _boidNodes[i];
      var vel = _boidVelocities[i];

      final seekWeight = _isUserAttracting ? 2.2 : 1.0;
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
          seekForce * seekWeight +
          sepForce * widget.settings.separationWeight +
          cohForce * widget.settings.cohesionWeight +
          aliForce * widget.settings.alignmentWeight;

      vel = (vel + totalForce * dt);
      if (vel.length > widget.settings.maxSteerSpeed) {
        vel = vel.normalized() * widget.settings.maxSteerSpeed;
      }
      _boidVelocities[i] = vel;
      node.position = node.position + vel * dt;

      // Orient boid smoothly along velocity direction
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
}

class _VirtualJoystick extends StatefulWidget {
  const _VirtualJoystick({required this.onChanged});

  final ValueChanged<vm.Vector2> onChanged;

  @override
  State<_VirtualJoystick> createState() => _VirtualJoystickState();
}

class _VirtualJoystickState extends State<_VirtualJoystick> {
  Offset _knobOffset = Offset.zero;
  static const double _radius = 45.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (details) => _updateKnob(details.localPosition),
      onPanUpdate: (details) => _updateKnob(details.localPosition),
      onPanEnd: (_) => _resetKnob(),
      child: Container(
        width: _radius * 2,
        height: _radius * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.35),
          border: Border.all(color: Colors.white30, width: 2),
        ),
        child: Center(
          child: Transform.translate(
            offset: _knobOffset,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _updateKnob(Offset localPosition) {
    final center = const Offset(_radius, _radius);
    final delta = localPosition - center;
    final dist = delta.distance;

    final clampedDelta = dist > _radius ? (delta / dist) * _radius : delta;

    setState(() {
      _knobOffset = clampedDelta;
    });

    widget.onChanged(
      vm.Vector2(clampedDelta.dx / _radius, -clampedDelta.dy / _radius),
    );
  }

  void _resetKnob() {
    setState(() {
      _knobOffset = Offset.zero;
    });
    widget.onChanged(vm.Vector2.zero());
  }
}
