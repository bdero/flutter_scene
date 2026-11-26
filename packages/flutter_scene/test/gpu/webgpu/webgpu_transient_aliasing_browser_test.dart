// Verifies intra-frame transient texture aliasing on the real WebGPU backend:
// descriptor isolation (attachmentKey, MSAA, storageMode, format), 2-frames-in-
// flight ring protection, pixel readback after intra-frame reuse, history/
// custom-pass isolation, resize clear(), and post-processing pool reduction.
//
// ignore_for_file: implementation_imports
@TestOn('browser')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/shared/sidecar_hash.dart';
import 'package:flutter_scene/src/gpu/web/_gpu.dart' as web_gpu;
import 'package:flutter_scene/src/gpu/webgpu/webgpu_backend.dart';
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

const bool _webGpuEnabled = bool.fromEnvironment('flutter_scene.webgpu');

final Uint8List _copyBundle = Uint8List.fromList(utf8.encode('aliasing copy'));

const _copyVertexWgsl = '''
struct Out {
  @builtin(position) position : vec4<f32>,
  @location(0u) uv : vec2<f32>,
}
@vertex
fn main(@location(0u) corner : vec2<f32>) -> Out {
  return Out(vec4<f32>(corner * 2.0 - vec2<f32>(1.0), 0.0, 1.0), corner);
}
''';

const _copyFragmentWgsl = '''
@group(0u) @binding(65u) var src : texture_2d<f32>;
@group(0u) @binding(193u) var src_sampler : sampler;
@fragment
fn main(@location(0u) uv : vec2<f32>) -> @location(0u) vec4<f32> {
  return textureSample(src, src_sampler, uv);
}
''';

String _copySidecar() => jsonEncode({
  'format': 2,
  'translator': 'test',
  'bundle': sidecarBundleHash(_copyBundle),
  'shaders': {
    'CopyVertex': {
      'stage': 'vertex',
      'entryPoint': 'main',
      'wgsl': _copyVertexWgsl,
      'inputs': [
        {'name': 'corner', 'location': 0, 'vecSize': 2, 'offset': 0},
      ],
      'uniforms': <Object?>[],
      'textures': <Object?>[],
    },
    'CopyFragment': {
      'stage': 'fragment',
      'entryPoint': 'main',
      'wgsl': _copyFragmentWgsl,
      'inputs': <Object?>[],
      'uniforms': <Object?>[],
      'textures': [
        {'name': 'src', 'group': 0, 'binding': 65, 'sampler': 193},
      ],
    },
  },
});

class _RecordingObserver implements RenderGraphObserver {
  final List<(TransientTextureDescriptor, gpu.Texture)> acquisitions = [];

  @override
  void onPassBegin(RenderGraphPass pass, int indexInGraph) {}

  @override
  void onPassEnd(RenderGraphPass pass, int elapsedMicros) {}

  @override
  void onBlackboardRead(Object key, Object? value) {}

  @override
  void onBlackboardWrite(Object key, Object? value) {}

  @override
  void onTextureAcquired(
    TransientTextureDescriptor descriptor,
    gpu.Texture texture,
  ) {
    acquisitions.add((descriptor, texture));
  }
}

void main() {
  if (!_webGpuEnabled) {
    test(
      'transient texture aliasing requires --dart-define=flutter_scene.webgpu=true',
      () => markTestSkipped('WebGPU backend not enabled.'),
    );
    return;
  }

  late web_gpu.Shader copyFragment;
  late web_gpu.RenderPipeline copyPipeline;
  late web_gpu.BufferView copyCorners;

  setUpAll(() async {
    await web_gpu.initializeGpuBackend();
    final lib = await webGpuShaderLibraryFromSidecar(_copySidecar());
    final copyVertex = lib['CopyVertex']!;
    copyFragment = lib['CopyFragment']!;
    copyPipeline = web_gpu.gpuContext.createRenderPipeline(
      copyVertex,
      copyFragment,
    );
    final quad = web_gpu.gpuContext.createDeviceBufferWithCopy(
      ByteData.sublistView(Float32List.fromList([0, 0, 1, 0, 0, 1, 1, 1])),
    );
    copyCorners = web_gpu.BufferView(quad, offsetInBytes: 0, lengthInBytes: 32);
  });

  void copyTexture(gpu.Texture source, gpu.Texture target) {
    final cb = web_gpu.gpuContext.createCommandBuffer();
    final pass = cb.createRenderPass(
      web_gpu.RenderTarget.singleColor(
        web_gpu.ColorAttachment(texture: target as web_gpu.Texture),
      ),
    );
    pass
      ..bindPipeline(copyPipeline)
      ..setPrimitiveType(web_gpu.PrimitiveType.triangleStrip)
      ..bindVertexBuffer(copyCorners)
      ..bindTexture(
        copyFragment.getUniformSlot('src'),
        source as web_gpu.Texture,
      )
      ..draw(4);
    cb.submit();
  }

  Future<List<int>> readPixel(gpu.Texture texture, int x, int y) async {
    final bytes = await webGpuReadTexture(texture as web_gpu.Texture);
    final i = (y * texture.width + x) * 4;
    return bytes.sublist(i, i + 4);
  }

  void clearTexture(gpu.Texture texture, vm.Vector4 color) {
    final cb = gpu.gpuContext.createCommandBuffer();
    cb.createRenderPass(
      gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(
          texture: texture,
          loadAction: gpu.LoadAction.clear,
          clearValue: color,
        ),
      ),
    );
    cb.submit();
  }

  test(
    'strict descriptor compatibility, MSAA, attachmentKey, and history isolation',
    () {
      final pool = TransientTexturePool(framesInFlight: 2);
      pool.beginFrame();

      const baseDesc = TransientTextureDescriptor.color(
        width: 64,
        height: 64,
        format: gpu.PixelFormat.r16g16b16a16Float,
        debugName: 'scoped_a',
      );
      final a = pool.acquireScoped(baseDesc);
      pool.releaseScoped(a);

      // Same physical descriptor (different debugName) -> reuses exact texture.
      final b = pool.acquireScoped(
        const TransientTextureDescriptor.color(
          width: 64,
          height: 64,
          format: gpu.PixelFormat.r16g16b16a16Float,
          debugName: 'scoped_b',
        ),
      );
      expect(identical(a, b), isTrue);

      // Overlapping live request -> allocates a second physical slot.
      final c = pool.acquireScoped(
        const TransientTextureDescriptor.color(
          width: 64,
          height: 64,
          format: gpu.PixelFormat.r16g16b16a16Float,
          debugName: 'scoped_c',
        ),
      );
      expect(identical(b, c), isFalse);
      pool.releaseScoped(b);
      pool.releaseScoped(c);

      // Different attachmentKey must NOT alias (preserves GLES FBO cache safety).
      final diffAttachmentKey = pool.acquireScoped(
        const TransientTextureDescriptor.color(
          width: 64,
          height: 64,
          format: gpu.PixelFormat.r16g16b16a16Float,
          debugName: 'with_depth',
          attachmentKey: 'depth_transient',
        ),
      );
      expect(identical(diffAttachmentKey, a), isFalse);
      expect(identical(diffAttachmentKey, c), isFalse);

      // Different sampleCount (4x MSAA) must NOT alias.
      final msaa = pool.acquireScoped(
        const TransientTextureDescriptor(
          width: 64,
          height: 64,
          format: gpu.PixelFormat.r16g16b16a16Float,
          sampleCount: 4,
          storageMode: gpu.StorageMode.deviceTransient,
          enableShaderReadUsage: false,
          debugName: 'msaa4',
        ),
      );
      expect(identical(msaa, a), isFalse);

      // Non-scoped acquire() (custom passes / history) never aliases with scoped.
      final customOrHistory = pool.acquire(
        const TransientTextureDescriptor.color(
          width: 64,
          height: 64,
          format: gpu.PixelFormat.r16g16b16a16Float,
          debugName: 'custom_or_history',
        ),
      );
      expect(identical(customOrHistory, a), isFalse);
      expect(identical(customOrHistory, c), isFalse);
      // Calling releaseScoped on a non-scoped texture is a safe no-op.
      pool.releaseScoped(customOrHistory);

      pool.clear();
      expect(pool.residentBytes, 0);
      expect(pool.heldTextureCount, 0);
    },
  );

  test(
    'intra-frame reuse pixel readback, 2-frames-in-flight ring, and resize clear',
    () async {
      final pool = TransientTexturePool(framesInFlight: 2);
      const desc1 = TransientTextureDescriptor.color(
        width: 4,
        height: 4,
        format: gpu.PixelFormat.r8g8b8a8UNormInt,
        debugName: 'pass_1',
      );
      const desc2 = TransientTextureDescriptor.color(
        width: 4,
        height: 4,
        format: gpu.PixelFormat.r8g8b8a8UNormInt,
        debugName: 'pass_2',
      );

      // Frame 0: submit back-to-back without intermediate readback (WAR check):
      // pass 1 writes red to A -> pass 2 samples A into B -> release A ->
      // alias A's physical slot and overwrite green -> read back B & aliased A.
      const desc3 = TransientTextureDescriptor.color(
        width: 4,
        height: 4,
        format: gpu.PixelFormat.r8g8b8a8UNormInt,
        debugName: 'pass_3',
      );
      pool.beginFrame();
      final f0TexA = pool.acquireScoped(desc1);
      clearTexture(f0TexA, vm.Vector4(1, 0, 0, 1));

      final f0TexB = pool.acquireScoped(desc2);
      expect(identical(f0TexA, f0TexB), isFalse);
      copyTexture(f0TexA, f0TexB);
      pool.releaseScoped(f0TexA);

      final f0Aliased = pool.acquireScoped(desc3);
      expect(identical(f0TexA, f0Aliased), isTrue);
      clearTexture(f0Aliased, vm.Vector4(0, 1, 0, 1));
      pool.releaseScoped(f0TexB);
      pool.releaseScoped(f0Aliased);

      expect(await readPixel(f0TexB, 1, 1), [255, 0, 0, 255]);
      expect(await readPixel(f0Aliased, 1, 1), [0, 255, 0, 255]);

      // Frame 1: must use the OTHER ring slot (framesInFlight = 2 protection).
      pool.beginFrame();
      final f1TexA = pool.acquireScoped(desc1);
      expect(identical(f1TexA, f0TexA), isFalse);
      clearTexture(f1TexA, vm.Vector4(0, 0, 1, 1));
      expect(await readPixel(f1TexA, 1, 1), [0, 0, 255, 255]);
      pool.releaseScoped(f1TexA);

      // Frame 2: wraps back to Frame 0's texture with zero new allocations.
      final createdBeforeSteady = TransientTexturePool.texturesCreated;
      pool.beginFrame();
      final f2TexA = pool.acquireScoped(desc1);
      expect(identical(f2TexA, f0TexA), isTrue);
      expect(TransientTexturePool.texturesCreated, createdBeforeSteady);

      // Resize clear() releases all resident textures cleanly.
      pool.clear();
      expect(pool.residentBytes, 0);
      expect(pool.heldTextureCount, 0);
    },
  );

  test(
    'post-processing chain aliasing reduces held textures and resident bytes',
    () {
      void checkChain(
        String label, {
        required bool ssgi,
        required int expectedAliasedCount,
      }) {
        const fullW = 64;
        const fullH = 64;
        const halfW = 32;
        const halfH = 32;
        final aoFmt = ssgi
            ? gpu.PixelFormat.r16g16b16a16Float
            : gpu.PixelFormat.r8g8b8a8UNormInt;

        ({int bytes, int count}) runPool({required bool aliased}) {
          final pool = TransientTexturePool(framesInFlight: 2);
          gpu.Texture getTex(int w, int h, gpu.PixelFormat fmt, String name) {
            final d = TransientTextureDescriptor.color(
              width: w,
              height: h,
              format: fmt,
              debugName: name,
            );
            return aliased ? pool.acquireScoped(d) : pool.acquire(d);
          }

          void dropTex(gpu.Texture t) {
            if (aliased) pool.releaseScoped(t);
          }

          // Run 2 full frames so both framesInFlight slots allocate.
          for (var f = 0; f < 2; f++) {
            pool.beginFrame();
            // SSAO / SSGI half-res chain (3 targets -> 2 aliased).
            final ssaoRaw = getTex(halfW, halfH, aoFmt, 'ssao_raw');
            final ssaoH = getTex(
              halfW,
              halfH,
              aoFmt,
              'ssao_blurred_horizontal',
            );
            dropTex(ssaoRaw);
            final ssaoOut = getTex(halfW, halfH, aoFmt, 'ssao_blurred');
            dropTex(ssaoH);
            // ScenePass reads ssaoOut, then releases it.
            dropTex(ssaoOut);

            // SSR half-res reflection (1 target, released after composite).
            final ssrRefl = getTex(
              halfW,
              halfH,
              gpu.PixelFormat.r16g16b16a16Float,
              'ssr_reflection',
            );
            dropTex(ssrRefl);

            // DoF half-res chain (5 targets -> 3 aliased, reusing SSR/SSGI).
            final coc = getTex(
              halfW,
              halfH,
              gpu.PixelFormat.r16g16b16a16Float,
              'dof_coc_color',
            );
            final nearRow = getTex(
              halfW,
              halfH,
              gpu.PixelFormat.r16g16b16a16Float,
              'dof_near_coc_row',
            );
            final nearCoc = getTex(
              halfW,
              halfH,
              gpu.PixelFormat.r16g16b16a16Float,
              'dof_near_coc',
            );
            dropTex(nearRow);
            final gather = getTex(
              halfW,
              halfH,
              gpu.PixelFormat.r16g16b16a16Float,
              'dof_gather',
            );
            dropTex(coc);
            dropTex(nearCoc);
            final post = getTex(
              halfW,
              halfH,
              gpu.PixelFormat.r16g16b16a16Float,
              'dof_postfilter',
            );
            dropTex(gather);
            dropTex(post);

            // SMAA full-res edges/weights.
            final smaaEdges = getTex(
              fullW,
              fullH,
              gpu.PixelFormat.r8g8b8a8UNormInt,
              'smaa_edges',
            );
            final smaaWeights = getTex(
              fullW,
              fullH,
              gpu.PixelFormat.r8g8b8a8UNormInt,
              'smaa_weights',
            );
            dropTex(smaaEdges);
            dropTex(smaaWeights);
          }
          final result = (
            bytes: pool.residentBytes,
            count: pool.heldTextureCount,
          );
          pool.clear();
          return result;
        }

        final base = runPool(aliased: false);
        final opt = runPool(aliased: true);
        expect(base.count, 22, reason: label);
        expect(opt.count, expectedAliasedCount, reason: label);
        expect(opt.bytes, lessThan(base.bytes), reason: label);
      }

      checkChain('AO_SSR_DoF_SMAA', ssgi: false, expectedAliasedCount: 14);
      checkChain('SSGI_SSR_DoF_SMAA', ssgi: true, expectedAliasedCount: 10);
    },
  );

  test(
    'ObservedTexturePool disables intra-frame aliasing and records acquisitions',
    () {
      final inner = TransientTexturePool(framesInFlight: 2);
      final observer = _RecordingObserver();
      final observed = ObservedTexturePool(inner, observer);
      const descA = TransientTextureDescriptor.color(
        width: 16,
        height: 16,
        format: gpu.PixelFormat.r8g8b8a8UNormInt,
        debugName: 'capture_a',
      );
      const descB = TransientTextureDescriptor.color(
        width: 16,
        height: 16,
        format: gpu.PixelFormat.r8g8b8a8UNormInt,
        debugName: 'capture_b',
      );

      observed.beginFrame();
      final texA = observed.acquireScoped(descA);
      observed.releaseScoped(texA);
      final texB = observed.acquireScoped(descB);
      observed.releaseScoped(texB);

      expect(identical(texA, texB), isFalse);
      expect(observer.acquisitions.length, 2);
      expect(observer.acquisitions[0].$1, descA);
      expect(identical(observer.acquisitions[0].$2, texA), isTrue);
      expect(observer.acquisitions[1].$1, descB);
      expect(identical(observer.acquisitions[1].$2, texB), isTrue);
      expect(observed.heldTextureCount, inner.heldTextureCount);
      expect(observed.heldTextureCount, 2);

      observed.clear();
      expect(observed.heldTextureCount, 0);
    },
  );
}
