import 'dart:isolate';

/// Locates flutter_scene's framework shader directory, the one that has to be
/// on `impellerc`'s include path for a generated or hand-written shader to
/// `#include` the engine's GLSL.
///
/// flutter_scene has no top-level `flutter_scene.dart` library, so this
/// resolves through `build_hooks.dart` (which always exists) and hops to the
/// sibling `shaders/`.
Future<Uri> frameworkShaderInclude() async {
  final frameworkLib = await Isolate.resolvePackageUri(
    Uri.parse('package:flutter_scene/build_hooks.dart'),
  );
  if (frameworkLib == null) {
    throw Exception(
      'Could not resolve the flutter_scene package location, so its shader '
      'include directory is unavailable.',
    );
  }
  return frameworkLib.resolve('../shaders/');
}
