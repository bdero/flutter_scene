import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// An infotainment-style navigation scene: a ground map, a route
/// corridor ribbon, a camera-facing route line of constant pixel width,
/// and a marker travelling the route.
///
/// Exercises the dynamic geometry API: [PlaneGeometry], [CatmullRomPath],
/// [RibbonGeometry], [PolylineGeometry], and [SphereGeometry].
class ExampleNavRoute extends StatefulWidget {
  const ExampleNavRoute({super.key, this.elapsedSeconds = 0});
  final double elapsedSeconds;

  @override
  ExampleNavRouteState createState() => ExampleNavRouteState();
}

class ExampleNavRouteState extends State<ExampleNavRoute> {
  final Scene scene = Scene();

  // Waypoints of the planned route, smoothed into a curve.
  static final CatmullRomPath route = CatmullRomPath([
    vm.Vector3(-8, 0.05, -6),
    vm.Vector3(-3, 0.05, -8),
    vm.Vector3(2, 0.05, -3),
    vm.Vector3(6, 0.05, 3),
    vm.Vector3(1, 0.05, 7),
    vm.Vector3(-5, 0.05, 4),
  ]);

  late final PolylineGeometry routeLine;
  late final Node markerNode;

  @override
  void initState() {
    // The ground map.
    final ground = Node(
      mesh: Mesh(
        PlaneGeometry(width: 40, depth: 40),
        UnlitMaterial()..baseColorFactor = vm.Vector4(0.16, 0.17, 0.2, 1.0),
      ),
    );
    scene.add(ground);

    // A flat corridor ribbon along the route, on the ground.
    final corridor = Node(
      mesh: Mesh(
        RibbonGeometry(route, width: 1.8, stations: 96),
        UnlitMaterial()..baseColorFactor = vm.Vector4(0.1, 0.2, 0.35, 1.0),
      ),
    );
    scene.add(corridor);

    // The route line: a camera-facing strip of constant pixel width,
    // sampled from the smooth route and floated above the ground.
    final samples = route.sample(96, evenlySpaced: true);
    final linePoints = <vm.Vector3>[
      for (final p in samples) vm.Vector3(p.x, 0.3, p.z),
    ];
    routeLine = PolylineGeometry(
      linePoints,
      width: 16,
      cap: PolylineCap.round,
      join: PolylineJoin.round,
      perVertexColor: <vm.Vector4>[
        for (var i = 0; i < linePoints.length; i++)
          _lerpColor(
            vm.Vector4(0.2, 0.85, 1.0, 1.0),
            vm.Vector4(0.15, 0.35, 1.0, 1.0),
            i / (linePoints.length - 1),
          ),
      ],
    );
    scene.add(Node(mesh: Mesh(routeLine, UnlitMaterial())));

    // A marker that drives the route.
    markerNode = Node(
      mesh: Mesh(
        SphereGeometry(radius: 0.45),
        UnlitMaterial()..baseColorFactor = vm.Vector4(1.0, 0.85, 0.2, 1.0),
      ),
    );
    scene.add(markerNode);

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _NavRoutePainter(
        scene: scene,
        route: route,
        routeLine: routeLine,
        markerNode: markerNode,
        elapsedSeconds: widget.elapsedSeconds,
      ),
    );
  }
}

vm.Vector4 _lerpColor(vm.Vector4 a, vm.Vector4 b, double t) => a + (b - a) * t;

class _NavRoutePainter extends CustomPainter {
  _NavRoutePainter({
    required this.scene,
    required this.route,
    required this.routeLine,
    required this.markerNode,
    required this.elapsedSeconds,
  });

  final Scene scene;
  final CatmullRomPath route;
  final PolylineGeometry routeLine;
  final Node markerNode;
  final double elapsedSeconds;

  @override
  void paint(Canvas canvas, Size size) {
    final angle = elapsedSeconds * 0.3;
    final camera = PerspectiveCamera(
      position: vm.Vector3(sin(angle) * 17, 11, cos(angle) * 17),
      target: vm.Vector3(0, 0.3, 0),
    );

    // The camera-facing route line is rebuilt for the current view.
    routeLine.updateForCamera(camera, size);

    // Drive the marker along the route, looping.
    final distance = (elapsedSeconds * 3.5) % route.length;
    markerNode.localTransform = vm.Matrix4.translation(
      route.positionAtDistance(distance)..y = 0.45,
    );

    scene.render(camera, canvas, viewport: Offset.zero & size);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
