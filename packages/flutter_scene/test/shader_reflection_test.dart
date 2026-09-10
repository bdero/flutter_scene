// Covers shader reflection: parsing a bundle's reflection and per-backend
// output, decoding std140 uniform bytes through it, compile-log diagnostics,
// and (GPU-gated) mapping the base library's shaders back to their names.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/web/shader_bundle_generated.dart' as fb;
import 'package:flutter_test/flutter_test.dart';

Uint8List _bundle() {
  final fragInfo = fb.ShaderUniformStructObjectBuilder(
    name: 'FragInfo',
    $set: 0,
    binding: 1,
    sizeInBytes: 96,
    fields: [
      fb.ShaderUniformStructFieldObjectBuilder(
        name: 'color',
        type: fb.UniformDataType.kFloat,
        offsetInBytes: 0,
        elementSizeInBytes: 16,
        totalSizeInBytes: 16,
        arrayElements: 0,
        vecSize: 4,
        columns: 1,
      ),
      fb.ShaderUniformStructFieldObjectBuilder(
        name: 'basis',
        type: fb.UniformDataType.kFloat,
        offsetInBytes: 16,
        elementSizeInBytes: 48,
        totalSizeInBytes: 48,
        arrayElements: 0,
        vecSize: 3,
        columns: 3,
      ),
      fb.ShaderUniformStructFieldObjectBuilder(
        name: 'weights',
        type: fb.UniformDataType.kFloat,
        offsetInBytes: 64,
        elementSizeInBytes: 16,
        totalSizeInBytes: 32,
        arrayElements: 2,
        vecSize: 1,
        columns: 1,
      ),
    ],
  );
  fb.BackendShaderObjectBuilder backend(String text, {bool spirv = false}) =>
      fb.BackendShaderObjectBuilder(
        stage: fb.ShaderStage.kFragment,
        entrypoint: 'main0',
        inputs: const [],
        uniformStructs: [fragInfo],
        uniformTextures: [
          fb.ShaderUniformTextureObjectBuilder(
            name: 'base_color_texture',
            $set: 0,
            binding: 2,
          ),
        ],
        shader: spirv ? const [3, 2, 35, 7] : utf8.encode(text),
      );
  final vertex = fb.ShaderObjectBuilder(
    name: 'TestVertex',
    openglEs: fb.BackendShaderObjectBuilder(
      stage: fb.ShaderStage.kVertex,
      entrypoint: 'main',
      inputs: [
        fb.ShaderInputObjectBuilder(
          name: 'position',
          location: 0,
          type: fb.InputDataType.kFloat,
          bitWidth: 32,
          vecSize: 3,
          columns: 1,
          offset: 0,
        ),
      ],
      uniformStructs: const [],
      uniformTextures: const [],
      shader: utf8.encode('void main() {}'),
    ),
  );
  final fragment = fb.ShaderObjectBuilder(
    name: 'TestFragment',
    metalDesktop: backend('// msl'),
    openglEs: backend('// glsl'),
    vulkan: backend('', spirv: true),
  );
  return fb.ShaderBundleObjectBuilder(
    shaders: [vertex, fragment],
    formatVersion: 2,
  ).toBytes();
}

bool _gpuAvailable() {
  try {
    Scene();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  test('parses reflection and per-backend output', () {
    final info = ShaderBundleInfo.parse(_bundle());
    expect(info.formatVersion, 2);
    expect(info.shaders.map((s) => s.name), ['TestVertex', 'TestFragment']);
    expect(info.backends, {
      ShaderBackend.openglEs,
      ShaderBackend.metalDesktop,
      ShaderBackend.vulkan,
    });

    final vertex = info['TestVertex']!;
    final vertexGl = vertex.backends[ShaderBackend.openglEs]!;
    expect(vertexGl.stage, ShaderStageKind.vertex);
    expect(vertexGl.inputs.single.name, 'position');
    expect(vertexGl.inputs.single.vecSize, 3);
    expect(vertexGl.source.text, 'void main() {}');

    final fragment = info['TestFragment']!;
    expect(
      fragment.backends[ShaderBackend.metalDesktop]!.source.text,
      '// msl',
    );
    final spirv = fragment.backends[ShaderBackend.vulkan]!.source;
    expect(spirv.text, isNull);
    expect(spirv.bytes, [3, 2, 35, 7]);
    final gl = fragment.backends[ShaderBackend.openglEs]!;
    expect(gl.entrypoint, 'main0');
    expect(gl.textures.single.name, 'base_color_texture');
    expect(gl.textures.single.binding, 2);
    final block = gl.uniformBlock('FragInfo')!;
    expect(block.sizeBytes, 96);
    expect(block.fields.map((f) => f.typeName), ['vec4', 'mat3', 'float[2]']);
    // The running platform's backend is preferred; any backend otherwise.
    expect(fragment.current, isNotNull);
    expect(info.toJson(includeSource: true)['shaders'], hasLength(2));
  });

  test('decodes std140 bytes through the field layout', () {
    final block = ShaderBundleInfo.parse(_bundle())['TestFragment']!
        .backends[ShaderBackend.openglEs]!
        .uniformBlock('FragInfo')!;
    final bytes = ByteData(96);
    for (var i = 0; i < 4; i++) {
      bytes.setFloat32(i * 4, 1.0 + i, Endian.little);
    }
    // mat3 columns are padded to 16 bytes each.
    for (var c = 0; c < 3; c++) {
      for (var r = 0; r < 3; r++) {
        bytes.setFloat32(16 + c * 16 + r * 4, c * 10.0 + r, Endian.little);
      }
    }
    // float[2] elements sit on 16-byte strides.
    bytes.setFloat32(64, 0.5, Endian.little);
    bytes.setFloat32(80, 0.25, Endian.little);

    final values = decodeUniformBlock(block, bytes);
    expect(values.map((v) => v.name), ['color', 'basis', 'weights']);
    expect(values[0].values, [1.0, 2.0, 3.0, 4.0]);
    expect(values[1].values, [
      0.0,
      1.0,
      2.0,
      10.0,
      11.0,
      12.0,
      20.0,
      21.0,
      22.0,
    ]);
    expect(values[2].values, [0.5, 0.25]);

    // A short buffer reports what it holds instead of throwing.
    final short = decodeUniformBlock(block, ByteData(8));
    expect(short[0].values, [0.0, 0.0]);
    expect(short[1].values, isEmpty);
  });

  test('matches emplaced buffers to declared blocks', () {
    final frag = ShaderBundleInfo.parse(_bundle())['TestFragment']!
        .backends[ShaderBackend.openglEs]!
        .uniformBlock('FragInfo')!;
    const frameInfo = ShaderUniformBlockInfo(
      name: 'FrameInfo',
      set: 0,
      binding: 0,
      sizeBytes: 128,
      fields: [
        ShaderUniformFieldInfo(
          name: 'mvp',
          type: ShaderScalarType.float32,
          offsetBytes: 0,
          elementSizeBytes: 64,
          totalSizeBytes: 64,
          arrayElements: 0,
          vecSize: 4,
          columns: 4,
        ),
        ShaderUniformFieldInfo(
          name: 'camera_position',
          type: ShaderScalarType.float32,
          offsetBytes: 64,
          elementSizeBytes: 16,
          totalSizeBytes: 16,
          arrayElements: 0,
          vecSize: 3,
          columns: 1,
        ),
        ShaderUniformFieldInfo(
          name: 'extra',
          type: ShaderScalarType.float32,
          offsetBytes: 80,
          elementSizeBytes: 48,
          totalSizeBytes: 48,
          arrayElements: 0,
          vecSize: 3,
          columns: 3,
        ),
      ],
    );
    // An exact 96-byte FragInfo, then an 80-byte prefix of FrameInfo. The
    // prefix also lands on a FragInfo boundary (color + basis), but FragInfo
    // is already claimed by the exact match.
    final matches = matchUniformBlocks([frameInfo, frag], [96, 80, 12]);
    expect(matches[0].map((b) => b.name), ['FragInfo']);
    expect(matches[1].map((b) => b.name), ['FrameInfo']);
    expect(matches[2], isEmpty);
    // Without the exact match both blocks stay candidates.
    final ambiguous = matchUniformBlocks([frameInfo, frag], [64]);
    expect(ambiguous.single.map((b) => b.name), ['FrameInfo', 'FragInfo']);
    // A buffer only FrameInfo can be claims it, which settles the other.
    final settled = matchUniformBlocks([frameInfo, frag], [64, 80]);
    expect(settled[0].map((b) => b.name), ['FragInfo']);
    expect(settled[1].map((b) => b.name), ['FrameInfo']);
  });

  test('parses compiler diagnostics and windows the source', () {
    const log = '''
impellerc failed for "Foo":
ERROR: 0:12: 'foo' : undeclared identifier
ERROR: shaders/foo.glsl:3: '' : compilation terminated
WARNING: 0:2: 'x' : unused
lib/foo.frag:7:3: error: use of undeclared identifier 'bar'
''';
    final diagnostics = parseShaderCompileErrors(log);
    expect(diagnostics, hasLength(4));
    expect(diagnostics[0].line, 12);
    expect(diagnostics[0].file, isNull);
    expect(diagnostics[0].isError, isTrue);
    expect(diagnostics[0].message, "'foo' : undeclared identifier");
    expect(diagnostics[1].file, 'shaders/foo.glsl');
    expect(diagnostics[1].line, 3);
    expect(diagnostics[2].isError, isFalse);
    expect(diagnostics[3].file, 'lib/foo.frag');
    expect(diagnostics[3].line, 7);
    expect(diagnostics[3].message, "use of undeclared identifier 'bar'");
    expect(parseShaderCompileErrors('nothing to see'), isEmpty);

    final source = List.generate(10, (i) => 'line ${i + 1}').join('\n');
    final window = shaderSourceWindow(source, 5, context: 1);
    expect(window, '  4 | line 4\n> 5 | line 5\n  6 | line 6\n');
    expect(
      shaderSourceWindow(source, 1, context: 2).split('\n').first,
      '> 1 | line 1',
    );
  });

  test('maps the base library shaders back to their names', () async {
    if (!_gpuAvailable()) return;
    await loadBaseShaderLibrary();
    final library = baseShaderLibrary;
    final info = await ShaderReflection.loadBundleInfo(library);
    expect(info, isNotNull, reason: 'base bundle source unregistered');
    expect(
      identical(await ShaderReflection.loadBundleInfo(library), info),
      isTrue,
    );
    expect(ShaderReflection.bundleInfoFor(library), same(info));
    final vertex = library['UnskinnedVertex']!;
    expect(ShaderReflection.nameOf(vertex), 'UnskinnedVertex');
    expect(ShaderReflection.libraryOf(vertex), same(library));
    final shader = ShaderReflection.infoFor(vertex)!;
    expect(shader.stage, ShaderStageKind.vertex);
    expect(shader.current!.inputs.map((i) => i.name), contains('position'));
    final fragment = ShaderReflection.infoFor(library['StandardFragment']!)!;
    expect(
      fragment.current!.textures.map((t) => t.name),
      contains('base_color_texture'),
    );
    expect(ShaderReflection.sourceOf(vertex), isNotNull);

    final material = UnlitMaterial();
    expect(ShaderReflection.nameOf(material.fragmentShader), 'UnlitFragment');

    final all = await ShaderReflection.loadAll();
    expect(all, contains(same(info)));

    ShaderReflection.invalidate(library);
    expect(ShaderReflection.bundleInfoFor(library), isNull);
    expect(ShaderReflection.infoFor(vertex), isNull);
    final reloaded = await ShaderReflection.loadBundleInfo(library);
    expect(reloaded, isNotNull);
    expect(identical(reloaded, info), isFalse);
    // Keep the shim type in the import graph so the analyzer resolves it.
    expect(library, isA<gpu.ShaderLibrary>());
  });
}
