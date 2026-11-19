/// Makes write-only storage buffers read-write in SPIR-V, before the WGSL
/// translation.
///
/// WGSL has no write-only storage buffer, so Tint refuses a GLSL `writeonly`
/// buffer outright. Dropping the `NonReadable` decoration only widens access,
/// which leaves what the shader does unchanged.
///
/// Binary layout per the SPIR-V specification, section 2.3 (Physical Layout
/// of a SPIR-V Module and Instruction); `NonReadable` is decoration 25
/// (section 3.20).
library;

import 'dart:typed_data';

const int _opDecorate = 71;
const int _opMemberDecorate = 72;
const int _decorationNonReadable = 25;

/// Returns [spirv] (little-endian words) without its `NonReadable`
/// decorations, or [spirv] itself when it has none.
Uint8List dropNonReadable(Uint8List spirv) {
  if (spirv.length < 20 || spirv.length % 4 != 0) return spirv;
  final words = Uint32List.sublistView(
    spirv.offsetInBytes % 4 == 0 ? spirv : Uint8List.fromList(spirv),
  );
  if (words[0] != 0x07230203) return spirv;

  final kept = <int>[...words.sublist(0, 5)];
  var dropped = false;
  for (var i = 5; i < words.length;) {
    final count = words[i] >> 16;
    if (count == 0 || i + count > words.length) return spirv;
    final opcode = words[i] & 0xffff;
    final nonReadable = switch (opcode) {
      _opDecorate => count >= 3 && words[i + 2] == _decorationNonReadable,
      _opMemberDecorate => count >= 4 && words[i + 3] == _decorationNonReadable,
      _ => false,
    };
    if (nonReadable) {
      dropped = true;
    } else {
      kept.addAll(words.sublist(i, i + count));
    }
    i += count;
  }
  if (!dropped) return spirv;
  return Uint32List.fromList(kept).buffer.asUint8List();
}
