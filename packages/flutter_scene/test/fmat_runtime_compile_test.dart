// FmatRuntimeCompiler against the SDK cache's impellerc: bundle output, the
// sidecar shape, disk caching, and the error paths. Runs only when impellerc
// resolves (CI without engine artifacts skips).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_gpu_shaders/environment.dart';
import 'package:flutter_scene/src/fmat/fmat_ast.dart' show FmatException;
import 'package:flutter_scene/src/fmat/runtime_compile.dart';
import 'package:flutter_test/flutter_test.dart';

const _surface = '''
material {
  name: "RuntimeTest",
  shading_model: unlit,
  parameters: [
    { type: vec4, name: tint, hint: source_color, default: [1.0, 0.0, 0.0, 1.0] },
    { type: float, name: strength, hint: range(0, 1, 0.01), default: 0.5 },
  ],
}

fragment {
  void Surface(inout MaterialInputs material) {
    material.base_color = material_params.tint * material_params.strength;
    PrepareMaterial(material);
  }
}
''';

const _sky = '''
material {
  name: "RuntimeTestSky",
  parameters: [
    { type: vec3, name: zenith, default: [0.1, 0.2, 0.8] },
  ],
}

sky {
  vec3 Sky(vec3 direction) {
    return material_params.zenith * max(direction.y, 0.0);
  }
}
''';

// Exercises every declared instance-attribute type and both stages: the
// vertex hook reads an input, Surface() reads another through its accessor.
const _instanceAttributes = '''
material {
  name: "RuntimeInstanced",
  shading_model: unlit,
  instance_attributes: [
    { type: float, name: wobble },
    { type: vec3, name: tint_shift },
    { type: vec2, name: uv_pan },
    { type: vec4, name: extra },
  ],
}

vertex {
  void Vertex(inout VertexInputs vertex) {
    vertex.world_position.y += sin(instance_wobble) + instance_uv_pan.x +
        instance_extra.w;
  }
}

fragment {
  void Surface(inout MaterialInputs material) {
    material.base_color = vec4(GetInstanceTintShift(), 1.0);
    PrepareMaterial(material);
  }
}
''';

const _sceneInputs = '''
material {
  name: "RuntimeSceneInputs",
  shading_model: unlit,
  blending: additive,
  engine_inputs: [scene_color, scene_depth],
  scene_color_reach: 0.25,
}

fragment {
  void Surface(inout MaterialInputs material) {
    vec2 offset = vec2(0.01, 0.0) * GetTime();
    float thickness = GetSceneDepth(offset) - GetFragmentViewDepth();
    vec3 behind = GetSceneWorldPosition(offset);
    vec2 projected = ProjectWorldOffsetToScreenUv(vec3(0.0, 0.1, 0.0));
    vec3 refracted = GetSceneColor(projected - GetScreenUv());
    material.base_color =
        vec4(refracted * clamp(thickness, 0.0, 1.0) + behind * 0.001, 1.0);
    PrepareMaterial(material);
  }
}
''';

// A projected box decal, the shape assets/scorch_decal.fmat ships: unlit,
// front-culled, drawn with `depth_test: always`, unprojecting the opaque depth
// into the box's local space.
const _decal = '''
material {
  name: "RuntimeDecal",
  shading_model: unlit,
  blending: alpha,
  culling: front,
  depth_test: always,
  engine_inputs: [scene_depth],
  scene_color_reach: 0.0,
  parameters: [
    { type: mat4, name: decal_inverse },
    { type: float, name: decal_fade, default: 1.0 },
    { type: sampler2d, name: decal_texture, hint: default_transparent },
  ],
}

fragment {
  void Surface(inout MaterialInputs material) {
    vec3 local = (material_params.decal_inverse *
                  vec4(GetSceneWorldPosition(vec2(0.0)), 1.0)).xyz;
    vec3 outside = step(vec3(0.5), abs(local));
    if (max(outside.x, max(outside.y, outside.z)) > 0.0) {
      discard;
    }
    float coverage = texture(decal_texture, local.xz + 0.5).a *
                     material_params.decal_fade;
    material.base_color = vec4(0.0, 0.0, 0.0, coverage);
    PrepareMaterial(material);
  }
}
''';

const _broken = '''
material {
  name: "RuntimeBroken",
  shading_model: unlit,
}

fragment {
  void Surface(inout MaterialInputs material) {
    material.base_color = not_a_function(1.0);
  }
}
''';

void main() async {
  Uri? impellerc;
  try {
    impellerc = await findImpellerC();
  } catch (_) {
    impellerc = null;
  }
  final skip = impellerc == null
      ? 'impellerc not found in the SDK cache'
      : false;

  late Directory cacheDir;
  late FmatRuntimeCompiler compiler;

  setUp(() {
    cacheDir = Directory.systemTemp.createTempSync('fmat_compile_test_');
    compiler = FmatRuntimeCompiler(
      impellerc: impellerc ?? Uri.file('/nonexistent'),
      includeDirectories: [Directory('shaders').absolute.uri],
      cacheDirectory: cacheDir,
    );
  });

  tearDown(() => cacheDir.deleteSync(recursive: true));

  test('compiles a surface material to a shader bundle plus sidecar', () async {
    final result = await compiler.compile(_surface, fileName: 'test.fmat');
    expect(result.entryName, 'RuntimeTest');
    // The flatbuffer file identifier sits after the root offset.
    expect(
      utf8.decode(Uint8List.sublistView(result.shaderBundle, 4, 8)),
      'IPSB',
    );
    final metadata = (result.sidecar['RuntimeTest'] as Map)
        .cast<String, Object?>();
    expect(metadata['domain'], 'surface');
    expect(metadata['shading_model'], 'unlit');
    final names = [
      for (final p in metadata['parameters'] as List) (p as Map)['name'],
    ];
    expect(names, containsAll(['tint', 'strength']));
    // The depfile-tracked framework includes are watchable inputs.
    expect(result.includeDependencies, isNotEmpty);
    for (final path in result.includeDependencies) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
  }, skip: skip);

  test('compiles a sky material', () async {
    final result = await compiler.compile(_sky, fileName: 'sky.fmat');
    final metadata = (result.sidecar['RuntimeTestSky'] as Map)
        .cast<String, Object?>();
    expect(metadata['domain'], 'sky');
  }, skip: skip);

  test('serves an unchanged source from the disk cache', () async {
    await compiler.compile(_surface, fileName: 'test.fmat');
    // Prove the second compile reads the cached bundle: overwrite it on disk
    // with a sentinel and observe the sentinel coming back.
    final cached = cacheDir
        .listSync(recursive: true)
        .whereType<File>()
        .singleWhere((f) => f.path.endsWith('out.shaderbundle'));
    cached.writeAsBytesSync([1, 2, 3, 4]);
    final again = await compiler.compile(_surface, fileName: 'test.fmat');
    expect(Uint8List.sublistView(again.shaderBundle), [1, 2, 3, 4]);

    // An edited source misses the cache and compiles a real bundle again.
    final edited = await compiler.compile(
      _surface.replaceFirst('0.5', '0.75'),
      fileName: 'test.fmat',
    );
    expect(edited.shaderBundle.lengthInBytes, greaterThan(1000));
  }, skip: skip);

  test('compiles a material with instance attributes', () async {
    // impellerc builds every backend in the bundle, so this covers the
    // generated instance-rate inputs and the forwarded varying on all of them.
    final result = await compiler.compile(
      _instanceAttributes,
      fileName: 'instanced.fmat',
    );
    expect(result.entryName, 'RuntimeInstanced');
    final metadata = (result.sidecar['RuntimeInstanced'] as Map)
        .cast<String, Object?>();
    expect(metadata['instance_attributes'], [
      {'name': 'wobble', 'type': 'float', 'offset': 80},
      {'name': 'tint_shift', 'type': 'vec3', 'offset': 84},
      {'name': 'uv_pan', 'type': 'vec2', 'offset': 100},
      {'name': 'extra', 'type': 'vec4', 'offset': 108},
    ]);
    expect(metadata['instance_record_bytes'], 124);
    expect(
      utf8.decode(Uint8List.sublistView(result.shaderBundle, 4, 8)),
      'IPSB',
    );
  }, skip: skip);

  test('compiles an unlit material with engine inputs', () async {
    final result = await compiler.compile(
      _sceneInputs,
      fileName: 'scene_inputs.fmat',
    );
    expect(result.entryName, 'RuntimeSceneInputs');
    final metadata = (result.sidecar['RuntimeSceneInputs'] as Map)
        .cast<String, Object?>();
    expect(metadata['engine_inputs'], ['scene_color', 'scene_depth']);
    expect(metadata['scene_color_reach'], 0.25);
  }, skip: skip);

  test('compiles a projected decal material', () async {
    final result = await compiler.compile(_decal, fileName: 'decal.fmat');
    expect(result.entryName, 'RuntimeDecal');
    final metadata = (result.sidecar['RuntimeDecal'] as Map)
        .cast<String, Object?>();
    expect(metadata['depth_test'], 'always');
    expect(metadata['culling'], 'front');
    expect(metadata['engine_inputs'], ['scene_depth']);
  }, skip: skip);

  test('reports GLSL errors as FmatCompileException', () async {
    await expectLater(
      compiler.compile(_broken, fileName: 'broken.fmat'),
      throwsA(isA<FmatCompileException>()),
    );
  }, skip: skip);

  test('reports source errors as FmatException', () async {
    await expectLater(
      compiler.compile('material {', fileName: 'parse.fmat'),
      throwsA(isA<FmatException>()),
    );
  }, skip: skip);
}
