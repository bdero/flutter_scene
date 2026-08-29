import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/fmat/fmat_ast.dart' show FmatType;
import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/geometry/primitives.dart';
import 'package:flutter_scene/src/material/material_parameters.dart';
import 'package:flutter_scene/src/material/preprocessed_material.dart';
import 'package:flutter_scene/src/mesh.dart';
import 'package:flutter_scene/src/node.dart';

/// The `decal_inverse` mat4 parameter a decal material reads, the world to
/// unit-box transform written by [DecalNode].
const String kDecalInverseParameter = 'decal_inverse';

/// The `decal_fade` float parameter a decal material reads.
const String kDecalFadeParameter = 'decal_fade';

/// A box-projected decal. Its material paints every opaque surface inside the
/// box, conforming to that surface rather than to the box's own faces, so a
/// scorch mark follows terrain, steps, and props.
///
/// Drive it with a `.fmat` declaring `engine_inputs: [scene_depth]`,
/// `depth_test: always`, and `culling: front` (see the decals section of
/// `MATERIALS.md`). The node keeps the material's `decal_inverse` and
/// `decal_fade` parameters in sync with its own world transform each frame, so
/// moving or reparenting a placed decal is enough; names the material does not
/// declare are skipped. The projection lives in those parameters, so each decal
/// needs its own material instance.
///
/// Unprojecting the receiving surface needs the opaque depth and a perspective
/// camera, so a decal draws nothing under an [OrthographicCamera].
///
/// ```dart
/// final decal = DecalNode(material: await loadFmatMaterial('assets/scorch_decal.fmat'))
///   ..project(point: impactPoint, normal: groundNormal, size: 2.4);
/// scene.add(decal);
/// ```
/// {@category Rendering}
base class DecalNode extends Node {
  /// Creates a decal drawn with [material], unplaced until [project] runs.
  DecalNode({required PreprocessedMaterial material, super.name})
    : _material = material {
    mesh = Mesh(unitBoxGeometry(), material);
    // The box is a projection volume, not geometry: it must not cast its own
    // cube shadow, and a ray should reach whatever it paints.
    castsShadows = false;
    raycastable = false;
    _writeParameters();
  }

  static Geometry? _unitBox;

  /// The shared unit box every decal draws, spanning -0.5 to 0.5 on each axis.
  /// Built once, on first use.
  @internal
  static Geometry unitBoxGeometry() =>
      _unitBox ??= CuboidGeometry(Vector3(1, 1, 1));

  PreprocessedMaterial _material;

  /// The projecting material. Its `decal_inverse` mat4 and `decal_fade` float
  /// parameters are written by this node.
  PreprocessedMaterial get material => _material;
  set material(PreprocessedMaterial value) {
    if (identical(value, _material)) return;
    _material = value;
    mesh?.primitives.first.material = value;
    _writeParameters();
  }

  double _fade = 1.0;

  /// Overall opacity, animated to fade a decal out before removing it.
  double get fade => _fade;
  set fade(double value) {
    if (value == _fade) return;
    _fade = value;
    _writeParameters();
  }

  // The world transform version the parameters were written from, so a decal
  // moved (or whose parent moved) after project() refreshes itself.
  int _writtenTransformVersion = -1;

  /// Places the box so it projects onto [point] along [normal], spanning [size]
  /// world units across and [depth] units along the normal, centered on
  /// [point]. [rotation] spins the projection about the normal, in radians.
  ///
  /// The texture is sampled across the box's local XZ plane. Give [depth]
  /// enough room to absorb the depth precision at the decal's distance from the
  /// camera; a surface outside the box is not painted.
  void project({
    required Vector3 point,
    required Vector3 normal,
    required double size,
    double depth = 0.5,
    double rotation = 0.0,
  }) {
    localTransform = boxTransform(
      point: point,
      normal: normal,
      size: size,
      depth: depth,
      rotation: rotation,
    );
    _writeParameters();
  }

  /// The box transform [project] places, exposed for tests and for callers
  /// driving a decal's transform themselves.
  @internal
  static Matrix4 boxTransform({
    required Vector3 point,
    required Vector3 normal,
    required double size,
    double depth = 0.5,
    double rotation = 0.0,
  }) {
    final up = normal.length2 > 0 ? normal.normalized() : Vector3(0, 1, 0);
    // Any axis not parallel to the normal seeds the basis. +Z first, so a
    // straight-down projection lands on the world X and Z axes.
    final seed = up.z.abs() < 0.99 ? Vector3(0, 0, 1) : Vector3(1, 0, 0);
    final right = up.cross(seed).normalized();
    final forward = right.cross(up);
    final basis = Matrix4.identity()
      ..setColumn(0, Vector4(right.x, right.y, right.z, 0))
      ..setColumn(1, Vector4(up.x, up.y, up.z, 0))
      ..setColumn(2, Vector4(forward.x, forward.y, forward.z, 0))
      ..setTranslation(point);
    return basis
      ..multiply(Matrix4.rotationY(rotation))
      ..multiply(Matrix4.diagonal3Values(size, depth, size));
  }

  @override
  void scenePrePass(double deltaSeconds, [bool ancestorsVisible = true]) {
    // Components and the animation player tick in super, so the inverse is
    // written after it: a decal driven by its own component would otherwise
    // paint from last frame's transform while its box drew at this frame's.
    super.scenePrePass(deltaSeconds, ancestorsVisible);
    // The world transform can change without project() running (the node or an
    // ancestor moved), so the inverse is refreshed from it each frame.
    if (worldTransformVersion != _writtenTransformVersion) _writeParameters();
  }

  void _writeParameters() {
    _writtenTransformVersion = worldTransformVersion;
    // A degenerate box (a zero size or depth) has no inverse; leave it
    // unprojected rather than throwing mid-frame.
    final inverse = Matrix4.zero();
    if (inverse.copyInverse(globalTransform) == 0.0) return;
    writeDecalParameters(_material.parameters, inverse: inverse, fade: _fade);
  }
}

/// Writes a decal's world to unit-box [inverse] and [fade] into [parameters],
/// skipping either name the material does not declare.
@internal
void writeDecalParameters(
  MaterialParameters parameters, {
  required Matrix4 inverse,
  required double fade,
}) {
  if (parameters.hasParameterOfType(kDecalInverseParameter, FmatType.mat4)) {
    parameters.setMat4(kDecalInverseParameter, inverse);
  }
  if (parameters.hasParameterOfType(kDecalFadeParameter, FmatType.float_)) {
    parameters.setFloat(kDecalFadeParameter, fade);
  }
}
