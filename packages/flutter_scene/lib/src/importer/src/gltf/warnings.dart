/// A non-fatal issue noticed while importing a glTF/GLB asset, for example an
/// unrecognized `extensionsUsed` entry or an image that failed to resolve.
/// Delivered to a caller-supplied [GltfWarningCallback] when one is given to
/// the importer, or printed otherwise.
/// {@category Assets and loading}
class GltfImportWarning {
  const GltfImportWarning(this.message);

  /// Human-readable description of the issue.
  final String message;

  @override
  String toString() => message;
}

/// Receives non-fatal issues noticed during a glTF/GLB import.
/// {@category Assets and loading}
typedef GltfWarningCallback = void Function(GltfImportWarning warning);
