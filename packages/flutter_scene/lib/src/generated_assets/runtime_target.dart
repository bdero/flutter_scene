/// The operating system the app is running on, for picking the generated
/// outputs compiled for this build's graphics backend.
///
/// Reads the real OS rather than `defaultTargetPlatform`, which
/// `debugDefaultTargetPlatformOverride` moves for UI testing while the graphics
/// backend stays put. The web implementation is also the analyzer fallback; no
/// OS means the GLES target, which is what a non-native build gets.
library;

export 'runtime_target_web.dart' if (dart.library.io) 'runtime_target_io.dart';
