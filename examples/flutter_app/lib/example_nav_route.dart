import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_settings.dart';

// Added to the heading derived from the lane tangent, to account for the
// car model's forward axis. Flip the sign if the car faces backward.
const double _carHeadingOffset = -pi / 2;

const double _roadWidth = 5.0;
const double _markingHeight = 0.05;

/// An infotainment-style navigation scene: a long looping road track
/// with painted edge and center lines, and the example car driving it
/// indefinitely.
///
/// Exercises the dynamic geometry API: [PlaneGeometry], [CatmullRomPath],
/// [RibbonGeometry], and [PolylineGeometry] (solid and dashed).
class ExampleNavRoute extends StatefulWidget {
  const ExampleNavRoute({super.key});

  @override
  ExampleNavRouteState createState() => ExampleNavRouteState();
}

class ExampleNavRouteState extends State<ExampleNavRoute> {
  final Scene scene = Scene();

  // The waypoints of the closed loop. The track runs through them in
  // order and back to the first. They are spaced widely around a long
  // elongated circuit that winds gently, so the lap is long while every
  // curve stays large-radius and smooth. The three around the join,
  // with the first repeated to close the path, are collinear and evenly
  // spaced, so the Catmull-Rom tangents match across the seam and the
  // car's heading does not kink as it loops.
  static final List<vm.Vector3> _loopWaypoints = [
    vm.Vector3(0, 0.05, 16), // join
    vm.Vector3(4, 0.05, 16),
    vm.Vector3(10, 0.05, 17),
    vm.Vector3(16, 0.05, 14),
    vm.Vector3(20, 0.05, 8),
    vm.Vector3(21, 0.05, 0),
    vm.Vector3(19, 0.05, -8),
    vm.Vector3(14, 0.05, -13),
    vm.Vector3(7, 0.05, -14),
    vm.Vector3(0, 0.05, -12),
    vm.Vector3(-7, 0.05, -14),
    vm.Vector3(-14, 0.05, -13),
    vm.Vector3(-19, 0.05, -8),
    vm.Vector3(-21, 0.05, 0),
    vm.Vector3(-20, 0.05, 8),
    vm.Vector3(-16, 0.05, 14),
    vm.Vector3(-10, 0.05, 17),
    vm.Vector3(-4, 0.05, 16), // collinear with the join and its neighbor
  ];

  // The looping track the car drives, closed back to the join.
  static final CatmullRomPath mainRoad = CatmullRomPath([
    ..._loopWaypoints,
    _loopWaypoints.first,
  ]);

  // Every camera-facing marking line, rebuilt each frame.
  final List<PolylineGeometry> markings = [];

  // The car model, loaded asynchronously, with the scale and ground
  // offset that fit it to the road.
  Node? carNode;
  double carScale = 1.0;
  double carLift = 0.0;

  // Smoothing state for the chase camera, carried across frames.
  final _FollowCamState _followCam = _FollowCamState();

  // The car's animated parts (doors, wheels), keyed by node name.
  final Map<String, _CarPart> _carParts = {};
  bool _carPartsReady = false;
  bool _controlsOpen = false;
  // Rolling wheel-spin angle, advanced from the spin slider each frame.
  double _wheelRotation = 0.0;

  // The animated route line ahead of the car. Its mesh is rebuilt every
  // frame by the painter; the node and material persist.
  final Node _navNode = Node();
  final UnlitMaterial _navMaterial = UnlitMaterial();

  // The free "inspection" camera, and whether it is active. While
  // inactive it is kept synced to the chase camera (by the painter), so
  // toggling it on does not jump the view.
  bool _freeCamera = false;
  final _FreeCamState _freeCam = _FreeCamState();

  // Total elapsed seconds, updated each frame from SceneView's tick.
  double _elapsedSeconds = 0;
  // The camera computed each frame by the frame updater and returned to
  // SceneView. Seeded with a sensible default for the first frame.
  Camera _camera = PerspectiveCamera(
    position: vm.Vector3(0, 12, 30),
    target: vm.Vector3(0, 0, 0),
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // The scene hot reloads in place; onReload re-grabs the car parts (the
    // patch replaces the inner node instances). _applyCarParts re-poses them
    // each frame, so only the references need refreshing.
    final carRoot = await loadScene(
      'assets_src/fcar.glb',
      onReload: _grabCarParts,
    );
    if (!mounted) {
      return;
    }

    // The directional "sun" and its cascaded shadows are driven by the shared
    // settings panel via ExampleSettings.applyTo.

    // The ground. A lit material, so it receives the car's shadow.
    scene.add(
      Node(
        mesh: Mesh(
          PlaneGeometry(width: 64, depth: 64),
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.13, 0.14, 0.16, 1.0)
            ..metallicFactor = 0.0
            ..roughnessFactor = 0.95,
        ),
      ),
    );

    _addRoad(mainRoad);

    // The route line ahead of the car lives in its own node; the
    // painter rebuilds its mesh every frame.
    scene.add(_navNode);

    // The example car drives the loop. It is wrapped in a parent node so
    // its imported transform is left intact, and scaled from its bounds.
    carRoot.name = 'Car';
    final parent = Node()..add(carRoot);
    scene.add(parent);
    final bounds = parent.combinedLocalBounds;
    if (bounds != null) {
      final extent = bounds.max - bounds.min;
      final longest = [extent.x, extent.y, extent.z].reduce(max);
      carScale = longest > 0 ? 2.5 / longest : 1.0;
      carLift = -bounds.min.y * carScale;
    }

    // Capture the doors and wheels so the controls submenu can pose them.
    _grabCarParts(carRoot);

    setState(() => carNode = parent);
  }

  // (Re-)resolves the posable car parts by name, preserving each part's current
  // slider amount. Each part remembers its imported transform to pose from;
  // _applyCarParts re-poses them every frame. Also used as the model reload
  // callback, since a reload swaps the inner node instances.
  void _grabCarParts(Node carRoot) {
    for (final name in _carPartNames) {
      final node = carRoot.getChildByNamePath([name]);
      if (node != null) {
        final amount = _carParts[name]?.amount ?? 0.0;
        _carParts[name] = _CarPart(node, node.localTransform.clone())
          ..amount = amount;
      }
    }
    _carPartsReady = _carParts.length == _carPartNames.length;
  }

  // Adds the road's surface ribbon plus its edge and center marking
  // lines.
  void _addRoad(ScenePath road) {
    // A lit material, so the road receives the car's shadow.
    scene.add(
      Node(
        mesh: Mesh(
          RibbonGeometry(road, width: _roadWidth, stations: 280),
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.30, 0.31, 0.35, 1.0)
            ..metallicFactor = 0.0
            ..roughnessFactor = 0.85,
        ),
      ),
    );

    // Solid white edge lines.
    for (final side in [-_roadWidth / 2, _roadWidth / 2]) {
      final line = PolylineGeometry(
        _offsetPath(road, side, lift: _markingHeight),
        width: 8,
      );
      markings.add(line);
      scene.add(Node(mesh: Mesh(line, UnlitMaterial())));
    }

    // A dashed yellow center line, each dash rounded at both ends.
    final center = PolylineGeometry(
      _offsetPath(road, 0.0, lift: _markingHeight),
      width: 8 * 0.01,
      widthMode: PolylineWidthMode.worldUnits,
      dash: const DashPattern(
        dashLength: 1.6,
        gapLength: 1.2,
        cap: PolylineCap.round,
      ),
    );
    markings.add(center);
    scene.add(
      Node(
        mesh: Mesh(
          center,
          UnlitMaterial()..baseColorFactor = vm.Vector4(0.95, 0.78, 0.20, 1.0),
        ),
      ),
    );
  }

  // Poses the car's doors and wheels from the current control amounts.
  // Runs every frame so slider changes and the rolling wheels both take
  // effect. The door and wheel math mirrors the Car example.
  void _applyCarParts() {
    if (!_carPartsReady) return;

    // Side doors swing open about their hinge.
    for (final name in const [
      'DoorFront.L',
      'DoorFront.R',
      'DoorBack.L',
      'DoorBack.R',
    ]) {
      final part = _carParts[name]!;
      part.node.localTransform = part.startTransform.clone()
        ..rotate(vm.Vector3(0, -1, 0), part.amount * pi / 2);
    }
    final frunk = _carParts['Frunk']!;
    frunk.node.localTransform = frunk.startTransform.clone()
      ..rotate(vm.Vector3(0, 0, 1), frunk.amount * pi / 2);
    final trunk = _carParts['Trunk']!;
    trunk.node.localTransform = trunk.startTransform.clone()
      ..rotate(vm.Vector3(0, 0, -1), trunk.amount * pi / 2);

    // The spin slider sets a speed, accumulated into a rolling angle.
    _wheelRotation += _carParts['WheelBack.L']!.amount / 10;
    for (final name in const ['WheelBack.L', 'WheelBack.R']) {
      final wheel = _carParts[name]!;
      wheel.node.localTransform = wheel.startTransform.clone()
        ..rotate(vm.Vector3(0, 0, -1), _wheelRotation);
    }
    // The front wheels also steer about their vertical axis.
    final steer = _carParts['WheelFront.L']!.amount;
    for (final name in const ['WheelFront.L', 'WheelFront.R']) {
      final wheel = _carParts[name]!;
      wheel.node.localTransform =
          wheel.startTransform.clone() *
          vm.Matrix4.rotationY(-steer / 2) *
          vm.Matrix4.rotationZ(-_wheelRotation);
    }
  }

  // Toggles the free inspection camera. Returning to the chase camera
  // snaps it back onto the car.
  void _toggleFreeCamera() {
    setState(() {
      _freeCamera = !_freeCamera;
      _freeCam.heldKeys.clear();
      _freeCam.lastElapsed = _elapsedSeconds;
      if (!_freeCamera) {
        _followCam.anchorPosition = null;
        _followCam.anchorDirection = null;
      }
    });
  }

  // Tracks held keys for the free camera. Movement keys are consumed
  // while it is active so the platform does not beep at them.
  KeyEventResult _onFreeCameraKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      _freeCam.heldKeys.add(event.logicalKey);
    } else if (event is KeyUpEvent) {
      _freeCam.heldKeys.remove(event.logicalKey);
    }
    return _freeCamera && _freeCamMoveKeys.contains(event.logicalKey)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  // Rotates the free camera by a drag.
  void _onFreeCameraLook(DragUpdateDetails details) {
    setState(() {
      _freeCam.yaw += details.delta.dx * 0.005;
      _freeCam.pitch = (_freeCam.pitch - details.delta.dy * 0.005).clamp(
        -1.5,
        1.5,
      );
    });
  }

  // Advances the free camera by the held movement keys, once per frame.
  void _moveFreeCamera() {
    final dt = (_elapsedSeconds - _freeCam.lastElapsed).clamp(0.0, 0.1);
    _freeCam.lastElapsed = _elapsedSeconds;
    const speed = 20.0;
    final keys = _freeCam.heldKeys;
    final forward = _freeCam.forward;
    final right = vm.Vector3(0, 1, 0).cross(forward)..normalize();
    final move = vm.Vector3.zero();
    if (keys.contains(LogicalKeyboardKey.keyW)) move.add(forward);
    if (keys.contains(LogicalKeyboardKey.keyS)) move.sub(forward);
    if (keys.contains(LogicalKeyboardKey.keyD)) move.add(right);
    if (keys.contains(LogicalKeyboardKey.keyA)) move.sub(right);
    if (keys.contains(LogicalKeyboardKey.space)) {
      move.add(vm.Vector3(0, 1, 0));
    }
    if (keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight)) {
      move.sub(vm.Vector3(0, 1, 0));
    }
    if (move.length2 > 1e-6) {
      move.normalize();
      _freeCam.position += move * (speed * dt);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _onFreeCameraKey,
      child: Stack(
        children: [
          // The 3D scene. In free-camera mode a drag rotates the view.
          Positioned.fill(
            child: GestureDetector(
              onPanUpdate: _freeCamera ? _onFreeCameraLook : null,
              // LayoutBuilder gives the per-frame frame updater the viewport
              // size it needs to lay out the camera-facing marking lines.
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = constraints.biggest;
                  return SceneView(
                    scene,
                    cameraBuilder: (elapsed) => _camera,
                    onTick: (elapsed, deltaSeconds) {
                      _elapsedSeconds = elapsed.inMicroseconds / 1e6;
                      _applyCarParts();
                      if (_freeCamera) _moveFreeCamera();
                      _camera = _NavRouteFrame(
                        scene: scene,
                        road: mainRoad,
                        markings: markings,
                        carNode: carNode,
                        carScale: carScale,
                        carLift: carLift,
                        followCam: _followCam,
                        freeCamera: _freeCamera,
                        freeCam: _freeCam,
                        navNode: _navNode,
                        navMaterial: _navMaterial,
                        elapsedSeconds: _elapsedSeconds,
                        size: size,
                      ).update();
                      exampleSettings.applyTo(scene);
                    },
                  );
                },
              ),
            ),
          ),
          if (_carPartsReady)
            Positioned(
              top: 56,
              left: 8,
              child: _CarControlsMenu(
                open: _controlsOpen,
                onToggle: () => setState(() => _controlsOpen = !_controlsOpen),
                parts: _carParts,
                onControl: (key, value) =>
                    setState(() => _carParts[key]!.amount = value),
              ),
            ),
          Positioned(
            left: 8,
            bottom: 8,
            child: _CameraToggle(
              freeCamera: _freeCamera,
              onToggle: _toggleFreeCamera,
            ),
          ),
        ],
      ),
    );
  }
}

// The horizontal unit vector perpendicular to [tangent].
vm.Vector3 _lateral(vm.Vector3 tangent) {
  var lateral = tangent.cross(vm.Vector3(0, 1, 0));
  if (lateral.length2 < 1e-9) lateral = vm.Vector3(1, 0, 0);
  return lateral.normalized();
}

// Samples [path], shifting each point sideways by [offset] along the
// horizontal perpendicular and up by [lift].
List<vm.Vector3> _offsetPath(
  ScenePath path,
  double offset, {
  double lift = 0.0,
}) {
  const samples = 240;
  final result = <vm.Vector3>[];
  for (var i = 0; i < samples; i++) {
    final frame = path.frameAtDistance(path.length * i / (samples - 1));
    final p = frame.position + _lateral(frame.tangent) * offset;
    result.add(vm.Vector3(p.x, p.y + lift, p.z));
  }
  return result;
}

// Arc length between bright bands in the route line, and how fast (in
// pattern cycles per second) the bands flow forward along it.
const double _navWavelength = 20.0;
const double _navPulseSpeed = 0.4;

// Builds the route line: a thick blue ribbon lying flat just above the
// car's lane, starting just ahead of the car and reaching forward along
// the road. A flat ribbon (rather than a camera-facing line) never
// tilts down into the road surface, and ordinary depth testing then
// layers it correctly: above the flat road, below the taller car. Each
// vertex carries a color from a gradient whose bright bands flow away
// from the car as [elapsedSeconds] advances.
MeshGeometry _buildNavLine(
  ScenePath road,
  double carDistance,
  double elapsedSeconds,
) {
  const samples = 88;
  const startOffset = 1.6; // begins just past the car's front
  const aheadLength = 84.0; // how far ahead the route reaches
  const lift = 0.18; // floats just above the road
  const halfWidth = 0.35; // a ~1.1 unit wide ribbon
  final up = vm.Vector3(0, 1, 0);
  final deep = vm.Vector3(0.05, 0.18, 0.55);
  final bright = vm.Vector3(0.45, 0.85, 1.5);

  final builder = GeometryBuilder(deduplicate: false)..normal(up);
  for (var i = 0; i < samples; i++) {
    final t = i / (samples - 1);
    final ahead = startOffset + (aheadLength - startOffset) * t;
    // Ahead of the car is the decreasing-distance direction; wrap so the
    // line reaches across the loop's seam.
    final d = (carDistance - ahead) % road.length;
    final frame = road.frameAtDistance(d);
    final lateral = _lateral(frame.tangent);
    final center = frame.position + lateral * (_roadWidth / 4);
    final y = center.y + lift;
    final left = center - lateral * halfWidth;
    final right = center + lateral * halfWidth;

    // Bright bands flow outward, dimming toward the far end.
    final phase =
        (ahead - startOffset) / _navWavelength -
        elapsedSeconds * _navPulseSpeed;
    final pulse = 0.5 + 0.5 * sin(2 * pi * phase);
    final fade = 1.0 - 0.5 * t;
    final c = (deep + (bright - deep) * pulse)..scale(fade);

    builder
      ..color(vm.Vector4(c.x, c.y, c.z, 1.0))
      ..addVertex(vm.Vector3(left.x, y, left.z))
      ..addVertex(vm.Vector3(right.x, y, right.z));
  }
  // Stitch consecutive cross-sections into a triangle strip. The line is
  // sampled in the car's travel direction (decreasing path distance), so
  // the winding is reversed from a forward-traversed ribbon to keep the
  // surface facing up.
  for (var i = 0; i < samples - 1; i++) {
    final base = i * 2;
    builder
      ..addTriangle(base, base + 1, base + 2)
      ..addTriangle(base + 1, base + 3, base + 2);
  }
  return builder.build();
}

// Mutable smoothing state for the chase camera, carried across frames.
class _FollowCamState {
  vm.Vector3? anchorPosition;
  vm.Vector3? anchorDirection;
  double lastElapsed = 0.0;
}

// The keys the free camera consumes for movement.
final Set<LogicalKeyboardKey> _freeCamMoveKeys = {
  LogicalKeyboardKey.keyW,
  LogicalKeyboardKey.keyA,
  LogicalKeyboardKey.keyS,
  LogicalKeyboardKey.keyD,
  LogicalKeyboardKey.space,
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
};

// Mutable state for the free "inspection" camera: a fly camera driven
// by held keys and drag-to-look.
class _FreeCamState {
  vm.Vector3 position = vm.Vector3(0, 12, 30);
  double yaw = 0.0;
  double pitch = 0.0;
  final Set<LogicalKeyboardKey> heldKeys = {};
  double lastElapsed = 0.0;

  // The unit look direction from [yaw] (around Y) and [pitch].
  vm.Vector3 get forward =>
      vm.Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch));
}

// Computes the camera and updates the scene (car pose, route line, camera-
// facing marking lines) for one frame. SceneView issues the render; this only
// mutates the scene and returns the camera to render with.
class _NavRouteFrame {
  _NavRouteFrame({
    required this.scene,
    required this.road,
    required this.markings,
    required this.carNode,
    required this.carScale,
    required this.carLift,
    required this.followCam,
    required this.freeCamera,
    required this.freeCam,
    required this.navNode,
    required this.navMaterial,
    required this.elapsedSeconds,
    required this.size,
  });

  final Scene scene;
  final ScenePath road;
  final List<PolylineGeometry> markings;
  final Node? carNode;
  final double carScale;
  final double carLift;
  final _FollowCamState followCam;
  final bool freeCamera;
  final _FreeCamState freeCam;
  final Node navNode;
  final UnlitMaterial navMaterial;
  final double elapsedSeconds;
  final Size size;

  PerspectiveCamera update() {
    // The car's pose on the loop. Distance runs backward along the path
    // so the car travels counterclockwise, and its lane is the
    // centerline shifted to the opposite side. Querying the smooth
    // curve directly keeps the heading continuous.
    final distance = (-elapsedSeconds * 4.0) % road.length;
    final frame = road.frameAtDistance(distance);
    final carPosition =
        frame.position + _lateral(frame.tangent) * (_roadWidth / 4);
    // The car travels against the path tangent.
    final travelDirection = -frame.tangent;

    // The free inspection camera replaces the chase camera when active.
    // While the chase camera is in use the free camera is kept synced
    // to it, so toggling the free camera on does not jump the view.
    final PerspectiveCamera camera;
    if (freeCamera) {
      camera = PerspectiveCamera(
        position: freeCam.position.clone(),
        target: freeCam.position + freeCam.forward,
      );
    } else {
      camera = _followCamera(carPosition, travelDirection);
      freeCam.position = camera.position.clone();
      final look = (camera.target - camera.position)..normalize();
      freeCam.yaw = atan2(look.x, look.z);
      freeCam.pitch = asin(look.y.clamp(-1.0, 1.0));
    }

    // The camera-facing marking lines are rebuilt for the current view.
    for (final marking in markings) {
      marking.updateForCamera(camera, size);
    }

    // The route line: a thick blue ribbon along the lane ahead of the
    // car, rebuilt each frame so its gradient pulses forward.
    if (carNode != null) {
      navNode.mesh = Mesh(
        _buildNavLine(road, distance, elapsedSeconds),
        navMaterial,
      );
    }

    final car = carNode;
    if (car != null) {
      final heading =
          atan2(travelDirection.x, travelDirection.z) + _carHeadingOffset;
      car.localTransform =
          vm.Matrix4.translation(
              vm.Vector3(carPosition.x, carPosition.y + carLift, carPosition.z),
            )
            ..rotateY(heading)
            ..scaleByDouble(carScale, carScale, carScale, 1.0);
    }

    return camera;
  }

  // A chase camera that eases along behind the car and looks down at it
  // at 45 degrees. The followed anchor lags the car, which smooths the
  // swing through curves; the camera sits rigidly behind the anchor, so
  // the downward angle stays a constant 45 degrees.
  PerspectiveCamera _followCamera(
    vm.Vector3 carPosition,
    vm.Vector3 travelDirection,
  ) {
    const followDistance = 6.5;
    const lookLift = 0.2;
    const stiffness = 5.0;

    // Ease the anchor toward the car by a time-based fraction.
    final dt = (elapsedSeconds - followCam.lastElapsed).clamp(0.0, 0.05);
    followCam.lastElapsed = elapsedSeconds;
    final blend = 1.0 - exp(-stiffness * dt);

    final anchorPosition = followCam.anchorPosition;
    final anchorDirection = followCam.anchorDirection;
    if (anchorPosition == null || anchorDirection == null) {
      followCam.anchorPosition = carPosition.clone();
      followCam.anchorDirection = travelDirection.clone();
    } else {
      followCam.anchorPosition =
          anchorPosition + (carPosition - anchorPosition) * blend;
      final direction =
          anchorDirection + (travelDirection - anchorDirection) * blend;
      if (direction.length2 > 1e-9) direction.normalize();
      followCam.anchorDirection = direction;
    }

    final anchor = followCam.anchorPosition!;
    final forward = followCam.anchorDirection!;
    // Behind the anchor, raised by the follow distance above the look
    // target: equal horizontal and vertical offsets give a 45 degree
    // downward look.
    return PerspectiveCamera(
      position:
          anchor -
          forward * followDistance +
          vm.Vector3(0.0, lookLift + followDistance / 2, 0.0),
      target: anchor + vm.Vector3(0.0, lookLift + 2, 0.0),
    );
  }
}

// The car node names the controls submenu poses.
const List<String> _carPartNames = [
  'DoorFront.L',
  'DoorFront.R',
  'DoorBack.L',
  'DoorBack.R',
  'Frunk',
  'Trunk',
  'WheelFront.L',
  'WheelFront.R',
  'WheelBack.L',
  'WheelBack.R',
];

// One slider each: a label, the car part whose amount it drives, and
// the slider's range. Back doors and the front-left wheel stand in for
// their mirrored partners, which follow along.
const List<(String, String, double, double)> _carControls = [
  ('Front door L', 'DoorFront.L', 0.0, 1.0),
  ('Front door R', 'DoorFront.R', 0.0, 1.0),
  ('Back door L', 'DoorBack.L', 0.0, 1.0),
  ('Back door R', 'DoorBack.R', 0.0, 1.0),
  ('Frunk', 'Frunk', 0.0, 1.0),
  ('Trunk', 'Trunk', 0.0, 1.0),
  ('Wheel spin', 'WheelBack.L', 0.0, 1.0),
  ('Wheel steer', 'WheelFront.L', -1.0, 1.0),
];

// A car node the controls submenu animates, plus its imported
// transform and the current control amount driving it.
class _CarPart {
  _CarPart(this.node, this.startTransform);

  final Node node;
  final vm.Matrix4 startTransform;
  double amount = 0.0;
}

// A collapsible submenu of sliders that pose the car's doors and
// wheels, styled to match the Toon example's control card.
class _CarControlsMenu extends StatelessWidget {
  const _CarControlsMenu({
    required this.open,
    required this.onToggle,
    required this.parts,
    required this.onControl,
  });

  final bool open;
  final VoidCallback onToggle;
  final Map<String, _CarPart> parts;
  final void Function(String key, double value) onControl;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.black54,
      child: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The toggle header.
            InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Row(
                  children: [
                    const Icon(
                      Icons.directions_car,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Car Controls',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      open ? Icons.expand_less : Icons.expand_more,
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
            ),
            if (open) ...[
              const Divider(height: 1, color: Colors.white24),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (label, key, lo, hi) in _carControls)
                      _SliderRow(
                        label: label,
                        value: parts[key]!.amount,
                        min: lo,
                        max: hi,
                        onChanged: (value) => onControl(key, value),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// A labeled slider styled to match the Toon example's controls.
class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            '$label: ${value.toStringAsFixed(2)}',
            style: const TextStyle(color: Colors.white),
          ),
        ),
        Expanded(
          child: Slider(value: value, min: min, max: max, onChanged: onChanged),
        ),
      ],
    );
  }
}

// A toggle for the free "inspection" camera, with a usage hint shown
// while it is active. Styled to match the Car Controls card.
class _CameraToggle extends StatelessWidget {
  const _CameraToggle({required this.freeCamera, required this.onToggle});

  final bool freeCamera;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (freeCamera)
          Card(
            color: Colors.black54,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                'WASD to move, Space and Shift for up and down, drag to look',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
              ),
            ),
          ),
        Card(
          color: Colors.black54,
          child: InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    freeCamera ? Icons.videocam : Icons.videocam_outlined,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    freeCamera ? 'Free camera' : 'Chase camera',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
