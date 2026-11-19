// Data textures on a real GPU context: 2D-array textures in single-channel and
// float formats are created, uploaded a layer at a time, sampled through a
// sampler2DArray compiled at test time, and read back. Needs Flutter GPU (run
// with --enable-impeller) and impellerc; skips without them.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_gpu_shaders/build.dart'
    show shaderBundleImpellercArguments;
import 'package:flutter_gpu_shaders/environment.dart' show findImpellerC;
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/fmat/fmat_bytes_library.dart';
import 'package:flutter_scene/src/fmat/runtime_compile.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';

import 'support/gpu_available.dart';

const _vertex = '''
in vec2 position;
out vec2 v_uv;
void main() {
  v_uv = position * 0.5 + 0.5;
  gl_Position = vec4(position, 0.0, 1.0);
}
''';

// Writes the sampled layer's red channel, and its green when the format has
// one, so single- and two-channel textures read back unambiguously.
const _arrayFragment = '''
uniform sampler2DArray layers;
uniform Params {
  float layer;
} params;
in vec2 v_uv;
out vec4 frag_color;
void main() {
  vec4 texel = texture(layers, vec3(v_uv, params.layer));
  frag_color = vec4(texel.r, texel.g, 0.0, 1.0);
}
''';

// A material sampling a 2D array.
const _arrayMaterial = '''
material {
  name: "ArrayMaterial",
  shading_model: unlit,
  parameters: [
    { type: sampler2DArray, name: layers, hint: default_black },
    { type: float, name: layer, default: 0.0 },
  ],
}
fragment {
  void Surface(inout MaterialInputs material) {
    float v = texture(layers, vec3(GetUV0(), material_params.layer)).r;
    material.base_color = vec4(v, v, v, 1.0);
    PrepareMaterial(material);
  }
}
''';

Future<ByteData> _compileBundle(Uri impellerc) async {
  final dir = Directory.systemTemp.createTempSync('data_texture_test_');
  try {
    final vertex = File('${dir.path}/quad.vert')..writeAsStringSync(_vertex);
    final fragment = File('${dir.path}/array.frag')
      ..writeAsStringSync(_arrayFragment);
    final bundle = File('${dir.path}/test.shaderbundle');
    final result = await Process.run(
      impellerc.toFilePath(),
      shaderBundleImpellercArguments(
        outputBundleFilePath: bundle.uri,
        manifestJson: jsonEncode({
          'QuadVertex': {'type': 'vertex', 'file': vertex.path},
          'ArrayFragment': {'type': 'fragment', 'file': fragment.path},
        }),
        manifestDirectory: dir.uri,
        shaderLibDirectory: impellerc.resolve('./shader_lib'),
        glesLanguageVersion: 300,
      ),
    );
    if (result.exitCode != 0) {
      throw StateError('impellerc failed: ${result.stderr}${result.stdout}');
    }
    return ByteData.sublistView(bundle.readAsBytesSync());
  } finally {
    dir.deleteSync(recursive: true);
  }
}

/// Draws [layer] of [texture] over a 4x4 target with nearest sampling and
/// returns the target's top-left texel as RGBA bytes.
Future<List<int>> _sampleLayer(
  gpu.ShaderLibrary library,
  gpu.Texture texture,
  double layer,
) async {
  final target = gpu.gpuContext.createTexture(
    gpu.StorageMode.devicePrivate,
    4,
    4,
  );
  final pipeline = gpu.gpuContext.createRenderPipeline(
    library['QuadVertex']!,
    library['ArrayFragment']!,
  );
  final fragment = library['ArrayFragment']!;
  final quad = gpu.gpuContext.createDeviceBufferWithCopy(
    ByteData.sublistView(Float32List.fromList([-1, -1, 3, -1, -1, 3])),
  );
  final transients = gpu.gpuContext.createHostBuffer();
  final commandBuffer = gpu.gpuContext.createCommandBuffer();
  final pass = commandBuffer.createRenderPass(
    gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: target)),
  );
  pass.bindPipeline(pipeline);
  pass.bindVertexBuffer(
    gpu.BufferView(quad, offsetInBytes: 0, lengthInBytes: quad.sizeInBytes),
  );
  pass.bindUniform(
    fragment.getUniformSlot('Params'),
    transients.emplace(
      ByteData.sublistView(Float32List.fromList([layer, 0, 0, 0])),
    ),
  );
  pass.bindTexture(
    fragment.getUniformSlot('layers'),
    texture,
    sampler: gpu.SamplerOptions(),
  );
  pass.draw(3);
  commandBuffer.submit();
  final image = target.asImage();
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  image.dispose();
  return bytes.buffer.asUint8List(0, 4);
}

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  Uri? impellerc;
  try {
    impellerc = await findImpellerC();
  } catch (_) {
    impellerc = null;
  }
  final skip = !gpuAvailable()
      ? 'no GPU context in this environment'
      : impellerc == null
      ? 'impellerc not found in the SDK cache'
      : false;
  // Native engines before Flutter 3.50 (and backends without arrays) report
  // none; the tests below that need arrays skip there, and the last group
  // checks that arrays are refused cleanly instead.
  final arraysSupported = skip == false && Texture2DArray.isSupported;
  final arraySkip = skip != false
      ? skip
      : arraysSupported
      ? false
      : 'no 2D-array textures on this engine';
  final noArraySkip = skip != false
      ? skip
      : arraysSupported
      ? 'this engine has 2D-array textures'
      : false;

  late gpu.ShaderLibrary library;
  setUpAll(() async {
    if (skip != false) return;
    library = (await gpu.loadShaderLibraryFromBytesAsync(
      await _compileBundle(impellerc!),
    ))!;
  });

  group('Texture2DArray', () {
    test('samples each r8 layer it was given', () async {
      final layers = Texture2DArray.fromLayers(
        [
          for (final value in [10, 120, 250])
            Uint8List(8 * 8)..fillRange(0, 64, value),
        ],
        width: 8,
        height: 8,
        format: DataTextureFormat.r8,
      );
      expect(gpu.isTexture2DArray(layers.gpuTexture), isTrue);
      expect(layers.layerCount, 3);
      expect(layers.byteSize, 8 * 8 * 3);
      expect((await _sampleLayer(library, layers.gpuTexture, 0))[0], 10);
      expect((await _sampleLayer(library, layers.gpuTexture, 1))[0], 120);
      expect((await _sampleLayer(library, layers.gpuTexture, 2))[0], 250);
    }, skip: arraySkip);

    test('rewrites one rg8 layer in place', () async {
      final layers = Texture2DArray.fromLayers(
        [for (var i = 0; i < 2; i++) Uint8List(4 * 4 * 2)],
        width: 4,
        height: 4,
        format: DataTextureFormat.rg8,
      );
      final texels = Uint8List(4 * 4 * 2);
      for (var i = 0; i < 16; i++) {
        texels[i * 2] = 200;
        texels[i * 2 + 1] = 40;
      }
      layers.writeLayer(1, texels);
      expect(
        (await _sampleLayer(library, layers.gpuTexture, 0)).sublist(0, 2),
        [0, 0],
      );
      expect(
        (await _sampleLayer(library, layers.gpuTexture, 1)).sublist(0, 2),
        [200, 40],
      );
    }, skip: arraySkip);

    test('holds r32Float values', () async {
      final layers = Texture2DArray.fromLayers(
        [Float32List(16)..fillRange(0, 16, 0.5)],
        width: 4,
        height: 4,
        format: DataTextureFormat.r32Float,
      );
      expect(layers.byteSize, 4 * 4 * 4);
      // 0.5 written to an 8-bit target rounds to 127 or 128.
      expect(
        (await _sampleLayer(library, layers.gpuTexture, 0))[0],
        inInclusiveRange(127, 128),
      );
    }, skip: arraySkip);

    test('rejects a layer of the wrong size', () {
      final layers = Texture2DArray.empty(
        width: 4,
        height: 4,
        layerCount: 2,
        format: DataTextureFormat.r8,
      );
      expect(() => layers.writeLayer(0, Uint8List(15)), throwsArgumentError);
      expect(() => layers.writeLayer(2, Uint8List(16)), throwsRangeError);
    }, skip: arraySkip);

    test('32-bit float layers sample nearest unless asked', () {
      final floats = Texture2DArray.empty(
        width: 4,
        height: 4,
        layerCount: 1,
        format: DataTextureFormat.r32Float,
      );
      expect(floats.sampledSampler.minFilter, gpu.MinMagFilter.nearest);
      expect(floats.sampledSampler.magFilter, gpu.MinMagFilter.nearest);
      final bytes = Texture2DArray.empty(
        width: 4,
        height: 4,
        layerCount: 1,
        format: DataTextureFormat.r8,
      );
      expect(bytes.sampledSampler.minFilter, gpu.MinMagFilter.linear);
      final filtered = Texture2DArray.empty(
        width: 4,
        height: 4,
        layerCount: 1,
        format: DataTextureFormat.r32Float,
        sampling: TextureSampling.data,
      );
      expect(filtered.sampledSampler.minFilter, gpu.MinMagFilter.linear);
    }, skip: arraySkip);
  });

  group('Texture2D.fromData', () {
    test('creates a single-level texture of the given format', () {
      final texture = Texture2D.fromData(
        Uint8List(16 * 8 * 2),
        16,
        8,
        format: DataTextureFormat.rg8,
      );
      expect(texture.gpuTexture.format, gpu.PixelFormat.r8g8UNormInt);
      expect(texture.gpuTexture.mipLevelCount, 1);
      expect(texture.sampledSampler.mipFilter, gpu.MipFilter.nearest);
      expect(
        texture.sampledSampler.widthAddressMode,
        gpu.SamplerAddressMode.clampToEdge,
      );
    }, skip: skip);

    test('rejects data of the wrong length', () {
      expect(
        () => Texture2D.fromData(
          Uint8List(10),
          4,
          4,
          format: DataTextureFormat.r8,
        ),
        throwsArgumentError,
      );
    }, skip: skip);
  });

  group('.fmat array samplers', () {
    late Directory cacheDir;
    late FmatRuntimeCompiler compiler;

    setUp(() {
      cacheDir = Directory.systemTemp.createTempSync('data_texture_fmat_');
      compiler = FmatRuntimeCompiler(
        impellerc: impellerc ?? Uri.file('/nonexistent'),
        includeDirectories: [Directory('shaders').absolute.uri],
        cacheDirectory: cacheDir,
      );
    });

    tearDown(() => cacheDir.deleteSync(recursive: true));

    test('bind a 2D-array texture and refuse a 2D one', () async {
      final compiled = await compiler.compile(
        _arrayMaterial,
        fileName: 'array.fmat',
      );
      final materials = await FmatBytesLibrary.load(
        compiled.shaderBundle,
        compiled.sidecar,
      );
      final material = materials.createMaterial(compiled.entryName);
      expect(material.parameters.samplerNames, ['layers']);

      final layers = Texture2DArray.fromLayers(
        [Uint8List(4 * 4)],
        width: 4,
        height: 4,
        format: DataTextureFormat.r8,
      );
      material.parameters.setTexture(
        'layers',
        layers.gpuTexture,
        sampler: layers.sampledSampler,
      );
      expect(material.parameters.getTexture('layers'), layers.gpuTexture);

      final flat = Texture2D.fromData(
        Uint8List(16),
        4,
        4,
        format: DataTextureFormat.r8,
      );
      expect(
        () => material.parameters.setTexture('layers', flat.gpuTexture),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('needs a 2D-array texture'),
          ),
        ),
      );
    }, skip: arraySkip);

    test('refuse an array material and texture without arrays', () async {
      expect(
        () => Texture2DArray.empty(width: 4, height: 4, layerCount: 2),
        throwsUnsupportedError,
      );
      final compiled = await compiler.compile(
        _arrayMaterial,
        fileName: 'array.fmat',
      );
      final materials = await FmatBytesLibrary.load(
        compiled.shaderBundle,
        compiled.sidecar,
      );
      expect(
        () => materials.createMaterial(compiled.entryName),
        throwsUnsupportedError,
      );
    }, skip: noArraySkip);
  });
}
