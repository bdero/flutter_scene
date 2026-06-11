import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

/// Geometric description of a collider's volume.
///
/// Shapes are immutable, pure-data descriptors with no engine state. A
/// single [Shape] instance can be shared across many colliders; backends
/// cook each instance into a native acceleration structure on first use
/// and cache the result keyed by identity.
/// {@category Physics}
sealed class Shape {
  const Shape();
}

/// A sphere centered at the collider's local origin.
class SphereShape extends Shape {
  final double radius;

  const SphereShape({required this.radius});
}

/// An axis-aligned box of the given [halfExtents] centered at the
/// collider's local origin.
/// {@category Physics}
class BoxShape extends Shape {
  final Vector3 halfExtents;

  BoxShape({required this.halfExtents});
}

/// A capsule aligned with the local Y axis. [halfHeight] is the half
/// length of the cylindrical section, excluding the hemispherical caps.
/// {@category Physics}
class CapsuleShape extends Shape {
  final double radius;
  final double halfHeight;

  const CapsuleShape({required this.radius, required this.halfHeight});
}

/// A cylinder aligned with the local Y axis. [halfHeight] is half the
/// total height.
/// {@category Physics}
class CylinderShape extends Shape {
  final double radius;
  final double halfHeight;

  const CylinderShape({required this.radius, required this.halfHeight});
}

/// The convex hull of [points], stored as packed `xyz` triplets.
/// {@category Physics}
class ConvexHullShape extends Shape {
  final Float32List points;

  const ConvexHullShape({required this.points});
}

/// A triangle mesh defined by [vertices] (packed `xyz` triplets) and
/// [indices] (groups of three vertex indices forming one triangle each).
/// {@category Physics}
class TriMeshShape extends Shape {
  final Float32List vertices;
  final Uint32List indices;

  const TriMeshShape({required this.vertices, required this.indices});
}

/// A row-major heightfield of [width] x [depth] samples, scaled by
/// [scale]. Heights are sampled in the local XZ plane and offset along Y.
/// {@category Physics}
class HeightFieldShape extends Shape {
  final int width;
  final int depth;
  final Float32List heights;
  final Vector3 scale;

  HeightFieldShape({
    required this.width,
    required this.depth,
    required this.heights,
    required this.scale,
  });
}

/// One child of a [CompoundShape]: a [shape] positioned by [localPose]
/// relative to the compound's origin.
/// {@category Physics}
class CompoundChild {
  final Shape shape;
  final Matrix4 localPose;

  CompoundChild({required this.shape, required this.localPose});
}

/// A union of [children], each positioned by its own local pose.
///
/// Use this when one collider needs to represent a non-convex shape made
/// of several primitives (for example an L-block made of two boxes).
/// {@category Physics}
class CompoundShape extends Shape {
  final List<CompoundChild> children;

  CompoundShape({required this.children});
}
