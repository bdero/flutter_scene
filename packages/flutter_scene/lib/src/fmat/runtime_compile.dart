/// Runtime `.fmat` compilation for tooling hosts (the scene editor).
///
/// Runs the same preprocess-then-impellerc pipeline as `buildMaterials`, on
/// demand and outside the build-hook system, producing shader-bundle bytes
/// for `FmatBytesLibrary` plus the parameter sidecar. Native-only (spawns the
/// `impellerc` subprocess); not exported through any public barrel.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_gpu_shaders/build.dart'
    show
        impellerCHelpSupportsDepfile,
        parseImpellerCDepfileDependencies,
        shaderBundleImpellercArguments;

import 'package:flutter_scene/src/fmat/fmat.dart';
import 'package:flutter_scene/src/fmat/fmat_emitter.dart'
    show
        emitFragmentGlsl,
        kRadianceCubeDefine,
        materialSamplesEnvironment,
        radianceCubeEntryName;
import 'package:flutter_scene/src/importer/build_cache.dart';

/// A failed `.fmat` runtime compile. A parse error surfaces as the underlying
/// [FmatException]; this carries impellerc's GLSL errors.
final class FmatCompileException implements Exception {
  FmatCompileException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One compiled `.fmat`, ready to load with `FmatBytesLibrary`.
final class FmatCompileResult {
  FmatCompileResult({
    required this.entryName,
    required this.shaderBundle,
    required this.sidecar,
    required this.includeDependencies,
  });

  /// The fragment entry name in the bundle (the material's `name`).
  final String entryName;

  /// The compiled shader bundle bytes.
  final ByteData shaderBundle;

  /// Per-entry sidecar metadata (`{entryName: metadata}`, the combined shape
  /// `buildMaterials` writes), covering the fragment entry and any generated
  /// vertex variants it references.
  final Map<String, Object?> sidecar;

  /// Absolute paths of every GLSL file the compile read (transitive
  /// `#include`s from the depfile), so a watcher can re-trigger on framework
  /// shader edits. Empty when the resolved impellerc predates `--depfile`.
  final List<String> includeDependencies;
}

/// Compiles one `.fmat` source at a time by shelling out to [impellerc],
/// mirroring the build hook (GLES 3.00 dialect, the same include-path shape).
///
/// Results are cached on disk under [cacheDirectory], keyed by the source
/// content, the tracked include files, and the tool binary, so reopening a
/// scene skips recompiles.
// Folded into cache keys so bundles written by an older layout are never
// served. Bump when the emitted entry set changes.
const int _cacheFormat = 2;

final class FmatRuntimeCompiler {
  FmatRuntimeCompiler({
    required this.impellerc,
    required this.includeDirectories,
    Uri? shaderLibDirectory,
    Directory? cacheDirectory,
  }) : shaderLibDirectory =
           shaderLibDirectory ?? impellerc.resolve('./shader_lib'),
       cacheDirectory =
           cacheDirectory ??
           Directory.systemTemp.createTempSync('fmat_runtime_');

  /// The impellerc binary.
  final Uri impellerc;

  /// impellerc's `shader_lib/` include directory. Defaults to the binary's
  /// sibling (the SDK cache layout); a packaged editor keeps it in the
  /// bundle's data directory instead.
  final Uri shaderLibDirectory;

  /// Extra include directories (flutter_scene's `shaders/`, so the generated
  /// GLSL's framework includes resolve).
  final List<Uri> includeDirectories;

  /// Where generated GLSL, compiled bundles, and cache metadata live.
  final Directory cacheDirectory;

  bool? _supportsDepfile;

  /// Compiles `.fmat` [source]. [fileName] labels parse errors. Throws
  /// [FmatException] for source errors and [FmatCompileException] when
  /// impellerc rejects the generated GLSL.
  Future<FmatCompileResult> compile(String source, {String? fileName}) async {
    // Parse before consulting the cache, so a source error is always reported
    // (and reported identically) whether or not a stale cache entry exists.
    final compiled = compileFmat(source, fileName: fileName);
    final sourceHash = contentHash(utf8.encode(source));
    final key = contentHash(
      utf8.encode(
        '$_cacheFormat\n$_toolStamp\n$shaderLibDirectory\n'
        '${includeDirectories.join(' ')}\n$sourceHash',
      ),
    );
    final entryDir = Directory('${cacheDirectory.path}/$key');
    final cached = _readCache(entryDir, sourceHash, compiled.material.name);
    if (cached != null) return cached;
    return _compileToCache(compiled, entryDir, sourceHash);
  }

  // The tool identity folded into cache keys, so a different (or rebuilt)
  // impellerc never serves stale bundles across engine versions.
  late final String _toolStamp = () {
    final stat = File(impellerc.toFilePath()).statSync();
    return '${impellerc.toFilePath()}|${stat.size}|'
        '${stat.modified.microsecondsSinceEpoch}';
  }();

  Future<FmatCompileResult> _compileToCache(
    FmatCompilation compiled,
    Directory entryDir,
    String sourceHash,
  ) async {
    final genDir = Directory('${entryDir.path}/gen')
      ..createSync(recursive: true);
    final entryName = compiled.material.name;

    // An environment-sampling material needs the cubemap-radiance twin the
    // offline build emits, because each entry declares only its own sampler
    // type and createMaterial resolves the twin whenever the sidecar says the
    // material samples the environment.
    final cubeEntry = radianceCubeEntryName(entryName);
    final needsCube = materialSamplesEnvironment(compiled.material);

    final manifest = <String, Object?>{
      entryName: {
        'type': 'fragment',
        'file': _writeShader(genDir, '$entryName.frag', compiled.glsl),
      },
      if (needsCube)
        cubeEntry: {
          'type': 'fragment',
          'file': _writeShader(
            genDir,
            '$cubeEntry.frag',
            emitFragmentGlsl(
              compiled.material,
              defines: const [kRadianceCubeDefine],
            ),
          ),
        },
      for (final MapEntry(key: vertexEntry, value: vertexGlsl)
          in compiled.vertexGlsl.entries)
        vertexEntry: {
          'type': 'vertex',
          'file': _writeShader(genDir, '$vertexEntry.vert', vertexGlsl),
        },
    };

    final bundleFile = File('${entryDir.path}/out.shaderbundle');
    final depfile = File('${bundleFile.path}.d');
    if (depfile.existsSync()) depfile.deleteSync();
    final supportsDepfile = await _probeDepfileSupport();

    final args = shaderBundleImpellercArguments(
      outputBundleFilePath: bundleFile.uri,
      manifestJson: jsonEncode(manifest),
      manifestDirectory: genDir.uri,
      shaderLibDirectory: shaderLibDirectory,
      includeDirectories: includeDirectories,
      depfilePath: supportsDepfile ? depfile.uri : null,
      // Match the engine bundle's GLES dialect (GLSL ES 3.00); the framework
      // radiance sampling uses textureLod, unavailable in 1.00.
      glesLanguageVersion: 300,
    );
    final result = await Process.run(impellerc.toFilePath(), args);
    if (result.exitCode != 0) {
      throw FmatCompileException(
        'impellerc failed for "$entryName":\n'
                '${result.stderr}\n${result.stdout}'
            .trim(),
      );
    }

    // The watchable inputs are the depfile's transitive includes minus the
    // generated shaders themselves (they live under the cache).
    final dependencies = <String>[];
    if (supportsDepfile && depfile.existsSync()) {
      for (final uri in parseImpellerCDepfileDependencies(
        depfile.readAsStringSync(),
        relativeTo: entryDir.uri,
      )) {
        final path = uri.toFilePath();
        if (!path.startsWith(cacheDirectory.path)) dependencies.add(path);
      }
      depfile.deleteSync();
    }

    final bundleBytes = bundleFile.readAsBytesSync();
    // The combined sidecar shape: the fragment entry's metadata under its
    // entry name (vertex variants are referenced through its `vertex` map).
    final sidecar = <String, Object?>{entryName: compiled.sidecar};

    File(
      '${entryDir.path}/sidecar.json',
    ).writeAsStringSync(jsonEncode(sidecar));
    File('${entryDir.path}/meta.json').writeAsStringSync(
      jsonEncode({
        'entryName': entryName,
        'sourceHash': sourceHash,
        'deps': {
          for (final path in dependencies) path: _fileHashOrNull(path) ?? '',
        },
      }),
    );

    return FmatCompileResult(
      entryName: entryName,
      shaderBundle: ByteData.sublistView(bundleBytes),
      sidecar: sidecar,
      includeDependencies: dependencies,
    );
  }

  static String _writeShader(Directory genDir, String fileName, String glsl) {
    final file = File('${genDir.path}/$fileName');
    file.writeAsStringSync(glsl);
    return file.path;
  }

  Future<bool> _probeDepfileSupport() async {
    if (_supportsDepfile != null) return _supportsDepfile!;
    try {
      final help = await Process.run(impellerc.toFilePath(), ['--help']);
      _supportsDepfile = impellerCHelpSupportsDepfile(
        '${help.stdout}\n${help.stderr}',
      );
    } catch (_) {
      _supportsDepfile = false;
    }
    return _supportsDepfile!;
  }

  static String? _fileHashOrNull(String path) {
    try {
      return contentHash(File(path).readAsBytesSync());
    } catch (_) {
      return null;
    }
  }

  // A cache entry is valid when the source hash matches and every recorded
  // include dependency still hashes the same (the tool is part of the key).
  FmatCompileResult? _readCache(
    Directory entryDir,
    String sourceHash,
    String entryName,
  ) {
    try {
      final meta =
          (jsonDecode(File('${entryDir.path}/meta.json').readAsStringSync())
                  as Map)
              .cast<String, Object?>();
      if (meta['sourceHash'] != sourceHash) return null;
      if (meta['entryName'] != entryName) return null;
      final deps = (meta['deps'] as Map).cast<String, Object?>();
      for (final MapEntry(key: path, value: hash) in deps.entries) {
        if (_fileHashOrNull(path) != hash) return null;
      }
      final bundleBytes = File(
        '${entryDir.path}/out.shaderbundle',
      ).readAsBytesSync();
      final sidecar =
          (jsonDecode(File('${entryDir.path}/sidecar.json').readAsStringSync())
                  as Map)
              .cast<String, Object?>();
      return FmatCompileResult(
        entryName: entryName,
        shaderBundle: ByteData.sublistView(bundleBytes),
        sidecar: sidecar,
        includeDependencies: deps.keys.toList(),
      );
    } catch (_) {
      return null;
    }
  }
}
