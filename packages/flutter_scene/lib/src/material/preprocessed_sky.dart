import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/hot_reload/hot_reloadable_fmat.dart';
import 'package:flutter_scene/src/material/engine_lighting.dart';
import 'package:flutter_scene/src/material/environment.dart';
import 'package:flutter_scene/src/material/material_parameters.dart';
import 'package:flutter_scene/src/skybox.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';

/// A sky driven by a `.fmat` sky shader (`sky { vec3 Sky(vec3 direction) }`)
/// and its sidecar metadata (produced at build time by `buildMaterials`).
///
/// Wraps the compiled sky fragment as a [ShaderSkySource] and exposes typed,
/// name-addressed [parameters] from the sidecar, set the same way as a
/// `PreprocessedMaterial`'s:
///
/// ```dart
/// final sky = await loadFmatSky('assets/gradient_sky.fmat');
/// sky.parameters.setColor('zenith_color', const Color(0xff2255cc));
/// scene.skybox = Skybox(sky);
/// ```
///
/// Loaded via `loadFmatSky`, which registers it for in-place hot reload so a
/// `.fmat` edit shows up without a restart.
/// {@category Lighting and environment}
class PreprocessedSky extends ShaderSkySource implements HotReloadableFmat {
  // fragmentShader is also consumed in the initializer (to build parameters),
  // so it can't be a super parameter.
  // ignore: use_super_parameters
  PreprocessedSky({
    required gpu.Shader fragmentShader,
    required Map<String, Object?> metadata,
  }) : parameters = MaterialParameters.fromMetadata(fragmentShader, metadata),
       super(
         fragmentShader: fragmentShader,
         useEnvironment: metadata['use_environment'] == true,
       );

  /// The sky's parameters, set by name. See [MaterialParameters].
  final MaterialParameters parameters;

  // 16 zero bytes (a std140 vec4) for the FragmentKeepAlive block.
  static final ByteData _zeroKeepAlive = ByteData(16);

  @override
  void updateFromMetadata(
    gpu.Shader fragmentShader,
    Map<String, Object?> metadata,
  ) {
    this.fragmentShader = fragmentShader;
    useEnvironment = metadata['use_environment'] == true;
    parameters.updateFromMetadata(fragmentShader, metadata);
  }

  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    EnvironmentMap environment,
  ) {
    // Parameters (the MaterialParams block plus any declared samplers) carry
    // the sky's inputs; the raw uniform-block path is unused here.
    parameters.bind(pass, fragmentShader, transientsBuffer);
    // Zero keep-alive, mirroring PreprocessedMaterial; the generated sky
    // references every declared parameter resource through it so none can be
    // optimized out. Environment skies always declare the block (it keeps
    // the radiance samplers live even when the author never samples them).
    if (parameters.hasAnyParameters || useEnvironment) {
      pass.bindUniform(
        fragmentShader.getUniformSlot('FragmentKeepAlive'),
        transientsBuffer.emplace(_zeroKeepAlive),
      );
    }
    // A `requires: [environment]` sky samples the prefiltered radiance
    // through SampleEnvironment, bound the same way the standard material
    // binds it (both layout samplers plus the layout selector block).
    if (useEnvironment) {
      EngineLightingUniforms.bindPrefilteredRadiance(
        pass,
        fragmentShader,
        sampledEnvironment ?? environment,
      );
    }
  }
}
