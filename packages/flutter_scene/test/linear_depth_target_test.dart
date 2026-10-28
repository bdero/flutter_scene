// Covers the depth prepass target: the depth-only variant writes a
// single-channel fp32 target, the normal-writing variant keeps four
// channels, and both carry the planar view-space depth in red.

@TestOn('vm')
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/render/frame_transients.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/scene_encoder.dart' show resolvePipeline;

import 'support/gpu_available.dart';

const int _size = 32;

// Reads the prepass target and copies it into an 8-bit texture, so depths
// in [0, 1] world units read back exactly enough and the far clear reads 255.
class _DepthProbe extends CustomRenderPass {
  _DepthProbe(this.inputs);

  @override
  final Set<RenderInput> inputs;

  @override
  String get name => 'depth_probe';

  @override
  RenderStage get stage => RenderStage.afterScene;

  gpu.PixelFormat? format;
  gpu.Texture? copy;

  static final gpu.Shader _vertex = baseShaderLibrary['FullscreenVertex']!;
  static final gpu.Shader _copyFragment = baseShaderLibrary['CopyFragment']!;

  @override
  void execute(RenderPassContext context) {
    final depth = context.sceneDepthLinear!;
    format = depth.format;
    final target = gpu.gpuContext.createTexture(
      gpu.StorageMode.devicePrivate,
      depth.width,
      depth.height,
      format: gpu.PixelFormat.r8g8b8a8UNormInt,
      enableRenderTargetUsage: true,
      enableShaderReadUsage: true,
    );
    final quad = gpu.gpuContext.createDeviceBufferWithCopy(
      ByteData.sublistView(
        Float32List.fromList(<double>[
          -1.0, -1.0, 1.0, -1.0, -1.0, 1.0, //
          -1.0, 1.0, 1.0, -1.0, 1.0, 1.0, //
        ]),
      ),
    );
    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final renderPass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: target)),
    );
    renderPass.bindPipeline(resolvePipeline(_vertex, _copyFragment));
    renderPass.setDepthWriteEnable(false);
    renderPass.setDepthCompareOperation(gpu.CompareFunction.always);
    renderPass.setColorBlendEnable(false);
    renderPass.setCullMode(gpu.CullMode.none);
    bindVertexBufferCompat(
      renderPass,
      gpu.BufferView(quad, offsetInBytes: 0, lengthInBytes: 6 * 2 * 4),
      6,
    );
    renderPass.bindTexture(
      _copyFragment.getUniformSlot('source_texture'),
      depth,
      sampler: gpu.SamplerOptions(
        minFilter: gpu.MinMagFilter.nearest,
        magFilter: gpu.MinMagFilter.nearest,
      ),
    );
    drawCompat(renderPass, 6);
    rendererSubmissions.submit(commandBuffer);
    copy = target;
  }
}

Future<({gpu.PixelFormat format, int centre, int corner})> _probe(
  Set<RenderInput> inputs,
) async {
  final scene = Scene();
  // A thin card whose near face sits half a world unit in front of the eye.
  scene.add(
    Node(mesh: Mesh(CuboidGeometry(Vector3(0.1, 0.1, 0.002)), UnlitMaterial()))
      ..position = Vector3(0, 0, 0.001),
  );
  final probe = _DepthProbe(inputs);
  scene.addRenderPass(probe);
  final recorder = ui.PictureRecorder();
  scene.render(
    PerspectiveCamera(position: Vector3(0, 0, -0.5), fovNear: 0.01),
    ui.Canvas(recorder),
    viewport: const ui.Rect.fromLTWH(0, 0, _size + 0.0, _size + 0.0),
    pixelRatio: 1.0,
  );
  recorder.endRecording().dispose();
  final bytes = (await probe.copy!.asImage().toByteData(
    format: ui.ImageByteFormat.rawRgba,
  ))!;
  int red(int x, int y) => bytes.getUint8((y * _size + x) * 4);
  return (
    format: probe.format!,
    centre: red(_size ~/ 2, _size ~/ 2),
    corner: red(0, 0),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final noGpu = gpuAvailable()
      ? null
      : 'Requires a GPU device: --enable-impeller --enable-flutter-gpu.';

  setUpAll(() async {
    if (noGpu == null) await Scene.initializeStaticResources();
  });

  test('the depth-only prepass writes a single-channel fp32 target', () async {
    final result = await _probe(const {RenderInput.depth});
    expect(result.format, gpu.PixelFormat.r32Float);
    expect(result.centre, closeTo(128, 2));
    expect(result.corner, 255);
  }, skip: noGpu);

  test('the normal-writing prepass keeps four fp32 channels', () async {
    final result = await _probe(const {RenderInput.normals});
    expect(result.format, gpu.PixelFormat.r32g32b32a32Float);
    expect(result.centre, closeTo(128, 2));
    expect(result.corner, 255);
  }, skip: noGpu);
}
