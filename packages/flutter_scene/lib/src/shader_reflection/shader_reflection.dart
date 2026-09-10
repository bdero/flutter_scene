/// Shader reflection and source access over compiled shader bundles.
///
/// A `.shaderbundle` carries, for every shader and every backend it was
/// compiled for, the entrypoint, vertex inputs, uniform blocks with their
/// field layouts, texture bindings, and the compiled output itself (MSL and
/// GLSL as text, SPIR-V as bytes). The engine reads none of that on native,
/// where the backend unpacks the bundle itself, so this module parses the
/// same bytes a second time, on demand, for tooling.
///
/// Nothing here runs unless asked: [ShaderReflection.loadBundleInfo] reads a
/// library's bundle once and caches the result for the library's lifetime.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import 'package:flutter_scene/src/generated_assets/generated_assets.dart'
    show ShaderBundleBackend, shaderBundleBackendsForOS;
import 'package:flutter_scene/src/generated_assets/runtime_target.dart'
    show runtimeOperatingSystem;
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/shared/shader_library_sources.dart';
import 'package:flutter_scene/src/gpu/web/shader_bundle_generated.dart' as fb;

/// A rendering backend a shader bundle can carry compiled output for.
/// {@category Debugging and profiling}
enum ShaderBackend {
  metalIos,
  metalDesktop,
  openglEs,
  openglDesktop,
  vulkan;

  /// Whether this backend's compiled output is source text (MSL, GLSL)
  /// rather than SPIR-V bytes.
  bool get isTextual => this != vulkan;

  /// The backends the running platform can use, most likely first. The
  /// engine picks among them at startup and does not report its choice, so a
  /// caller wanting one backend's source takes the first that the bundle
  /// holds.
  static List<ShaderBackend> forCurrentPlatform() {
    final os = runtimeOperatingSystem;
    if (os == null) return const [ShaderBackend.openglEs];
    return [
      for (final backend in shaderBundleBackendsForOS(os))
        switch (backend) {
          ShaderBundleBackend.metalIos => ShaderBackend.metalIos,
          ShaderBundleBackend.metalDesktop => ShaderBackend.metalDesktop,
          ShaderBundleBackend.openglEs => ShaderBackend.openglEs,
          ShaderBundleBackend.vulkan => ShaderBackend.vulkan,
        },
    ];
  }
}

/// The pipeline stage a compiled shader runs in.
/// {@category Debugging and profiling}
enum ShaderStageKind { vertex, fragment, compute }

/// The scalar type of a uniform field or vertex input.
/// {@category Debugging and profiling}
enum ShaderScalarType {
  boolean,
  int8,
  uint8,
  int16,
  uint16,
  int32,
  uint32,
  int64,
  uint64,
  float16,
  float32,
  float64,
  sampledImage,
  unknown;

  /// Bytes per scalar, or 0 when the type is not a plain scalar.
  int get byteSize => switch (this) {
    boolean || int8 || uint8 => 1,
    int16 || uint16 || float16 => 2,
    int32 || uint32 || float32 => 4,
    int64 || uint64 || float64 => 8,
    sampledImage || unknown => 0,
  };

  static ShaderScalarType _fromUniform(fb.UniformDataType type) =>
      switch (type) {
        fb.UniformDataType.kBoolean => boolean,
        fb.UniformDataType.kSignedByte => int8,
        fb.UniformDataType.kUnsignedByte => uint8,
        fb.UniformDataType.kSignedShort => int16,
        fb.UniformDataType.kUnsignedShort => uint16,
        fb.UniformDataType.kSignedInt => int32,
        fb.UniformDataType.kUnsignedInt => uint32,
        fb.UniformDataType.kSignedInt64 => int64,
        fb.UniformDataType.kUnsignedInt64 => uint64,
        fb.UniformDataType.kHalfFloat => float16,
        fb.UniformDataType.kFloat => float32,
        fb.UniformDataType.kDouble => float64,
        fb.UniformDataType.kSampledImage => sampledImage,
        _ => unknown,
      };

  static ShaderScalarType _fromInput(fb.InputDataType type) => switch (type) {
    fb.InputDataType.kBoolean => boolean,
    fb.InputDataType.kSignedByte => int8,
    fb.InputDataType.kUnsignedByte => uint8,
    fb.InputDataType.kSignedShort => int16,
    fb.InputDataType.kUnsignedShort => uint16,
    fb.InputDataType.kSignedInt => int32,
    fb.InputDataType.kUnsignedInt => uint32,
    fb.InputDataType.kSignedInt64 => int64,
    fb.InputDataType.kUnsignedInt64 => uint64,
    fb.InputDataType.kFloat => float32,
    fb.InputDataType.kDouble => float64,
    _ => unknown,
  };
}

/// One vertex-stage input attribute.
/// {@category Debugging and profiling}
final class ShaderInputInfo {
  const ShaderInputInfo({
    required this.name,
    required this.location,
    required this.type,
    required this.bitWidth,
    required this.vecSize,
    required this.columns,
    required this.offset,
  });

  final String name;
  final int location;
  final ShaderScalarType type;
  final int bitWidth;
  final int vecSize;
  final int columns;

  /// Byte offset within the bundle's default interleaved vertex layout.
  final int offset;

  Map<String, Object?> toJson() => {
    'name': name,
    'location': location,
    'type': type.name,
    'bitWidth': bitWidth,
    'vecSize': vecSize,
    'columns': columns,
    'offset': offset,
  };
}

/// One member of a uniform block, with its std140 placement.
/// {@category Debugging and profiling}
final class ShaderUniformFieldInfo {
  const ShaderUniformFieldInfo({
    required this.name,
    required this.type,
    required this.offsetBytes,
    required this.elementSizeBytes,
    required this.totalSizeBytes,
    required this.arrayElements,
    required this.vecSize,
    required this.columns,
  });

  final String name;
  final ShaderScalarType type;
  final int offsetBytes;

  /// Bytes one element occupies, padding included (a `mat3` is 48).
  final int elementSizeBytes;

  /// Bytes the whole member occupies, all array elements included.
  final int totalSizeBytes;

  /// Array length, or 0 for a non-array member.
  final int arrayElements;
  final int vecSize;
  final int columns;

  /// The GLSL-style type name (`vec3`, `mat4`, `float[4]`).
  String get typeName {
    final prefix = switch (type) {
      ShaderScalarType.float32 => '',
      ShaderScalarType.int32 => 'i',
      ShaderScalarType.uint32 => 'u',
      ShaderScalarType.boolean => 'b',
      ShaderScalarType.float64 => 'd',
      _ => '${type.name}_',
    };
    final base = columns > 1
        ? '${prefix}mat${columns == vecSize ? '$columns' : '${columns}x$vecSize'}'
        : vecSize > 1
        ? '${prefix}vec$vecSize'
        : switch (type) {
            ShaderScalarType.float32 => 'float',
            ShaderScalarType.int32 => 'int',
            ShaderScalarType.uint32 => 'uint',
            ShaderScalarType.boolean => 'bool',
            ShaderScalarType.float64 => 'double',
            _ => type.name,
          };
    return arrayElements > 0 ? '$base[$arrayElements]' : base;
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'type': typeName,
    'scalar': type.name,
    'offset': offsetBytes,
    'elementSize': elementSizeBytes,
    'totalSize': totalSizeBytes,
    'arrayElements': arrayElements,
    'vecSize': vecSize,
    'columns': columns,
  };
}

/// One uniform block (a `uniform Name { ... }` declaration).
/// {@category Debugging and profiling}
final class ShaderUniformBlockInfo {
  const ShaderUniformBlockInfo({
    required this.name,
    required this.set,
    required this.binding,
    required this.sizeBytes,
    required this.fields,
  });

  final String name;
  final int set;
  final int binding;

  /// Block size in bytes, alignment padding included.
  final int sizeBytes;
  final List<ShaderUniformFieldInfo> fields;

  Map<String, Object?> toJson() => {
    'name': name,
    'set': set,
    'binding': binding,
    'size': sizeBytes,
    'fields': [for (final field in fields) field.toJson()],
  };
}

/// One sampler binding.
/// {@category Debugging and profiling}
final class ShaderTextureInfo {
  const ShaderTextureInfo({
    required this.name,
    required this.set,
    required this.binding,
  });

  final String name;
  final int set;
  final int binding;

  Map<String, Object?> toJson() => {
    'name': name,
    'set': set,
    'binding': binding,
  };
}

/// The compiled output for one backend.
/// {@category Debugging and profiling}
final class ShaderSource {
  const ShaderSource({required this.backend, required this.bytes});

  final ShaderBackend backend;

  /// The raw compiled bytes: UTF-8 source text for a textual backend, SPIR-V
  /// for Vulkan.
  final Uint8List bytes;

  /// The source text, or null for a binary backend.
  String? get text =>
      backend.isTextual ? utf8.decode(bytes, allowMalformed: true) : null;
}

/// One shader as compiled for one backend.
/// {@category Debugging and profiling}
final class ShaderBackendInfo {
  const ShaderBackendInfo({
    required this.backend,
    required this.stage,
    required this.entrypoint,
    required this.inputs,
    required this.uniformBlocks,
    required this.textures,
    required this.source,
  });

  final ShaderBackend backend;
  final ShaderStageKind stage;
  final String entrypoint;
  final List<ShaderInputInfo> inputs;
  final List<ShaderUniformBlockInfo> uniformBlocks;
  final List<ShaderTextureInfo> textures;
  final ShaderSource source;

  ShaderUniformBlockInfo? uniformBlock(String name) {
    for (final block in uniformBlocks) {
      if (block.name == name) return block;
    }
    return null;
  }

  Map<String, Object?> toJson({bool includeSource = false}) => {
    'backend': backend.name,
    'stage': stage.name,
    'entrypoint': entrypoint,
    'inputs': [for (final input in inputs) input.toJson()],
    'uniformBlocks': [for (final block in uniformBlocks) block.toJson()],
    'textures': [for (final texture in textures) texture.toJson()],
    'sourceBytes': source.bytes.length,
    if (includeSource) 'source': source.text ?? base64Encode(source.bytes),
  };
}

/// One named shader entry with every backend it was compiled for.
/// {@category Debugging and profiling}
final class ShaderInfo {
  const ShaderInfo({required this.name, required this.backends});

  final String name;
  final Map<ShaderBackend, ShaderBackendInfo> backends;

  /// The reflection for the running platform: the first of
  /// [ShaderBackend.forCurrentPlatform] this entry holds, else any.
  ShaderBackendInfo? get current {
    for (final backend in ShaderBackend.forCurrentPlatform()) {
      final info = backends[backend];
      if (info != null) return info;
    }
    return backends.values.firstOrNull;
  }

  ShaderStageKind? get stage => current?.stage;

  Map<String, Object?> toJson({bool includeSource = false}) => {
    'name': name,
    'backends': {
      for (final entry in backends.entries)
        entry.key.name: entry.value.toJson(includeSource: includeSource),
    },
  };
}

/// A parsed shader bundle.
/// {@category Debugging and profiling}
final class ShaderBundleInfo {
  ShaderBundleInfo._({required this.formatVersion, required this.shaders});

  /// Parses `.shaderbundle` [bytes].
  factory ShaderBundleInfo.parse(Uint8List bytes) {
    final bundle = fb.ShaderBundle(bytes);
    final shaders = <ShaderInfo>[];
    for (final entry in bundle.shaders ?? const <fb.Shader>[]) {
      final name = entry.name;
      if (name == null) continue;
      final backends = <ShaderBackend, ShaderBackendInfo>{};
      void add(ShaderBackend backend, fb.BackendShader? shader) {
        if (shader == null) return;
        backends[backend] = _backendInfo(backend, shader);
      }

      add(ShaderBackend.metalIos, entry.metalIos);
      add(ShaderBackend.metalDesktop, entry.metalDesktop);
      add(ShaderBackend.openglEs, entry.openglEs);
      add(ShaderBackend.openglDesktop, entry.openglDesktop);
      add(ShaderBackend.vulkan, entry.vulkan);
      shaders.add(ShaderInfo(name: name, backends: backends));
    }
    return ShaderBundleInfo._(
      formatVersion: bundle.formatVersion,
      shaders: shaders,
    );
  }

  final int formatVersion;
  final List<ShaderInfo> shaders;

  ShaderInfo? operator [](String name) {
    for (final shader in shaders) {
      if (shader.name == name) return shader;
    }
    return null;
  }

  /// Every backend at least one entry was compiled for.
  Set<ShaderBackend> get backends => {
    for (final shader in shaders) ...shader.backends.keys,
  };

  Map<String, Object?> toJson({bool includeSource = false}) => {
    'formatVersion': formatVersion,
    'shaders': [
      for (final shader in shaders) shader.toJson(includeSource: includeSource),
    ],
  };

  static ShaderBackendInfo _backendInfo(
    ShaderBackend backend,
    fb.BackendShader shader,
  ) {
    final bytes = shader.shader;
    return ShaderBackendInfo(
      backend: backend,
      stage: switch (shader.stage) {
        fb.ShaderStage.kVertex => ShaderStageKind.vertex,
        fb.ShaderStage.kFragment => ShaderStageKind.fragment,
        _ => ShaderStageKind.compute,
      },
      entrypoint: shader.entrypoint ?? '',
      inputs: [
        for (final input in shader.inputs ?? const <fb.ShaderInput>[])
          ShaderInputInfo(
            name: input.name ?? '',
            location: input.location,
            type: ShaderScalarType._fromInput(input.type),
            bitWidth: input.bitWidth,
            vecSize: input.vecSize,
            columns: input.columns,
            offset: input.offset,
          ),
      ],
      uniformBlocks: [
        for (final block
            in shader.uniformStructs ?? const <fb.ShaderUniformStruct>[])
          ShaderUniformBlockInfo(
            name: block.name ?? '',
            set: block.$set,
            binding: block.binding,
            sizeBytes: block.sizeInBytes,
            fields: [
              for (final field
                  in block.fields ?? const <fb.ShaderUniformStructField>[])
                ShaderUniformFieldInfo(
                  name: field.name ?? '',
                  type: ShaderScalarType._fromUniform(field.type),
                  offsetBytes: field.offsetInBytes,
                  elementSizeBytes: field.elementSizeInBytes,
                  totalSizeBytes: field.totalSizeInBytes,
                  arrayElements: field.arrayElements,
                  vecSize: field.vecSize,
                  columns: field.columns,
                ),
            ],
          ),
      ],
      textures: [
        for (final texture
            in shader.uniformTextures ?? const <fb.ShaderUniformTexture>[])
          ShaderTextureInfo(
            name: texture.name ?? '',
            set: texture.$set,
            binding: texture.binding,
          ),
      ],
      source: ShaderSource(
        backend: backend,
        bytes: bytes == null ? Uint8List(0) : Uint8List.fromList(bytes),
      ),
    );
  }
}

/// Matches emplaced uniform buffers, by byte length, to the blocks a draw's
/// shaders declare. Returns one candidate list per length, in order.
///
/// An exact size match wins. The engine also binds a block's leading members
/// only (a `FrameInfo` written to 80 of its 128 bytes), so a shorter buffer
/// matches a block when its length lands on a member boundary, among the
/// blocks no other buffer already claimed; a buffer with one candidate claims
/// it, which narrows the rest until nothing changes. More than one candidate
/// left means the buffer cannot be named.
/// {@category Debugging and profiling}
List<List<ShaderUniformBlockInfo>> matchUniformBlocks(
  List<ShaderUniformBlockInfo> declared,
  List<int> lengths,
) {
  final result = <List<ShaderUniformBlockInfo>>[];
  final claimed = <ShaderUniformBlockInfo>{};
  for (final length in lengths) {
    final exact = [
      for (final block in declared)
        if (block.sizeBytes == length) block,
    ];
    result.add(exact);
    if (exact.length == 1) claimed.add(exact.single);
  }
  for (var i = 0; i < lengths.length; i++) {
    if (result[i].isNotEmpty) continue;
    final length = lengths[i];
    result[i] = [
      for (final block in declared)
        if (!claimed.contains(block) &&
            block.sizeBytes > length &&
            _endsOnMemberBoundary(block, length))
          block,
    ];
  }
  var changed = true;
  while (changed) {
    changed = false;
    for (final candidates in result) {
      if (candidates.length == 1) {
        if (claimed.add(candidates.single)) changed = true;
        continue;
      }
      final before = candidates.length;
      candidates.removeWhere(claimed.contains);
      if (candidates.length != before) changed = true;
    }
  }
  return result;
}

bool _endsOnMemberBoundary(ShaderUniformBlockInfo block, int length) {
  for (final field in block.fields) {
    final size = field.totalSizeBytes > 0
        ? field.totalSizeBytes
        : field.elementSizeBytes;
    if (field.offsetBytes + size == length) return true;
  }
  return false;
}

/// One uniform member's value, decoded from packed block bytes.
/// {@category Debugging and profiling}
final class ShaderUniformValue {
  const ShaderUniformValue({required this.field, required this.values});

  final ShaderUniformFieldInfo field;

  /// The scalars in declaration order (column-major for matrices, element
  /// after element for arrays). Empty when the bytes were too short.
  final List<num> values;

  String get name => field.name;

  Map<String, Object?> toJson() => {
    'name': field.name,
    'type': field.typeName,
    'values': values,
  };
}

/// Decodes [bytes], packed to [block]'s std140 layout, into one value per
/// member. Members past the end of [bytes] decode empty rather than failing,
/// so a short buffer still reports what it holds.
/// {@category Debugging and profiling}
List<ShaderUniformValue> decodeUniformBlock(
  ShaderUniformBlockInfo block,
  ByteData bytes,
) {
  final values = <ShaderUniformValue>[];
  for (final field in block.fields) {
    values.add(
      ShaderUniformValue(field: field, values: _decodeField(field, bytes)),
    );
  }
  return values;
}

List<num> _decodeField(ShaderUniformFieldInfo field, ByteData bytes) {
  final scalarSize = field.type.byteSize;
  if (scalarSize == 0) return const [];
  final elements = field.arrayElements > 0 ? field.arrayElements : 1;
  final elementStride = field.arrayElements > 0
      ? field.totalSizeBytes ~/ field.arrayElements
      : field.elementSizeBytes;
  final columns = field.columns > 0 ? field.columns : 1;
  final vecSize = field.vecSize > 0 ? field.vecSize : 1;
  final columnStride = columns > 1
      ? field.elementSizeBytes ~/ columns
      : vecSize * scalarSize;
  final out = <num>[];
  for (var e = 0; e < elements; e++) {
    for (var c = 0; c < columns; c++) {
      final base = field.offsetBytes + e * elementStride + c * columnStride;
      for (var i = 0; i < vecSize; i++) {
        final offset = base + i * scalarSize;
        if (offset + scalarSize > bytes.lengthInBytes) return out;
        out.add(_readScalar(bytes, offset, field.type));
      }
    }
  }
  return out;
}

num _readScalar(ByteData bytes, int offset, ShaderScalarType type) =>
    switch (type) {
      ShaderScalarType.float32 => bytes.getFloat32(offset, Endian.little),
      ShaderScalarType.float64 => bytes.getFloat64(offset, Endian.little),
      ShaderScalarType.float16 => _halfToDouble(
        bytes.getUint16(offset, Endian.little),
      ),
      ShaderScalarType.int32 => bytes.getInt32(offset, Endian.little),
      ShaderScalarType.uint32 => bytes.getUint32(offset, Endian.little),
      ShaderScalarType.int16 => bytes.getInt16(offset, Endian.little),
      ShaderScalarType.uint16 => bytes.getUint16(offset, Endian.little),
      ShaderScalarType.int8 => bytes.getInt8(offset),
      ShaderScalarType.uint8 ||
      ShaderScalarType.boolean => bytes.getUint8(offset),
      // 64-bit integers read as their low and high words combined in double
      // precision, which keeps the decode portable to dart2js.
      ShaderScalarType.int64 || ShaderScalarType.uint64 =>
        bytes.getUint32(offset, Endian.little) +
            bytes.getUint32(offset + 4, Endian.little) * 4294967296.0,
      _ => 0,
    };

double _halfToDouble(int bits) {
  final sign = (bits & 0x8000) != 0 ? -1.0 : 1.0;
  final exponent = (bits >> 10) & 0x1F;
  final mantissa = bits & 0x3FF;
  if (exponent == 0) return sign * mantissa * 5.960464477539063e-8;
  if (exponent == 0x1F) return mantissa == 0 ? sign / 0.0 : double.nan;
  return sign * (1 + mantissa / 1024) * _pow2(exponent - 15);
}

double _pow2(int e) {
  var result = 1.0;
  if (e >= 0) {
    for (var i = 0; i < e; i++) {
      result *= 2;
    }
  } else {
    for (var i = 0; i < -e; i++) {
      result /= 2;
    }
  }
  return result;
}

/// Reflection over the shader libraries the engine has loaded.
///
/// A library's bundle is parsed once, the first time it is asked for, from
/// the asset or bytes it was loaded from; the parse is cached for the
/// library's lifetime. Shader objects are mapped back to their entry names
/// so a material's shader can be described.
/// {@category Debugging and profiling}
abstract final class ShaderReflection {
  static final Expando<_CachedBundle> _bundles = Expando<_CachedBundle>(
    'shaderBundleInfo',
  );
  static final Expando<_ShaderIdentity> _identities = Expando<_ShaderIdentity>(
    'shaderIdentity',
  );
  static final Expando<Future<ShaderBundleInfo?>> _pending =
      Expando<Future<ShaderBundleInfo?>>('shaderBundleLoad');

  /// The parsed bundle for [library] once [loadBundleInfo] has completed,
  /// else null.
  static ShaderBundleInfo? bundleInfoFor(gpu.ShaderLibrary library) {
    final cached = _bundles[library];
    if (cached == null || cached.isStale(library)) return null;
    return cached.info;
  }

  /// Parses [library]'s bundle (once) and maps its shader objects to their
  /// entry names. Null when the library's source is unknown (it was not
  /// loaded through the engine's loaders) or the asset cannot be read.
  static Future<ShaderBundleInfo?> loadBundleInfo(
    gpu.ShaderLibrary library, {
    AssetBundle? bundle,
  }) {
    final cached = bundleInfoFor(library);
    if (cached != null) return Future.value(cached);
    final pending = _pending[library];
    if (pending != null) return pending;
    final future = _load(library, bundle ?? rootBundle).whenComplete(() {
      _pending[library] = null;
    });
    _pending[library] = future;
    return future;
  }

  static Future<ShaderBundleInfo?> _load(
    gpu.ShaderLibrary library,
    AssetBundle assetBundle,
  ) async {
    final source = shaderLibrarySourceOf(library);
    if (source == null) return null;
    Uint8List bytes;
    final raw = source.bytes;
    if (raw != null) {
      bytes = raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes);
    } else {
      final data = await assetBundle.load(source.assetKey!);
      bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    }
    final info = ShaderBundleInfo.parse(bytes);
    _bundles[library] = _CachedBundle(info, source);
    for (final shader in info.shaders) {
      final object = library[shader.name];
      if (object != null) {
        _identities[object] = _ShaderIdentity(library, shader.name);
      }
    }
    return info;
  }

  /// Loads bundle info for every library the engine has loaded so far, so
  /// every shader object maps to its name. Libraries whose bundle cannot be
  /// read are skipped.
  static Future<List<ShaderBundleInfo>> loadAll({AssetBundle? bundle}) async {
    final result = <ShaderBundleInfo>[];
    for (final library in knownShaderLibraries()) {
      if (library is! gpu.ShaderLibrary) continue;
      try {
        final info = await loadBundleInfo(library, bundle: bundle);
        if (info != null) result.add(info);
      } catch (_) {
        // A library whose asset is gone (a hot reload that failed) is not a
        // reason to fail the rest.
      }
    }
    return result;
  }

  /// Forgets the parse for [library], so the next [loadBundleInfo] re-reads
  /// it (after a hot reload rewrote the bundle).
  static void invalidate(gpu.ShaderLibrary library) {
    _bundles[library] = null;
    _pending[library] = null;
  }

  /// The bundle entry name of [shader], or null before its library's bundle
  /// info has loaded.
  static String? nameOf(gpu.Shader shader) => _identities[shader]?.name;

  /// The library [shader] came from, or null before its bundle info loaded.
  static gpu.ShaderLibrary? libraryOf(gpu.Shader shader) =>
      _identities[shader]?.library;

  /// Reflection for [shader], or null before its library's bundle info
  /// loaded.
  static ShaderInfo? infoFor(gpu.Shader shader) {
    final identity = _identities[shader];
    if (identity == null) return null;
    return bundleInfoFor(identity.library)?[identity.name];
  }

  /// The compiled output of [shader] for [backend] (the running platform's
  /// by default), or null when unavailable.
  static ShaderSource? sourceOf(gpu.Shader shader, {ShaderBackend? backend}) {
    final info = infoFor(shader);
    if (info == null) return null;
    final backendInfo = backend == null ? info.current : info.backends[backend];
    return backendInfo?.source;
  }
}

final class _ShaderIdentity {
  const _ShaderIdentity(this.library, this.name);

  final gpu.ShaderLibrary library;
  final String name;
}

/// A parse plus what it was parsed from, so an in-place bundle reload (new
/// bytes registered, or the asset's generation bumped) reads as stale.
final class _CachedBundle {
  _CachedBundle(this.info, this.source)
    : generation = source.assetKey == null
          ? 0
          : shaderLibraryGeneration(source.assetKey!);

  final ShaderBundleInfo info;
  final ShaderLibrarySource source;
  final int generation;

  bool isStale(gpu.ShaderLibrary library) {
    final current = shaderLibrarySourceOf(library);
    if (current == null) return true;
    if (!identical(current, source)) return true;
    final key = source.assetKey;
    return key != null && shaderLibraryGeneration(key) != generation;
  }
}
