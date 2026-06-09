import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/material/environment.dart';
import 'package:flutter_scene/src/scene_encoder.dart' show resolvePipeline;
import 'package:flutter_scene/src/shaders.dart';
import 'package:flutter_scene/src/skybox.dart';

// Two triangles of NDC positions covering the whole render target (6 vec2s).
final gpu.DeviceBuffer _fullscreenQuad = gpu.gpuContext
    .createDeviceBufferWithCopy(
      ByteData.sublistView(
        Float32List.fromList(<double>[
          -1.0, -1.0, 1.0, -1.0, -1.0, 1.0, //
          -1.0, 1.0, 1.0, -1.0, 1.0, 1.0, //
        ]),
      ),
    );
final gpu.BufferView _fullscreenQuadView = gpu.BufferView(
  _fullscreenQuad,
  offsetInBytes: 0,
  lengthInBytes: 6 * 2 * 4,
);

/// Draws [skybox] into [renderPass] as the scene background.
///
/// Issued before the scene geometry, into the same HDR color target: the sky
/// covers the screen, writes no depth (so opaque geometry, depth-tested
/// against the cleared far value, draws over it) and does not blend. Exposure
/// and tone mapping are applied later by the resolve pass, so the sky is
/// emitted as linear HDR radiance with premultiplied alpha.
///
/// The render pass is left with the skybox's fixed-function state (no depth
/// write, `lessEqual` depth compare, no cull, no blend); the scene encoder
/// re-asserts the opaque-phase state when it is constructed afterward.
void encodeSkybox(
  gpu.RenderPass renderPass,
  gpu.HostBuffer transientsBuffer,
  Skybox skybox,
  EnvironmentMap environment,
  double environmentIntensity,
  Matrix3? environmentTransform,
  Camera camera,
  ui.Size dimensions,
) {
  final source = skybox.source;
  final vertexShader = baseShaderLibrary['SkyboxVertex']!;
  final gpu.Shader fragmentShader;
  if (source is EnvironmentSkySource) {
    fragmentShader = baseShaderLibrary['SkyboxEnvironmentFragment']!;
  } else if (source is ShaderSkySource) {
    fragmentShader = source.fragmentShader;
  } else {
    return;
  }

  // Share the scene encoder's pipeline cache so a hot-reloaded sky fragment is
  // rebuilt (the cache is evicted by shader identity on reload).
  renderPass.clearBindings();
  renderPass.bindPipeline(resolvePipeline(vertexShader, fragmentShader));
  renderPass.setColorBlendEnable(false);
  // Draw at the far plane behind everything: pass where nothing has been
  // drawn (depth still at the cleared far value) and never write depth, so
  // opaque geometry draws in front.
  renderPass.setDepthWriteEnable(false);
  renderPass.setDepthCompareOperation(gpu.CompareFunction.lessEqual);
  renderPass.setCullMode(gpu.CullMode.none);
  renderPass.setPrimitiveType(gpu.PrimitiveType.triangle);
  bindVertexBufferCompat(renderPass, _fullscreenQuadView, 6);

  // Vertex SkyboxFrameInfo: the world view ray is reconstructed from the
  // inverse of the exact view-projection the scene geometry uses, rotated by
  // the environment transform. Shared by every sky source.
  _bindFrameInfo(
    renderPass,
    transientsBuffer,
    vertexShader,
    environmentTransform,
    camera,
    dimensions,
  );

  // Fragment bindings depend on the source.
  if (source is EnvironmentSkySource) {
    _bindEnvironmentSource(
      renderPass,
      transientsBuffer,
      fragmentShader,
      source,
      environment,
      environmentIntensity * skybox.intensity,
    );
  } else if (source is ShaderSkySource) {
    source.bind(renderPass, transientsBuffer, environment);
  }

  drawCompat(renderPass, 6);
}

// Binds SkyboxFrameInfo (inverse view-projection, environment rotation as a
// mat4, camera position) on the sky vertex shader.
void _bindFrameInfo(
  gpu.RenderPass renderPass,
  gpu.HostBuffer transientsBuffer,
  gpu.Shader vertexShader,
  Matrix3? environmentTransform,
  Camera camera,
  ui.Size dimensions,
) {
  final inverseViewProjection = camera.getViewTransform(dimensions).clone()
    ..invert();
  final transform = (environmentTransform ?? Matrix3.identity()).storage;
  final cameraPosition = camera.position;
  final frameInfo = Float32List(36);
  frameInfo.setRange(0, 16, inverseViewProjection.storage);
  // environment_transform: a mat4 carrying the 3x3 rotation; std140 mat4
  // columns are 16 bytes (4 floats) each, starting at float 16.
  for (var col = 0; col < 3; col++) {
    frameInfo[16 + col * 4] = transform[col * 3];
    frameInfo[16 + col * 4 + 1] = transform[col * 3 + 1];
    frameInfo[16 + col * 4 + 2] = transform[col * 3 + 2];
  }
  frameInfo[31] = 1.0; // mat4 column 3 = (0, 0, 0, 1)
  frameInfo[32] = cameraPosition.x;
  frameInfo[33] = cameraPosition.y;
  frameInfo[34] = cameraPosition.z;
  renderPass.bindUniform(
    vertexShader.getUniformSlot('SkyboxFrameInfo'),
    transientsBuffer.emplace(ByteData.sublistView(frameInfo)),
  );
}

// Binds the built-in environment sky fragment: SkyboxInfo (blurriness +
// combined intensity) and the prefiltered-radiance atlas.
void _bindEnvironmentSource(
  gpu.RenderPass renderPass,
  gpu.HostBuffer transientsBuffer,
  gpu.Shader fragmentShader,
  EnvironmentSkySource source,
  EnvironmentMap environment,
  double intensity,
) {
  final skyboxInfo = Float32List(4);
  skyboxInfo[0] = source.blurriness;
  skyboxInfo[1] = intensity;
  renderPass.bindUniform(
    fragmentShader.getUniformSlot('SkyboxInfo'),
    transientsBuffer.emplace(ByteData.sublistView(skyboxInfo)),
  );

  // The prefiltered-radiance atlas: horizontal repeat (longitude wraps),
  // vertical clamp (roughness bands must not bleed). Matches the standard
  // material's binding so the sky and reflections sample identically.
  renderPass.bindTexture(
    fragmentShader.getUniformSlot('prefiltered_radiance'),
    environment.prefilteredRadianceTexture,
    sampler: gpu.SamplerOptions(
      minFilter: gpu.MinMagFilter.linear,
      magFilter: gpu.MinMagFilter.linear,
      widthAddressMode: gpu.SamplerAddressMode.repeat,
      heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
    ),
  );
}
