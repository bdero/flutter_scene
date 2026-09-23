/// What this build of the editor speaks.
///
/// A client compiled against one engine talks to another, so it has to be
/// able to ask rather than assume. The version says what shape the verbs
/// have; the capabilities say which optional ones are here. A client that
/// finds a capability missing degrades instead of failing at the first
/// unknown verb.
library;

/// The protocol's version and capability set.
abstract final class EditorProtocol {
  /// Bumped when a verb changes shape in a way a client can see. Within a
  /// major, added verbs and added optional params are the only changes, so a
  /// client that knows major 1 keeps working as minors rise.
  static const int major = 1;

  /// Bumped when verbs or capabilities are added.
  static const int minor = 0;

  /// `major.minor`.
  static const String version = '$major.$minor';

  /// Reading the document through declared queries.
  static const String queries = 'queries';

  /// Running many commands as one undo step.
  static const String batch = 'batch';

  /// Subscribing to what changed.
  static const String events = 'events';

  /// Reading payload bytes.
  static const String payloadRead = 'payloadRead';

  /// Bytes carried as base64 inside the JSON body, the fallback for a
  /// transport that cannot frame binary.
  static const String base64Blobs = 'base64Blobs';

  /// What this build speaks.
  ///
  /// `binaryFrames` is deliberately absent. Framing belongs to the extension
  /// host's socket, and until that exists every transport here is JSON-RPC,
  /// where [base64Blobs] is the honest answer.
  static const List<String> capabilities = [
    queries,
    batch,
    events,
    payloadRead,
    base64Blobs,
  ];

  /// Whether a client asking for [range] can talk to this build. [range] is
  /// a major version, or `major.minor` naming the lowest minor it needs.
  static bool supports(String range) {
    final parts = range.split('.');
    final wantedMajor = int.tryParse(parts.first);
    if (wantedMajor != major) return false;
    if (parts.length < 2) return true;
    final wantedMinor = int.tryParse(parts[1]);
    return wantedMinor != null && wantedMinor <= minor;
  }
}
