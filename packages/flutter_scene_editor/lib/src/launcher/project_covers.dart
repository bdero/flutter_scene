/// Cover images for the launcher's project cards.
///
/// A card without art is a filename in a grid of filenames. The editor
/// captures the viewport when a project's scene is saved and files it here,
/// so the gallery shows what each project actually looks like. A project with
/// no capture yet falls back to a placeholder derived from its path, which at
/// least makes the cards distinguishable at a glance.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Reads and writes the per-project cover captures.
class ProjectCoverStore {
  ProjectCoverStore(this.directory);

  /// Where the PNGs live, typically a `covers/` folder beside the settings.
  final Directory directory;

  /// The cover file for [projectPath], whether or not it exists.
  ///
  /// Named by a hash of the path rather than the project's name, so two
  /// projects called "Game" in different folders do not share a cover and
  /// nothing has to be escaped for the file system.
  File fileFor(String projectPath) =>
      File('${directory.path}/${coverKey(projectPath)}.png');

  /// The cover path for [projectPath], or null when there is no capture yet.
  String? pathFor(String projectPath) {
    final file = fileFor(projectPath);
    return file.existsSync() ? file.path : null;
  }

  /// Files [image] as [projectPath]'s cover, downscaled to card size.
  ///
  /// A viewport capture is a full-resolution framebuffer; a card is a few
  /// hundred pixels wide, and keeping the original would put megabytes per
  /// project in the settings folder for pixels nothing ever shows.
  Future<void> write(String projectPath, ui.Image image) async {
    final scaled = await _downscale(image, _coverWidth);
    try {
      final bytes = await scaled.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      directory.createSync(recursive: true);
      fileFor(projectPath).writeAsBytesSync(
        Uint8List.view(
          bytes.buffer,
          bytes.offsetInBytes,
          bytes.lengthInBytes,
        ),
      );
    } on FileSystemException {
      // A cover is a nicety; failing to file one must not fail a save.
    } finally {
      if (!identical(scaled, image)) scaled.dispose();
    }
  }

  /// Forgets [projectPath]'s cover, for when it is removed from the gallery.
  void remove(String projectPath) {
    try {
      final file = fileFor(projectPath);
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // Nothing to do; the gallery falls back to the placeholder.
    }
  }

  /// Card covers are drawn at most this wide.
  static const int _coverWidth = 480;

  static Future<ui.Image> _downscale(ui.Image source, int width) async {
    if (source.width <= width) return source;
    final height = (source.height * width / source.width).round();
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(
      source,
      ui.Rect.fromLTWH(
        0,
        0,
        source.width.toDouble(),
        source.height.toDouble(),
      ),
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    picture.dispose();
    return image;
  }
}

/// A stable, file-system-safe key for [projectPath].
///
/// A 64-bit FNV-1a in hex: short, collision-free enough for a covers folder,
/// and stable across runs so a project keeps its cover.
///
/// Formatted from the two 32-bit halves rather than the whole. Dart's `int` is
/// signed, so the accumulator wraps negative partway through any real path,
/// and rendering that directly gives a leading minus and a name that is not
/// sixteen hex digits.
String coverKey(String projectPath) {
  var hash = 0xcbf29ce484222325;
  for (final byte in utf8.encode(projectPath)) {
    hash ^= byte;
    hash *= 0x100000001b3;
  }
  final high = (hash >>> 32) & 0xFFFFFFFF;
  final low = hash & 0xFFFFFFFF;
  return high.toRadixString(16).padLeft(8, '0') +
      low.toRadixString(16).padLeft(8, '0');
}

/// A deterministic hue for a project with no capture yet, in `[0, 360)`.
///
/// Derived from the same hash as the cover key, so a project's placeholder
/// keeps its colour between runs and the cards stay distinguishable while
/// their art is still missing.
double placeholderHue(String projectPath) =>
    int.parse(coverKey(projectPath).substring(0, 4), radix: 16) % 360;
