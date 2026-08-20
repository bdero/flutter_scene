import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show internal, visibleForTesting;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/fmat/fmat_ast.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';

class _ParamSlot {
  _ParamSlot(this.type, this.offsetBytes, {this.sourceColor = false});

  final FmatType type;

  /// std140 byte offset of this member within the uniform block, from shader
  /// reflection.
  final int offsetBytes;

  /// Whether a `source_color` hint applies (sRGB-decode colors on set).
  final bool sourceColor;
}

class _SamplerSlot {
  _SamplerSlot(this.defaultPlaceholder);

  final FmatHintKind? defaultPlaceholder;
  gpu.Texture? texture;
  gpu.SamplerOptions? sampler;
}

/// Type-checked, name-addressed parameters for a custom material.
///
/// Parameters are set by name. The declared type comes from the material's
/// sidecar metadata, and byte offsets come from the compiled shader's
/// reflection, so callers never compute std140 padding and a wrong-typed value
/// throws instead of silently corrupting the uniform block. Three tiers of
/// access share one backing buffer:
///
///  * typed setters ([setFloat], [setVec4], [setColor], ...): the safe default;
///  * the dynamic [operator []=]: dispatches on the declared type and throws on
///    a mismatch;
///  * [rawBlock] / [offsetOf]: a raw escape hatch for hot loops.
///
/// Typed getters ([getFloat], [getVec4], [getColor], ...) mirror the setters
/// and read back the effective value, the explicitly assigned value if set,
/// otherwise the sidecar default. [getParameter] is the type-erased
/// equivalent, and [parameters] enumerates every declared parameter.
/// {@category Materials}
class MaterialParameters {
  MaterialParameters._(
    this._blockName,
    this._block,
    this._layout,
    this._samplers,
  );

  static final gpu.SamplerOptions _defaultSampler = gpu.SamplerOptions();

  /// Builds parameters from a shader's reflection plus a `.fmat` sidecar entry.
  ///
  /// Offsets and the block size come from [shader]; types, defaults, and hints
  /// come from [metadata]. Throws if a parameter named in the metadata is not
  /// present in the compiled shader block (a stale bundle or metadata).
  factory MaterialParameters.fromMetadata(
    gpu.Shader shader,
    Map<String, Object?> metadata,
  ) {
    final blockName =
        (metadata['uniform_block'] as String?) ?? 'MaterialParams';
    final slot = shader.getUniformSlot(blockName);
    final sizeInBytes = slot.sizeInBytes ?? 0;

    final layout = <String, _ParamSlot>{};
    final defaults = <String, Object>{};
    for (final raw in (metadata['parameters'] as List?) ?? const []) {
      final p = (raw as Map).cast<String, Object?>();
      final name = p['name'] as String;
      final type = FmatType.fromToken(p['type'] as String);
      if (type == null) {
        throw StateError('Unknown parameter type "${p['type']}" for "$name".');
      }
      final offset = slot.getMemberOffsetInBytes(name);
      if (offset == null) {
        throw StateError(
          'Material parameter "$name" is not present in the compiled shader '
          'block "$blockName" (stale bundle or metadata).',
        );
      }
      final hint = (p['hint'] as Map?)?.cast<String, Object?>();
      layout[name] = _ParamSlot(
        type,
        offset,
        sourceColor: hint?['kind'] == 'source_color',
      );
      final defaultValue = p['default'];
      if (defaultValue != null) defaults[name] = defaultValue;
    }

    final samplers = <String, _SamplerSlot>{};
    for (final raw in (metadata['samplers'] as List?) ?? const []) {
      final s = (raw as Map).cast<String, Object?>();
      final hint = (s['hint'] as Map?)?.cast<String, Object?>();
      samplers[s['name'] as String] = _SamplerSlot(
        _hintKind(hint?['kind'] as String?),
      );
    }

    final params = MaterialParameters._(
      blockName,
      ByteData(sizeInBytes),
      layout,
      samplers,
    );
    params._defaults = defaults;
    defaults.forEach(params._applyDefault);
    return params;
  }

  /// Builds parameters from an explicit layout, without shader reflection.
  /// Primarily for tests and advanced callers.
  @visibleForTesting
  factory MaterialParameters.withLayout({
    required String blockName,
    required int blockSizeBytes,
    required Map<String, ({FmatType type, int offset, bool sourceColor})>
    parameters,
    Map<String, FmatHintKind?> samplers = const {},
    Map<String, Object> defaults = const {},
  }) {
    final layout = {
      for (final e in parameters.entries)
        e.key: _ParamSlot(
          e.value.type,
          e.value.offset,
          sourceColor: e.value.sourceColor,
        ),
    };
    final samplerSlots = {
      for (final e in samplers.entries) e.key: _SamplerSlot(e.value),
    };
    final params = MaterialParameters._(
      blockName,
      ByteData(blockSizeBytes),
      layout,
      samplerSlots,
    );
    params._defaults = Map.of(defaults);
    defaults.forEach(params._applyDefault);
    return params;
  }

  String _blockName;
  ByteData _block;
  Map<String, _ParamSlot> _layout;
  Map<String, _SamplerSlot> _samplers;

  /// Names the caller explicitly set (vs. left at the sidecar default). On a
  /// hot-reload refresh ([updateFromMetadata]) these keep their value, while
  /// unset parameters take the new default, so editing a default in the `.fmat`
  /// takes effect live.
  final Set<String> _overridden = <String>{};

  final Map<String, Object> _assigned = <String, Object>{};

  /// Sidecar-declared defaults by parameter name, raw as authored (a `num`
  /// for scalars, a `List` for vectors and matrices). Absent for a parameter
  /// with no declared default. Kept in sync with the current layout across
  /// [updateFromMetadata].
  Map<String, Object> _defaults = <String, Object>{};

  /// The values explicitly assigned through the typed setters, keyed by
  /// parameter name, as last set (vectors and matrices are stored as defensive
  /// copies; textures appear as their live `gpu.Texture`). Sidecar defaults
  /// are not included. Used by the scene serializer to round-trip parameter
  /// overrides.
  Map<String, Object> get assignedValues => Map.unmodifiable(_assigned);

  /// The names of the scalar/vector parameters in this material.
  Iterable<String> get parameterNames => _layout.keys;

  /// The names of the sampler parameters in this material.
  Iterable<String> get samplerNames => _samplers.keys;

  /// Whether a scalar/vector parameter named [name] is declared.
  bool hasParameter(String name) => _layout.containsKey(name);

  /// Whether a sampler parameter named [name] is declared.
  bool hasSampler(String name) => _samplers.containsKey(name);

  /// Whether [name] was explicitly set on this instance, as opposed to left
  /// at the sidecar default. Throws [ArgumentError] if [name] is not a
  /// declared parameter.
  bool isParameterAssigned(String name) {
    _slot(name, null);
    return _assigned.containsKey(name);
  }

  /// The raw uniform-block bytes, for the hot-loop escape hatch. Pair with
  /// [offsetOf]; you own correctness (type and std140 layout) here.
  ByteData get rawBlock => _block;

  /// The std140 byte offset of [name], or throws if it is unknown.
  int offsetOf(String name) => _slot(name, null).offsetBytes;

  /// Re-reads parameter declarations from a regenerated [shader] and [metadata]
  /// (a hot-reloaded `.fmat`), preserving values the caller explicitly set.
  ///
  /// For a parameter present before and after with the same type: an
  /// explicitly-set value is kept; otherwise the new default is taken, so
  /// editing a default in the `.fmat` takes effect live. New parameters take
  /// their new default; removed parameters are dropped. Sampler bindings are
  /// preserved by name. A parameter declared in [metadata] but absent from the
  /// compiled block (a transient bundle/metadata mismatch mid-reload) is
  /// skipped rather than throwing.
  void updateFromMetadata(gpu.Shader shader, Map<String, Object?> metadata) {
    final newBlockName =
        (metadata['uniform_block'] as String?) ?? 'MaterialParams';
    final slot = shader.getUniformSlot(newBlockName);

    final newLayout = <String, _ParamSlot>{};
    final newDefaults = <String, Object>{};
    for (final raw in (metadata['parameters'] as List?) ?? const []) {
      final p = (raw as Map).cast<String, Object?>();
      final name = p['name'] as String;
      final type = FmatType.fromToken(p['type'] as String);
      if (type == null) continue;
      final offset = slot.getMemberOffsetInBytes(name);
      if (offset == null) continue;
      final hint = (p['hint'] as Map?)?.cast<String, Object?>();
      newLayout[name] = _ParamSlot(
        type,
        offset,
        sourceColor: hint?['kind'] == 'source_color',
      );
      final defaultValue = p['default'];
      if (defaultValue != null) newDefaults[name] = defaultValue;
    }

    final newSamplerHints = <String, FmatHintKind?>{};
    for (final raw in (metadata['samplers'] as List?) ?? const []) {
      final s = (raw as Map).cast<String, Object?>();
      final hint = (s['hint'] as Map?)?.cast<String, Object?>();
      newSamplerHints[s['name'] as String] = _hintKind(
        hint?['kind'] as String?,
      );
    }

    _applyRefresh(
      newBlockName,
      slot.sizeInBytes ?? 0,
      newLayout,
      newDefaults,
      newSamplerHints,
    );
  }

  /// Test hook mirroring [updateFromMetadata] but with an explicit reflected
  /// layout, so the value-preservation logic can be exercised without a GPU
  /// shader (see [withLayout]).
  @visibleForTesting
  void updateFromLayout({
    required String blockName,
    required int blockSizeBytes,
    required Map<String, ({FmatType type, int offset, bool sourceColor})>
    parameters,
    Map<String, Object> defaults = const {},
    Map<String, FmatHintKind?> samplers = const {},
  }) {
    final layout = {
      for (final e in parameters.entries)
        e.key: _ParamSlot(
          e.value.type,
          e.value.offset,
          sourceColor: e.value.sourceColor,
        ),
    };
    _applyRefresh(blockName, blockSizeBytes, layout, defaults, samplers);
  }

  void _applyRefresh(
    String newBlockName,
    int newBlockSizeBytes,
    Map<String, _ParamSlot> newLayout,
    Map<String, Object> newDefaults,
    Map<String, FmatHintKind?> newSamplerHints,
  ) {
    final newBlock = ByteData(newBlockSizeBytes);

    // Carry over explicitly-set values for parameters that survive with the
    // same type; everything else takes the (possibly edited) default.
    for (final entry in newLayout.entries) {
      final name = entry.key;
      final newSlot = entry.value;
      final oldSlot = _layout[name];
      final keepOld =
          oldSlot != null &&
          oldSlot.type == newSlot.type &&
          _overridden.contains(name);
      if (keepOld) {
        _copyMember(
          _block,
          oldSlot.offsetBytes,
          newBlock,
          newSlot.offsetBytes,
          newSlot.type,
        );
      } else if (newDefaults.containsKey(name)) {
        _applyDefaultInto(newBlock, newSlot, newDefaults[name]!);
      }
    }

    // Rebuild samplers, preserving user-bound textures by name.
    final newSamplers = <String, _SamplerSlot>{};
    for (final entry in newSamplerHints.entries) {
      final samplerSlot = _SamplerSlot(entry.value);
      final old = _samplers[entry.key];
      if (old != null) {
        samplerSlot.texture = old.texture;
        samplerSlot.sampler = old.sampler;
      }
      newSamplers[entry.key] = samplerSlot;
    }

    _blockName = newBlockName;
    _block = newBlock;
    _layout = newLayout;
    _samplers = newSamplers;
    _defaults = Map.of(newDefaults);
    _overridden.removeWhere(
      (name) => !newLayout.containsKey(name) && !newSamplers.containsKey(name),
    );
    _assigned.removeWhere(
      (name, _) =>
          !newLayout.containsKey(name) && !newSamplers.containsKey(name),
    );
  }

  /// Copies the full parameter state (block bytes, explicit-set tracking, and
  /// sampler bindings) from [other], which must have been built from the same
  /// compiled shader entry so the layouts agree. The editor uses this to apply
  /// a re-realized material onto the live instance in place.
  void copyStateFrom(MaterialParameters other) {
    if (other._block.lengthInBytes == _block.lengthInBytes) {
      Uint8List.sublistView(
        _block,
      ).setAll(0, Uint8List.sublistView(other._block));
    }
    _overridden
      ..clear()
      ..addAll(other._overridden);
    _assigned
      ..clear()
      ..addAll(other._assigned);
    for (final entry in _samplers.entries) {
      final source = other._samplers[entry.key];
      entry.value
        ..texture = source?.texture
        ..sampler = source?.sampler;
    }
  }

  void setFloat(String name, double value) {
    _overridden.add(name);
    _assigned[name] = value;
    _block.setFloat32(
      _slot(name, FmatType.float_).offsetBytes,
      value,
      Endian.host,
    );
  }

  void setInt(String name, int value) {
    _overridden.add(name);
    _assigned[name] = value;
    _block.setInt32(_slot(name, FmatType.int_).offsetBytes, value, Endian.host);
  }

  void setVec2(String name, Vector2 value) {
    _overridden.add(name);
    _assigned[name] = value.clone();
    _writeFloats(_slot(name, FmatType.vec2).offsetBytes, value.storage);
  }

  void setVec3(String name, Vector3 value) {
    _overridden.add(name);
    _assigned[name] = value.clone();
    _writeFloats(_slot(name, FmatType.vec3).offsetBytes, value.storage);
  }

  void setVec4(String name, Vector4 value) {
    _overridden.add(name);
    _assigned[name] = value.clone();
    _writeFloats(_slot(name, FmatType.vec4).offsetBytes, value.storage);
  }

  void setMat4(String name, Matrix4 value) {
    _overridden.add(name);
    _assigned[name] = value.clone();
    _writeFloats(_slot(name, FmatType.mat4).offsetBytes, value.storage);
  }

  /// Sets a vec4 parameter from a [Color]. If the parameter has a
  /// `source_color` hint, the rgb channels are sRGB-decoded to linear (matching
  /// the shader's `SRGBToLinear`); alpha is written as-is.
  void setColor(String name, Color color) {
    _overridden.add(name);
    _assigned[name] = color;
    final slot = _slot(name, FmatType.vec4);
    var r = color.r, g = color.g, b = color.b;
    if (slot.sourceColor) {
      r = _srgbToLinear(r);
      g = _srgbToLinear(g);
      b = _srgbToLinear(b);
    }
    _writeFloats(slot.offsetBytes, [r, g, b, color.a]);
  }

  void setTexture(
    String name,
    gpu.Texture texture, {
    gpu.SamplerOptions? sampler,
  }) {
    final slot = _samplers[name];
    if (slot == null) {
      throw ArgumentError('Unknown sampler parameter "$name".');
    }
    _overridden.add(name);
    _assigned[name] = texture;
    slot.texture = texture;
    slot.sampler = sampler;
  }

  /// Restores a sampler to its declared placeholder.
  @internal
  void clearTexture(String name) {
    final slot = _samplers[name];
    if (slot == null) {
      throw ArgumentError('Unknown sampler parameter "$name".');
    }
    _overridden.remove(name);
    _assigned.remove(name);
    slot.texture = null;
    slot.sampler = null;
  }

  /// Effective value of a float parameter, the assigned value if set,
  /// otherwise the sidecar default. Throws on an unknown name or wrong type.
  double getFloat(String name) =>
      _block.getFloat32(_slot(name, FmatType.float_).offsetBytes, Endian.host);

  /// Effective value of an int parameter, the assigned value if set,
  /// otherwise the sidecar default. Throws on an unknown name or wrong type.
  int getInt(String name) =>
      _block.getInt32(_slot(name, FmatType.int_).offsetBytes, Endian.host);

  /// Effective value of a vec2 parameter, the assigned value if set,
  /// otherwise the sidecar default. Throws on an unknown name or wrong type.
  Vector2 getVec2(String name) {
    final f = _readFloats(_slot(name, FmatType.vec2).offsetBytes, 2);
    return Vector2(f[0], f[1]);
  }

  /// Effective value of a vec3 parameter, the assigned value if set,
  /// otherwise the sidecar default. Throws on an unknown name or wrong type.
  Vector3 getVec3(String name) {
    final f = _readFloats(_slot(name, FmatType.vec3).offsetBytes, 3);
    return Vector3(f[0], f[1], f[2]);
  }

  /// Effective value of a vec4 parameter, the assigned value if set,
  /// otherwise the sidecar default. Throws on an unknown name or wrong type.
  Vector4 getVec4(String name) {
    final f = _readFloats(_slot(name, FmatType.vec4).offsetBytes, 4);
    return Vector4(f[0], f[1], f[2], f[3]);
  }

  /// Effective value of a mat4 parameter, the assigned value if set,
  /// otherwise the sidecar default. Throws on an unknown name or wrong type.
  Matrix4 getMat4(String name) =>
      Matrix4.fromList(_readFloats(_slot(name, FmatType.mat4).offsetBytes, 16));

  /// Effective value of a vec4 parameter as a [Color], the assigned value if
  /// set, otherwise the sidecar default. For a `source_color`-hinted
  /// parameter the rgb channels are sRGB-encoded back from the stored linear
  /// value, the inverse of [setColor]; alpha is read as-is. A non-source_color
  /// parameter reads its raw channels unencoded. Throws on an unknown name or
  /// wrong type.
  Color getColor(String name) {
    final slot = _slot(name, FmatType.vec4);
    final f = _readFloats(slot.offsetBytes, 4);
    var r = f[0], g = f[1], b = f[2];
    if (slot.sourceColor) {
      r = _linearToSrgb(r);
      g = _linearToSrgb(g);
      b = _linearToSrgb(b);
    }
    return Color.from(alpha: f[3], red: r, green: g, blue: b);
  }

  /// The texture bound to sampler [name], or null when unset. The engine
  /// binds the declared placeholder at draw time for an unset sampler, so
  /// that placeholder is never surfaced here. Throws on an unknown sampler
  /// name.
  gpu.Texture? getTexture(String name) {
    final slot = _samplers[name];
    if (slot == null) {
      throw ArgumentError('Unknown sampler parameter "$name".');
    }
    return slot.texture;
  }

  /// Effective value of a declared parameter, boxed as [double], [int],
  /// [Vector2], [Vector3], [Vector4], or [Matrix4] matching its declared
  /// type. For samplers use [getTexture]. Throws on an unknown name.
  Object getParameter(String name) {
    final type = _slot(name, null).type;
    return switch (type) {
      FmatType.float_ => getFloat(name),
      FmatType.int_ => getInt(name),
      FmatType.vec2 => getVec2(name),
      FmatType.vec3 => getVec3(name),
      FmatType.vec4 => getVec4(name),
      FmatType.mat4 => getMat4(name),
      // Samplers are declared separately (see _samplers) and never appear in
      // _layout, so _slot never returns one of these for a plain parameter.
      FmatType.sampler2d ||
      FmatType.samplerCube => throw StateError('unreachable: sampler type'),
    };
  }

  /// Every declared scalar/vector parameter (not samplers, see
  /// [samplerNames]), with its GLSL type spelling and sidecar-declared
  /// default (null if none was declared).
  Iterable<({String name, String type, Object? defaultValue})> get parameters =>
      _layout.entries.map(
        (e) => (
          name: e.key,
          type: e.value.type.glslType,
          defaultValue: _defaults[e.key],
        ),
      );

  /// Dynamic, type-checked assignment. Dispatches on the parameter's declared
  /// type and throws if [value]'s runtime type does not match.
  void operator []=(String name, Object value) {
    final slot = _layout[name];
    if (slot != null) {
      _setDynamic(name, slot.type, value);
      return;
    }
    if (_samplers.containsKey(name)) {
      if (value is gpu.Texture) {
        setTexture(name, value);
        return;
      }
      throw ArgumentError('Sampler parameter "$name" requires a gpu.Texture.');
    }
    throw ArgumentError('Unknown material parameter "$name".');
  }

  /// Whether this material has a non-empty `MaterialParams` uniform block (any
  /// non-sampler parameters). When false the generated shaders declare no block
  /// and none is bound.
  @internal
  bool get hasUniformBlock => _block.lengthInBytes > 0;

  /// Whether this material declares any parameter at all (the uniform block
  /// or samplers). Mirrors the emitter's condition for declaring the
  /// `FragmentKeepAlive` block, so the runtime binds it exactly when the
  /// generated shader carries it.
  @internal
  bool get hasAnyParameters => hasUniformBlock || _samplers.isNotEmpty;

  /// Binds only the `MaterialParams` uniform block on [shader] into [pass],
  /// not the sampler parameters. Used to make the block available to the
  /// vertex stage, whose generated shader declares the block but not the
  /// material's samplers.
  void bindUniformBlock(
    gpu.RenderPass pass,
    gpu.Shader shader,
    TransientWriter transientsBuffer,
  ) {
    if (_block.lengthInBytes > 0) {
      pass.bindUniform(
        shader.getUniformSlot(_blockName),
        transientsBuffer.emplace(_block),
      );
    }
  }

  /// Binds the uniform block and the sampler parameters on [shader] into [pass].
  void bind(
    gpu.RenderPass pass,
    gpu.Shader shader,
    TransientWriter transientsBuffer,
  ) {
    bindUniformBlock(pass, shader, transientsBuffer);
    for (final entry in _samplers.entries) {
      final slot = entry.value;
      pass.bindTexture(
        shader.getUniformSlot(entry.key),
        slot.texture ?? _placeholder(slot.defaultPlaceholder),
        sampler: slot.sampler ?? _defaultSampler,
      );
    }
  }

  _ParamSlot _slot(String name, FmatType? expected) {
    final slot = _layout[name];
    if (slot == null) {
      throw ArgumentError('Unknown material parameter "$name".');
    }
    if (expected != null && slot.type != expected) {
      throw ArgumentError(
        'Parameter "$name" is ${slot.type.glslType}, but a '
        '${expected.glslType} value was set.',
      );
    }
    return slot;
  }

  void _writeFloats(int offset, List<double> values) {
    for (var i = 0; i < values.length; i++) {
      _block.setFloat32(offset + i * 4, values[i], Endian.host);
    }
  }

  List<double> _readFloats(int offset, int count) => [
    for (var i = 0; i < count; i++)
      _block.getFloat32(offset + i * 4, Endian.host),
  ];

  void _setDynamic(String name, FmatType type, Object value) {
    if (type == FmatType.float_ && value is num) {
      setFloat(name, value.toDouble());
      return;
    }
    if (type == FmatType.int_ && value is int) {
      setInt(name, value);
      return;
    }
    if (type == FmatType.vec2 && value is Vector2) {
      setVec2(name, value);
      return;
    }
    if (type == FmatType.vec3 && value is Vector3) {
      setVec3(name, value);
      return;
    }
    if (type == FmatType.vec4 && value is Vector4) {
      setVec4(name, value);
      return;
    }
    if (type == FmatType.vec4 && value is Color) {
      setColor(name, value);
      return;
    }
    if (type == FmatType.mat4 && value is Matrix4) {
      setMat4(name, value);
      return;
    }
    throw ArgumentError(
      'Parameter "$name" is ${type.glslType}; cannot assign a '
      '${value.runtimeType}.',
    );
  }

  void _applyDefault(String name, Object value) =>
      _applyDefaultInto(_block, _layout[name]!, value);

  static void _applyDefaultInto(ByteData block, _ParamSlot slot, Object value) {
    if (slot.type == FmatType.float_) {
      block.setFloat32(
        slot.offsetBytes,
        (value as num).toDouble(),
        Endian.host,
      );
    } else if (slot.type == FmatType.int_) {
      block.setInt32(slot.offsetBytes, (value as num).toInt(), Endian.host);
    } else if (value is List) {
      for (var i = 0; i < value.length; i++) {
        block.setFloat32(
          slot.offsetBytes + i * 4,
          (value[i] as num).toDouble(),
          Endian.host,
        );
      }
    }
  }

  /// Copies one parameter's bytes (its [type]'s component size) from one block
  /// to another, used to carry an explicitly-set value across a refresh.
  static void _copyMember(
    ByteData src,
    int srcOffset,
    ByteData dst,
    int dstOffset,
    FmatType type,
  ) {
    final bytes = type.componentCount * 4;
    for (var i = 0; i < bytes; i++) {
      dst.setUint8(dstOffset + i, src.getUint8(srcOffset + i));
    }
  }

  gpu.Texture _placeholder(FmatHintKind? kind) => switch (kind) {
    FmatHintKind.defaultNormal => Material.normalPlaceholder(null),
    // White is the neutral fallback; dedicated black/transparent
    // placeholders are a future addition.
    _ => Material.whitePlaceholder(null),
  };
}

// sRGB -> linear matching pbr.glsl's SRGBToLinear on the GPU.
double _srgbToLinear(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

// linear -> sRGB, the inverse of _srgbToLinear, for reading a source_color
// parameter back out through getColor.
double _linearToSrgb(double c) => c <= 0.0031308
    ? c * 12.92
    : 1.055 * math.pow(c, 1 / 2.4).toDouble() - 0.055;

FmatHintKind? _hintKind(String? kind) => switch (kind) {
  'default_white' => FmatHintKind.defaultWhite,
  'default_black' => FmatHintKind.defaultBlack,
  'default_normal' => FmatHintKind.defaultNormal,
  'default_transparent' => FmatHintKind.defaultTransparent,
  _ => null,
};
