import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

// Added to the heading derived from the lane tangent, to account for the
// car model's forward axis. Flip the sign if the car faces backward.
const double _carHeadingOffset = -pi / 2;

const double _roadWidth = 5.0;
const double _markingHeight = 0.13;

/// An infotainment-style navigation scene: a long looping road track
/// with painted edge and center lines, and the example car driving it
/// indefinitely.
///
/// Exercises the dynamic geometry API: [PlaneGeometry], [CatmullRomPath],
/// [RibbonGeometry], and [PolylineGeometry] (solid and dashed).
class ExampleNavRoute extends StatefulWidget {
  const ExampleNavRoute({super.key, this.elapsedSeconds = 0});
  final double elapsedSeconds;

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

  @override
  void initState() {
    // The ground.
    scene.add(
      Node(
        mesh: Mesh(
          PlaneGeometry(width: 64, depth: 64),
          UnlitMaterial()..baseColorFactor = vm.Vector4(0.13, 0.14, 0.16, 1.0),
        ),
      ),
    );

    _addRoad(mainRoad);

    // The example car drives the loop. It is wrapped in a parent node so
    // its imported transform is left intact, and scaled from its bounds.
    Node.fromAsset('build/models/fcar.model').then((carRoot) {
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
      if (mounted) setState(() => carNode = parent);
    });

    super.initState();
  }

  // Adds the road's surface ribbon plus its edge and center marking
  // lines.
  void _addRoad(ScenePath road) {
    scene.add(
      Node(
        mesh: Mesh(
          RibbonGeometry(road, width: _roadWidth, stations: 280),
          UnlitMaterial()..baseColorFactor = vm.Vector4(0.30, 0.31, 0.35, 1.0),
        ),
      ),
    );

    // Solid white edge lines.
    for (final side in [-_roadWidth / 2, _roadWidth / 2]) {
      final line = PolylineGeometry(
        _offsetPath(road, side, lift: _markingHeight),
        width: 5,
      );
      markings.add(line);
      scene.add(Node(mesh: Mesh(line, UnlitMaterial())));
    }

    // A dashed yellow center line, each dash rounded at both ends.
    final center = PolylineGeometry(
      _offsetPath(road, 0.0, lift: _markingHeight),
      width: 5,
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

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _NavRoutePainter(
        scene: scene,
        road: mainRoad,
        markings: markings,
        carNode: carNode,
        carScale: carScale,
        carLift: carLift,
        followCam: _followCam,
        elapsedSeconds: widget.elapsedSeconds,
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

// Mutable smoothing state for the chase camera, carried across frames.
class _FollowCamState {
  vm.Vector3? anchorPosition;
  vm.Vector3? anchorDirection;
  double lastElapsed = 0.0;
}

class _NavRoutePainter extends CustomPainter {
  _NavRoutePainter({
    required this.scene,
    required this.road,
    required this.markings,
    required this.carNode,
    required this.carScale,
    required this.carLift,
    required this.followCam,
    required this.elapsedSeconds,
  });

  final Scene scene;
  final ScenePath road;
  final List<PolylineGeometry> markings;
  final Node? carNode;
  final double carScale;
  final double carLift;
  final _FollowCamState followCam;
  final double elapsedSeconds;

  @override
  void paint(Canvas canvas, Size size) {
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

    final camera = _followCamera(carPosition, travelDirection);

    // The camera-facing marking lines are rebuilt for the current view.
    for (final marking in markings) {
      marking.updateForCamera(camera, size);
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

    scene.render(camera, canvas, viewport: Offset.zero & size);
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

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
