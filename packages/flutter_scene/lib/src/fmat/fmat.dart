// The `.fmat` custom-material preprocessor: parse a declarative material into
// an AST, then emit standard GLSL plus a metadata sidecar for `impellerc` and
// the runtime. This is pure Dart with no GPU dependency; the build hook
// (package:flutter_scene/build.dart) drives it, and the runtime consumes the
// sidecar.

import 'package:flutter_scene/src/fmat/fmat_ast.dart';
import 'package:flutter_scene/src/fmat/fmat_emitter.dart';
import 'package:flutter_scene/src/fmat/fmat_parser.dart';

export 'package:flutter_scene/src/fmat/fmat_ast.dart';
export 'package:flutter_scene/src/fmat/fmat_emitter.dart'
    show
        emitFragmentGlsl,
        emitVertexGlsl,
        vertexVariantEntryName,
        kVertexVariants,
        buildSidecar,
        kMaterialParamsBlock,
        kMaterialParamsInstance;
export 'package:flutter_scene/src/fmat/fmat_parser.dart' show parseFmat;

/// The result of preprocessing a `.fmat` source: the parsed material, the
/// emitted GLSL fragment shader, the per-variant vertex shaders (empty unless
/// the material has a `vertex { }` block), and the metadata sidecar.
class FmatCompilation {
  FmatCompilation({
    required this.material,
    required this.glsl,
    required this.vertexGlsl,
    required this.sidecar,
  });

  final FmatMaterial material;
  final String glsl;

  /// The generated vertex shaders keyed by shader-bundle entry name, or empty
  /// when the material does not customize the vertex stage.
  final Map<String, String> vertexGlsl;
  final Map<String, Object?> sidecar;
}

/// Parses, validates, and emits [source]. Throws [FmatException] on error.
FmatCompilation compileFmat(String source, {String? fileName}) {
  final material = parseFmat(source, fileName: fileName);
  return FmatCompilation(
    material: material,
    glsl: emitFragmentGlsl(material),
    vertexGlsl: emitVertexGlsl(material),
    sidecar: buildSidecar(material),
  );
}
