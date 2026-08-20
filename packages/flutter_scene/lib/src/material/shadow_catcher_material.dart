import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/light.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/material/physical_material_variant.dart';
import 'package:flutter_scene/src/material/preprocessed_material.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';

/// An invisible ground surface that receives shadows and ambient occlusion.
///
/// Assign it to a plane under a model and the plane itself never shows; it
/// writes only the darkening that grounds the model, so a product scene
/// composites over a transparent Flutter background (or any backdrop) with a
/// believable contact to the ground. The output is
/// `(shadowColor * alpha, alpha)` where
/// `alpha = saturate(shadowIntensity * (1 - shadow visibility) +
/// aoStrength * (1 - occlusion)) * radial fade`.
///
/// The shadow term samples the same aggregate the lit path shades with, the
/// directional light's cascades, every shadow-casting spot's atlas tile, and
/// the sun contact term marched by the occlusion chain, so the catcher's
/// shadow always matches what lit geometry receives. The occlusion term
/// samples the screen-space ambient-occlusion chain and therefore needs the
/// scene's ambient occlusion enabled to contribute (the contact term needs
/// `DirectionalLight.contactShadows`); with both off, only the mapped shadow
/// term draws.
///
/// The catcher draws into the linear HDR scene color as ordinary translucent
/// geometry, before the resolve pass applies exposure, tone mapping, and the
/// display transform. That staging is load-bearing: the overlay rides the
/// same exposure and tone curve as the geometry that casts onto it, so the
/// shadow neither over-darkens nor washes out as the scene's exposure moves.
///
/// Unlike other translucent materials, the catcher also joins the camera
/// depth prepass, so the screen-space chain evaluates occlusion, contact
/// shadows, and depth effects at the plane's own depth rather than the
/// backdrop behind it. The plane therefore acts like a ground surface for
/// every screen-space effect (a model standing on it gains ambient occlusion
/// from it, and depth of field focuses on it), which is the behavior a real
/// ground plane would have.
///
/// [shadowIntensity] doubles as the enable switch. At exactly `0` the
/// catcher registers no draws in any pass at all, a true early-out.
///
/// Construct only after `Scene.initializeStaticResources()` has completed
/// (the `Scene` constructor starts it); the material draws with the engine's
/// bundled catcher shader, which loads there.
/// {@category Materials}
class ShadowCatcherMaterial extends Material {
  /// Creates a shadow catcher. All parameters can be reassigned later.
  ShadowCatcherMaterial({
    Color shadowColor = const Color(0xFF000000),
    double shadowIntensity = 0.8,
    double aoStrength = 0.5,
    double softness = 0.0,
    double fadeStart = 0.0,
    double fadeEnd = 0.0,
  }) : _shadowColor = shadowColor,
       _shadowIntensity = shadowIntensity,
       _aoStrength = aoStrength,
       _softness = softness,
       _fadeStart = fadeStart,
       _fadeEnd = fadeEnd;

  Color _shadowColor;
  double _shadowIntensity;
  double _aoStrength;
  double _softness;
  double _fadeStart;
  double _fadeEnd;
  bool _paramsDirty = true;

  /// The color the surface darkens toward where it is shadowed or occluded.
  ///
  /// Authored in sRGB and decoded to linear like other material colors. The
  /// default black is exposure-invariant; a tinted shadow is written as a
  /// linear HDR color and rides the scene's exposure and tone mapping.
  Color get shadowColor => _shadowColor;
  set shadowColor(Color value) {
    _shadowColor = value;
    _paramsDirty = true;
  }

  /// How strongly aggregate shadow visibility darkens the surface, `0` to
  /// `1`.
  ///
  /// Exactly `0` disables the catcher entirely: no render passes draw it.
  double get shadowIntensity => _shadowIntensity;
  set shadowIntensity(double value) {
    _shadowIntensity = value;
    _paramsDirty = true;
  }

  /// How strongly screen-space ambient occlusion darkens the surface, `0` to
  /// `1`. Contributes only while the scene's ambient occlusion is enabled.
  double get aoStrength => _aoStrength;
  set aoStrength(double value) {
    _aoStrength = value;
    _paramsDirty = true;
  }

  /// World-space penumbra radius for this catcher's shadow lookup.
  ///
  /// `0` (the default) inherits the scene's `DirectionalLight.shadowSoftness`.
  /// A positive value overrides the softness for this catcher's draws only,
  /// per draw in its own uniform block, so it never perturbs the scene-wide
  /// shadow settings or other receivers. Large values stay bounded by the
  /// fixed shadow filter kernel, so very soft shadows read best with a
  /// matching `shadowFilter`/resolution setup on the light.
  double get softness => _softness;
  set softness(double value) {
    _softness = value;
    _paramsDirty = true;
  }

  /// Radial distance from the mesh origin, in the mesh's local units, where
  /// the overlay starts fading out. See [fadeEnd].
  double get fadeStart => _fadeStart;
  set fadeStart(double value) {
    _fadeStart = value;
    _paramsDirty = true;
  }

  /// Radial distance from the mesh origin, in the mesh's local units, where
  /// the overlay reaches zero, so the plane has no hard visible edge.
  ///
  /// A [fadeEnd] at or below [fadeStart] (the default `0`/`0`) disables the
  /// fade. Size both to the catcher mesh: for a unit plane scaled by its
  /// node, values around half the mesh's local extent for [fadeStart] and
  /// the full extent for [fadeEnd] keep the falloff inside the geometry.
  double get fadeEnd => _fadeEnd;
  set fadeEnd(double value) {
    _fadeEnd = value;
    _paramsDirty = true;
  }

  /// The catcher's composed straight alpha, the same math the shader runs.
  ///
  /// `shadowVisibility` and `occlusion` are `1` fully lit/unoccluded to `0`
  /// fully dark; `radialDistance` is the fragment's distance from the mesh
  /// origin in local units.
  @visibleForTesting
  static double composeAlpha({
    required double shadowVisibility,
    required double occlusion,
    required double shadowIntensity,
    required double aoStrength,
    double radialDistance = 0.0,
    double fadeStart = 0.0,
    double fadeEnd = 0.0,
  }) {
    final shadowTerm = shadowIntensity * (1.0 - shadowVisibility);
    final aoTerm = aoStrength * (1.0 - occlusion);
    var radialFade = 1.0;
    if (fadeEnd > fadeStart) {
      final t = ((radialDistance - fadeStart) / (fadeEnd - fadeStart)).clamp(
        0.0,
        1.0,
      );
      radialFade = 1.0 - t * t * (3.0 - 2.0 * t);
    }
    return (shadowTerm + aoTerm).clamp(0.0, 1.0) * radialFade;
  }

  _ShadowCatcherVariant? _variant;

  _ShadowCatcherVariant get _prepared {
    final variant = _variant ??= _ShadowCatcherVariant(this);
    if (_paramsDirty) {
      variant.applyParameters(this);
      _paramsDirty = false;
    }
    return variant;
  }

  @override
  bool isOpaque() => false;

  @override
  bool get depthPrepassParticipates => true;

  @override
  bool get drawsNothing => _shadowIntensity == 0;

  @override
  gpu.Shader get fragmentShader => _prepared.fragmentShader;

  @override
  gpu.Shader fragmentShaderForLighting(Lighting lighting) =>
      _prepared.fragmentShaderForLighting(lighting);

  @override
  gpu.Shader? materialVertexShader(String variant) =>
      _prepared.materialVertexShader(variant);

  @override
  void bindVertexStage(
    gpu.RenderPass pass,
    gpu.Shader vertexShader,
    TransientWriter transientsBuffer,
  ) => _prepared.bindVertexStage(pass, vertexShader, transientsBuffer);

  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Lighting lighting,
  ) {
    final prepared = _prepared
      ..name = name
      ..depthBias = depthBias
      ..lodFade = lodFade
      ..lightListOffset = lightListOffset
      ..lightListCount = lightListCount;
    prepared.bind(pass, transientsBuffer, lighting);
  }
}

/// The shader-backed half of [ShadowCatcherMaterial], prepared lazily at
/// first draw from the engine's physical bundle (which carries the catcher
/// entries).
class _ShadowCatcherVariant extends PreprocessedMaterial {
  factory _ShadowCatcherVariant(ShadowCatcherMaterial owner) {
    const entry = 'ShadowCatcher';
    final assets = requirePhysicalBundleAssets();
    gpu.Shader require(String name) {
      final shader = assets.library[name];
      if (shader == null) {
        throw StateError('Physical shader entry "$name" is missing.');
      }
      return shader;
    }

    final metadata = (assets.metadata[entry] as Map).cast<String, Object?>();
    final vertexMeta = (metadata['vertex'] as Map).cast<String, Object?>();
    final variant = _ShadowCatcherVariant._(
      owner: owner,
      fragmentShader: require(entry),
      metadata: metadata,
      vertexShaders: {
        for (final MapEntry(:key, :value) in vertexMeta.entries)
          key: require(value as String),
      },
    )..setShadowFragmentShader(require('${entry}Shadow'));
    return variant;
  }

  _ShadowCatcherVariant._({
    required ShadowCatcherMaterial owner,
    required super.fragmentShader,
    required super.metadata,
    required super.vertexShaders,
  }) : _owner = owner;

  final ShadowCatcherMaterial _owner;

  /// Pushes the owner's public properties into the shader parameters.
  void applyParameters(ShadowCatcherMaterial owner) {
    parameters
      ..setVec3('shadow_color', _linearColor(owner.shadowColor))
      ..setFloat('shadow_intensity', owner.shadowIntensity.clamp(0.0, 1.0))
      ..setFloat('ao_strength', owner.aoStrength.clamp(0.0, 1.0))
      ..setFloat('fade_start', owner.fadeStart)
      ..setFloat('fade_end', owner.fadeEnd);
  }

  /// sRGB-decodes [color] to a linear rgb vector, matching what `setColor`
  /// does for a `source_color` vec4 parameter (the catcher's is a vec3).
  static Vector3 _linearColor(Color color) => Vector3(
    _srgbToLinear(color.r),
    _srgbToLinear(color.g),
    _srgbToLinear(color.b),
  );

  static double _srgbToLinear(double value) => value <= 0.04045
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();

  @override
  void adjustEngineLighting(Float32List fragInfo) {
    // A positive per-catcher softness replaces the scene softness in this
    // draw's own uniform block ([135] is FragInfo.shadow_softness), leaving
    // every other receiver on the scene-wide setting.
    if (_owner.softness > 0.0) {
      fragInfo[135] = _owner.softness;
    }
  }
}
