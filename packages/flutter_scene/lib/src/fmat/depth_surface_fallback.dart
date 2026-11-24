// What a build does when a material's own depth passes fail to compile.

/// The materials whose own depth passes [error] blames, from
/// [depthSurfaceOwners] (depth-pass entry name to material entry name), or
/// null when it names any other entry or none.
///
/// A material without its own depth passes still draws, through the
/// engine's, so a build drops a failing material's depth passes rather than
/// failing. A cutout then casts and writes depth as solid geometry.
Set<String>? materialsFailingOnlyInDepthPasses(
  Object error,
  Map<String, String> depthSurfaceOwners,
  Set<String> entryNames,
) {
  final text = '$error';
  final named = {
    for (final m in RegExp(r'"(\w+)"').allMatches(text)) m.group(1)!,
    for (final m in RegExp(r'^\s*(\w+):', multiLine: true).allMatches(text))
      m.group(1)!,
  }.intersection(entryNames);
  if (named.isEmpty || !named.every(depthSurfaceOwners.containsKey)) {
    return null;
  }
  return {for (final entry in named) depthSurfaceOwners[entry]!};
}

/// [sidecar] without the depth-pass entries, so the runtime keeps the
/// engine's depth shaders for the material.
Map<String, Object?> withoutDepthSurfaces(Map<String, Object?> sidecar) =>
    Map.of(sidecar)..remove('depth_surface');
