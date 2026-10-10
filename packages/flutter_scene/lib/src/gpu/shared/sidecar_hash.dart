/// The hash a WGSL sidecar records for the bundle it was built with, checked
/// at load so a stale sidecar is never paired with a newer bundle.
///
/// FNV-1a, 32-bit (http://www.isthe.com/chongo/tech/comp/fnv/), because the
/// build hook computes it on the VM and the WebGPU backend in the browser: the
/// multiply is split into 16-bit halves so no intermediate passes 2^53, which
/// keeps dart2js, dart2wasm, and the VM in agreement.
library;

/// The 8-hex-digit FNV-1a hash of [bytes].
String sidecarBundleHash(List<int> bytes) {
  const prime = 16777619;
  var hash = 0x811c9dc5;
  for (final byte in bytes) {
    hash = (hash ^ byte) & 0xffffffff;
    final low = (hash & 0xffff) * prime;
    final high = (((hash >> 16) * prime) & 0xffff) << 16;
    hash = (low + high) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
