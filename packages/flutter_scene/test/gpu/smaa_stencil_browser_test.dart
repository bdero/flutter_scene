// Verifies the cross-pass discard -> stencil write -> stencil equal pattern
// used by SmaaPass on both web backends (WebGL2 and WebGPU):
//
//   flutter test --platform chrome test/gpu/smaa_stencil_browser_test.dart
//   flutter test --platform chrome --dart-define=flutter_scene.webgpu=true test/gpu/smaa_stencil_browser_test.dart
//
// ignore_for_file: implementation_imports
@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';
import 'package:flutter_scene/src/gpu/shared/sidecar_hash.dart';
import 'package:flutter_scene/src/gpu/web/_gpu.dart' show useWebGpuBackend;
import 'package:flutter_scene/src/gpu/web/shader_bundle_generated.dart' as fb;
import 'package:flutter_scene/src/gpu/webgpu/webgpu_backend.dart'
    show webGpuShaderLibraryFromSidecar;
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector4;
import 'package:web/web.dart' as web;

const int _width = 8;
const int _height = 4;

final Uint8List _wgslBundleBytes = Uint8List.fromList(
  utf8.encode('smaa stencil mask test'),
);

const String _vertexWgsl = '''
struct Out {
  @builtin(position) position : vec4<f32>,
  @location(0u) uv : vec2<f32>,
}
@vertex
fn main(@location(0u) position : vec2<f32>) -> Out {
  return Out(vec4<f32>(position, 0.0, 1.0), position * 0.5 + vec2<f32>(0.5));
}
''';

const String _markRightHalfWgsl = '''
@fragment
fn main(@location(0u) uv : vec2<f32>) -> @location(0u) vec4<f32> {
  if (uv.x < 0.5) {
    discard;
  }
  return vec4<f32>(0.0, 1.0, 0.0, 1.0);
}
''';

const String _solidRedWgsl = '''
@fragment
fn main(@location(0u) uv : vec2<f32>) -> @location(0u) vec4<f32> {
  return vec4<f32>(1.0, 0.0, 0.0, 1.0);
}
''';

String _webGpuSidecar() => jsonEncode({
  'format': 2,
  'translator': 'test',
  'bundle': sidecarBundleHash(_wgslBundleBytes),
  'shaders': {
    'QuadVertex': {
      'stage': 'vertex',
      'entryPoint': 'main',
      'wgsl': _vertexWgsl,
      'inputs': [
        {'name': 'position', 'location': 0, 'vecSize': 2, 'offset': 0},
      ],
      'uniforms': <Object?>[],
      'textures': <Object?>[],
    },
    'MarkRightHalfFragment': {
      'stage': 'fragment',
      'entryPoint': 'main',
      'wgsl': _markRightHalfWgsl,
      'inputs': <Object?>[],
      'uniforms': <Object?>[],
      'textures': <Object?>[],
    },
    'SolidRedFragment': {
      'stage': 'fragment',
      'entryPoint': 'main',
      'wgsl': _solidRedWgsl,
      'inputs': <Object?>[],
      'uniforms': <Object?>[],
      'textures': <Object?>[],
    },
  },
});

Uint8List _webGlBundle() {
  fb.ShaderObjectBuilder shader(
    String name,
    fb.ShaderStage stage,
    String source, {
    List<fb.ShaderInputObjectBuilder> inputs = const [],
  }) => fb.ShaderObjectBuilder(
    name: name,
    openglEs: fb.BackendShaderObjectBuilder(
      stage: stage,
      entrypoint: 'main',
      inputs: inputs,
      uniformStructs: const [],
      uniformTextures: const [],
      shader: utf8.encode(source),
    ),
  );
  return fb.ShaderBundleObjectBuilder(
    formatVersion: 2,
    shaders: [
      shader(
        'QuadVertex',
        fb.ShaderStage.kVertex,
        '#version 100\nattribute vec2 position;\nvarying vec2 v_uv;\n'
            'void main() { gl_Position = vec4(position, 0.0, 1.0); '
            'v_uv = position * 0.5 + vec2(0.5); }\n',
        inputs: [fb.ShaderInputObjectBuilder(name: 'position')],
      ),
      shader(
        'MarkRightHalfFragment',
        fb.ShaderStage.kFragment,
        '#version 100\nprecision mediump float;\nvarying vec2 v_uv;\n'
            'void main() { if (v_uv.x < 0.5) discard; '
            'gl_FragColor = vec4(0.0, 1.0, 0.0, 1.0); }\n',
      ),
      shader(
        'SolidRedFragment',
        fb.ShaderStage.kFragment,
        '#version 100\nprecision mediump float;\nvarying vec2 v_uv;\n'
            'void main() { gl_FragColor = vec4(1.0, 0.0, 0.0, 1.0); }\n',
      ),
    ],
  ).toBytes();
}

Future<gpu.ShaderLibrary> _loadTestLibrary() async {
  if (useWebGpuBackend) {
    return (await webGpuShaderLibraryFromSidecar(_webGpuSidecar()))
        as gpu.ShaderLibrary;
  }
  return (await gpu.loadShaderLibraryFromBytesAsync(
    ByteData.sublistView(_webGlBundle()),
  ))!;
}

Uint8List _readTexture(gpu.Texture texture) {
  final bitmap =
      gpu.gpuHost.textureToPlatformImage(texture)! as web.ImageBitmap;
  try {
    final reader = web.OffscreenCanvas(bitmap.width, bitmap.height);
    final ctx =
        reader.getContext('2d')! as web.OffscreenCanvasRenderingContext2D
          ..drawImage(bitmap, 0, 0);
    return Uint8List.fromList(
      ctx.getImageData(0, 0, bitmap.width, bitmap.height).data.toDart,
    );
  } finally {
    bitmap.close();
  }
}

List<int> _pixel(Uint8List pixels, int x, int y) {
  final i = (y * _width + x) * 4;
  return pixels.sublist(i, i + 4);
}

void main() {
  late gpu.ShaderLibrary library;
  late gpu.RenderPipeline markPipeline;
  late gpu.RenderPipeline redPipeline;
  late gpu.BufferView quadView;

  setUpAll(() async {
    await gpu.initializeGpuBackend();
    library = await _loadTestLibrary();
    final vertex = library['QuadVertex']!;
    const layout = gpu.VertexLayout(
      buffers: [
        gpu.VertexBuffer(
          strideInBytes: 8,
          attributes: [
            gpu.VertexAttribute(
              name: 'position',
              format: gpu.VertexFormat.float32x2,
            ),
          ],
        ),
      ],
    );
    markPipeline = gpu.gpuContext.createRenderPipeline(
      vertex,
      library['MarkRightHalfFragment']!,
      vertexLayout: layout,
    );
    redPipeline = gpu.gpuContext.createRenderPipeline(
      vertex,
      library['SolidRedFragment']!,
      vertexLayout: layout,
    );
    final quadBuffer = gpu.gpuContext.createDeviceBufferWithCopy(
      ByteData.sublistView(
        Float32List.fromList(<double>[
          -1.0, -1.0, 1.0, -1.0, -1.0, 1.0, //
          -1.0, 1.0, 1.0, -1.0, 1.0, 1.0, //
        ]),
      ),
    );
    quadView = gpu.BufferView(
      quadBuffer,
      offsetInBytes: 0,
      lengthInBytes: 6 * 2 * 4,
    );
  });

  test(
    'discarded fragments leave stencil 0 so a subsequent pass skips them',
    () {
      final pool = TransientTexturePool(framesInFlight: 1);
      addTearDown(pool.clear);
      pool.beginFrame();

      final stencil = pool.acquireScoped(
        TransientTextureDescriptor(
          width: _width,
          height: _height,
          format: gpu.gpuContext.defaultDepthStencilFormat,
          enableShaderReadUsage: false,
          debugName: 'smaa_stencil',
        ),
      );
      final edges = pool.acquireScoped(
        TransientTextureDescriptor.color(
          width: _width,
          height: _height,
          format: gpu.PixelFormat.r8g8b8a8UNormInt,
          debugName: 'smaa_edges',
          attachmentKey: 'smaa_stencil',
        ),
      );
      final weights = pool.acquireScoped(
        TransientTextureDescriptor.color(
          width: _width,
          height: _height,
          format: gpu.PixelFormat.r8g8b8a8UNormInt,
          debugName: 'smaa_weights',
          attachmentKey: 'smaa_stencil',
        ),
      );

      // Simulate a prior pass leaving DEPTH_TEST enabled (less) on WebGL2 so
      // both passes must explicitly configure depthWrite=false / always.
      {
        final cmd = gpu.gpuContext.createCommandBuffer();
        final rp = cmd.createRenderPass(
          gpu.RenderTarget.singleColor(
            gpu.ColorAttachment(texture: edges),
            depthStencilAttachment: gpu.DepthStencilAttachment(
              texture: stencil,
            ),
          ),
        );
        rp.setDepthWriteEnable(true);
        rp.setDepthCompareOperation(gpu.CompareFunction.less);
        cmd.submit();
      }

      // Pass 1: discard left half, mark surviving right half with stencil = 1.
      {
        final cmd = gpu.gpuContext.createCommandBuffer();
        final rp = cmd.createRenderPass(
          gpu.RenderTarget.singleColor(
            gpu.ColorAttachment(
              texture: edges,
              loadAction: gpu.LoadAction.clear,
              clearValue: Vector4.zero(),
            ),
            depthStencilAttachment: gpu.DepthStencilAttachment(
              texture: stencil,
              depthLoadAction: gpu.LoadAction.dontCare,
              depthStoreAction: gpu.StoreAction.dontCare,
              stencilLoadAction: gpu.LoadAction.clear,
              stencilStoreAction: gpu.StoreAction.store,
              stencilClearValue: 0,
            ),
          ),
        );
        rp.bindPipeline(markPipeline);
        rp.setDepthWriteEnable(false);
        rp.setDepthCompareOperation(gpu.CompareFunction.always);
        rp.setStencilReference(1);
        rp.setStencilConfig(
          gpu.StencilConfig(
            depthStencilPassOperation: gpu.StencilOperation.setToReferenceValue,
          ),
        );
        bindVertexBufferCompat(rp, quadView, 6);
        drawCompat(rp, 6);
        cmd.submit();
      }

      // Pass 2: shade only stencil == 1; left half must keep cleared zero.
      {
        final cmd = gpu.gpuContext.createCommandBuffer();
        final rp = cmd.createRenderPass(
          gpu.RenderTarget.singleColor(
            gpu.ColorAttachment(
              texture: weights,
              loadAction: gpu.LoadAction.clear,
              clearValue: Vector4.zero(),
            ),
            depthStencilAttachment: gpu.DepthStencilAttachment(
              texture: stencil,
              depthLoadAction: gpu.LoadAction.dontCare,
              depthStoreAction: gpu.StoreAction.dontCare,
              stencilLoadAction: gpu.LoadAction.load,
              stencilStoreAction: gpu.StoreAction.dontCare,
            ),
          ),
        );
        rp.bindPipeline(redPipeline);
        rp.setDepthWriteEnable(false);
        rp.setDepthCompareOperation(gpu.CompareFunction.always);
        rp.setStencilReference(1);
        rp.setStencilConfig(
          gpu.StencilConfig(
            compareFunction: gpu.CompareFunction.equal,
            writeMask: 0,
          ),
        );
        bindVertexBufferCompat(rp, quadView, 6);
        drawCompat(rp, 6);
        cmd.submit();
      }

      final edgePixels = _readTexture(edges);
      expect(_pixel(edgePixels, 1, 2), [0, 0, 0, 0]);
      expect(_pixel(edgePixels, _width - 2, 2), [0, 255, 0, 255]);

      final weightPixels = _readTexture(weights);
      expect(_pixel(weightPixels, 1, 2), [0, 0, 0, 0]);
      expect(_pixel(weightPixels, _width - 2, 2), [255, 0, 0, 255]);

      pool.releaseScoped(edges);
      pool.releaseScoped(stencil);
      pool.releaseScoped(weights);
      final heldAfterFrame1 = pool.heldTextureCount;

      // Second frame reuses the exact same pooled descriptors without growth.
      pool.beginFrame();
      final stencil2 = pool.acquireScoped(
        TransientTextureDescriptor(
          width: _width,
          height: _height,
          format: gpu.gpuContext.defaultDepthStencilFormat,
          enableShaderReadUsage: false,
          debugName: 'smaa_stencil',
        ),
      );
      final edges2 = pool.acquireScoped(
        TransientTextureDescriptor.color(
          width: _width,
          height: _height,
          format: gpu.PixelFormat.r8g8b8a8UNormInt,
          debugName: 'smaa_edges',
          attachmentKey: 'smaa_stencil',
        ),
      );
      final weights2 = pool.acquireScoped(
        TransientTextureDescriptor.color(
          width: _width,
          height: _height,
          format: gpu.PixelFormat.r8g8b8a8UNormInt,
          debugName: 'smaa_weights',
          attachmentKey: 'smaa_stencil',
        ),
      );
      expect(identical(stencil2, stencil), isTrue);
      expect(identical(edges2, edges), isTrue);
      expect(identical(weights2, weights), isTrue);
      expect(pool.heldTextureCount, heldAfterFrame1);
    },
  );
}
