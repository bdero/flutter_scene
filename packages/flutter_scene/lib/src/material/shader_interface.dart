// Checks that a fragment shader's inputs line up with the outputs of the
// vertex shader it is paired with, before the pipeline is built.
//
// Metal matches a fragment input to a vertex output by location, not by
// name, so a hand-written ShaderMaterial fragment shader that declares only
// some of the engine varyings shifts the rest onto the wrong outputs, and the
// backend refuses the pipeline. On Flutter 3.47 that refusal crashes the app
// at the draw (flutter/flutter#189899 makes it a recoverable error from
// 3.50). Reading the pairing from the compiled MSL catches it first, so the
// draw is skipped with a message naming the varying instead.
//
// TODO(shader-interface): check Vulkan pairs from their SPIR-V as well. They
// build, but read undefined values for a mismatched varying.
// TODO(shader-interface): check a custom vertex shader against the engine
// fragment shaders it meets in the depth prepass and shadow passes. That needs
// the engine bundle's reflection, which costs too much to parse eagerly.

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/generated_assets/runtime_target.dart'
    show runtimeOperatingSystem;
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/shared/shader_library_sources.dart'
    show knownShaderLibraries;
import 'package:flutter_scene/src/shader_reflection/shader_reflection.dart';
import 'package:flutter_scene/src/shaders.dart' show loadedBaseShaderLibrary;

/// One varying at a stage boundary, as the compiled MSL declares it.
@immutable
final class StageVarying {
  /// A varying named [name] of MSL [type] (`float3`, `float4`) at
  /// [location].
  const StageVarying(this.location, this.type, this.name);

  /// The interface location the stages match on.
  final int location;

  /// The MSL type, which the stages must agree on exactly.
  final String type;

  /// The GLSL name, for messages only.
  final String name;

  @override
  bool operator ==(Object other) =>
      other is StageVarying &&
      other.location == location &&
      other.type == type &&
      other.name == name;

  @override
  int get hashCode => Object.hash(location, type, name);

  @override
  String toString() => '$name ($type) at location $location';
}

/// The varyings every engine material vertex shader writes, in location
/// order. Declared in `shaders/material_varyings.glsl`.
const List<StageVarying> standardVaryings = [
  StageVarying(0, 'float3', 'v_position'),
  StageVarying(1, 'float3', 'v_normal'),
  StageVarying(2, 'float3', 'v_viewvector'),
  StageVarying(3, 'float2', 'v_texture_coords'),
  StageVarying(4, 'float2', 'v_texture_coords_1'),
  StageVarying(5, 'float4', 'v_color'),
  StageVarying(6, 'float4', 'v_tangent'),
];

/// The base library's vertex shaders that write exactly [standardVaryings],
/// which are the ones a material's fragment shader is paired with.
const List<String> standardVertexShaderNames = [
  'UnskinnedVertex',
  'UnskinnedDepthVertex',
  'MorphedUnskinnedVertex',
  'SkinnedVertex',
  'MorphedSkinnedVertex',
  'LineSegmentsVertex',
];

final RegExp _mslVarying = RegExp(
  r'(\w+)\s+(\w+)\s*\[\[user\(locn(\d+)\)[^\]]*\]\]',
);

/// The `[[user(locnN)]]` members of the MSL struct SPIRV-Cross emits for
/// [entrypoint]'s stage [outputs] (`<entrypoint>_out`) or inputs
/// (`<entrypoint>_in`), sorted by location. Empty when the struct is absent,
/// which is how a stage with no varyings on that side compiles.
List<StageVarying> parseMslVaryings(
  String msl,
  String entrypoint, {
  required bool outputs,
}) {
  final struct = RegExp(
    'struct ${RegExp.escape(entrypoint)}_${outputs ? 'out' : 'in'}'
    r'\s*\{([^}]*)\}',
  ).firstMatch(msl);
  if (struct == null) return const [];
  return [
    for (final member in _mslVarying.allMatches(struct.group(1)!))
      StageVarying(
        int.parse(member.group(3)!),
        member.group(1)!,
        member.group(2)!,
      ),
  ]..sort((a, b) => a.location.compareTo(b.location));
}

/// How [fragmentInputs] fail to meet [vertexOutputs], one clause per
/// mismatched input, or null when every input meets an output of its type at
/// its location. An output nothing reads is fine.
String? describeVaryingMismatch(
  List<StageVarying> vertexOutputs,
  List<StageVarying> fragmentInputs,
) {
  final byLocation = {
    for (final output in vertexOutputs) output.location: output,
  };
  final problems = <String>[];
  for (final input in fragmentInputs) {
    final output = byLocation[input.location];
    if (output == null) {
      problems.add(
        '${input.name} (${input.type}) at location ${input.location}, which '
        'the vertex shader does not write',
      );
    } else if (output.type != input.type) {
      problems.add(
        '${input.name} (${input.type}) at location ${input.location}, where '
        'the vertex shader writes ${output.name} (${output.type})',
      );
    }
  }
  return problems.isEmpty ? null : problems.join('; ');
}

/// Whether pipelines are checked before they are built. Only Metal refuses a
/// mismatched pipeline, so only Apple platforms check.
bool get checksStageInterfaces => switch (runtimeOperatingSystem) {
  'macos' || 'ios' => true,
  _ => false,
};

Future<void>? _interfaceLoad;

/// Whether the reflection [requestStageInterfaces] started is still loading.
bool get stageInterfacesPending => _interfaceLoad != null;

/// Completes once the reflection [requestStageInterfaces] started has loaded,
/// or null when none is loading. Never completes with an error.
Future<void>? get stageInterfacesLoad => _interfaceLoad;

final Expando<bool> _engineLibraries = Expando<bool>('engineShaderLibrary');

/// Marks [library] as one the engine loads for itself (the base and physical
/// bundles, `.fmat` materials), so [requestStageInterfaces] does not parse it.
/// Its shaders never take a hand-written fragment shader's place.
void markEngineShaderLibrary(gpu.ShaderLibrary library) {
  _engineLibraries[library] = true;
}

final Expando<bool> _awaitingShaders = Expando<bool>('stageInterfaceAwaiting');

/// Starts loading the reflection of every app shader library loaded so far,
/// so the next pipeline build can read a ShaderMaterial's stage interfaces.
///
/// Each of [shaders] whose reflection is not loaded yet has its pipelines
/// deferred until the load lands (see [stageInterfaceDeferred]). Engine
/// libraries are skipped, since the pairs they take part in are known (see
/// [standardVaryings]). Does nothing where the check does not run.
void requestStageInterfaces([Iterable<gpu.Shader?> shaders = const []]) {
  if (!checksStageInterfaces) return;
  for (final shader in shaders) {
    if (shader != null && ShaderReflection.infoFor(shader) == null) {
      _awaitingShaders[shader] = true;
    }
  }
  final loads = <Future<void>>[
    for (final library in knownShaderLibraries())
      if (library is gpu.ShaderLibrary &&
          _engineLibraries[library] != true &&
          ShaderReflection.bundleInfoFor(library) == null)
        // A library whose bundle cannot be read is left unchecked rather
        // than failing anything.
        ShaderReflection.loadBundleInfo(
          library,
        ).then<void>((_) {}, onError: (Object _) {}),
  ];
  if (loads.isEmpty) return;
  final previous = _interfaceLoad;
  final load = Future.wait([?previous, ...loads]).then<void>((_) {});
  _interfaceLoad = load;
  load.whenComplete(() {
    if (identical(_interfaceLoad, load)) _interfaceLoad = null;
  });
}

/// Whether the pipeline pairing [vertexShader] with [fragmentShader] waits on
/// reflection [requestStageInterfaces] is still loading for one of them.
///
/// Its draw is skipped rather than rejected, so the pairing is checked once
/// the load lands. Every path that builds a pipeline goes through this, so a
/// capture or bake that runs before the load cannot build a pairing nobody
/// has checked.
bool stageInterfaceDeferred(
  gpu.Shader vertexShader,
  gpu.Shader fragmentShader,
) =>
    _interfaceLoad != null &&
    (_awaitsReflection(fragmentShader) || _awaitsReflection(vertexShader));

bool _awaitsReflection(gpu.Shader shader) =>
    _awaitingShaders[shader] == true &&
    ShaderReflection.infoFor(shader) == null;

// The standard vertex shaders, keyed by the base library they came from so a
// reloaded library is read again.
(gpu.ShaderLibrary, Set<gpu.Shader>)? _standardVertexShaders;

bool _isStandardVertexShader(gpu.Shader shader) {
  final library = loadedBaseShaderLibrary;
  if (library == null) return false;
  var cached = _standardVertexShaders;
  if (cached == null || !identical(cached.$1, library)) {
    cached = _standardVertexShaders = (
      library,
      {for (final name in standardVertexShaderNames) ?library[name]},
    );
  }
  return cached.$2.contains(shader);
}

ShaderBackendInfo? _mslInfo(gpu.Shader shader) {
  final info = ShaderReflection.infoFor(shader)?.current;
  if (info == null || info.source.text == null) return null;
  return switch (info.backend) {
    ShaderBackend.metalDesktop || ShaderBackend.metalIos => info,
    _ => null,
  };
}

/// Why [fragmentShader] cannot be paired with [vertexShader], as a message,
/// or null when they line up or either side's interface is unknown.
///
/// A fragment shader's interface is known once [requestStageInterfaces] has
/// loaded its library. A vertex shader's is known when it is one of the
/// [standardVertexShaderNames] or its library has loaded.
String? stageInterfaceProblem(
  gpu.Shader vertexShader,
  gpu.Shader fragmentShader,
) {
  if (!checksStageInterfaces) return null;
  final fragment = _mslInfo(fragmentShader);
  if (fragment == null || fragment.stage != ShaderStageKind.fragment) {
    return null;
  }
  final List<StageVarying> outputs;
  final String vertexName;
  if (_isStandardVertexShader(vertexShader)) {
    outputs = standardVaryings;
    vertexName = 'the engine vertex shader';
  } else {
    final vertex = _mslInfo(vertexShader);
    if (vertex == null || vertex.stage != ShaderStageKind.vertex) return null;
    outputs = parseMslVaryings(
      vertex.source.text!,
      vertex.entrypoint,
      outputs: true,
    );
    vertexName = 'vertex shader "${ShaderReflection.nameOf(vertexShader)}"';
  }
  final mismatch = describeVaryingMismatch(
    outputs,
    parseMslVaryings(
      fragment.source.text!,
      fragment.entrypoint,
      outputs: false,
    ),
  );
  if (mismatch == null) return null;
  return 'flutter_scene: skipping draws that pair fragment shader '
      '"${ShaderReflection.nameOf(fragmentShader)}" with $vertexName, because '
      'the fragment shader reads $mismatch. Metal matches varyings by '
      'location, so a fragment shader declares every varying its vertex '
      'stage writes, in order, including the ones it does not read (v_position '
      'through v_tangent for the engine vertex shaders, see MATERIALS.md).';
}
