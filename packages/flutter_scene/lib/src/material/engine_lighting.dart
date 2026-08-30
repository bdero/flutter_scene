import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;

import 'package:flutter_scene/src/fog.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/light.dart';
import 'package:flutter_scene/src/material/environment.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/material/physically_based_material.dart'
    show TextureTransform;
import 'package:flutter_scene/src/render/custom_render_pass.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/render/irradiance_field.dart';

/// Packs the engine lighting half of the shared `FragInfo` uniform block and
/// binds the image-based-lighting and shadow samplers.
///
/// The `FragInfo` block (declared in `shaders/material_engine_lighting.glsl`
/// and read by `EvaluateLighting` in `material_lighting.glsl`) mixes
/// material-specific fields with engine lighting / IBL / shadow fields. This
/// helper owns the lighting fields, which are identical for every lit material;
/// callers add their own material fields (if any) to the same buffer. Both
/// [PhysicallyBasedMaterial] and `PreprocessedMaterial` use it so the lighting
/// packing lives in one place.
class EngineLightingUniforms {
  /// The float count of the full `FragInfo` block (800 bytes / 200 floats:
  /// the mat4 `environment_transform` ends at float 155, the `ssao_params`
  /// vec4 at floats 156..159, then the `radiance_blend` vec4 at floats
  /// 160..163, `ssao_lighting` at 164..167, `model_scale` at 168..171,
  /// `dielectric_f0` at 172..175, the five irradiance-field vec4s at
  /// 176..195, and `froxel_grid` at 196..199). See the layout map in the
  /// implementation.
  static const fragInfoFloatCount = 200;

  /// Index of the `dielectric_f0` vec4 in `FragInfo`. [packInto] writes the
  /// standard 0.04 dielectric reflectance; a material with a non-default
  /// ior, specular factor, or specular color overwrites it afterward.
  static const dielectricF0Index = 172;

  /// The dielectric F0 of a default material (ior 1.5, specular 1, white
  /// specular color), the value the standard shader used to hard-code.
  static const defaultDielectricF0 = 0.04;

  /// Index of the first irradiance-field vec4 (`gi_grid`).
  static const irradianceFieldIndex = 176;

  /// Index of the LOD cross-fade `fade` field in `FragInfo`, occupying std140
  /// padding before `environment_transform` (so the block size is unchanged).
  static const fadeIndex = 137;

  /// Default geometric-specular-antialiasing strength and threshold, matching
  /// [PhysicallyBasedMaterial]'s defaults. Packed at [138]/[139] (the remaining
  /// std140 padding after `fade`) so every lit material gets antialiasing by
  /// default; a material that exposes the knobs overwrites these afterward.
  static const defaultSpecularAaVariance = 0.15;
  static const defaultSpecularAaThreshold = 1.0;

  /// Writes the engine lighting / IBL / shadow fields of `FragInfo` into
  /// [fragInfo] from [lighting] and [env]. Leaves the material-specific fields
  /// (color, factors, alpha mode) untouched for the caller to fill.
  ///
  /// [nodeChannelMask] is the drawing item's `Node.lightChannelMask`. When it
  /// misses the directional light's own channels the light is packed away for
  /// this draw, which is what suppresses the primary directional per object
  /// (the punctual lights are already filtered by the culler).
  static void packInto(
    Float32List fragInfo,
    Lighting lighting,
    EnvironmentMap env, {
    int nodeChannelMask = 0xFF,
    double modelScaleX = 1.0,
    double modelScaleY = 1.0,
    double modelScaleZ = 1.0,
  }) {
    // Default to fully drawn; a material with an active LOD cross-fade
    // overwrites this. Without it the zero-initialized slot would discard
    // every fragment.
    fragInfo[fadeIndex] = 1.0;
    // A node outside the light's channels gets no direct sun and no cast
    // shadow; the image-based ambient is untouched, so the shadow-ambient
    // control is cleared with it below.
    final scene = lighting.directionalLight;
    final light = scene != null && (scene.channelMask & nodeChannelMask) != 0
        ? scene
        : null;
    final cascades = lighting.shadowMap == null
        ? const <ShadowCascade>[]
        : lighting.cascades;

    // diffuse_sh0..6 at [8..35] are now unused: the shader samples the
    // sh_coefficients texture (bound in bindEngineTextures) instead, so the
    // GPU-computed coefficients of a baked sky need no read-back. Left zero.

    // probe_box [36..39] and probe_extents [40..43] (the retired sh7/sh8
    // rows): the primary environment's parallax box proxy, when it carries
    // one. Written unconditionally since the scratch list is shared across
    // draws with different environments.
    final parallaxCenter = env.parallaxBoxCenter;
    final parallaxExtents = env.parallaxBoxHalfExtents;
    if (parallaxCenter != null && parallaxExtents != null) {
      fragInfo[36] = parallaxCenter.x;
      fragInfo[37] = parallaxCenter.y;
      fragInfo[38] = parallaxCenter.z;
      fragInfo[39] = 1.0;
      fragInfo[40] = parallaxExtents.x;
      fragInfo[41] = parallaxExtents.y;
      fragInfo[42] = parallaxExtents.z;
    } else {
      fragInfo[36] = 0.0;
      fragInfo[37] = 0.0;
      fragInfo[38] = 0.0;
      fragInfo[39] = 0.0;
      fragInfo[40] = 0.0;
      fragInfo[41] = 0.0;
      fragInfo[42] = 0.0;
    }
    fragInfo[43] = 0.0;

    // directional_light_direction [44..47], directional_light_color [48..51].
    if (light != null) {
      // The world-space direction comes from the light node's transform;
      // fall back to the light's own field for a node-less light.
      final direction = lighting.directionalLightDirection ?? light.direction;
      fragInfo[44] = direction.x;
      fragInfo[45] = direction.y;
      fragInfo[46] = direction.z;
      fragInfo[47] = light.shadowFilter.index.toDouble();
      fragInfo[48] = light.color.x * light.intensity;
      fragInfo[49] = light.color.y * light.intensity;
      fragInfo[50] = light.color.z * light.intensity;
      // directional_light_color.w is the cascade cross-fade fraction; 0 (the
      // default) leaves the shader's hard cascade hand-off.
      fragInfo[51] = light.cascadeOverlap.clamp(0.0, 1.0);
    }
    // light_space_matrix[4] at [52..115], cascade_box_sizes at [116..119].
    for (var i = 0; i < cascades.length; i++) {
      fragInfo.setRange(
        52 + i * 16,
        68 + i * 16,
        cascades[i].lightSpaceMatrix.storage,
      );
      fragInfo[116 + i] = cascades[i].boxSize;
    }
    fragInfo[126] = lighting.environmentIntensity;
    fragInfo[127] = light != null ? 1.0 : 0.0;
    fragInfo[128] = cascades.isEmpty ? 0.0 : 1.0;
    fragInfo[129] = light?.shadowDepthBias ?? 0.0;
    fragInfo[130] = light?.shadowNormalBias ?? 0.0;
    fragInfo[131] = light == null ? 0.0 : 1.0 / light.shadowMapResolution;
    fragInfo[134] = light?.shadowFadeRange ?? 0.0;
    fragInfo[135] = light?.shadowSoftness ?? 0.0;
    fragInfo[136] = cascades.length.toDouble();
    // Geometric specular antialiasing at [138]/[139] (specular_aa_variance and
    // specular_aa_threshold). Defaults for every lit material; a material with
    // its own knobs overwrites these after packInto.
    fragInfo[138] = defaultSpecularAaVariance;
    fragInfo[139] = defaultSpecularAaThreshold;
    // environment_transform: a mat4 carrying the 3x3 rotation; std140 mat4
    // columns are 16 bytes each, at [140], [144], [148], [152].
    final envTransform = lighting.environmentTransform.storage;
    for (var col = 0; col < 3; col++) {
      fragInfo[140 + col * 4] = envTransform[col * 3];
      fragInfo[141 + col * 4] = envTransform[col * 3 + 1];
      fragInfo[142 + col * 4] = envTransform[col * 3 + 2];
    }
    fragInfo[155] = 1.0; // mat4 column 3 = (0, 0, 0, 1)
    // ssao_params at [156..159]: occlusion enabled, specular occlusion
    // enabled, and the reciprocal render-target size (for the gl_FragCoord
    // to occlusion-UV mapping).
    fragInfo[156] = lighting.ssaoMap != null ? 1.0 : 0.0;
    fragInfo[157] = lighting.specularOcclusionMode;
    final viewport = lighting.viewportSize;
    fragInfo[158] = viewport.width > 0 ? 1.0 / viewport.width : 0.0;
    fragInfo[159] = viewport.height > 0 ? 1.0 / viewport.height : 0.0;
    // radiance_blend at [160..163]: x is the IBL cross-fade factor toward the
    // secondary environment (0 and ignored when there is no secondary); y is
    // the shadow-ambient strength (how much the cast shadow darkens the IBL
    // ambient, 0 leaves it physical); zw reserved.
    fragInfo[160] = lighting.environmentMapB != null
        ? lighting.environmentBlend.clamp(0.0, 1.0)
        : 0.0;
    fragInfo[161] = light?.shadowAmbientStrength.clamp(0.0, 1.0) ?? 0.0;
    // camera_up.w flags the occlusion texture's indirect-light layout
    // (radiance in rgb, visibility in a). radiance_blend.zw are the per-draw
    // punctual light slice, so they cannot carry frame flags.
    fragInfo[31] = lighting.ssaoIndirectLight ? 1.0 : 0.0;
    // ssao_lighting at [164..167]: x is the fraction of screen-space
    // occlusion applied to analytic direct lights, y the multi-bounce
    // amount, z whether the occlusion texture's ba carry a packed bent
    // normal, w whether its g channel carries the sun contact shadow.
    fragInfo[164] = lighting.ssaoDirectLightAffect.clamp(0.0, 1.0);
    fragInfo[165] = lighting.ssaoMultiBounce.clamp(0.0, 1.0);
    fragInfo[166] = lighting.ssaoBentNormals ? 1.0 : 0.0;
    fragInfo[167] = lighting.ssaoContactShadows ? 1.0 : 0.0;
    // model_scale at [168..170]: the draw's model scale, set by the encoder
    // on the material before bind (replaces the old v_model_scale varying).
    fragInfo[168] = modelScaleX;
    fragInfo[169] = modelScaleY;
    fragInfo[170] = modelScaleZ;
    // dielectric_f0 at [172..174]: the standard shader path's dielectric
    // reflectance, the plain 0.04 unless the material overwrites it.
    fragInfo[dielectricF0Index] = defaultDielectricF0;
    fragInfo[dielectricF0Index + 1] = defaultDielectricF0;
    fragInfo[dielectricF0Index + 2] = defaultDielectricF0;
    // The irradiance field at [176..195]. A zero intensity in gi_grid.w
    // disables the whole receiver, so a scene without the field pays nothing
    // beyond these writes.
    const gi = irradianceFieldIndex;
    final field = lighting.irradianceField;
    if (field == null) {
      for (var i = gi; i < gi + 20; i++) {
        fragInfo[i] = 0.0;
      }
    } else {
      final placement = field.placement;
      final layout = field.layout;
      fragInfo[gi] = placement.spacing.x;
      fragInfo[gi + 1] = placement.spacing.y;
      fragInfo[gi + 2] = placement.spacing.z;
      fragInfo[gi + 3] = field.intensity;
      fragInfo[gi + 4] = placement.anchor.x;
      fragInfo[gi + 5] = placement.anchor.y;
      fragInfo[gi + 6] = placement.anchor.z;
      fragInfo[gi + 7] = field.shadowBias;
      fragInfo[gi + 8] = layout.resolution.x;
      fragInfo[gi + 9] = layout.resolution.y;
      fragInfo[gi + 10] = layout.resolution.z;
      fragInfo[gi + 11] = layout.tilesPerRow.toDouble();
      fragInfo[gi + 12] = layout.irradianceOriginY.toDouble();
      fragInfo[gi + 13] = layout.depthOriginY.toDouble();
      fragInfo[gi + 14] = 1.0 / layout.atlasWidth;
      fragInfo[gi + 15] = 1.0 / layout.atlasHeight;
      fragInfo[gi + 16] = field.visibility;
      // The visibility bias is authored relative to the cell edge, so one
      // default holds across scene scales.
      fragInfo[gi + 17] = field.visibilityBias * placement.minCellEdge;
      fragInfo[gi + 18] = placement.maxProbeDistance;
      fragInfo[gi + 19] = IrradianceFieldBinding.boundaryFadeCells;
    }
    // punctual_dims [8..10] (the first unused diffuse-SH vec4 slot): the
    // dimensions the shader needs to normalize its punctual-light fetches.
    // x: parameters-texture row count (all scene lights). y/z: the light-index
    // texture width/height (the froxel data texture's in froxel mode). These
    // are frame-constant. The per-object slice (radiance_blend.z count, .w
    // offset) is written per draw by the material and ignored in froxel mode.
    fragInfo[8] = lighting.punctualParamsCount.toDouble();
    fragInfo[9] = lighting.punctualIndexWidth.toDouble();
    fragInfo[10] = lighting.punctualIndexHeight.toDouble();
    // punctual_dims.w [11] + froxel_grid [196..199]: this view's froxel
    // clustering. froxel_grid.z (slice count) of 0 selects the per-object
    // path; nonzero, the fragment derives its froxel from the camera basis
    // and reads its light slice from the froxel data texture.
    final froxels = lighting.froxels;
    fragInfo[11] = froxels?.zBias ?? 0.0;
    fragInfo[196] = froxels?.nx.toDouble() ?? 0.0;
    fragInfo[197] = froxels?.ny.toDouble() ?? 0.0;
    fragInfo[198] = froxels?.nz.toDouble() ?? 0.0;
    fragInfo[199] = froxels?.zScale ?? 0.0;
    // spot_shadow_params [12..15] (more of the unused SH region): the shared
    // spot-shadow parameters. x is the total non-cascade tile count (spot
    // tiles then point-shadow tiles); 0 disables both spot and point shadow
    // sampling, and the shader uses it to size the shared shadow atlas.
    fragInfo[12] = (lighting.spotShadowCount + lighting.pointShadowTileCount)
        .toDouble();
    fragInfo[13] = lighting.spotShadowDepthBias;
    fragInfo[14] = lighting.spotShadowNormalBias;
    fragInfo[15] = lighting.spotShadowSoftness;
    // scene_inputs [16..19] (more of the unused SH region): gates for the
    // material scene-input samplers (bound only into materials that declare
    // engine_inputs) and the engine time. The accumulated snapshot exists only
    // while a screen-reading translucent batch encodes, so earlier draws read
    // 0 for x.
    fragInfo[16] = lighting.opaqueSceneColor != null ? 1.0 : 0.0;
    fragInfo[17] = lighting.sceneDepthLinear != null ? 1.0 : 0.0;
    fragInfo[18] = lighting.time;
    // scene_inputs.w / camera_forward.w: the projection's half-fov
    // tangents, for materials that project world positions to screen UV
    // (screen-space reflection marches). Zero when non-perspective.
    fragInfo[19] = lighting.tanHalfFovX;
    // camera_forward [20..23]: the camera's world-space forward direction,
    // for a fragment's planar view depth (dot(-v_viewvector, forward)).
    final forward = lighting.cameraForward;
    if (forward != null) {
      fragInfo[20] = forward.x;
      fragInfo[21] = forward.y;
      fragInfo[22] = forward.z;
    }
    fragInfo[23] = lighting.tanHalfFovY;
    // camera_right/camera_up [24..31]: the remaining camera basis axes used
    // to project a world-space refraction exit back into scene-color UV. The
    // right axis' w slot [27] carries the sun's angular radius for the
    // percentage-closer soft-shadow penumbra.
    final right = lighting.cameraRight;
    if (right != null) {
      fragInfo[24] = right.x;
      fragInfo[25] = right.y;
      fragInfo[26] = right.z;
    }
    fragInfo[27] = light?.angularRadius ?? 0.005;
    final up = lighting.cameraUp;
    if (up != null) {
      fragInfo[28] = up.x;
      fragInfo[29] = up.y;
      fragInfo[30] = up.z;
    }
    // transmission_info [32..35]: the filtered scene-color atlas is packed
    // into unused SH storage so the shared uniform block does not grow.
    final filtered = lighting.filteredSceneColor;
    fragInfo[32] = filtered != null ? 1.0 : 0.0;
    fragInfo[33] = lighting.transmissionFilterBandCount.toDouble();
    if (filtered != null) {
      fragInfo[34] = filtered.width > 0 ? 1.0 / filtered.width : 0.0;
      fragInfo[35] = filtered.height > 0 ? 1.0 / filtered.height : 0.0;
    }
  }

  /// Packs the `FogInfo` block (6 vec4s / 24 floats, see `shaders/fog.glsl`)
  /// from [lighting]'s fog and directional light, and binds it on [shader].
  /// Every material shader declares `FogInfo`, so this is always bound; when
  /// there is no fog the `enabled` flag is 0 and `ApplyFog` is a no-op.
  static void bindFog(
    gpu.RenderPass pass,
    gpu.Shader shader,
    TransientWriter transientsBuffer,
    Lighting lighting,
  ) {
    // Frame-constant per (pass, shader, lighting); see the bind memo above.
    if (_memoPassIs(pass) && identical(_fogMemo[shader], lighting)) {
      return;
    }
    _fogMemo[shader] = lighting;
    final fog = lighting.fog;
    final buffer = Float32List(24);
    if (fog != null && fog.enabled && fog.mode != FogMode.none) {
      // params0: mode, enabled, maxOpacity, sky-color influence.
      buffer[0] = fog.mode.index.toDouble();
      buffer[1] = 1.0;
      buffer[2] = fog.maxOpacity.clamp(0.0, 1.0);
      buffer[3] = fog.skyColorInfluence.clamp(0.0, 1.0);
      // params1: density, start, end, cutoffDistance.
      buffer[4] = fog.density;
      buffer[5] = fog.start;
      buffer[6] = fog.end;
      buffer[7] = fog.cutoffDistance;
      // params2: height, heightFalloff, sunInScatter, sunExponent.
      buffer[8] = fog.height;
      buffer[9] = fog.heightFalloff;
      buffer[10] = fog.sunInScatter;
      buffer[11] = fog.sunInScatterExponent;
      // color.
      buffer[12] = fog.color.x;
      buffer[13] = fog.color.y;
      buffer[14] = fog.color.z;
      // sun color * intensity + has-sun, and sun travel direction. Reuses the
      // scene's directional light (the same source packInto uses for lighting).
      final light = lighting.directionalLight;
      if (light != null && fog.sunInScatter > 0.0) {
        buffer[16] = light.color.x * light.intensity;
        buffer[17] = light.color.y * light.intensity;
        buffer[18] = light.color.z * light.intensity;
        buffer[19] = 1.0; // has-sun
        final direction = lighting.directionalLightDirection ?? light.direction;
        buffer[20] = direction.x;
        buffer[21] = direction.y;
        buffer[22] = direction.z;
      }
    }
    // buffer[1] left 0 (disabled) when there is no active fog.
    pass.bindUniform(
      shader.getUniformSlot('FogInfo'),
      transientsBuffer.emplace(ByteData.sublistView(buffer)),
    );
  }

  // Tiny constant uniform blocks (std140, 16 bytes) telling the two 2D
  // radiance layouts apart in the shader (RadianceLayoutInfo in texture.glsl);
  // device-resident so binding needs no per-frame buffer. Mip: the 2D mip
  // equirect. Atlas: the legacy 2D stacked-band equirect. The cube layout has
  // its own shader variant and reads neither.
  static final gpu.BufferView _layoutMip = _layoutFlagBuffer(1.0);
  static final gpu.BufferView _layoutAtlas = _layoutFlagBuffer(0.0);

  static gpu.BufferView _layoutFlagBuffer(double mip) {
    final buffer = gpu.gpuContext.createDeviceBufferWithCopy(
      ByteData.sublistView(Float32List(4)..[0] = mip),
    );
    return gpu.BufferView(buffer, offsetInBytes: 0, lengthInBytes: 16);
  }

  // The engine lighting samplers are frame-invariant, so their options are
  // shared rather than allocated per draw (this binding path runs for every lit
  // draw, so at high draw counts the per-draw allocation churn is real).
  static final gpu.SamplerOptions _radianceMipSampler = gpu.SamplerOptions(
    minFilter: gpu.MinMagFilter.linear,
    magFilter: gpu.MinMagFilter.linear,
    mipFilter: gpu.MipFilter.linear,
    widthAddressMode: gpu.SamplerAddressMode.repeat,
    heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
  );
  static final gpu.SamplerOptions _radianceAtlasSampler = gpu.SamplerOptions(
    minFilter: gpu.MinMagFilter.linear,
    magFilter: gpu.MinMagFilter.linear,
    mipFilter: gpu.MipFilter.nearest,
    widthAddressMode: gpu.SamplerAddressMode.repeat,
    heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
  );
  static final gpu.SamplerOptions _cubeSampler = gpu.SamplerOptions(
    minFilter: gpu.MinMagFilter.linear,
    magFilter: gpu.MinMagFilter.linear,
    mipFilter: gpu.MipFilter.linear,
    widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
    heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
  );
  static final gpu.SamplerOptions _clampLinearSampler = gpu.SamplerOptions(
    minFilter: gpu.MinMagFilter.linear,
    magFilter: gpu.MinMagFilter.linear,
    widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
    heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
  );
  static final gpu.SamplerOptions _nearestSampler = gpu.SamplerOptions(
    minFilter: gpu.MinMagFilter.nearest,
    magFilter: gpu.MinMagFilter.nearest,
  );
  static final gpu.SamplerOptions _nearestClampSampler = gpu.SamplerOptions(
    minFilter: gpu.MinMagFilter.nearest,
    magFilter: gpu.MinMagFilter.nearest,
    widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
    heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
  );

  // Selects the mip-vs-atlas radiance sampler for a prefiltered radiance
  // texture's layout (the mip layout needs a linear mip filter for textureLod;
  // the single-level band atlas is inert under either).
  static gpu.SamplerOptions _radianceSampler(bool mipLayout) =>
      mipLayout ? _radianceMipSampler : _radianceAtlasSampler;

  /// Binds the prefiltered radiance sampler plus the `RadianceLayoutInfo`
  /// block that tells `SamplePrefilteredRadiance` which layout the bound
  /// texture uses. Every engine site that binds `prefiltered_radiance`
  /// goes through this so the texture and its layout flag never disagree.
  static void bindPrefilteredRadiance(
    gpu.RenderPass pass,
    gpu.Shader shader,
    EnvironmentMap env, {
    bool? cubeShader,
  }) {
    final cubeLayout = cubeShader ?? env.usesCubeRadianceLayout;
    final mipLayout = env.usesMipRadianceLayout;
    // A material built without the cube variant keeps its 2D sampler, which
    // cannot read a cubemap. Bind a 2D placeholder rather than a texture the
    // sampler would misread, and say so once.
    if (cubeLayout != env.usesCubeRadianceLayout) {
      assert(() {
        if (!_warnedLayoutMismatch) {
          _warnedLayoutMismatch = true;
          debugPrint(
            'flutter_scene: a material that samples the environment has no '
            'cubemap-radiance variant, so it contributes no image-based '
            'specular. Pass radianceCubeFragmentShader (the entry built with '
            'FLUTTER_SCENE_RADIANCE_CUBE) when constructing it.',
          );
        }
        return true;
      }());
      pass.bindTexture(
        shader.getUniformSlot('prefiltered_radiance'),
        Material.getBlackPlaceholderTexture(),
        sampler: _radianceSampler(false),
      );
      pass.bindUniform(
        shader.getUniformSlot('RadianceLayoutInfo'),
        _layoutAtlas,
      );
      return;
    }
    // The cube wants mip-linear for the roughness textureLod and clamped
    // faces. The 2D mip equirect needs the linear mip filter too; the legacy
    // band atlas has a single level, where the mip filter is inert, and both
    // repeat horizontally (longitude wraps) and clamp vertically.
    pass.bindTexture(
      shader.getUniformSlot('prefiltered_radiance'),
      env.prefilteredRadiance,
      sampler: cubeLayout ? _cubeSampler : _radianceSampler(mipLayout),
    );
    // Only the 2D variants read the layout flag, to tell the mip equirect from
    // the legacy band atlas. The cube variant declares the block through the
    // shared include but never samples it, so it has no live binding to fill
    // and binding one anyway is rejected.
    if (!cubeLayout) {
      pass.bindUniform(
        shader.getUniformSlot('RadianceLayoutInfo'),
        mipLayout ? _layoutMip : _layoutAtlas,
      );
    }
  }

  // Pass-scoped memo for the engine-constant bind set. Bindings persist
  // across draws within a pass, and the lighting samplers plus the fog block
  // are identical for a given (pass, shader, lighting, environment), so
  // re-issuing them per item only burns main-thread time (each bind marshals
  // its slot name across the FFI). The scene encoder invalidates the memo
  // whenever it clears the pass's bindings (on pipeline changes), keeping the
  // skip exactly as safe as re-binding.
  static gpu.RenderPass? _memoPass;
  static final Map<gpu.Shader, (Lighting, EnvironmentMap)> _texturesMemo = {};
  static final Map<gpu.Shader, Lighting> _fogMemo = {};

  /// Forgets all memoized bindings; the encoder calls this whenever it clears
  /// the render pass's bindings.
  static void invalidateBindMemo() {
    _memoPass = null;
    _texturesMemo.clear();
    _fogMemo.clear();
  }

  static bool _memoPassIs(gpu.RenderPass pass) {
    if (identical(pass, _memoPass)) return true;
    _memoPass = pass;
    _texturesMemo.clear();
    _fogMemo.clear();
    return false;
  }

  /// Binds the engine image-based-lighting and shadow samplers
  /// (`prefiltered_radiance`, `brdf_lut`, `shadow_map`) on [shader].
  static void bindEngineTextures(
    gpu.RenderPass pass,
    gpu.Shader shader,
    Lighting lighting,
    EnvironmentMap env, {
    bool bindSsao = true,
    bool bindShadows = true,
    bool bindDiffuseSh = true,
    bool? cubeShader,
  }) {
    if (_memoPassIs(pass)) {
      final previous = _texturesMemo[shader];
      if (previous != null &&
          identical(previous.$1, lighting) &&
          identical(previous.$2, env)) {
        return;
      }
    }
    _texturesMemo[shader] = (lighting, env);
    bindPrefilteredRadiance(pass, shader, env, cubeShader: cubeShader);
    pass.bindTexture(
      shader.getUniformSlot('brdf_lut'),
      Material.getBrdfLutTexture(),
      sampler: _clampLinearSampler,
    );
    if (bindShadows) {
      pass.bindTexture(
        shader.getUniformSlot('shadow_map'),
        Material.whitePlaceholder(lighting.shadowMap),
        // The atlas is fp32. GLES devices may support rendering/sampling float
        // textures without GL_OES_texture_float_linear, making linear filtering
        // incomplete. The shader already performs PCF explicitly, so nearest is
        // the portable choice.
        sampler: _nearestSampler,
      );
    }
    // The environment's diffuse SH coefficients, or the irradiance field's
    // atlas (whose first two rows are that same strip) when the field is on.
    // During a cross-fade [Lighting.diffuseShTexture] carries a 9x2 composite
    // holding both environments' rows; otherwise the primary's own 9x1
    // texture is bound and both shader row coordinates land on its single
    // row. Sampled in EvaluateDiffuseSH. A baked-lightmap variant reads its
    // diffuse ambient from the lightmap and declares no such sampler.
    if (bindDiffuseSh) {
      final field = lighting.irradianceField;
      pass.bindTexture(
        shader.getUniformSlot('irradiance_field'),
        field?.atlas ?? lighting.diffuseShTexture ?? env.diffuseShTexture,
        sampler: field != null ? _clampLinearSampler : _nearestClampSampler,
      );
    }
    // The secondary cross-fade environment's radiance (the *_b samplers).
    // When no cross-fade is active the primary is bound here too (a valid
    // no-op, since frag_info.radiance_blend.x is 0 and the shader never
    // reads it).
    bindSecondaryRadiance(
      pass,
      shader,
      lighting.environmentMapB ?? env,
      primary: env,
      cubeShader: cubeShader,
    );
    // Punctual light parameters (all scene lights) and the per-object light
    // index buffer, both RGBA32F data textures, point-sampled (each texel is
    // packed data). White placeholders are bound when there are no lights or no
    // reached items; the shader never reads them because the per-object count is
    // 0.
    pass.bindTexture(
      shader.getUniformSlot('punctual_lights'),
      Material.whitePlaceholder(lighting.punctualParamsTexture),
      sampler: _nearestClampSampler,
    );
    pass.bindTexture(
      shader.getUniformSlot('punctual_index'),
      Material.whitePlaceholder(lighting.punctualIndexTexture),
      sampler: _nearestClampSampler,
    );
    // Screen-space ambient occlusion. Bilinear so a half-resolution
    // occlusion buffer upsamples smoothly; a white placeholder makes the
    // sample a no-op when occlusion is off. The shader gates it on
    // ssao_params.x regardless.
    if (bindSsao) {
      pass.bindTexture(
        shader.getUniformSlot('ssao_texture'),
        Material.whitePlaceholder(lighting.ssaoMap),
        sampler: _clampLinearSampler,
      );
    }
  }

  /// Binds the engine samplers a shadow-catcher fragment shader declares.
  ///
  /// The catcher's generated `main()` never calls `EvaluateLighting`, so the
  /// radiance, BRDF, and SH samplers (and the fog block) are compiled out of
  /// it; binding those slots would fail. Its shadow variant, selected exactly
  /// when [Lighting.shadowMap] is set, is the only one that declares the
  /// shadow atlas and the punctual textures (its no-shadow twin compiles the
  /// spot loop out), so those bind only then.
  static void bindShadowCatcherTextures(
    gpu.RenderPass pass,
    gpu.Shader shader,
    Lighting lighting,
  ) {
    final shadowMap = lighting.shadowMap;
    if (shadowMap != null) {
      // fp32 atlas; PCF is explicit in the shader, so nearest is portable.
      pass.bindTexture(
        shader.getUniformSlot('shadow_map'),
        shadowMap,
        sampler: _nearestSampler,
      );
      pass.bindTexture(
        shader.getUniformSlot('punctual_lights'),
        Material.whitePlaceholder(lighting.punctualParamsTexture),
        sampler: _nearestClampSampler,
      );
      pass.bindTexture(
        shader.getUniformSlot('punctual_index'),
        Material.whitePlaceholder(lighting.punctualIndexTexture),
        sampler: _nearestClampSampler,
      );
    }
    pass.bindTexture(
      shader.getUniformSlot('ssao_texture'),
      Material.whitePlaceholder(lighting.ssaoMap),
      sampler: _clampLinearSampler,
    );
  }

  static final Float32List _lightmapInfoScratch = Float32List(12);

  /// Packs the `LightmapInfo` std140 block (three vec4s) into [target]. See
  /// `shaders/lightmap.glsl` for the field layout.
  @visibleForTesting
  static void packLightmapInfo(
    Float32List target, {
    required TextureTransform transform,
    required int texCoord,
    required double intensity,
    required bool rgbm,
  }) {
    target
      ..[0] = transform.offset.x
      ..[1] = transform.offset.y
      ..[2] = transform.scale.x
      ..[3] = transform.scale.y
      ..[4] = math.cos(transform.rotation)
      ..[5] = math.sin(transform.rotation)
      ..[6] = texCoord.clamp(0, 1).toDouble()
      ..[7] = rgbm ? 1.0 : 0.0
      ..[8] = intensity
      ..[9] = 0.0
      ..[10] = 0.0
      ..[11] = 0.0;
  }

  /// Binds the baked lightmap sampler and its `LightmapInfo` block. Both exist
  /// only in the `FLUTTER_SCENE_LIGHTMAP` variants, so this runs exactly when
  /// the material selected one (see `lightmap.glsl`).
  ///
  /// The bake replaces the SH diffuse ambient, so an unbound texture reads
  /// black (no indirect light) rather than white.
  static void bindLightmap(
    gpu.RenderPass pass,
    gpu.Shader shader,
    TransientWriter transientsBuffer, {
    required gpu.Texture? texture,
    required TextureTransform transform,
    required int texCoord,
    required double intensity,
    required bool rgbm,
    gpu.SamplerOptions? sampler,
  }) {
    pass.bindTexture(
      shader.getUniformSlot('lightmap_texture'),
      texture ?? Material.getBlackPlaceholderTexture(),
      sampler: sampler ?? _clampLinearSampler,
    );
    packLightmapInfo(
      _lightmapInfoScratch,
      transform: transform,
      texCoord: texCoord,
      intensity: intensity,
      rgbm: rgbm,
    );
    pass.bindUniform(
      shader.getUniformSlot('LightmapInfo'),
      transientsBuffer.emplace(ByteData.sublistView(_lightmapInfoScratch)),
    );
  }

  /// Binds the material scene-input samplers for a material that declared
  /// them (`Material.sceneInputs`); their slots exist only in shaders
  /// emitted with `engine_inputs`, so this must not run for other
  /// materials. Placeholders cover frames where an input was not produced
  /// (the `scene_inputs` gates read 0 then).
  static void bindSceneInputTextures(
    gpu.RenderPass pass,
    gpu.Shader shader,
    Lighting lighting,
    Set<RenderInput> sceneInputs,
  ) {
    if (sceneInputs.contains(RenderInput.opaqueSceneColor)) {
      pass.bindTexture(
        shader.getUniformSlot('scene_opaque_color'),
        Material.whitePlaceholder(lighting.opaqueSceneColor),
        sampler: _clampLinearSampler,
      );
    }
    if (sceneInputs.contains(RenderInput.filteredSceneColor)) {
      pass.bindTexture(
        shader.getUniformSlot('scene_filtered_color'),
        Material.whitePlaceholder(lighting.filteredSceneColor),
        sampler: _clampLinearSampler,
      );
    }
    if (sceneInputs.contains(RenderInput.depth)) {
      pass.bindTexture(
        shader.getUniformSlot('scene_depth'),
        Material.whitePlaceholder(lighting.sceneDepthLinear),
        sampler: _nearestClampSampler,
      );
    }
  }

  /// Binds the standalone `SceneInputInfo` block that
  /// `shaders/scene_inputs.glsl` declares, carrying what a `.fmat` material
  /// reads out of `FragInfo`: which inputs exist this frame, the render-target
  /// size the screen UV comes from, and the camera basis a refraction projects
  /// against. A raw [gpu.Shader] has no `FragInfo`, so without this it can
  /// neither gate on availability nor find the UV to sample with.
  ///
  /// Does nothing when the shader does not declare the block, which is both
  /// the material that computes its own mapping and the one whose declaration
  /// was optimized away. Unlike a sampler, an absent block reflects as a null
  /// size, so this is detectable rather than a bad bind.
  static void bindSceneInputInfo(
    gpu.RenderPass pass,
    gpu.Shader shader,
    Lighting lighting,
    TransientWriter transientsBuffer,
  ) {
    final slot = shader.getUniformSlot('SceneInputInfo');
    if (slot.sizeInBytes == null) return;

    final info = Float32List(20);
    info[0] = lighting.opaqueSceneColor != null ? 1.0 : 0.0;
    info[1] = lighting.sceneDepthLinear != null ? 1.0 : 0.0;
    info[2] = lighting.filteredSceneColor != null ? 1.0 : 0.0;
    final viewport = lighting.viewportSize;
    info[4] = viewport.width;
    info[5] = viewport.height;
    info[6] = viewport.width > 0 ? 1.0 / viewport.width : 0.0;
    info[7] = viewport.height > 0 ? 1.0 / viewport.height : 0.0;
    final forward = lighting.cameraForward;
    if (forward != null) {
      info[8] = forward.x;
      info[9] = forward.y;
      info[10] = forward.z;
    }
    info[11] = lighting.tanHalfFovY;
    final right = lighting.cameraRight;
    if (right != null) {
      info[12] = right.x;
      info[13] = right.y;
      info[14] = right.z;
    }
    info[15] = lighting.tanHalfFovX;
    final up = lighting.cameraUp;
    if (up != null) {
      info[16] = up.x;
      info[17] = up.y;
      info[18] = up.z;
    }
    pass.bindUniform(
      slot,
      transientsBuffer.emplace(ByteData.sublistView(info)),
    );
  }

  /// Binds the secondary cross-fade environment's prefiltered radiance to the
  /// `prefiltered_radiance_b` sampler (the specular term only, no diffuse SH).
  /// Shared by the lit material and the environment skybox; both share the
  /// primary's [RadianceLayoutInfo], so the layout flag is not re-bound here.
  ///
  /// [primary] selects the shader variant in use, so a secondary built in the
  /// other layout cannot be bound. It falls back to [primary], which leaves
  /// the cross-fade sampling one environment instead of binding a cube to a 2D
  /// sampler.
  static bool _warnedLayoutMismatch = false;

  static void bindSecondaryRadiance(
    gpu.RenderPass pass,
    gpu.Shader shader,
    EnvironmentMap env, {
    required EnvironmentMap primary,
    bool? cubeShader,
  }) {
    if (cubeShader != null && cubeShader != primary.usesCubeRadianceLayout) {
      pass.bindTexture(
        shader.getUniformSlot('prefiltered_radiance_b'),
        Material.getBlackPlaceholderTexture(),
        sampler: _radianceSampler(false),
      );
      return;
    }
    final source = env.usesCubeRadianceLayout == primary.usesCubeRadianceLayout
        ? env
        : primary;
    assert(() {
      if (!identical(source, env)) {
        debugPrint(
          'flutter_scene: the cross-faded environment uses a different '
          'prefiltered radiance layout than the primary; its specular '
          'contribution is skipped.',
        );
      }
      return true;
    }());
    pass.bindTexture(
      shader.getUniformSlot('prefiltered_radiance_b'),
      source.prefilteredRadiance,
      sampler: source.usesCubeRadianceLayout
          ? _cubeSampler
          : _radianceSampler(source.usesMipRadianceLayout),
    );
  }
}
