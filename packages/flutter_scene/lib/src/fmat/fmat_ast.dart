// Abstract syntax tree for the `.fmat` custom-material format and the error
// type the parser, validator, and emitter throw.

/// Which rendering contract a `.fmat` targets.
enum FmatDomain {
  /// A surface material: the author writes `void Surface(inout MaterialInputs)`
  /// run on scene geometry through the standard vertex shader.
  surface,

  /// A sky: the author writes `vec3 Sky(vec3 direction)` drawn full-screen as
  /// the background. The engine supplies the world view direction and owns the
  /// draw; `shading_model`, `blending`, and `culling` do not apply.
  sky,
}

/// The lighting contract a material opts into.
enum FmatShadingModel {
  /// The engine runs its physically based lighting (image-based lighting plus
  /// the analytic directional light). The material's `Surface()` fills the
  /// surface description; the framework produces the lit color.
  lit,

  /// No lighting. The material's `Surface()` writes the final color into
  /// `base_color`; the framework outputs it premultiplied. Use for stylized
  /// or self-lit effects (matches Godot's `unshaded`).
  unlit,
}

/// How the material's alpha is composited.
enum FmatBlending {
  /// Drawn in the opaque pass with no blending.
  opaque,

  /// Drawn in the depth-sorted translucent pass with premultiplied
  /// source-over blending.
  alpha,
}

/// Which triangle faces are culled.
enum FmatCulling { back, front, none }

/// The type of a material parameter. Scalar and vector types are packed into
/// the generated `MaterialParams` uniform block; sampler types are declared as
/// top-level uniforms.
enum FmatType {
  float_('float', 4),
  int_('int', 4),
  vec2('vec2', 8),
  vec3('vec3', 12),
  vec4('vec4', 16),
  mat4('mat4', 64),
  sampler2d('sampler2D', 0),
  samplerCube('samplerCube', 0);

  const FmatType(this.glslType, this.componentBytes);

  /// The GLSL type name emitted for this parameter.
  final String glslType;

  /// The tightly packed (non-std140) size in bytes, or 0 for samplers. The
  /// runtime resolves real std140 offsets from shader reflection, so this is
  /// informational only.
  final int componentBytes;

  bool get isSampler => this == sampler2d || this == samplerCube;

  /// The number of scalar components, or 0 for samplers (mat4 counts as 16).
  int get componentCount => switch (this) {
    float_ || int_ => 1,
    vec2 => 2,
    vec3 => 3,
    vec4 => 4,
    mat4 => 16,
    sampler2d || samplerCube => 0,
  };

  static FmatType? fromToken(String token) {
    for (final t in FmatType.values) {
      // Accept the GLSL spelling (vec4, sampler2D) and a lowercase alias
      // (sampler2d) for the author's convenience.
      if (token == t.glslType || token == t.glslType.toLowerCase()) {
        return t;
      }
    }
    if (token == 'int') return FmatType.int_;
    if (token == 'float') return FmatType.float_;
    return null;
  }
}

/// What kind of authoring hint annotates a parameter. Hints carry editor and
/// runtime semantics (sRGB decode, value ranges, sampler placeholders).
enum FmatHintKind {
  /// An sRGB-authored color: decoded to linear when set. Valid on vec3/vec4.
  sourceColor,

  /// A bounded numeric range with a step. Valid on float/int.
  range,

  /// Sampler placeholder defaults, used when the texture is unset.
  defaultWhite,
  defaultBlack,
  defaultNormal,
  defaultTransparent,
}

/// An authoring hint on a parameter.
class FmatHint {
  const FmatHint(this.kind, {this.rangeMin, this.rangeMax, this.rangeStep});

  final FmatHintKind kind;

  /// Set only when [kind] is [FmatHintKind.range].
  final double? rangeMin;
  final double? rangeMax;
  final double? rangeStep;
}

/// A single declared material parameter.
class FmatParameter {
  FmatParameter({
    required this.type,
    required this.name,
    this.hint,
    this.defaultValue,
  });

  final FmatType type;
  final String name;
  final FmatHint? hint;

  /// The default value: a `num` for scalars, a `List<num>` for vectors and
  /// matrices, or `null`. Samplers carry their default via [hint].
  final Object? defaultValue;

  bool get isSampler => type.isSampler;
}

/// A custom interpolant the vertex stage writes and the fragment stage reads,
/// declared in the material's `varyings` list. The emitter generates the
/// matching `out` (vertex) and `in` (fragment) declarations under [name], so
/// the author writes `name = ...` in `Vertex()` and reads `name` in
/// `Surface()`. Only interpolatable float and vector types are allowed.
class FmatVarying {
  const FmatVarying({required this.type, required this.name});

  final FmatType type;
  final String name;
}

/// A custom per-vertex attribute the mesh supplies and the vertex stage reads,
/// declared in the material's `attributes` list. The emitter declares it as a
/// vertex `in <name>` (matched to the geometry's attribute by name), so the
/// author reads `name` in `Vertex()`. The geometry must provide a matching
/// stream (see `MeshGeometry.setCustomAttribute`). Only float and vector types
/// are supported.
class FmatAttribute {
  const FmatAttribute({required this.type, required this.name});

  final FmatType type;
  final String name;

  /// Number of float components (1..4), used for the vertex format and the
  /// zero fallback in the depth variant.
  int get components => type.componentCount;
}

/// A fully parsed and validated `.fmat` material.
class FmatMaterial {
  FmatMaterial({
    required this.name,
    this.domain = FmatDomain.surface,
    this.useEnvironment = false,
    required this.shadingModel,
    required this.blending,
    required this.culling,
    required this.parameters,
    required this.fragmentSource,
    required this.fragmentSourceLine,
    this.vertexSource,
    this.vertexSourceLine = 0,
    this.varyings = const [],
    this.attributes = const [],
  });

  final String name;

  /// The rendering contract this `.fmat` targets (surface material or sky).
  final FmatDomain domain;

  /// Whether the engine binds the scene environment's prefiltered-radiance
  /// atlas (`requires: [environment]`; sky materials only).
  final bool useEnvironment;

  final FmatShadingModel shadingModel;
  final FmatBlending blending;
  final FmatCulling culling;
  final List<FmatParameter> parameters;

  /// The verbatim contents of the code block (`fragment { }` for a surface
  /// material, `sky { }` for a sky).
  final String fragmentSource;

  /// The 1-based line in the source where [fragmentSource] begins, used to
  /// emit a `#line` directive so compiler errors map back to the `.fmat`.
  final int fragmentSourceLine;

  /// The verbatim contents of the optional `vertex { }` block (the author's
  /// `void Vertex(inout VertexInputs vertex)` hook and any helpers), or `null`
  /// when the material does not customize the vertex stage. Only surface
  /// materials may declare a vertex stage.
  final String? vertexSource;

  /// The 1-based line where [vertexSource] begins, for the `#line` directive.
  /// Zero when there is no vertex stage.
  final int vertexSourceLine;

  /// Whether this material customizes the vertex stage.
  bool get hasVertexStage => vertexSource != null;

  /// Custom interpolants forwarded from `Vertex()` to `Surface()`, in declared
  /// order. Empty unless the material declares a `varyings` list.
  final List<FmatVarying> varyings;

  /// Custom per-vertex attributes the mesh supplies to `Vertex()`, in declared
  /// order. Empty unless the material declares an `attributes` list.
  final List<FmatAttribute> attributes;

  /// Parameters packed into the `MaterialParams` uniform block, in declared
  /// order.
  Iterable<FmatParameter> get uniformParameters =>
      parameters.where((p) => !p.isSampler);

  /// Parameters declared as top-level sampler uniforms.
  Iterable<FmatParameter> get samplerParameters =>
      parameters.where((p) => p.isSampler);
}

/// Thrown when a `.fmat` source is malformed or fails validation. Carries a
/// 1-based source location when one is known.
class FmatException implements Exception {
  FmatException(this.message, {this.fileName, this.line, this.column});

  final String message;
  final String? fileName;
  final int? line;
  final int? column;

  @override
  String toString() {
    final location = StringBuffer();
    if (fileName != null) location.write(fileName);
    if (line != null) {
      location.write('${fileName != null ? ':' : ''}$line');
      if (column != null) location.write(':$column');
    }
    final prefix = location.isEmpty ? '' : '$location: ';
    return 'FmatException: $prefix$message';
  }
}
