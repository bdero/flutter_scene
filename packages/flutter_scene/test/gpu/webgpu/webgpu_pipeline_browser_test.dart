// The WebGPU backend's render pipelines: vertex layouts, the state baked into
// each variant, bind group layouts from sample types, and the variant cache.
// Every variant is checked with a validation error scope.
//
//   flutter test --platform chrome --dart-define=flutter_scene.webgpu=true \
//     test/gpu/webgpu/webgpu_pipeline_browser_test.dart
//
// The last test builds a pipeline for every shader of a real sidecar when one
// is served at FLUTTER_SCENE_SIDECAR_URL, with CORS, and skips otherwise.
//
// ignore_for_file: implementation_imports
@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/shared/sidecar_hash.dart';
import 'package:flutter_scene/src/gpu/web/_gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/webgpu/webgpu_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

const _sidecarUrl = String.fromEnvironment('FLUTTER_SCENE_SIDECAR_URL');

final Uint8List _bundle = Uint8List.fromList(utf8.encode('pipeline bundle'));

const _vertexWgsl = '''
struct FrameInfo { mvp : mat4x4<f32> }
@group(0u) @binding(0u) var<uniform> frame : FrameInfo;
struct Out {
  @builtin(position) position : vec4<f32>,
  @location(0u) uv : vec2<f32>,
}
@vertex
fn main(@location(0u) position : vec3<f32>, @location(1u) uv : vec2<f32>) -> Out {
  return Out(frame.mvp * vec4<f32>(position, 1.0), uv);
}
''';

const _fragmentWgsl = '''
struct FragInfo { tint : vec4<f32> }
@group(0u) @binding(64u) var<uniform> info : FragInfo;
@group(0u) @binding(65u) var albedo : texture_2d<f32>;
@group(0u) @binding(193u) var albedo_sampler : sampler;
@fragment
fn main(@location(0u) uv : vec2<f32>) -> @location(0u) vec4<f32> {
  return textureSample(albedo, albedo_sampler, uv) * info.tint;
}
''';

String _sidecar({String fragment = _fragmentWgsl}) => jsonEncode({
  'format': 2,
  'translator': 'test',
  'bundle': sidecarBundleHash(_bundle),
  'shaders': {
    'TestVertex': {
      'stage': 'vertex',
      'entryPoint': 'main',
      'wgsl': _vertexWgsl,
      'inputs': [
        {'name': 'position', 'location': 0, 'vecSize': 3, 'offset': 0},
        {'name': 'uv', 'location': 1, 'vecSize': 2, 'offset': 12},
      ],
      'uniforms': [
        {
          'name': 'FrameInfo',
          'group': 0,
          'binding': 0,
          'size': 64,
          'fields': [
            {'name': 'mvp', 'offset': 0},
          ],
        },
      ],
      'textures': <Object?>[],
    },
    'TestFragment': {
      'stage': 'fragment',
      'entryPoint': 'main',
      'wgsl': fragment,
      'inputs': <Object?>[],
      'uniforms': [
        {
          'name': 'FragInfo',
          'group': 0,
          'binding': 64,
          'size': 16,
          'fields': [
            {'name': 'tint', 'offset': 0},
          ],
        },
      ],
      'textures': [
        {'name': 'albedo', 'group': 0, 'binding': 65, 'sampler': 193},
      ],
    },
    // Reads a varying the vertex stage never writes.
    'MismatchedFragment': {
      'stage': 'fragment',
      'entryPoint': 'main',
      'wgsl': '''
@fragment
fn main(@location(5u) v : vec4<f32>) -> @location(0u) vec4<f32> {
  return v;
}
''',
      'inputs': <Object?>[],
      'uniforms': <Object?>[],
      'textures': <Object?>[],
    },
  },
});

/// Builds the variant and fails the test with the validation message when
/// WebGPU rejects it.
Future<Object> _valid(
  ({
    Object variant,
    Object bindGroupLayout,
    String layoutKey,
    List<int> dynamicBindings,
    Future<String?>? validation,
  })
  built,
) async {
  expect(built.validation, isNotNull, reason: 'validation runs in debug');
  expect(await built.validation, isNull);
  return built.variant;
}

void main() {
  if (!gpu.useWebGpuBackend) {
    test('needs --dart-define=flutter_scene.webgpu=true', () {
      markTestSkipped('The shim is WebGL2 in this build.');
    });
    return;
  }

  late gpu.ShaderLibrary library;
  late gpu.Shader vertex;
  late gpu.Shader fragment;

  setUpAll(() async {
    await gpu.initializeGpuBackend();
    library = await webGpuShaderLibraryFromSidecar(_bundle, _sidecar());
    vertex = library['TestVertex']!;
    fragment = library['TestFragment']!;
  });

  gpu.RenderPipeline pipeline({gpu.VertexLayout? layout}) => gpu.gpuContext
      .createRenderPipeline(vertex, fragment, vertexLayout: layout);

  test('the default layout builds a valid pipeline', () async {
    final built = webGpuPipelineVariant(pipeline());
    await _valid(built);
    expect(built.dynamicBindings, [0, 64]);
    expect(built.layoutKey, contains('"sampleType":"float"'));
    expect(built.layoutKey, contains('"type":"filtering"'));
  });

  test('an invalid pipeline reports its validation error', () async {
    final built = webGpuPipelineVariant(
      gpu.gpuContext.createRenderPipeline(
        vertex,
        library['MismatchedFragment']!,
      ),
    );
    expect(await built.validation, isNotNull);
  });

  test('variants are cached by state and share bind group layouts', () async {
    final p = pipeline();
    final a = webGpuPipelineVariant(p);
    expect(identical(webGpuPipelineVariant(p).variant, a.variant), isTrue);

    final culled = webGpuPipelineVariant(p, cullMode: gpu.CullMode.backFace);
    final blended = webGpuPipelineVariant(p, blend: gpu.ColorBlendEquation());
    await _valid(culled);
    await _valid(blended);
    expect(identical(culled.variant, a.variant), isFalse);
    expect(identical(blended.variant, a.variant), isFalse);
    expect(identical(culled.bindGroupLayout, a.bindGroupLayout), isTrue);

    // Another pipeline with the same bindings shares the layout too.
    final other = webGpuPipelineVariant(pipeline());
    expect(identical(other.bindGroupLayout, a.bindGroupLayout), isTrue);
  });

  test('state with no effect on a target shares its variant', () async {
    final p = pipeline();
    final base = webGpuPipelineVariant(p);
    // No depth attachment, so depth and stencil state are moot.
    final moot = webGpuPipelineVariant(
      p,
      depthWriteEnable: true,
      depthCompare: gpu.CompareFunction.less,
      stencil: gpu.StencilConfig(compareFunction: gpu.CompareFunction.equal),
    );
    expect(identical(moot.variant, base.variant), isTrue);
    // A strip index format only matters to strips.
    final list32 = webGpuPipelineVariant(
      p,
      stripIndexType: gpu.IndexType.int32,
    );
    expect(identical(list32.variant, base.variant), isTrue);
    final strip16 = webGpuPipelineVariant(
      p,
      primitiveType: gpu.PrimitiveType.triangleStrip,
      stripIndexType: gpu.IndexType.int16,
    );
    final strip32 = webGpuPipelineVariant(
      p,
      primitiveType: gpu.PrimitiveType.triangleStrip,
      stripIndexType: gpu.IndexType.int32,
    );
    await _valid(strip16);
    await _valid(strip32);
    expect(identical(strip16.variant, strip32.variant), isFalse);
  });

  test('depth, stencil, MSAA, and every topology validate', () async {
    final p = pipeline();
    await _valid(
      webGpuPipelineVariant(
        p,
        depthStencilFormat: gpu.PixelFormat.d24UnormS8Uint,
        depthWriteEnable: true,
        depthCompare: gpu.CompareFunction.lessEqual,
        stencil: gpu.StencilConfig(
          compareFunction: gpu.CompareFunction.notEqual,
          depthStencilPassOperation: gpu.StencilOperation.setToReferenceValue,
          readMask: 0x0f,
        ),
      ),
    );
    await _valid(
      webGpuPipelineVariant(
        p,
        depthStencilFormat: gpu.gpuContext.defaultStencilFormat,
        stencil: gpu.StencilConfig(
          depthFailureOperation: gpu.StencilOperation.incrementWrap,
        ),
      ),
    );
    await _valid(
      webGpuPipelineVariant(
        p,
        colorFormats: const [gpu.PixelFormat.r16g16b16a16Float],
        depthStencilFormat: gpu.reversedDepthStencilFormat,
        sampleCount: 4,
        depthCompare: gpu.CompareFunction.greaterEqual,
        blend: gpu.ColorBlendEquation(
          colorBlendOperation: gpu.BlendOperation.reverseSubtract,
          sourceColorBlendFactor: gpu.BlendFactor.sourceAlphaSaturated,
          destinationColorBlendFactor: gpu.BlendFactor.oneMinusBlendColor,
        ),
      ),
    );
    for (final topology in gpu.PrimitiveType.values) {
      await _valid(webGpuPipelineVariant(p, primitiveType: topology));
    }
  });

  test('blending into r32Float validates with or without the feature', () {
    return _valid(
      webGpuPipelineVariant(
        pipeline(),
        colorFormats: const [gpu.PixelFormat.r32Float],
        blend: gpu.ColorBlendEquation(),
      ),
    );
  });

  test('a bound depth texture makes the slot unfilterable', () async {
    final p = pipeline();
    final color = webGpuPipelineVariant(p);
    final depth = webGpuPipelineVariant(
      p,
      textures: [(format: gpu.PixelFormat.d24UnormS8Uint, filters: true)],
    );
    await _valid(depth);
    expect(depth.layoutKey, contains('"sampleType":"unfilterable-float"'));
    expect(depth.layoutKey, contains('"type":"non-filtering"'));
    expect(identical(depth.variant, color.variant), isFalse);
    expect(identical(depth.bindGroupLayout, color.bindGroupLayout), isFalse);
  });

  test('explicit layouts feed instance and split buffers', () async {
    final layout = gpu.VertexLayout(
      buffers: const [
        gpu.VertexBuffer(
          strideInBytes: 12,
          attributes: [
            gpu.VertexAttribute(
              name: 'position',
              format: gpu.VertexFormat.float32x3,
            ),
          ],
        ),
        gpu.VertexBuffer(
          strideInBytes: 8,
          stepMode: gpu.VertexStepMode.instance,
          attributes: [
            gpu.VertexAttribute(name: 'uv', format: gpu.VertexFormat.float32x2),
          ],
        ),
      ],
    );
    await _valid(webGpuPipelineVariant(pipeline(layout: layout)));
  });

  test('a layout that cannot feed the shader fails as an Exception', () {
    gpu.VertexLayout only(List<gpu.VertexAttribute> attributes) =>
        gpu.VertexLayout(
          buffers: [
            gpu.VertexBuffer(strideInBytes: 32, attributes: attributes),
          ],
        );
    const position = gpu.VertexAttribute(
      name: 'position',
      format: gpu.VertexFormat.float32x3,
    );
    expect(
      () => pipeline(layout: only(const [position])),
      throwsA(isA<Exception>().having((e) => '$e', 'message', contains('uv'))),
    );
    expect(
      () => pipeline(
        layout: only(const [
          position,
          gpu.VertexAttribute(
            name: 'uvs',
            format: gpu.VertexFormat.float32x2,
            offsetInBytes: 12,
          ),
        ]),
      ),
      throwsA(
        isA<Exception>().having((e) => '$e', 'message', contains('"uvs"')),
      ),
    );
    expect(
      () => pipeline(
        layout: only(const [
          position,
          gpu.VertexAttribute(
            name: 'uv',
            format: gpu.VertexFormat.uint32x2,
            offsetInBytes: 12,
          ),
        ]),
      ),
      throwsA(
        isA<Exception>().having((e) => '$e', 'message', contains('uint32x2')),
      ),
    );
    expect(
      () => gpu.gpuContext.createRenderPipeline(fragment, vertex),
      throwsException,
    );
  });

  test('a hot-reloaded shader rebuilds the variants', () async {
    final p = pipeline();
    final before = webGpuPipelineVariant(p);
    // The reload drops the uniform, so the layout loses its binding.
    await webGpuReloadShaderLibrary(
      library,
      _bundle,
      _sidecar(
        fragment: _fragmentWgsl
            .replaceFirst(
              '@group(0u) @binding(64u) var<uniform> info : FragInfo;',
              '',
            )
            .replaceFirst(' * info.tint', ''),
      ),
    );
    final after = webGpuPipelineVariant(p);
    await _valid(after);
    expect(identical(after.variant, before.variant), isFalse);
    expect(after.dynamicBindings, [0]);
    // Restore for the other tests.
    await webGpuReloadShaderLibrary(library, _bundle, _sidecar());
  });

  test('every shader of a real sidecar builds a valid pipeline', () async {
    if (_sidecarUrl.isEmpty) {
      markTestSkipped('Set FLUTTER_SCENE_SIDECAR_URL to a served sidecar.');
      return;
    }
    final response = await web.window.fetch(_sidecarUrl.toJS).toDart;
    final json = (jsonDecode((await response.text().toDart).toDart) as Map)
      ..['bundle'] = sidecarBundleHash(_bundle);
    final real = await webGpuShaderLibraryFromSidecar(
      _bundle,
      jsonEncode(json),
    );
    final shaders = (json['shaders'] as Map).cast<String, Map>();
    final vertices = [
      for (final MapEntry(:key, :value) in shaders.entries)
        if (value['stage'] == 'vertex') key,
    ];
    // Likely partners first, so most fragments validate on the first try.
    vertices.sort((a, b) {
      int rank(String n) => const [
        'FullscreenVertex',
        'UnskinnedVertex',
        'UnskinnedDepthVertex',
      ].indexOf(n).abs();
      return rank(a).compareTo(rank(b));
    });

    final unpaired = <String>[];
    final paired = <String, String>{};
    for (final MapEntry(:key, :value) in shaders.entries) {
      if (value['stage'] != 'fragment') continue;
      String? partner;
      for (final v in vertices) {
        final built = webGpuPipelineVariant(
          gpu.gpuContext.createRenderPipeline(real[v]!, real[key]!),
          colorFormats: const [gpu.PixelFormat.r16g16b16a16Float],
          depthStencilFormat: gpu.reversedDepthStencilFormat,
        );
        if (await built.validation == null) {
          partner = v;
          break;
        }
      }
      partner == null ? unpaired.add(key) : paired[key] = partner;
    }
    for (final v in vertices) {
      if (paired.containsValue(v)) continue;
      // A vertex shader no fragment chose first still has to pair with one.
      var ok = false;
      for (final f in paired.keys) {
        final built = webGpuPipelineVariant(
          gpu.gpuContext.createRenderPipeline(real[v]!, real[f]!),
          colorFormats: const [gpu.PixelFormat.r16g16b16a16Float],
          depthStencilFormat: gpu.reversedDepthStencilFormat,
        );
        if (await built.validation == null) {
          paired['$f ($v)'] = v;
          ok = true;
          break;
        }
      }
      if (!ok) unpaired.add(v);
    }
    // ignore: avoid_print
    print('PIPELINES ${paired.length} fragments paired, unpaired $unpaired');
    expect(unpaired, isEmpty);

    // The pair with the most uniform blocks can pass the device's dynamic
    // offset limit; the blocks past it bind at fixed offsets instead.
    if (real['MorphedSkinnedVertex'] case final v?) {
      if (real['StandardLightmapFragment'] case final f?) {
        final widest = webGpuPipelineVariant(
          gpu.gpuContext.createRenderPipeline(v, f),
          colorFormats: const [gpu.PixelFormat.r16g16b16a16Float],
          depthStencilFormat: gpu.reversedDepthStencilFormat,
        );
        await _valid(widest);
        // ignore: avoid_print
        print('WIDEST dynamic ${widest.dynamicBindings}');
      }
    }
  });
}
