import 'package:vector_math/vector_math.dart' as vm;

import 'package:flutter_scene/src/components/mesh_component.dart';
import 'package:flutter_scene/src/geometry/splat_geometry.dart';
import 'package:flutter_scene/src/material/splat_material.dart';
import 'package:flutter_scene/src/mesh.dart';
import 'package:flutter_scene/src/splats/gaussian_splats.dart';

// TODO(splats): export this (and GaussianSplats/SplatData under
// lib/src/splats/) from lib/scene.dart with doc categories once the API
// settles across the later phases (crop volumes, modifier hook, spz).

/// An engine component that draws a [GaussianSplats] set.
///
/// Attach it to a node like any other component; the node's transform
/// places and orients the set (uniform scale only, since a non-uniform
/// scale distorts the splat covariances). The inherited mesh-component
/// machinery registers, culls, and bounds the draw; the splats render in
/// the translucent phase, depth-tested against opaque scene geometry.
///
/// ```dart
/// final splats = await GaussianSplats.fromAsset('assets/garden.ply');
/// scene.add(Node()..addComponent(SplatComponent(splats)));
/// ```
class SplatComponent extends MeshComponent {
  /// Creates a component that draws [splats].
  factory SplatComponent(GaussianSplats splats) {
    final geometry = SplatGeometry(splats);
    final material = SplatMaterial();
    return SplatComponent._(splats, geometry, material);
  }

  SplatComponent._(this.splats, this._geometry, SplatMaterial material)
    : super(Mesh(_geometry, material));

  /// The splat set this component draws.
  final GaussianSplats splats;

  final SplatGeometry _geometry;

  @override
  void onUnmount() {
    super.onUnmount();
    // Stop the background sorter; a remount lazily respawns it.
    _geometry.disposeSorter();
  }

  /// Global opacity multiplier in [0, 1].
  double get opacity => _geometry.opacity;
  set opacity(double value) => _geometry.opacity = value;

  /// Multiplier on every splat's footprint; 1 is the captured size.
  double get splatScale => _geometry.splatScale;
  set splatScale(double value) => _geometry.splatScale = value;

  /// Linear RGBA tint multiplied into every splat.
  vm.Vector4 get tint => _geometry.tint;
  set tint(vm.Vector4 value) => _geometry.tint = value;

  /// The spherical-harmonic degree evaluated per splat, clamped to what the
  /// set carries.
  int get shDegree => _geometry.shDegree;
  set shDegree(int value) => _geometry.shDegree = value;

  /// Whether small-footprint opacity compensation (anti-aliased
  /// rasterization) is enabled.
  bool get antialiased => _geometry.antialiased;
  set antialiased(bool value) => _geometry.antialiased = value;

  /// The active crop box (a unit cube placed in the set's local space), or
  /// null when no crop is set. See [setCropBox].
  vm.Matrix4? get cropBox => _geometry.cropBox;

  /// How the crop box filters splats.
  SplatCropMode get cropMode => _geometry.cropMode;

  /// Sets or clears the crop box: [box] places a unit cube (corners at
  /// +/-1) in the set's local space, and [mode] keeps only the splats
  /// inside it or drops them. Cropping is evaluated per frame on the GPU,
  /// so the box can animate freely.
  void setCropBox(
    vm.Matrix4? box, {
    SplatCropMode mode = SplatCropMode.include,
  }) => _geometry.setCropBox(box, mode: mode);
}
