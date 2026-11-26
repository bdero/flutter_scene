import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:hooks/hooks.dart';

/// Locates flutter_scene's engine shader directory, the one that has to be on
/// `impellerc`'s include path for a generated or hand-written shader to
/// `#include` the engine's GLSL.
///
/// flutter_scene has no top-level `flutter_scene.dart` library, so this
/// resolves through `build_hooks.dart` (which always exists) and hops to the
/// sibling `shaders/`. An isolate with no package resolver (a hook that
/// `flutter test` calls in process) reads the package config nearest
/// [buildInput]'s package root instead.
Future<Uri> engineShaderIncludeDirectory(BuildInput buildInput) async {
  final root = await _resolvedRoot() ?? _configuredRoot(buildInput.packageRoot);
  if (root == null) {
    throw Exception(
      'Could not resolve the flutter_scene package location, so its shader '
      'include directory is unavailable.',
    );
  }
  return root.resolve('shaders/');
}

Future<Uri?> _resolvedRoot() async {
  try {
    final library = await Isolate.resolvePackageUri(
      Uri.parse('package:flutter_scene/build_hooks.dart'),
    );
    return library?.resolve('../');
  } on UnsupportedError {
    return null;
  }
}

Uri? _configuredRoot(Uri packageRoot) {
  for (
    var directory = Directory.fromUri(packageRoot).absolute;
    ;
    directory = directory.parent
  ) {
    final config = File.fromUri(
      directory.uri.resolve('.dart_tool/package_config.json'),
    );
    if (config.existsSync()) {
      final packages =
          (jsonDecode(config.readAsStringSync()) as Map)['packages'] as List;
      for (final package in packages.cast<Map>()) {
        if (package['name'] != 'flutter_scene') continue;
        final root = package['rootUri'] as String;
        return config.uri.resolve(root.endsWith('/') ? root : '$root/');
      }
      return null;
    }
    if (directory.parent.path == directory.path) return null;
  }
}
