import 'package:flutter/services.dart';

/// An [AssetBundle] that can report a cheap content fingerprint for a key
/// (mtime plus size for a file-backed key), letting the hot-reload scan skip
/// reading and hashing large assets each pass (a bistro-scale payload
/// sidecar costs seconds to hash). Null falls back to the bytes hash.
abstract interface class FingerprintedAssetBundle implements AssetBundle {
  int? fingerprintFor(String key);
}
