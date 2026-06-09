import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/material/environment.dart';
import 'package:flutter_scene/src/render/env_prefilter.dart';
import 'package:flutter_scene/src/render/skybox_encoder.dart';
import 'package:flutter_scene/src/scene_encoder.dart' show resolvePipeline;
import 'package:flutter_scene/src/shaders.dart';
import 'package:flutter_scene/src/skybox.dart';

// Fullscreen NDC quad (6 vec2s), shared by the face renders and the equirect
// assembly.
final gpu.DeviceBuffer _quad = gpu.gpuContext.createDeviceBufferWithCopy(
  ByteData.sublistView(
    Float32List.fromList(<double>[
      -1.0, -1.0, 1.0, -1.0, -1.0, 1.0, //
      -1.0, 1.0, 1.0, -1.0, 1.0, 1.0, //
    ]),
  ),
);
final gpu.BufferView _quadView = gpu.BufferView(
  _quad,
  offsetInBytes: 0,
  lengthInBytes: 6 * 2 * 4,
);

// The six cube faces as (forward, up). The right vector is up x forward (the
// look-at convention), and the assembly fragment samples with the same bases.
// Order matters: it maps to face_px, face_nx, face_py, face_ny, face_pz,
// face_nz in flutter_scene_cube_to_equirect.frag.
final List<(Vector3, Vector3)> _faceBases = [
  (Vector3(1, 0, 0), Vector3(0, 1, 0)), // +X
  (Vector3(-1, 0, 0), Vector3(0, 1, 0)), // -X
  (Vector3(0, 1, 0), Vector3(0, 0, -1)), // +Y
  (Vector3(0, -1, 0), Vector3(0, 0, 1)), // -Y
  (Vector3(0, 0, 1), Vector3(0, 1, 0)), // +Z
  (Vector3(0, 0, -1), Vector3(0, 1, 0)), // -Z
];

const List<String> _faceSamplerNames = [
  'face_px',
  'face_nx',
  'face_py',
  'face_ny',
  'face_pz',
  'face_nz',
];

gpu.Texture _hdrRenderTarget(int width, int height) {
  return gpu.gpuContext.createTexture(
    gpu.StorageMode.devicePrivate,
    width,
    height,
    format: gpu.PixelFormat.r16g16b16a16Float,
    enableRenderTargetUsage: true,
    enableShaderReadUsage: true,
    coordinateSystem: gpu.TextureCoordinateSystem.renderToTexture,
  );
}

// Inverse view-projection for a 90-degree-FOV face looking along [forward]
// from the origin. The near/far range is irrelevant since only the
// reconstructed direction is used.
Matrix4 _faceInverseViewProjection(Vector3 forward, Vector3 up) {
  final right = up.cross(forward)..normalize();
  final u = forward.cross(right)..normalize();
  final view = Matrix4(
    right.x,
    u.x,
    forward.x,
    0.0, //
    right.y,
    u.y,
    forward.y,
    0.0, //
    right.z,
    u.z,
    forward.z,
    0.0, //
    0.0,
    0.0,
    0.0,
    1.0,
  );
  const zn = 0.1, zf = 10.0;
  final a = zf / (zf - zn);
  final b = -(zf * zn) / (zf - zn);
  final proj = Matrix4(
    1.0,
    0.0,
    0.0,
    0.0, //
    0.0,
    1.0,
    0.0,
    0.0, //
    0.0,
    0.0,
    a,
    1.0, //
    0.0,
    0.0,
    b,
    0.0,
  );
  return (proj * view).clone()..invert();
}

gpu.Texture _renderFace(
  ShaderSkySource source,
  EnvironmentMap noEnvironment,
  Vector3 forward,
  Vector3 up,
  int resolution,
) {
  final face = _hdrRenderTarget(resolution, resolution);
  final commandBuffer = gpu.gpuContext.createCommandBuffer();
  final pass = commandBuffer.createRenderPass(
    gpu.RenderTarget.singleColor(
      gpu.ColorAttachment(texture: face, clearValue: Vector4.zero()),
    ),
  );
  final transients = gpu.gpuContext.createHostBuffer();
  final vertexShader = baseShaderLibrary['SkyboxVertex']!;
  pass.bindPipeline(resolvePipeline(vertexShader, source.fragmentShader));
  pass.setColorBlendEnable(false);
  pass.setCullMode(gpu.CullMode.none);
  pass.setPrimitiveType(gpu.PrimitiveType.triangle);
  bindVertexBufferCompat(pass, _quadView, 6);
  bindSkyboxFrameInfo(
    pass,
    transients,
    vertexShader,
    _faceInverseViewProjection(forward, up),
    Vector3.zero(),
    null,
  );
  source.bind(pass, transients, noEnvironment);
  drawCompat(pass, 6);
  commandBuffer.submit();
  return face;
}

gpu.Texture _assembleEquirect(List<gpu.Texture> faces, int width, int height) {
  final equirect = _hdrRenderTarget(width, height);
  final commandBuffer = gpu.gpuContext.createCommandBuffer();
  final pass = commandBuffer.createRenderPass(
    gpu.RenderTarget.singleColor(
      gpu.ColorAttachment(texture: equirect, clearValue: Vector4.zero()),
    ),
  );
  final vertexShader = baseShaderLibrary['FullscreenVertex']!;
  final fragmentShader = baseShaderLibrary['CubeToEquirectFragment']!;
  pass.bindPipeline(resolvePipeline(vertexShader, fragmentShader));
  pass.setColorBlendEnable(false);
  pass.setCullMode(gpu.CullMode.none);
  pass.setPrimitiveType(gpu.PrimitiveType.triangle);
  bindVertexBufferCompat(pass, _quadView, 6);
  for (var i = 0; i < 6; i++) {
    pass.bindTexture(
      fragmentShader.getUniformSlot(_faceSamplerNames[i]),
      faces[i],
      sampler: gpu.SamplerOptions(
        minFilter: gpu.MinMagFilter.linear,
        magFilter: gpu.MinMagFilter.linear,
        widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
        heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
      ),
    );
  }
  drawCompat(pass, 6);
  commandBuffer.submit();
  return equirect;
}

// Projects the equirect radiance onto 9 diffuse-irradiance SH coefficients
// (a 9x1 texture, coefficient i at texel i) entirely on the GPU.
gpu.Texture _projectSh(gpu.Texture equirect) {
  final sh = gpu.gpuContext.createTexture(
    gpu.StorageMode.devicePrivate,
    9,
    1,
    format: gpu.PixelFormat.r16g16b16a16Float,
    enableRenderTargetUsage: true,
    enableShaderReadUsage: true,
    coordinateSystem: gpu.TextureCoordinateSystem.renderToTexture,
  );
  final commandBuffer = gpu.gpuContext.createCommandBuffer();
  final pass = commandBuffer.createRenderPass(
    gpu.RenderTarget.singleColor(
      gpu.ColorAttachment(texture: sh, clearValue: Vector4.zero()),
    ),
  );
  final vertexShader = baseShaderLibrary['FullscreenVertex']!;
  final fragmentShader = baseShaderLibrary['ShProjectFragment']!;
  pass.bindPipeline(resolvePipeline(vertexShader, fragmentShader));
  pass.setColorBlendEnable(false);
  pass.setCullMode(gpu.CullMode.none);
  pass.setPrimitiveType(gpu.PrimitiveType.triangle);
  bindVertexBufferCompat(pass, _quadView, 6);
  pass.bindTexture(
    fragmentShader.getUniformSlot('source_equirect'),
    equirect,
    sampler: gpu.SamplerOptions(
      minFilter: gpu.MinMagFilter.linear,
      magFilter: gpu.MinMagFilter.linear,
      widthAddressMode: gpu.SamplerAddressMode.repeat,
      heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
    ),
  );
  drawCompat(pass, 6);
  commandBuffer.submit();
  return sh;
}

/// Renders [source] into six cube faces, assembles an equirectangular radiance
/// image, and produces both the prefiltered roughness-band atlas (specular,
/// see [prefilterEquirectRadiance]) and the 9-texel diffuse SH coefficient
/// texture. [noEnvironment] is passed to the sky fragment's bind for any
/// `useEnvironment` samplers (a sky baked into the environment cannot sample
/// the environment it is producing).
({gpu.Texture atlas, gpu.Texture sh}) bakeSkyEnvironment(
  ShaderSkySource source,
  EnvironmentMap noEnvironment, {
  int faceResolution = 128,
  int equirectWidth = 512,
}) {
  final faces = [
    for (final (forward, up) in _faceBases)
      _renderFace(source, noEnvironment, forward, up, faceResolution),
  ];
  final equirect = _assembleEquirect(faces, equirectWidth, equirectWidth ~/ 2);
  return (
    atlas: prefilterEquirectRadiance(equirect, sourceIsLinear: true),
    sh: _projectSh(equirect),
  );
}
