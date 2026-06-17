/// The visible background drawn behind a scene, and the sources that
/// describe what it looks like.
library;

import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/material/engine_lighting.dart';
import 'package:flutter_scene/src/material/environment.dart';
import 'package:flutter_scene/src/material/material.dart';

/// A sky that exposes a directional sun, so the engine can drive a matching
/// shadow-casting directional light from it.
///
/// The built-in [ShaderSkySource]s with a sun ([GradientSkySource],
/// [PhysicalSkySource]) implement this; assign one (or any sky that does) to a
/// `SunLight` to cast hard shadows that track the sky's sun. A custom
/// [ShaderSkySource] participates by implementing these getters.
/// {@category Lighting and environment}
abstract interface class SunSky {
  /// Direction toward the sun in world space (need not be unit length). The
  /// derived light travels the opposite way.
  Vector3 get sunDirection;

  /// Linear-RGB color the sun contributes as a directional light. Combined
  /// with [sunLightIntensity].
  Vector3 get sunLightColor;

  /// Scalar intensity for the derived directional light.
  double get sunLightIntensity;
}

/// A source of skybox color as a function of world-space view direction.
///
/// A [Skybox] wraps a source and the engine draws it behind all scene
/// geometry. Built-in sources are [EnvironmentSkySource] (show the scene's
/// environment) and [ShaderSkySource] (a custom fragment shader).
/// {@category Lighting and environment}
abstract class SkySource {
  const SkySource();
}

/// Shows the scene's image-based-lighting environment as the background,
/// optionally blurred.
///
/// Samples `Scene.environment`'s prefiltered-radiance atlas along each view
/// ray. [blurriness] selects how rough (and so how blurred) the sampled band
/// is: `0.0` shows the sharp environment, `1.0` shows the fully-blurred band.
/// The same atlas drives specular reflections, so a blurred background stays
/// consistent with what reflective surfaces show.
/// {@category Lighting and environment}
class EnvironmentSkySource extends SkySource {
  EnvironmentSkySource({this.blurriness = 0.0});

  /// How blurred the background is, from `0.0` (sharp) to `1.0` (fully
  /// blurred). Clamped to that range when sampled.
  double blurriness;
}

/// Draws a custom sky from a fragment shader.
///
/// The [fragmentShader] runs full-screen behind the scene. The engine supplies
/// the world-space view direction as the `v_ray` vertex input and owns the
/// full-screen draw, depth, and draw order, so you place no geometry; the
/// shader writes linear HDR radiance with premultiplied alpha (exposure and
/// tone mapping are applied later). Bind custom uniform blocks and textures by
/// name with [setUniformBlock] / [setTexture]; set [useEnvironment] to have
/// the engine bind the scene environment's IBL textures (`prefiltered_radiance`
/// and `brdf_lut`) when the shader declares them.
///
/// Unlike [EnvironmentSkySource], `Skybox.intensity` is not applied for you;
/// the shader controls its own output brightness.
/// {@category Lighting and environment}
class ShaderSkySource extends SkySource {
  ShaderSkySource({required this.fragmentShader, this.useEnvironment = false});

  /// The full-screen sky fragment shader, typically loaded from a
  /// `.shaderbundle`.
  gpu.Shader fragmentShader;

  /// Whether the engine binds the active environment's IBL textures
  /// (`prefiltered_radiance`, `brdf_lut`) when the shader declares them.
  bool useEnvironment;

  final Map<String, ByteData> _uniformBlocks = {};
  final Map<String, _SkyTexture> _textures = {};

  /// Assigns the byte contents of a uniform block by name. [bytes] must match
  /// the block's std140 layout; pass `null` to clear the binding.
  void setUniformBlock(String name, ByteData? bytes) {
    if (bytes == null) {
      _uniformBlocks.remove(name);
    } else {
      _uniformBlocks[name] = bytes;
    }
  }

  /// Convenience wrapper around [setUniformBlock] that packs a list of floats.
  /// The caller is still responsible for std140 padding.
  void setUniformBlockFromFloats(String name, List<double> floats) {
    setUniformBlock(name, ByteData.sublistView(Float32List.fromList(floats)));
  }

  /// Reads back a previously-set uniform block, or `null` when none is set.
  ByteData? getUniformBlock(String name) => _uniformBlocks[name];

  /// All currently-bound uniform block names, in insertion order.
  Iterable<String> get uniformBlockNames => _uniformBlocks.keys;

  /// Assigns a texture to a sampler uniform by name. Pass `null` to clear it.
  void setTexture(
    String name,
    gpu.Texture? texture, {
    gpu.SamplerOptions? sampler,
  }) {
    if (texture == null) {
      _textures.remove(name);
    } else {
      _textures[name] = _SkyTexture(texture, sampler);
    }
  }

  /// Reads back a previously-set texture binding, or `null` when none is set.
  gpu.Texture? getTexture(String name) => _textures[name]?.texture;

  /// All currently-bound sampler names, in insertion order.
  Iterable<String> get textureNames => _textures.keys;

  /// Binds the fragment's uniform blocks, textures, and (when
  /// [useEnvironment]) the environment IBL samplers. Called by the engine
  /// during the background draw; not part of the app-facing API.
  void bind(
    gpu.RenderPass pass,
    gpu.HostBuffer transientsBuffer,
    EnvironmentMap environment,
  ) {
    for (final entry in _uniformBlocks.entries) {
      pass.bindUniform(
        fragmentShader.getUniformSlot(entry.key),
        transientsBuffer.emplace(entry.value),
      );
    }
    for (final entry in _textures.entries) {
      pass.bindTexture(
        fragmentShader.getUniformSlot(entry.key),
        entry.value.texture,
        sampler: entry.value.sampler ?? gpu.SamplerOptions(),
      );
    }
    if (useEnvironment) {
      EngineLightingUniforms.bindPrefilteredRadiance(
        pass,
        fragmentShader,
        environment,
      );
      pass.bindTexture(
        fragmentShader.getUniformSlot('brdf_lut'),
        Material.getBrdfLutTexture(),
        sampler: gpu.SamplerOptions(
          minFilter: gpu.MinMagFilter.linear,
          magFilter: gpu.MinMagFilter.linear,
          widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
          heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
        ),
      );
    }
  }
}

class _SkyTexture {
  _SkyTexture(this.texture, this.sampler);
  final gpu.Texture texture;
  final gpu.SamplerOptions? sampler;
}

/// The visible background drawn behind a [Scene].
///
/// Assign one to `Scene.skybox`. The skybox is decoupled from the scene's
/// image-based lighting (`Scene.environment`): the default
/// [EnvironmentSkySource] shows that same environment, but the two can be set
/// independently. The engine draws the skybox behind all scene geometry at
/// the far plane; you never place or order any geometry yourself.
/// {@category Lighting and environment}
class Skybox {
  Skybox(this.source, {this.intensity = 1.0});

  /// What the sky looks like.
  SkySource source;

  /// Scales the sampled radiance for [EnvironmentSkySource]. It is combined
  /// with `Scene.environmentIntensity`, so a default skybox showing the
  /// environment matches the brightness of image-based reflections. A
  /// [ShaderSkySource] controls its own brightness and ignores this.
  double intensity;
}
