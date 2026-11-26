import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

final class _StatedBytes implements Finalizable {
  _StatedBytes(this.bytes);

  final int bytes;
}

// Frees the null token, so it does nothing but carry the external size.
final NativeFinalizer _finalizer = NativeFinalizer(malloc.nativeFree);
final Expando<_StatedBytes> _stated = Expando();

/// Tells the VM that [owner] keeps [bytes] of GPU memory alive, so the
/// collector runs as GPU memory piles up in unreachable owners. The VM forgets
/// the bytes when [owner] is collected.
@internal
void statesExternalBytes(Object owner, int bytes) {
  if (bytes <= 0 || _stated[owner] != null) return;
  final stated = _stated[owner] = _StatedBytes(bytes);
  // Only a finalizer attachment can state external size; nullptr frees nothing.
  // TODO(gpu-release): detach once GpuHost.releaseTexture frees native memory.
  // It frees nothing yet, so the bytes rightly stay stated until collection.
  _finalizer.attach(stated, nullptr, externalSize: bytes);
}

/// The bytes [statesExternalBytes] stated for [owner], or 0.
@visibleForTesting
int debugStatedExternalBytes(Object owner) => _stated[owner]?.bytes ?? 0;
