/// Per-draw binding tables and unboxed integer-tuple caches for render-pass
/// encoding.
///
/// A WebGPU pass clears and re-populates its bindings before every draw, and
/// looks up its bind group from the bound buffer/texture IDs and sampler keys.
/// Keeping the binding slots epoch-stamped in flat arrays makes `clearBindings`
/// O(1), and keying bind groups by unboxed `Uint32List` words avoids boxing
/// integers or allocating temporary lists per draw.
///
/// Pure Dart, so it is testable without a browser.
library;

import 'dart:typed_data';

/// Epoch-stamped per-binding storage for one render pass.
///
/// Positive epochs (`+_epoch`) mark an explicit bind to that stage's binding;
/// negative epochs (`-_epoch`) mark a cross-stage mirror bind that yields to an
/// explicit bind in the same draw epoch. Calling [clear] advances the epoch in
/// O(1) without touching the backing arrays.
final class PassBindingTable<
  B extends Object,
  T extends Object,
  S extends Object
> {
  PassBindingTable({
    int initialBindingCapacity = 128,
    int initialVertexSlots = 8,
  }) : _uniformBuffers = List<Object?>.filled(initialBindingCapacity, null),
       _uniformOffsets = Int32List(initialBindingCapacity),
       _uniformLengths = Int32List(initialBindingCapacity),
       _uniformEpochs = Int32List(initialBindingCapacity),
       _textures = List<Object?>.filled(initialBindingCapacity, null),
       _samplers = List<Object?>.filled(initialBindingCapacity, null),
       _textureEpochs = Int32List(initialBindingCapacity),
       _vertexBuffers = List<Object?>.filled(initialVertexSlots, null),
       _vertexOffsets = Int32List(initialVertexSlots),
       _vertexEpochs = Int32List(initialVertexSlots);

  static const int _maxEpoch = 0x3fffffff;

  int _epoch = 1;

  List<Object?> _uniformBuffers;
  Int32List _uniformOffsets;
  Int32List _uniformLengths;
  Int32List _uniformEpochs;

  List<Object?> _textures;
  List<Object?> _samplers;
  Int32List _textureEpochs;

  List<Object?> _vertexBuffers;
  Int32List _vertexOffsets;
  Int32List _vertexEpochs;

  /// Clears every uniform, texture, and vertex-buffer binding in O(1).
  void clear() {
    if (_epoch >= _maxEpoch) {
      _uniformEpochs.fillRange(0, _uniformEpochs.length, 0);
      _textureEpochs.fillRange(0, _textureEpochs.length, 0);
      _vertexEpochs.fillRange(0, _vertexEpochs.length, 0);
      _epoch = 1;
      return;
    }
    _epoch++;
  }

  /// Binds a uniform range at [binding]. When [explicit] is false, an existing
  /// explicit bind in the current epoch is preserved.
  void bindUniform(
    int binding,
    B buffer,
    int offset,
    int length, {
    required bool explicit,
  }) {
    if (binding >= _uniformEpochs.length) {
      _growUniforms(binding + 1);
    }
    if (!explicit && _uniformEpochs[binding] == _epoch) return;
    _uniformBuffers[binding] = buffer;
    _uniformOffsets[binding] = offset;
    _uniformLengths[binding] = length;
    _uniformEpochs[binding] = explicit ? _epoch : -_epoch;
  }

  bool hasUniform(int binding) {
    if (binding < 0 || binding >= _uniformEpochs.length) return false;
    final e = _uniformEpochs[binding];
    return e == _epoch || e == -_epoch;
  }

  B uniformBuffer(int binding) => _uniformBuffers[binding]! as B;

  int uniformOffset(int binding) => _uniformOffsets[binding];

  int uniformLength(int binding) => _uniformLengths[binding];

  /// Binds [texture] and [sampler] at [binding]. When [explicit] is false, an
  /// existing explicit bind in the current epoch is preserved.
  void bindTexture(
    int binding,
    T texture,
    S? sampler, {
    required bool explicit,
  }) {
    if (binding >= _textureEpochs.length) {
      _growTextures(binding + 1);
    }
    if (!explicit && _textureEpochs[binding] == _epoch) return;
    _textures[binding] = texture;
    _samplers[binding] = sampler;
    _textureEpochs[binding] = explicit ? _epoch : -_epoch;
  }

  bool hasTexture(int binding) {
    if (binding < 0 || binding >= _textureEpochs.length) return false;
    final e = _textureEpochs[binding];
    return e == _epoch || e == -_epoch;
  }

  T texture(int binding) => _textures[binding]! as T;

  S? sampler(int binding) => _samplers[binding] as S?;

  /// Binds a vertex [buffer] at [offset] to [slot].
  void bindVertexBuffer(int slot, B buffer, int offset) {
    if (slot >= _vertexEpochs.length) {
      _growVertexSlots(slot + 1);
    }
    _vertexBuffers[slot] = buffer;
    _vertexOffsets[slot] = offset;
    _vertexEpochs[slot] = _epoch;
  }

  bool hasVertexBuffer(int slot) =>
      slot >= 0 && slot < _vertexEpochs.length && _vertexEpochs[slot] == _epoch;

  B vertexBuffer(int slot) => _vertexBuffers[slot]! as B;

  int vertexOffset(int slot) => _vertexOffsets[slot];

  void _growUniforms(int minLength) {
    var next = _uniformEpochs.length;
    while (next < minLength) {
      next *= 2;
    }
    final buffers = List<Object?>.filled(next, null)
      ..setRange(0, _uniformBuffers.length, _uniformBuffers);
    final offsets = Int32List(next)
      ..setRange(0, _uniformOffsets.length, _uniformOffsets);
    final lengths = Int32List(next)
      ..setRange(0, _uniformLengths.length, _uniformLengths);
    final epochs = Int32List(next)
      ..setRange(0, _uniformEpochs.length, _uniformEpochs);
    _uniformBuffers = buffers;
    _uniformOffsets = offsets;
    _uniformLengths = lengths;
    _uniformEpochs = epochs;
  }

  void _growTextures(int minLength) {
    var next = _textureEpochs.length;
    while (next < minLength) {
      next *= 2;
    }
    final textures = List<Object?>.filled(next, null)
      ..setRange(0, _textures.length, _textures);
    final samplers = List<Object?>.filled(next, null)
      ..setRange(0, _samplers.length, _samplers);
    final epochs = Int32List(next)
      ..setRange(0, _textureEpochs.length, _textureEpochs);
    _textures = textures;
    _samplers = samplers;
    _textureEpochs = epochs;
  }

  void _growVertexSlots(int minLength) {
    var next = _vertexEpochs.length;
    while (next < minLength) {
      next *= 2;
    }
    final buffers = List<Object?>.filled(next, null)
      ..setRange(0, _vertexBuffers.length, _vertexBuffers);
    final offsets = Int32List(next)
      ..setRange(0, _vertexOffsets.length, _vertexOffsets);
    final epochs = Int32List(next)
      ..setRange(0, _vertexEpochs.length, _vertexEpochs);
    _vertexBuffers = buffers;
    _vertexOffsets = offsets;
    _vertexEpochs = epochs;
  }
}

final Uint32List _emptyTuple = Uint32List(0);

final class _TupleKey {
  _TupleKey.empty() : words = _emptyTuple, length = 0, hashCode = 0;

  _TupleKey.owned(this.words)
    : length = words.length,
      hashCode = _hashWords(words, words.length);

  Uint32List words;
  int length;

  @override
  int hashCode;

  void bind(Uint32List scratch, int count) {
    words = scratch;
    length = count;
    hashCode = _hashWords(scratch, count);
  }

  void release() {
    words = _emptyTuple;
    length = 0;
  }

  /// 29-bit Jenkins hash using positive Smi masks so VM, dart2wasm, and
  /// dart2js (53-bit numbers, signed 32-bit shifts) hash identically.
  static int _hashWords(Uint32List words, int length) {
    var hash = 0;
    for (var i = 0; i < length; i++) {
      hash = 0x1fffffff & (hash + words[i]);
      hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
      hash ^= hash >> 6;
    }
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    hash ^= hash >> 11;
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! _TupleKey ||
        other.hashCode != hashCode ||
        other.length != length) {
      return false;
    }
    final a = words;
    final b = other.words;
    for (var i = 0; i < length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

final class _CachedTuple<V extends Object> {
  _CachedTuple(this.words, this.value);

  final Uint32List words;
  final V value;
}

/// Maps fixed- or variable-length `uint32` tuples to cached GPU objects with
/// zero heap allocations on both MRU hits and hash-table hits.
final class IntTupleCache<V extends Object> {
  IntTupleCache({this.maxEntries = 1024});

  final int maxEntries;
  final Map<_TupleKey, _CachedTuple<V>> _entries = {};
  final _TupleKey _probe = _TupleKey.empty();

  Uint32List? _mruWords;
  V? _mruValue;

  int get length => _entries.length;

  void clear() {
    _entries.clear();
    _mruWords = null;
    _mruValue = null;
  }

  /// Returns the cached value for the first [length] words of [scratch], or
  /// null on miss, without allocating.
  V? lookup(Uint32List scratch, int length) {
    final mru = _mruValue;
    final mruWords = _mruWords;
    if (mru != null && mruWords != null && mruWords.length == length) {
      var same = true;
      for (var i = 0; i < length; i++) {
        if (mruWords[i] != scratch[i]) {
          same = false;
          break;
        }
      }
      if (same) return mru;
    }
    _probe.bind(scratch, length);
    final hit = _entries[_probe];
    _probe.release();
    if (hit == null) return null;
    _mruWords = hit.words;
    _mruValue = hit.value;
    return hit.value;
  }

  /// Inserts [value] under an owned copy of the first [length] words of
  /// [scratch], clearing the cache first when [maxEntries] is reached.
  V put(Uint32List scratch, int length, V value) {
    if (_entries.length >= maxEntries) {
      clear();
    }
    final copy = Uint32List(length)..setRange(0, length, scratch);
    final key = _TupleKey.owned(copy);
    _entries[key] = _CachedTuple(copy, value);
    _mruWords = copy;
    _mruValue = value;
    return value;
  }
}
