/// Translating a shader bundle's Vulkan SPIR-V into the WGSL sidecar the
/// WebGPU web backend loads, at build time.
///
/// Opt-in through `flutter_scene_webgpu: true` under `hooks: user_defines:`,
/// declared for each package whose hook builds shaders (`flutter_scene` for the
/// engine's own, the app for its `.fmat` and `ShaderMaterial` bundles). It
/// cannot key on the target, because a web build and the data-only pass
/// `flutter run` makes for a native target give the hook identical input.
///
/// See `notes/web-backend/webgpu_backend_plan.md` §2 in the development root
/// for the design.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:hooks/hooks.dart';

import '../gpu/shared/wgsl_bindings.dart';
import '../gpu/web/shader_bundle_generated.dart' as fb;
import 'spirv_constant_arrays.dart';
import 'tint_binary.dart';

/// The pubspec user-define that turns WGSL translation on.
const String kWebGpuUserDefine = 'flutter_scene_webgpu';

/// Environment switch for builders driven directly, from a test or a script.
const String kWebGpuEnv = 'FLUTTER_SCENE_WEBGPU';

/// The sidecar format revision, bumped when its shape changes.
const int kWgslSidecarFormat = 2;

/// Names the SPIR-V preprocessing ahead of the translator, recorded beside
/// its revision. Bump it when the preprocessing changes what Tint sees.
const String kSpirvPreprocessing = 'hoist-constant-arrays-1';

/// Whether [input]'s package asked for WGSL sidecars.
bool webGpuShadersRequested(BuildInput input) =>
    input.userDefines[kWebGpuUserDefine] == true ||
    Platform.environment.containsKey(kWebGpuEnv);

/// The sidecar's path next to the bundle it describes. The runtime finds it
/// the same way, from the bundle's asset key.
String wgslSidecarPathFor(String bundlePath) => '$bundlePath.wgsl.json';

/// One shader to translate.
typedef WgslTranslationJob = ({
  String name,
  Uint8List spirv,
  Map<int, int> samplerBindings,
});

/// Translates SPIR-V to WGSL in a batch, one call per bundle.
abstract interface class WgslBatchTranslator {
  /// The translator build, recorded in the sidecar.
  String get revision;

  /// Returns WGSL keyed by job name. Throws [WgslSidecarException] naming
  /// every shader that failed.
  Future<Map<String, String>> translateAll(List<WgslTranslationJob> jobs);
}

/// A shader that could not be translated or whose bindings disagree with the
/// prediction.
final class WgslSidecarException implements Exception {
  WgslSidecarException(this.message);
  final String message;

  @override
  String toString() => 'WgslSidecarException: $message';
}

/// The bundle reflection a Vulkan entry carries, as the binding predictor
/// reads it.
List<WgslReflectedResource> reflectedResources(fb.BackendShader shader) => [
  for (final u in shader.uniformStructs ?? const <fb.ShaderUniformStruct>[])
    (
      name: u.name ?? '',
      binding: u.binding,
      kind: WgslResourceKind.uniformBuffer,
    ),
  for (final t in shader.uniformTextures ?? const <fb.ShaderUniformTexture>[])
    (
      name: t.name ?? '',
      binding: t.binding,
      kind: WgslResourceKind.combinedTextureSampler,
    ),
];

/// Translates every Vulkan entry in [untrimmedBundle] and returns the sidecar
/// JSON, recording [shippedBundleHash] so the runtime can tell a sidecar from
/// a different build of the bundle it sits next to.
Future<String> buildWgslSidecar(
  Uint8List untrimmedBundle,
  WgslBatchTranslator translator, {
  required String shippedBundleHash,
}) async {
  final bundle = fb.ShaderBundle(untrimmedBundle);
  final jobs = <WgslTranslationJob>[];
  final maps = <String, WgslBindingMap>{};
  final stages = <String, String>{};
  final reflections = <String, fb.BackendShader>{};
  for (final shader in bundle.shaders ?? const <fb.Shader>[]) {
    final name = shader.name;
    final vulkan = shader.vulkan;
    if (name == null || vulkan == null) continue;
    final words = vulkan.shader;
    if (words == null || words.isEmpty) continue;
    final resources = reflectedResources(vulkan);
    final map = WgslBindingMap.mapped(resources);
    maps[name] = map;
    reflections[name] = vulkan;
    stages[name] = switch (vulkan.stage) {
      fb.ShaderStage.kVertex => 'vertex',
      fb.ShaderStage.kFragment => 'fragment',
      _ => 'compute',
    };
    jobs.add((
      name: name,
      spirv: hoistConstantArrays(Uint8List.fromList(words)),
      samplerBindings: map.samplerMappings,
    ));
  }
  if (jobs.isEmpty) {
    throw WgslSidecarException(
      'the bundle has no Vulkan SPIR-V to translate; it was trimmed first',
    );
  }

  final wgsl = await translator.translateAll(jobs);
  final failures = <String>[];
  final shaders = <String, Object?>{};
  for (final job in jobs) {
    final source = wgsl[job.name];
    if (source == null) {
      failures.add('${job.name}: no output');
      continue;
    }
    final map = maps[job.name]!;
    try {
      map.verifyAgainstWgsl(source, shaderName: job.name);
    } on WgslBindingMismatch catch (e) {
      failures.add('${job.name}: ${e.message}');
      continue;
    }
    shaders[job.name] = _sidecarEntry(
      stage: stages[job.name]!,
      wgsl: source,
      map: map,
      reflection: reflections[job.name]!,
    );
  }
  if (failures.isNotEmpty) {
    throw WgslSidecarException(failures.join('\n'));
  }
  return const JsonEncoder.withIndent(' ').convert({
    'format': kWgslSidecarFormat,
    'translator': '${translator.revision}, $kSpirvPreprocessing',
    'bundle': shippedBundleHash,
    'shaders': shaders,
  });
}

/// One shader's sidecar entry: its WGSL plus the reflection the WebGPU
/// backend binds by, read from the same Vulkan entry the WGSL came from, so
/// struct offsets and bindings match the WGSL by construction.
Map<String, Object?> _sidecarEntry({
  required String stage,
  required String wgsl,
  required WgslBindingMap map,
  required fb.BackendShader reflection,
}) => {
  'stage': stage,
  // Tint names every entry point `main`.
  'entryPoint': 'main',
  'wgsl': wgsl,
  'inputs': [
    for (final input in reflection.inputs ?? const <fb.ShaderInput>[])
      if (input.name != null)
        {
          'name': input.name,
          'location': input.location,
          'vecSize': input.vecSize,
          'offset': input.offset,
        },
  ],
  'uniforms': [
    for (final s
        in reflection.uniformStructs ?? const <fb.ShaderUniformStruct>[])
      if (s.name != null)
        {
          'name': s.name,
          'group': map[s.name!]!.group,
          'binding': map[s.name!]!.textureBinding,
          'size': s.sizeInBytes,
          'fields': [
            for (final f in s.fields ?? const <fb.ShaderUniformStructField>[])
              if (f.name != null)
                {
                  'name': f.name,
                  'offset': f.offsetInBytes,
                  'vecSize': f.vecSize,
                  'columns': f.columns,
                  'arrayElements': f.arrayElements,
                  'size': f.totalSizeInBytes,
                },
          ],
        },
  ],
  'textures': [
    for (final t
        in reflection.uniformTextures ?? const <fb.ShaderUniformTexture>[])
      if (t.name != null)
        {
          'name': t.name,
          'group': map[t.name!]!.group,
          'binding': map[t.name!]!.textureBinding,
          'sampler': map[t.name!]!.samplerBinding,
        },
  ],
};

/// Runs the native `flutter_scene_tint` binary over a batch.
final class TintProcessTranslator implements WgslBatchTranslator {
  TintProcessTranslator(this.binary, this.revision);

  /// Resolves the binary for [input] (override or pinned download) and reads
  /// its revision.
  static Future<TintProcessTranslator> resolve(BuildInput input) async {
    final binary = await resolveTintBinary(input);
    final version = await Process.run(binary, ['--version']);
    if (version.exitCode != 0) {
      throw WgslSidecarException('$binary --version failed: ${version.stderr}');
    }
    return TintProcessTranslator(binary, (version.stdout as String).trim());
  }

  final String binary;

  @override
  final String revision;

  @override
  Future<Map<String, String>> translateAll(
    List<WgslTranslationJob> jobs,
  ) async {
    final dir = await Directory.systemTemp.createTemp('flutter_scene_tint_');
    try {
      final manifest = StringBuffer();
      final outputs = <String, File>{};
      for (var i = 0; i < jobs.length; i++) {
        final job = jobs[i];
        final spv = File('${dir.path}/$i.spv')..writeAsBytesSync(job.spirv);
        final out = File('${dir.path}/$i.wgsl');
        outputs[job.name] = out;
        final mappings = [
          for (final MapEntry(:key, :value) in job.samplerBindings.entries)
            '0,$key,0,$value',
        ].join(';');
        manifest.writeln('${spv.path}\t${out.path}\t$mappings');
      }
      final manifestFile = File('${dir.path}/manifest.tsv')
        ..writeAsStringSync(manifest.toString());
      final result = await Process.run(binary, [
        'translate',
        manifestFile.path,
      ]);
      if (result.exitCode != 0) {
        final byIndex = <String>[];
        for (final line in (result.stderr as String).split('\n')) {
          if (!line.startsWith('FAILED\t')) continue;
          final parts = line.split('\t');
          final index = int.tryParse(
            parts[1].split(Platform.pathSeparator).last.split('.').first,
          );
          final name = index == null ? parts[1] : jobs[index].name;
          byIndex.add('$name: ${parts.skip(2).join('\t')}');
        }
        throw WgslSidecarException(
          byIndex.isEmpty ? '${result.stderr}' : byIndex.join('\n'),
        );
      }
      return {
        for (final MapEntry(:key, :value) in outputs.entries)
          key: value.readAsStringSync(),
      };
    } finally {
      dir.deleteSync(recursive: true);
    }
  }
}
