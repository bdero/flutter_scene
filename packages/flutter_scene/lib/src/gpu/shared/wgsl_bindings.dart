/// Canonical WGSL binding assignment for shaders translated from the shader
/// bundle's Vulkan SPIR-V.
///
/// Tint splits each combined image sampler into a separate texture and sampler,
/// which displaces every binding above it, so the numbers a shader's reflection
/// carries are not the numbers the emitted WGSL uses. This computes what Tint
/// will produce, so bind group layouts can be built without parsing WGSL, and
/// verifies the prediction against the emitted source so a future Tint that
/// changes policy fails loudly instead of binding to the wrong slot.
library;

/// The kind of resource a bundle reflection entry describes.
enum WgslResourceKind {
  /// A uniform buffer. Occupies one binding slot.
  uniformBuffer,

  /// A combined image sampler in SPIR-V. Occupies two consecutive binding
  /// slots once Tint splits it, the texture first and the sampler second.
  combinedTextureSampler,
}

/// One resource as the shader bundle reflection describes it, before
/// translation.
///
/// [binding] is the bundle's number, which is also its `ext_res_0`. Impellerc
/// starts vertex-stage bindings at 0 and offsets fragment-stage bindings by 64.
typedef WgslReflectedResource = ({
  String name,
  int binding,
  WgslResourceKind kind,
});

/// Where a resource ended up in the translated WGSL.
typedef WgslBinding = ({
  String name,
  int group,
  int textureBinding,

  /// Only set for [WgslResourceKind.combinedTextureSampler].
  int? samplerBinding,
});

/// Raised when the emitted WGSL disagrees with the predicted layout.
class WgslBindingMismatch implements Exception {
  WgslBindingMismatch(this.message);

  final String message;

  @override
  String toString() => 'WgslBindingMismatch: $message';
}

/// The predicted WGSL binding layout for one translated shader.
class WgslBindingMap {
  WgslBindingMap._(this.bindings);

  /// Resolved bindings keyed by the reflected resource name.
  final Map<String, WgslBinding> bindings;

  /// Computes the layout Tint produces for [resources].
  ///
  /// Every resource keeps its original binding number, displaced upward by one
  /// slot for each combined image sampler that sits at a strictly lower
  /// original binding, since splitting each of those inserts an extra sampler
  /// slot ahead of it. A combined sampler's own texture lands on the displaced
  /// number and its sampler immediately after.
  ///
  /// Gaps in the original numbering are preserved, which is what distinguishes
  /// this from packing densely. Impellerc leaves gaps whenever a shader mixes
  /// vertex-stage bindings (from 0) with fragment-stage ones (from 64).
  ///
  /// [verifyAgainstWgsl] guards the rule at runtime, since it is Tint's
  /// internal policy rather than a documented contract.
  ///
  /// Every resource keeps whatever descriptor set it was reflected with,
  /// which impellerc always emits as 0.
  factory WgslBindingMap.predict(
    List<WgslReflectedResource> resources, {
    int group = 0,
  }) {
    if (resources.isEmpty) {
      return WgslBindingMap._(const {});
    }
    final sorted = [...resources]
      ..sort((a, b) => a.binding.compareTo(b.binding));
    final seen = <String>{};
    for (final r in sorted) {
      if (!seen.add(r.name)) {
        throw WgslBindingMismatch('duplicate resource name "${r.name}"');
      }
    }

    var shift = 0;
    final out = <String, WgslBinding>{};
    for (final r in sorted) {
      final base = r.binding + shift;
      switch (r.kind) {
        case WgslResourceKind.uniformBuffer:
          out[r.name] = (
            name: r.name,
            group: group,
            textureBinding: base,
            samplerBinding: null,
          );
        case WgslResourceKind.combinedTextureSampler:
          out[r.name] = (
            name: r.name,
            group: group,
            textureBinding: base,
            samplerBinding: base + 1,
          );
          shift += 1;
      }
    }
    return WgslBindingMap._(Map.unmodifiable(out));
  }

  /// The binding for [name], or null when the shader does not declare it.
  WgslBinding? operator [](String name) => bindings[name];

  /// Every binding slot this map occupies, ascending. Used to build a bind
  /// group layout.
  List<int> get occupiedBindings {
    final slots = <int>[];
    for (final b in bindings.values) {
      slots.add(b.textureBinding);
      if (b.samplerBinding != null) slots.add(b.samplerBinding!);
    }
    slots.sort();
    return slots;
  }

  /// Checks the prediction against the `@group(G) @binding(B) var ...`
  /// declarations Tint actually emitted in [wgsl].
  ///
  /// Throws [WgslBindingMismatch] when they disagree, which means Tint changed
  /// its assignment policy and this predictor needs revisiting. Names are not
  /// compared because Tint strips them; the check is on the set of occupied
  /// slots and on each slot's kind.
  void verifyAgainstWgsl(String wgsl, {String? shaderName}) {
    final actual = parseWgslDeclarations(wgsl);
    final where = shaderName == null ? '' : ' in "$shaderName"';

    final expectedSamplers = <int>{};
    final expectedTextures = <int>{};
    final expectedUniforms = <int>{};
    for (final b in bindings.values) {
      if (b.samplerBinding == null) {
        expectedUniforms.add(b.textureBinding);
      } else {
        expectedTextures.add(b.textureBinding);
        expectedSamplers.add(b.samplerBinding!);
      }
    }

    final actualSamplers = <int>{};
    final actualTextures = <int>{};
    final actualUniforms = <int>{};
    for (final d in actual) {
      switch (d.kind) {
        case WgslDeclarationKind.sampler:
          actualSamplers.add(d.binding);
        case WgslDeclarationKind.texture:
          actualTextures.add(d.binding);
        case WgslDeclarationKind.uniform:
          actualUniforms.add(d.binding);
        case WgslDeclarationKind.other:
          break;
      }
    }

    void compare(String kind, Set<int> expected, Set<int> got) {
      if (expected.length == got.length && expected.containsAll(got)) return;
      throw WgslBindingMismatch(
        '$kind bindings$where disagree, predicted '
        '${(expected.toList()..sort())} but Tint emitted ${(got.toList()..sort())}',
      );
    }

    compare('uniform', expectedUniforms, actualUniforms);
    compare('texture', expectedTextures, actualTextures);
    compare('sampler', expectedSamplers, actualSamplers);
  }
}

/// What a parsed WGSL module-scope declaration binds.
enum WgslDeclarationKind { uniform, texture, sampler, other }

/// A `@group(G) @binding(B) var ...` declaration parsed out of WGSL source.
///
/// [type] is the declared WGSL type, such as `texture_2d<f32>` or `sampler`.
typedef WgslDeclaration = ({
  int group,
  int binding,
  WgslDeclarationKind kind,
  String type,
});

final _declaration = RegExp(
  r'@group\((\d+)u?\)\s*@binding\((\d+)u?\)\s*var(?:<([^>]*)>)?\s*[A-Za-z_]\w*\s*:\s*([^;]+);',
);

/// Parses the module-scope resource declarations out of [wgsl].
///
/// Tint emits these as a flat list at the top of the module, so a regex is
/// enough and avoids carrying a WGSL parser.
List<WgslDeclaration> parseWgslDeclarations(String wgsl) {
  final out = <WgslDeclaration>[];
  for (final m in _declaration.allMatches(wgsl)) {
    final addressSpace = m.group(3) ?? '';
    final type = m.group(4)!.trim();
    final kind = switch (0) {
      _ when addressSpace.startsWith('uniform') => WgslDeclarationKind.uniform,
      _ when type == 'sampler' || type == 'sampler_comparison' =>
        WgslDeclarationKind.sampler,
      _ when type.startsWith('texture_') => WgslDeclarationKind.texture,
      _ => WgslDeclarationKind.other,
    };
    out.add((
      group: int.parse(m.group(1)!),
      binding: int.parse(m.group(2)!),
      kind: kind,
      type: type,
    ));
  }
  return out;
}
