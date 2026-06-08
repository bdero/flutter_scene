/// Identity for the `.fscene` document model.
///
/// A document carries one global [DocumentId] (128-bit, minted once) plus
/// compact, document-scoped [LocalId]s for its nodes, resources, skins,
/// animations, and payloads. A cross-document reference is the
/// `(DocumentId, LocalId)` pair; within a document the [DocumentId] is
/// implicit and only the [LocalId] is stored. Ids are stored, never derived
/// from names or paths, so a rename or reparent never changes an id.
///
/// The representation is web-safe: ids are kept in 8-bit and 32-bit pieces
/// and never rely on 64-bit integer arithmetic (which `dart2js` cannot do
/// losslessly).
library;

import 'dart:math';
import 'dart:typed_data';

/// The Crockford base32 alphabet (no `I`, `L`, `O`, `U`), used for the
/// case-insensitive, dictatable text form of ids.
const String _base32Alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// Encodes [bytes] as an unpadded Crockford base32 string, most significant
/// bit first. Stays web-safe by never accumulating more than ~13 bits.
String encodeBase32(Uint8List bytes) {
  final out = StringBuffer();
  var buffer = 0;
  var bitsLeft = 0;
  for (final b in bytes) {
    buffer = (buffer << 8) | b;
    bitsLeft += 8;
    while (bitsLeft >= 5) {
      bitsLeft -= 5;
      out.write(_base32Alphabet[(buffer >> bitsLeft) & 0x1F]);
    }
    // Drop the bits already emitted so `buffer` stays small.
    buffer &= (1 << bitsLeft) - 1;
  }
  if (bitsLeft > 0) {
    out.write(_base32Alphabet[(buffer << (5 - bitsLeft)) & 0x1F]);
  }
  return out.toString();
}

// A uniformly random 32-bit value, assembled from two 16-bit draws to stay
// within `Random.nextInt`'s range and web-safe integer bounds.
int _random32(Random random) =>
    (random.nextInt(0x10000) << 16) | random.nextInt(0x10000);

/// A 128-bit document identifier, minted once when a document is created.
///
/// Stored as 16 bytes; the text form is Crockford base32. The high bits are
/// stamped UUIDv4 (random) so the id is a well-formed UUID, but the bytes are
/// the identity, not the UUID fields.
class DocumentId {
  /// Wraps the given 16 [bytes].
  DocumentId(this.bytes)
    : assert(bytes.length == 16, 'A DocumentId is 16 bytes');

  /// The 16 identity bytes.
  final Uint8List bytes;

  /// Mints a new random document id (UUIDv4 layout). Pass a seeded [random]
  /// for deterministic tests; the default is cryptographically random.
  factory DocumentId.generate([Random? random]) {
    final rng = random ?? Random.secure();
    final b = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      b[i] = rng.nextInt(0x100);
    }
    b[6] = (b[6] & 0x0F) | 0x40; // version 4
    b[8] = (b[8] & 0x3F) | 0x80; // variant 1
    return DocumentId(b);
  }

  /// The canonical text form: 26-character Crockford base32.
  String toToken() => encodeBase32(bytes);

  @override
  bool operator ==(Object other) {
    if (other is! DocumentId) return false;
    for (var i = 0; i < 16; i++) {
      if (bytes[i] != other.bytes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(bytes);

  @override
  String toString() => 'DocumentId(${toToken()})';
}

/// A compact, document-scoped identifier for a node, resource, skin,
/// animation, or payload.
///
/// A local id is a `(session, index)` pair: [session] is the 32-bit random
/// salt of the [IdAllocator] that minted it, and [index] is that allocator's
/// monotonic counter. The salt makes ids minted on different machines or
/// branches collision-free without a coordinator (a merge is a set union, no
/// renumbering); the counter is never reused. Both halves are 32-bit, so the
/// pair is web-safe and a fast map key.
class LocalId {
  /// Wraps an explicit [session] salt and [index] counter. Prefer
  /// [IdAllocator.mint] to allocate fresh ids.
  const LocalId(this.session, this.index);

  /// The 32-bit session salt of the minting allocator.
  final int session;

  /// The monotonic counter within that session.
  final int index;

  /// The canonical text token: Crockford base32 of the 8 id bytes (the
  /// big-endian [session] followed by the big-endian [index]).
  String toToken() {
    final b = Uint8List(8);
    ByteData.view(b.buffer)
      ..setUint32(0, session, Endian.big)
      ..setUint32(4, index, Endian.big);
    return encodeBase32(b);
  }

  @override
  bool operator ==(Object other) =>
      other is LocalId && other.session == session && other.index == index;

  @override
  int get hashCode => Object.hash(session, index);

  @override
  String toString() => 'LocalId(${toToken()})';
}

/// Mints fresh [LocalId]s for one editing session of a document.
///
/// Each allocator draws one random 32-bit [session] salt and hands out
/// monotonically increasing indices, so every id it mints is unique and
/// never reused. Continuing to edit a loaded document uses a new allocator
/// with a new session salt (pass [excludedSessions] to guarantee it differs
/// from sessions already present in the document), so newly minted ids never
/// collide with existing ones.
class IdAllocator {
  /// Creates an allocator. Pass an explicit [session] to resume a known
  /// session, or [excludedSessions] (the salts already used in a loaded
  /// document) to draw a fresh salt that avoids them. [random] is seedable
  /// for deterministic tests.
  IdAllocator({int? session, Set<int>? excludedSessions, Random? random})
    : session =
          session ?? _drawSession(random ?? Random.secure(), excludedSessions);

  static int _drawSession(Random random, Set<int>? excluded) {
    var s = _random32(random);
    if (excluded != null) {
      while (excluded.contains(s)) {
        s = _random32(random);
      }
    }
    return s;
  }

  /// This allocator's 32-bit session salt; every minted id carries it.
  final int session;

  int _nextIndex = 0;

  /// Mints the next unique [LocalId] for this session.
  LocalId mint() => LocalId(session, _nextIndex++);
}
