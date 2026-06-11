import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:vector_math/vector_math.dart';

/// The closest collider intersected by a [Ray], or one entry of a
/// raycast-all result list.
///
/// [worldPoint] is `origin + direction.normalized() * distance`.
/// [worldNormal] points out of the hit collider (opposite the ray's
/// direction of travel). [distance] is positive and measured along the
/// normalized direction. [Ray] is `vector_math`'s class; backends
/// normalize its direction internally.
/// {@category Physics}
class RaycastHit {
  /// The node whose collider was hit.
  final Node node;

  /// The specific collider that was hit, in case the node carries more
  /// than one.
  final Component collider;

  final Vector3 worldPoint;
  final Vector3 worldNormal;
  final double distance;

  RaycastHit({
    required this.node,
    required this.collider,
    required this.worldPoint,
    required this.worldNormal,
    required this.distance,
  });
}

/// One collider returned by an overlap query (sphere or box).
/// {@category Physics}
class OverlapHit {
  final Node node;
  final Component collider;

  OverlapHit({required this.node, required this.collider});
}

/// The first collider intersected by a shape cast, with the same fields
/// as [RaycastHit] plus the cast direction's hit distance.
/// {@category Physics}
class ShapeCastHit extends RaycastHit {
  ShapeCastHit({
    required super.node,
    required super.collider,
    required super.worldPoint,
    required super.worldNormal,
    required super.distance,
  });
}
