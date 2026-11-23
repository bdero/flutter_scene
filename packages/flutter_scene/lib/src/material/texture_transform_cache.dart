import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/material/physically_based_material.dart'
    show TextureTransform;

/// Packs one `TextureTransform` record (8 floats, 32 bytes) into [target]
/// at float index [offset].
@internal
void packTextureTransformRecord(
  Float32List target,
  int offset,
  TextureTransform transform,
  int texCoord,
) {
  target[offset] = transform.offset.x;
  target[offset + 1] = transform.offset.y;
  target[offset + 2] = transform.scale.x;
  target[offset + 3] = transform.scale.y;
  target[offset + 4] = math.cos(transform.rotation);
  target[offset + 5] = math.sin(transform.rotation);
  target[offset + 6] = texCoord.clamp(0, 1).toDouble();
  target[offset + 7] = 0.0;
}

/// A material's packed texture-transform uniform block, repacked only when a
/// transform is replaced or mutated in place.
@internal
final class TextureTransformCache {
  TextureTransformCache.single() : this._(1);
  TextureTransformCache.standardFive() : this._(5);

  TextureTransformCache._(this.slotCount)
    : _floats = Float32List(slotCount * 8),
      _identities = List<TextureTransform?>.filled(slotCount, null),
      _scalars = Float64List(slotCount * 5)
        ..fillRange(0, slotCount * 5, double.nan),
      _texCoords = Int32List(slotCount)..fillRange(0, slotCount, -1) {
    bytes = ByteData.sublistView(_floats);
  }

  final int slotCount;
  final Float32List _floats;
  late final ByteData bytes;
  final List<TextureTransform?> _identities;
  final Float64List _scalars;
  final Int32List _texCoords;

  /// Repacks so far.
  @visibleForTesting
  int packCount = 0;

  bool _isSlotUpToDate(int slot, TextureTransform transform, int texCoord) {
    if (!identical(_identities[slot], transform) ||
        _texCoords[slot] != texCoord) {
      return false;
    }
    final base = slot * 5;
    final offset = transform.offset;
    final scale = transform.scale;
    return _scalars[base] == offset.x &&
        _scalars[base + 1] == offset.y &&
        _scalars[base + 2] == scale.x &&
        _scalars[base + 3] == scale.y &&
        _scalars[base + 4] == transform.rotation;
  }

  void _packAndSnapshotSlot(
    int slot,
    TextureTransform transform,
    int texCoord,
  ) {
    packTextureTransformRecord(_floats, slot * 8, transform, texCoord);
    _identities[slot] = transform;
    _texCoords[slot] = texCoord;
    final base = slot * 5;
    final offset = transform.offset;
    final scale = transform.scale;
    _scalars
      ..[base] = offset.x
      ..[base + 1] = offset.y
      ..[base + 2] = scale.x
      ..[base + 3] = scale.y
      ..[base + 4] = transform.rotation;
  }

  /// Returns an up-to-date 32-byte view for a single-slot transform block.
  ByteData packSingle(TextureTransform t0, int uv0) {
    assert(slotCount == 1);
    if (_isSlotUpToDate(0, t0, uv0)) return bytes;
    _packAndSnapshotSlot(0, t0, uv0);
    packCount++;
    return bytes;
  }

  /// Returns an up-to-date 160-byte view for the standard 5-slot PBR block,
  /// setting float `[7]` when any slot transforms UVs or selects UV set 1.
  ByteData packFive(
    TextureTransform t0,
    int uv0,
    TextureTransform t1,
    int uv1,
    TextureTransform t2,
    int uv2,
    TextureTransform t3,
    int uv3,
    TextureTransform t4,
    int uv4,
  ) {
    assert(slotCount == 5);
    if (_isSlotUpToDate(0, t0, uv0) &&
        _isSlotUpToDate(1, t1, uv1) &&
        _isSlotUpToDate(2, t2, uv2) &&
        _isSlotUpToDate(3, t3, uv3) &&
        _isSlotUpToDate(4, t4, uv4)) {
      return bytes;
    }
    _packAndSnapshotSlot(0, t0, uv0);
    _packAndSnapshotSlot(1, t1, uv1);
    _packAndSnapshotSlot(2, t2, uv2);
    _packAndSnapshotSlot(3, t3, uv3);
    _packAndSnapshotSlot(4, t4, uv4);
    // The base record's padding float carries one flag the shader branches on
    // to skip the five UV-transform evaluations, set when any record
    // transforms its UVs or selects UV set 1. The identity transform
    // reproduces the raw UV bit-exactly, so the flag only gates work.
    final transformedUvs =
        !t0.isIdentity ||
        !t1.isIdentity ||
        !t2.isIdentity ||
        !t3.isIdentity ||
        !t4.isIdentity ||
        uv0.clamp(0, 1) != 0 ||
        uv1.clamp(0, 1) != 0 ||
        uv2.clamp(0, 1) != 0 ||
        uv3.clamp(0, 1) != 0 ||
        uv4.clamp(0, 1) != 0;
    _floats[7] = transformedUvs ? 1.0 : 0.0;
    packCount++;
    return bytes;
  }
}
