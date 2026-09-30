/// Shared by the native `buildTextures` and its web/wasm stub.
library;

/// How `buildTextures` stores a cooked texture.
///
/// {@category Assets and loading}
final class TextureEncoding {
  const TextureEncoding._(this._etc1s, this.quality);

  /// The engine's own `.fstex` block format, the default and the better
  /// quality of the two.
  static const TextureEncoding universal = TextureEncoding._(false, 0);

  /// Standard ETC1S KTX2 (what `basisu -ktx2` writes), several times smaller
  /// than [universal]. Each 4x4 block holds one hue, so color detail blurs;
  /// prefer [universal] for normal maps.
  ///
  /// [quality] runs from 1 (smallest) to 255 (best), as `basisu -q`.
  /// Encoding is single-threaded and slow for large images, around 5 s for a
  /// 2048x2048 texture, though a build does it once per source change.
  const TextureEncoding.etc1s({int quality = 128})
    : assert(quality >= 1 && quality <= 255, 'quality runs from 1 to 255'),
      _etc1s = true,
      quality = quality;

  final bool _etc1s;

  /// The ETC1S quality level, or 0 for [universal].
  final int quality;

  @override
  bool operator ==(Object other) =>
      other is TextureEncoding &&
      other._etc1s == _etc1s &&
      other.quality == quality;

  @override
  int get hashCode => Object.hash(_etc1s, quality);

  @override
  String toString() => _etc1s
      ? 'TextureEncoding.etc1s(quality: $quality)'
      : 'TextureEncoding.universal';
}

/// What `buildTextures` needs from a [TextureEncoding]. Not exported.
extension TextureEncodingDetails on TextureEncoding {
  /// Whether this is the ETC1S encoding.
  bool get isEtc1s => _etc1s;

  /// The cooked file's extension.
  String get fileExtension => _etc1s ? '.ktx2' : '.fstex';
}
