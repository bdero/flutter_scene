/// Where each loaded shader library came from, so the reflection layer can
/// re-read the bundle bytes on demand. Every backend's library loader
/// registers here; nothing else in the shim depends on it.
library;

import 'dart:typed_data';

/// The asset key or the raw bytes a shader library was loaded from.
final class ShaderLibrarySource {
  const ShaderLibrarySource({this.assetKey, this.bytes})
    : assert(assetKey != null || bytes != null);

  final String? assetKey;
  final ByteData? bytes;
}

final Expando<ShaderLibrarySource> _sources = Expando<ShaderLibrarySource>(
  'shaderLibrarySource',
);
final List<WeakReference<Object>> _known = [];

/// Records that [library] was loaded from [source]. Keyed by identity, so a
/// cached library reloaded under the same key keeps its entry.
void registerShaderLibrarySource(Object library, ShaderLibrarySource source) {
  if (_sources[library] == null) _known.add(WeakReference(library));
  _sources[library] = source;
}

/// Every registered library still alive, in registration order.
List<Object> knownShaderLibraries() {
  _known.removeWhere((ref) => ref.target == null);
  return [for (final ref in _known) ref.target!];
}

/// The source [library] was loaded from, or null for a library the shim did
/// not load (an inline-compiled web library, for instance).
ShaderLibrarySource? shaderLibrarySourceOf(Object library) => _sources[library];

final Map<String, int> _generations = {};

/// How many times the bundle at [assetKey] has been reloaded in place. A
/// reader caching a parse of it re-reads when this changes.
int shaderLibraryGeneration(String assetKey) => _generations[assetKey] ?? 0;

/// Records an in-place reload of the bundle at [assetKey].
void bumpShaderLibraryGeneration(String assetKey) {
  _generations[assetKey] = shaderLibraryGeneration(assetKey) + 1;
}
