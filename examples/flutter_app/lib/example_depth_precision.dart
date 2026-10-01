import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart' hide Material;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'depth_demo_exit.dart';
import 'example_chrome.dart';

/// One before/after comparison in [ExampleDepthPrecision].
enum DepthDemoAct {
  layers(
    'Depth layers',
    'Screens 5 mm off their backing and road paint flush with the road',
    'depthLayer 0',
    'depthLayer 1',
  ),
  nearFit(
    'Fitted near plane',
    'Window bands 15 cm proud of towers 150 to 280 m away',
    'near 0.10 m',
    'near fitted to content',
  ),
  reversedZ(
    'Reversed depth',
    'Lit windows 5.5 cm proud of towers 250 to 600 m across the river',
    'standard depth',
    'reversed float depth',
  ),
  tieBreak(
    'Coplanar tie-break',
    'Barriers 8.4 m long on an 8 m pitch, and overlapping ground patches',
    'tie-break off',
    'Scene.coplanarTieBreak',
  );

  const DepthDemoAct(this.title, this.caption, this.before, this.after);

  final String title;
  final String caption;
  final String before;
  final String after;
}

/// Side-by-side comparisons of the engine's z-fighting mitigations. Each act
/// builds the same content into two scenes that differ only in the setting
/// under test, and flies one scripted camera through both.
///
/// `--dart-define=DEPTH_DEMO=<act>` opens straight into an act with the
/// example chrome hidden, plays it once, and quits, for recording.
class ExampleDepthPrecision extends StatefulWidget {
  const ExampleDepthPrecision({super.key});

  @override
  State<ExampleDepthPrecision> createState() => _ExampleDepthPrecisionState();
}

const String _demoActName = String.fromEnvironment('DEPTH_DEMO');

/// Seconds one act plays in demo mode.
const double _actSeconds = 16.0;

class _ExampleDepthPrecisionState extends State<ExampleDepthPrecision> {
  late DepthDemoAct _act;
  late _ActScenes _scenes;
  final Stopwatch _clock = Stopwatch()..start();
  Timer? _quitTimer;
  bool get _demoMode => _demoActName.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _act = DepthDemoAct.values.firstWhere(
      (a) => a.name == _demoActName,
      orElse: () => DepthDemoAct.layers,
    );
    _scenes = _ActScenes.build(_act);
    if (_demoMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        exampleChromeVisible.value = false;
      });
      // A short settle before the clock starts, then one pass, then quit.
      _clock
        ..stop()
        ..reset();
      Timer(const Duration(milliseconds: 1500), _clock.start);
      _quitTimer = Timer(
        Duration(milliseconds: (1500 + _actSeconds * 1000 + 500).round()),
        quitDepthDemo,
      );
    }
  }

  @override
  void dispose() {
    _quitTimer?.cancel();
    if (_demoMode) exampleChromeVisible.value = true;
    super.dispose();
  }

  void _select(DepthDemoAct act) {
    setState(() {
      _act = act;
      _scenes = _ActScenes.build(act);
      _clock
        ..reset()
        ..start();
    });
  }

  double get _t => (_clock.elapsedMicroseconds / 1e6) % _actSeconds;

  @override
  Widget build(BuildContext context) {
    final camera = _scenes.camera;
    return Stack(
      children: [
        Row(
          children: [
            for (final (index, scene) in [
              _scenes.before,
              _scenes.after,
            ].indexed)
              Expanded(
                child: Stack(
                  children: [
                    SceneView(
                      scene,
                      cameraBuilder: (_) => camera(_t),
                      onTick: (_, _) => _scenes.tick(_t),
                    ),
                    _Label(
                      heading: index == 0 ? 'BEFORE' : 'AFTER',
                      detail: index == 0 ? _act.before : _act.after,
                      readout: index == 1 && _act == DepthDemoAct.nearFit
                          ? () {
                              // A debug readout of the plane the fit chose.
                              // ignore: invalid_use_of_visible_for_testing_member
                              final near = _scenes.after.debugFittedNearPlane();
                              return near == null
                                  ? null
                                  : 'near ${near.toStringAsFixed(2)} m';
                            }
                          : null,
                    ),
                  ],
                ),
              ),
          ],
        ),
        // The split.
        Align(
          alignment: Alignment.center,
          child: Container(width: 2, color: Colors.white70),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 28),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${_act.title}. ${_act.caption}.',
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
          ),
        ),
        if (!_demoMode)
          Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SegmentedButton<DepthDemoAct>(
                segments: [
                  for (final act in DepthDemoAct.values)
                    ButtonSegment(value: act, label: Text(act.title)),
                ],
                selected: {_act},
                onSelectionChanged: (s) => _select(s.first),
              ),
            ),
          ),
      ],
    );
  }
}

class _Label extends StatefulWidget {
  const _Label({required this.heading, required this.detail, this.readout});

  final String heading;
  final String detail;
  final String? Function()? readout;

  @override
  State<_Label> createState() => _LabelState();
}

class _LabelState extends State<_Label> {
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    if (widget.readout != null) {
      _refresh = Timer.periodic(
        const Duration(milliseconds: 100),
        (_) => setState(() {}),
      );
    }
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final readout = widget.readout?.call();
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.heading,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              Text(
                widget.detail,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
              if (readout != null)
                Text(
                  readout,
                  style: const TextStyle(
                    color: Colors.amberAccent,
                    fontSize: 16,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The two scenes of an act and the camera path both share.
class _ActScenes {
  _ActScenes(this.before, this.after, this.camera, {this.onTick});

  final Scene before;
  final Scene after;
  final PerspectiveCamera Function(double t) camera;
  final void Function(double t)? onTick;

  void tick(double t) => onTick?.call(t);

  static _ActScenes build(DepthDemoAct act) => switch (act) {
    DepthDemoAct.layers => _buildLayers(),
    DepthDemoAct.nearFit => _buildNearFit(),
    DepthDemoAct.reversedZ => _buildReversedZ(),
    DepthDemoAct.tieBreak => _buildTieBreak(),
  };
}

// A dusk sky, so flat-shaded content reads against it.
Skybox _sky() => Skybox(
  GradientSkySource(
    zenithColor: vm.Vector3(0.05, 0.07, 0.18),
    horizonColor: vm.Vector3(0.55, 0.32, 0.30),
    groundColor: vm.Vector3(0.06, 0.06, 0.08),
    sunColor: vm.Vector3.zero(),
  ),
);

UnlitMaterial _flat(double r, double g, double b) =>
    UnlitMaterial()..baseColorFactor = vm.Vector4(r, g, b, 1);

// A scene with the shared look and the engine defaults the act does not
// test pinned, so the two halves differ only in [configure].
Scene _sceneWith(void Function(Scene scene) configure) {
  final scene = Scene()
    ..skybox = _sky()
    ..antiAliasingMode = AntiAliasingMode.msaa;
  configure(scene);
  return scene;
}

Node _box(vm.Vector3 size, Material material, vm.Vector3 center) =>
    Node(mesh: Mesh(CuboidGeometry(size), material))..position = center;

// An upright quad of [width] by [height] facing -z (toward a camera looking
// down +z), centered at [center].
Node _screen(
  double width,
  double height,
  Material material,
  vm.Vector3 center,
) {
  return Node(
      mesh: Mesh(PlaneGeometry(width: width, depth: height), material),
    )
    ..position = center
    ..rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), -pi / 2);
}

// Act 1. Gantry signs span a street: each is a black backing box with a
// bright screen 5 mm in front of it, the spacing an agent-built billboard
// typically uses. The road's dashed center line and crosswalks lie flush on
// the road. The camera pulls back from the first sign to beyond the last,
// so the signs recede from 10 m to about 450 m.
_ActScenes _buildLayers() {
  void content(Scene scene, {required int overlayLayer}) {
    final asphalt = _flat(0.10, 0.10, 0.11);
    final paint = _flat(0.92, 0.90, 0.80)..depthLayer = overlayLayer;
    final backing = _flat(0.01, 0.01, 0.01);
    final post = _flat(0.20, 0.21, 0.24);
    final building = _flat(0.07, 0.07, 0.10);
    final screens = [
      _flat(0.95, 0.20, 0.55),
      _flat(0.15, 0.80, 0.95),
      _flat(0.98, 0.80, 0.15),
      _flat(0.30, 0.95, 0.35),
    ];
    for (final s in screens) {
      s.depthLayer = overlayLayer;
    }

    scene.add(
      Node(mesh: Mesh(PlaneGeometry(width: 16, depth: 700), asphalt))
        ..position = vm.Vector3(0, 0, 300),
    );
    // Dashed center line and a crosswalk every 50 m, flush with the road.
    for (var z = -200.0; z < 650; z += 6) {
      scene.add(
        Node(mesh: Mesh(PlaneGeometry(width: 0.25, depth: 3), paint))
          ..position = vm.Vector3(0, 0, z),
      );
    }
    for (var z = 0.0; z < 650; z += 50) {
      for (var x = -6.0; x <= 6.0; x += 1.5) {
        scene.add(
          Node(mesh: Mesh(PlaneGeometry(width: 0.8, depth: 3.5), paint))
            ..position = vm.Vector3(x, 0, z + 25),
        );
      }
    }
    // Buildings lining the street.
    final random = Random(7);
    for (var z = -200.0; z < 650; z += 18) {
      for (final side in [-1.0, 1.0]) {
        final height = 14 + random.nextDouble() * 30;
        scene.add(
          _box(
            vm.Vector3(10, height, 16),
            building,
            vm.Vector3(side * 14, height / 2, z),
          ),
        );
      }
    }
    // Gantry signs.
    var i = 0;
    for (final z in [20.0, 60.0, 110.0, 170.0, 240.0, 330.0, 440.0]) {
      final backingDepth = 0.3;
      scene.add(
        _box(vm.Vector3(11, 5, backingDepth), backing, vm.Vector3(0, 9, z)),
      );
      for (final x in [-5.2, 5.2]) {
        scene.add(_box(vm.Vector3(0.4, 7, 0.4), post, vm.Vector3(x, 3.5, z)));
      }
      // The screen sits 5 mm in front of the backing's camera-facing face.
      scene.add(
        _screen(
          10,
          4.2,
          screens[i++ % screens.length],
          vm.Vector3(0, 9, z - backingDepth / 2 - 0.005),
        ),
      );
    }
  }

  // Standard depth and the authored near plane on both sides, so only the
  // layer differs.
  void standard(Scene s) => s
    ..fitNearPlane = false
    ..reversedDepth = false;
  final before = _sceneWith(standard);
  final after = _sceneWith(standard);
  content(before, overlayLayer: 0);
  content(after, overlayLayer: 1);
  return _ActScenes(before, after, (t) {
    final u = t / _actSeconds;
    final eased = u * u * (3 - 2 * u);
    final z = 5 - eased * 230;
    return PerspectiveCamera(
      position: vm.Vector3(1.5, 4.0 + eased * 6, z),
      target: vm.Vector3(0, 7.5, z + 60),
      fovNear: 0.1,
      fovFar: 1000,
    );
  });
}

// Act 2. A skyline ring around a race track, built the way the reported
// game builds it: dark towers wrapped by window bands 15 cm proud, 165 to
// 235 m from the track center. A chase camera circles the track 3.6 m up,
// so nothing comes within a few metres of it while the towers sit 150 to
// 280 m away.
_ActScenes _buildNearFit() {
  void content(Scene scene) {
    final ground = _flat(0.05, 0.08, 0.05);
    final road = _flat(0.12, 0.12, 0.13);
    final car = _flat(0.85, 0.10, 0.10);
    final tones = [
      _flat(0.06, 0.06, 0.10),
      _flat(0.09, 0.08, 0.12),
      _flat(0.05, 0.07, 0.09),
    ];
    final warm = _flat(1.0, 0.55, 0.20);
    final cool = _flat(0.20, 0.60, 1.0);

    scene.add(Node(mesh: Mesh(PlaneGeometry(width: 700, depth: 700), ground)));
    final track = Node(
      mesh: Mesh(
        RingGeometry(innerRadius: 52, outerRadius: 64, segments: 128),
        road,
      ),
    )..position = vm.Vector3(0, 0.02, 0);
    scene.add(track);
    scene.add(
      _box(vm.Vector3(1.9, 1.3, 4.2), car, vm.Vector3.zero())..name = 'car',
    );

    final random = Random(7741);
    final towers = InstancedMesh(
      geometry: CuboidGeometry(vm.Vector3.all(1)),
      material: tones[0],
    );
    final towersB = InstancedMesh(
      geometry: CuboidGeometry(vm.Vector3.all(1)),
      material: tones[1],
    );
    final warmBands = InstancedMesh(
      geometry: CuboidGeometry(vm.Vector3.all(1)),
      material: warm,
    );
    final coolBands = InstancedMesh(
      geometry: CuboidGeometry(vm.Vector3.all(1)),
      material: cool,
    );
    const count = 64;
    for (var i = 0; i < count; i++) {
      final angle = i / count * pi * 2 + (random.nextDouble() - 0.5) * 0.05;
      final radius = 165 + random.nextDouble() * 70;
      final x = sin(angle) * radius;
      final z = cos(angle) * radius;
      final w = 12 + random.nextDouble() * 16;
      final d = 12 + random.nextDouble() * 16;
      final r = random.nextDouble();
      final h = 16 + r * r * 64;
      final rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), angle);
      (i.isEven ? towers : towersB).addInstance(
        vm.Matrix4.compose(
          vm.Vector3(x, h / 2, z),
          rotation,
          vm.Vector3(w, h, d),
        ),
      );
      final bands = 1 + random.nextInt(3);
      for (var b = 0; b < bands; b++) {
        final y = h * (0.3 + 0.6 * random.nextDouble());
        (random.nextDouble() < 0.7 ? warmBands : coolBands).addInstance(
          vm.Matrix4.compose(
            vm.Vector3(x, y, z),
            rotation,
            vm.Vector3(w + 0.3, 0.7, d + 0.3),
          ),
        );
      }
    }
    for (final mesh in [towers, towersB, warmBands, coolBands]) {
      scene.add(Node()..addComponent(InstancedMeshComponent(mesh)));
    }
  }

  // Standard depth on both sides, so only the near plane differs.
  final before = _sceneWith(
    (s) => s
      ..fitNearPlane = false
      ..reversedDepth = false,
  );
  final after = _sceneWith(
    (s) => s
      ..fitNearPlane = true
      ..reversedDepth = false,
  );
  content(before);
  content(after);

  vm.Vector3 trackPoint(double angle) =>
      vm.Vector3(sin(angle) * 58, 0, cos(angle) * 58);
  const speed = 2 * pi / _actSeconds * 0.6;

  void moveCar(Scene scene, double t) {
    final carNode = scene.root.children.firstWhere((n) => n.name == 'car');
    final angle = t * speed;
    carNode.position = trackPoint(angle) + vm.Vector3(0, 0.65, 0);
    carNode.rotation = vm.Quaternion.axisAngle(
      vm.Vector3(0, 1, 0),
      angle + pi / 2,
    );
  }

  return _ActScenes(
    before,
    after,
    (t) {
      final angle = t * speed;
      final ahead = trackPoint(angle);
      final behind = trackPoint(angle - 0.15);
      // Look along the track and a little outward, at the skyline.
      final outward = vm.Vector3(sin(angle), 0, cos(angle)) * 18;
      return PerspectiveCamera(
        position: behind + vm.Vector3(0, 3.6, 0),
        target: ahead + outward + vm.Vector3(0, 6, 0),
        fovRadiansY: 62 * vm.degrees2Radians,
        fovNear: 0.1,
        fovFar: 500,
      );
    },
    onTick: (t) {
      moveCar(before, t);
      moveCar(after, t);
    },
  );
}

// Act 3. A far shore of towers across a river, built the way the reported
// demo builds it: each tower's lit windows are boxes 5.5 cm proud of its
// face, and the towers stand 250 to 600 m from an aerial camera with a
// 0.09 m near plane. A buoy floats beside the camera path, so a fitted near
// plane could not help; only the depth mapping differs.
_ActScenes _buildReversedZ() {
  void content(Scene scene) {
    final water = _flat(0.03, 0.06, 0.10);
    final tones = [
      _flat(0.07, 0.07, 0.11),
      _flat(0.10, 0.08, 0.12),
      _flat(0.06, 0.08, 0.10),
    ];
    final windowColors = [
      _flat(1.0, 0.72, 0.30),
      _flat(0.55, 0.85, 1.0),
      _flat(1.0, 0.45, 0.65),
    ];
    final buoy = _flat(0.95, 0.35, 0.10);
    scene.add(
      Node(mesh: Mesh(PlaneGeometry(width: 3000, depth: 3000), water))
        ..position = vm.Vector3(0, -0.6, 300),
    );
    final random = Random(34);
    final towerMeshes = [
      for (final tone in tones)
        InstancedMesh(
          geometry: CuboidGeometry(vm.Vector3.all(1)),
          material: tone,
        ),
    ];
    final windowMeshes = [
      for (final color in windowColors)
        InstancedMesh(
          geometry: CuboidGeometry(vm.Vector3.all(1)),
          material: color,
        ),
    ];
    for (var i = 0; i < 40; i++) {
      final x = -420.0 + i * 21.0 + random.nextDouble() * 6;
      final front = 250.0 + random.nextDouble() * 350;
      final w = 14.0 + random.nextDouble() * 6;
      final h = 40.0 + random.nextDouble() * 110;
      const d = 16.0;
      towerMeshes[i % 3].addInstance(
        vm.Matrix4.compose(
          vm.Vector3(x, h / 2, front + d / 2),
          vm.Quaternion.identity(),
          vm.Vector3(w, h, d),
        ),
      );
      // Window boxes 5.5 cm proud of the face toward the camera.
      final windows = windowMeshes[random.nextInt(3)];
      for (var row = 3.0; row < h - 3; row += 3.2) {
        for (var col = -w / 2 + 1.4; col < w / 2 - 1.0; col += 2.2) {
          if (random.nextDouble() < 0.35) continue;
          windows.addInstance(
            vm.Matrix4.compose(
              vm.Vector3(x + col, row, front - 0.03),
              vm.Quaternion.identity(),
              vm.Vector3(1.2, 1.6, 0.05),
            ),
          );
        }
      }
    }
    for (final mesh in [...towerMeshes, ...windowMeshes]) {
      scene.add(Node()..addComponent(InstancedMeshComponent(mesh)));
    }
    scene.add(
      Node(mesh: Mesh(SphereGeometry(radius: 0.6), buoy))..name = 'buoy',
    );
  }

  // Both sides keep the authored 0.09 m plane; only the mapping differs.
  final before = _sceneWith(
    (s) => s
      ..fitNearPlane = false
      ..reversedDepth = false,
  );
  final after = _sceneWith(
    (s) => s
      ..fitNearPlane = false
      ..reversedDepth = true,
  );
  content(before);
  content(after);

  vm.Vector3 eyeAt(double t) {
    final u = t / _actSeconds;
    return vm.Vector3(-120 + u * 240, 48 - u * 30, -40 + u * 30);
  }

  void moveBuoy(Scene scene, double t) {
    final eye = eyeAt(t);
    scene.root.children.firstWhere((n) => n.name == 'buoy').position =
        vm.Vector3(eye.x + 1.5, eye.y - 2.2, eye.z + 3.0);
  }

  return _ActScenes(
    before,
    after,
    (t) {
      final eye = eyeAt(t);
      return PerspectiveCamera(
        position: eye,
        target: vm.Vector3(eye.x * 0.6, 35, 420),
        fovRadiansY: 50 * vm.degrees2Radians,
        fovNear: 0.09,
        fovFar: 2200,
      );
    },
    onTick: (t) {
      moveBuoy(before, t);
      moveBuoy(after, t);
    },
  );
}

// Act 4. Exact overlaps that no precision can fix, the reported game's track:
// barriers 8.4 m long placed every 8 m in alternating colors (so every joint
// holds 0.4 m of faces in one plane), and ground patches of three colors at
// one height overlapping each other. A chase camera drives the track.
_ActScenes _buildTieBreak() {
  void content(Scene scene) {
    final ground = _flat(0.06, 0.11, 0.05);
    final road = _flat(0.12, 0.12, 0.13);
    final red = _flat(0.78, 0.06, 0.04);
    final white = _flat(0.86, 0.86, 0.88);
    final patchColors = [
      _flat(0.16, 0.28, 0.08),
      _flat(0.04, 0.10, 0.04),
      _flat(0.22, 0.14, 0.07),
    ];
    scene.add(
      Node(mesh: Mesh(PlaneGeometry(width: 400, depth: 900), ground))
        ..position = vm.Vector3(0, 0, 350),
    );
    scene.add(
      Node(mesh: Mesh(PlaneGeometry(width: 8, depth: 900), road))
        ..position = vm.Vector3(0, 0.01, 350),
    );
    final barrierRed = InstancedMesh(
      geometry: CuboidGeometry(vm.Vector3(0.5, 0.9, 8.4)),
      material: red,
    );
    final barrierWhite = InstancedMesh(
      geometry: CuboidGeometry(vm.Vector3(0.5, 0.9, 8.4)),
      material: white,
    );
    var index = 0;
    for (var z = -40.0; z < 800; z += 8) {
      for (final side in [-1.0, 1.0]) {
        ((index + (side > 0 ? 1 : 0)).isEven ? barrierRed : barrierWhite)
            .addInstance(vm.Matrix4.translationValues(side * 4.25, 0.45, z));
      }
      index++;
    }
    final random = Random(7741);
    final patches = [
      for (final color in patchColors)
        InstancedMesh(
          geometry: CuboidGeometry(vm.Vector3.all(1)),
          material: color,
        ),
    ];
    for (var i = 0; i < 260; i++) {
      final side = random.nextBool() ? -1.0 : 1.0;
      final x = side * (9 + random.nextDouble() * 60);
      final z = random.nextDouble() * 700;
      final w = 3 + random.nextDouble() * 7;
      final d = 3 + random.nextDouble() * 7;
      final yaw = random.nextDouble() * pi;
      // Every patch at one height, so overlapping colors share a plane.
      patches[i % 3].addInstance(
        vm.Matrix4.compose(
          vm.Vector3(x, 0.02, z),
          vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), yaw),
          vm.Vector3(w, 0.02, d),
        ),
      );
    }
    for (final mesh in [barrierRed, barrierWhite, ...patches]) {
      scene.add(Node()..addComponent(InstancedMeshComponent(mesh)));
    }
  }

  final before = _sceneWith((s) => s.coplanarTieBreak = false);
  final after = _sceneWith((s) => s.coplanarTieBreak = true);
  content(before);
  content(after);
  return _ActScenes(before, after, (t) {
    final z = t * 28.0;
    return PerspectiveCamera(
      position: vm.Vector3(-1.2, 3.6, z),
      target: vm.Vector3(0.6, 1.2, z + 14),
      fovRadiansY: 62 * vm.degrees2Radians,
      fovNear: 0.1,
      fovFar: 500,
    );
  });
}
