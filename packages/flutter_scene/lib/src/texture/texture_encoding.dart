/// Shared by the native `buildTextures` and its web/wasm stub.
library;

/// How `buildTextures` stores a cooked texture.
///
/// {@category Assets and loading}
final class TextureEncoding {
  const TextureEncoding._(this.name, this.extension, this.quality);

  /// The engine's own `.fstex` block format, the default and the better
  /// quality of the two.
  static const TextureEncoding universal = TextureEncoding._(
    'universal',
    '.fstex',
    0,
  );

  /// Standard ETC1S KTX2 (what `basisu -ktx2` writes), typically a fifth of
  /// the size of [universal]. Each 4x4 block holds one hue, so color detail
  /// blurs; prefer [universal] for normal maps.
  ///
  /// [quality] runs from 1 (smallest) to 255 (best), as `basisu -q`.
  const TextureEncoding.etc1s({int quality = 128})
    : assert(quality >= 1 && quality <= 255, 'quality runs from 1 to 255'),
      name = 'etc1s',
      extension = '.ktx2',
      quality = quality;

  /// Identifies the encoding in build stamps.
  final String name;

  /// The cooked file's extension.
  final String extension;

  /// The ETC1S quality level, or 0 for [universal].
  final int quality;

  /// Whether this is the ETC1S encoding.
  bool get isEtc1s => name == 'etc1s';

  @override
  bool operator ==(Object other) =>
      other is TextureEncoding &&
      other.name == name &&
      other.quality == quality;

  @override
  int get hashCode => Object.hash(name, quality);

  @override
  String toString() => isEtc1s
      ? 'TextureEncoding.etc1s(quality: $quality)'
      : 'TextureEncoding.universal';
}
