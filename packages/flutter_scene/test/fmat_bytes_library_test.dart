// FmatBytesLibrary over runtime-compiled bundles: building live materials
// and skies from bytes, provenance stamping, and in-place refresh. Needs a
// GPU context (run with --enable-flutter-gpu) plus impellerc; skips otherwise.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_gpu_shaders/environment.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/fmat/fmat_bytes_library.dart';
import 'package:flutter_scene/src/fmat/material_registry.dart'
    show fmatSourcePathOf;
import 'package:flutter_scene/src/fmat/runtime_compile.dart';
import 'package:flutter_test/flutter_test.dart';

const _surfaceA = '''
material {
  name: "BytesTest",
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

// The same entry with an edited default plus a new parameter, the shape a
// hot-reloaded edit produces.
const _surfaceB = '''
material {
  name: "BytesTest",
  shading_model: unlit,
  parameters: [
    { type: vec4, name: tint, hint: source_color, default: [0.0, 1.0, 0.0, 1.0] },
    { type: float, name: strength, hint: range(0, 1, 0.01), default: 0.9 },
    { type: float, name: extra, default: 0.1 },
  ],
}

fragment {
  void Surface(inout MaterialInputs material) {
    material.base_color =
        material_params.tint * material_params.strength * material_params.extra;
    PrepareMaterial(material);
  }
}
''';

const _sky = '''
material {
  name: "BytesTestSky",
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

bool _gpuAvailable() {
  try {
    Scene();
    return true;
  } catch (_) {
    return false;
  }
}

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  Uri? impellerc;
  try {
    impellerc = await findImpellerC();
  } catch (_) {
    impellerc = null;
  }
  final gpu = _gpuAvailable();
  final skip = !gpu
      ? 'no GPU context in this environment'
      : impellerc == null
      ? 'impellerc not found in the SDK cache'
      : false;

  late Directory cacheDir;
  late FmatRuntimeCompiler compiler;

  setUp(() {
    cacheDir = Directory.systemTemp.createTempSync('fmat_bytes_test_');
    compiler = FmatRuntimeCompiler(
      impellerc: impellerc ?? Uri.file('/nonexistent'),
      includeDirectories: [Directory('shaders').absolute.uri],
      cacheDirectory: cacheDir,
    );
  });

  tearDown(() => cacheDir.deleteSync(recursive: true));

  test('builds a live material from bytes and refreshes it in place', () async {
    final a = await compiler.compile(_surfaceA, fileName: 'bytes.fmat');
    final library = await FmatBytesLibrary.load(a.shaderBundle, a.sidecar);
    final material = library.createMaterial(
      a.entryName,
      sourcePath: 'assets/bytes.fmat',
    );
    expect(fmatSourcePathOf(material), 'assets/bytes.fmat');
    expect(material.parameters.parameterNames, contains('tint'));
    final shader = material.fragmentShader;

    // An explicitly set value must survive the refresh; defaults refresh.
    material.parameters.setFloat('strength', 0.25);

    final b = await compiler.compile(_surfaceB, fileName: 'bytes.fmat');
    expect(b.entryName, a.entryName);
    final error = await library.refresh(b.shaderBundle, b.sidecar);
    expect(error, isNull);

    // Shader identity is preserved, the new parameter appears, and the
    // explicit value is kept.
    expect(identical(material.fragmentShader, shader), isTrue);
    expect(material.parameters.parameterNames, contains('extra'));
    expect(material.parameters.assignedValues['strength'], 0.25);
  }, skip: skip);

  test('builds a sky and rejects domain mismatches', () async {
    final sky = await compiler.compile(_sky, fileName: 'sky.fmat');
    final surface = await compiler.compile(_surfaceA, fileName: 'surf.fmat');
    final skyLibrary = await FmatBytesLibrary.load(
      sky.shaderBundle,
      sky.sidecar,
    );
    final surfaceLibrary = await FmatBytesLibrary.load(
      surface.shaderBundle,
      surface.sidecar,
    );
    expect(skyLibrary.createSky(sky.entryName), isA<PreprocessedSky>());
    expect(() => skyLibrary.createMaterial(sky.entryName), throwsStateError);
    expect(() => surfaceLibrary.createSky(surface.entryName), throwsStateError);
  }, skip: skip);

  test('refresh with unparseable bytes reports an error string', () async {
    final a = await compiler.compile(_surfaceA, fileName: 'bytes.fmat');
    final library = await FmatBytesLibrary.load(a.shaderBundle, a.sidecar);
    final error = await library.refresh(
      ByteData.sublistView(Uint8List.fromList(List.filled(64, 7))),
      a.sidecar,
    );
    expect(error, isNotNull);
  }, skip: skip);
}
