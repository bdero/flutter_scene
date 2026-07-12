// A shared image-based-lighting environment switcher for the examples: a
// list of Khronos sample environments (plus the built-in studio and a
// procedural axis test), a resolver that downloads/decodes/caches them, and
// the HUD popup menu. Used by the stress tests and the widget-texture
// example.

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' hide Material;
import 'package:http/http.dart' as http;

import 'hdr_image.dart';
import 'stress_cache.dart';

/// An image-based-lighting environment selectable from the menu.
class ExampleEnvironment {
  const ExampleEnvironment({required this.id, required this.title, this.url});

  final String id;
  final String title;

  /// Radiance `.hdr` URL, or null for the renderer's built-in procedural
  /// studio environment.
  final String? url;
}

// Khronos sample-environment HDRs, downloaded at runtime. They are Git LFS
// blobs, so they are fetched through media.githubusercontent.com (the
// raw.githubusercontent.com path serves only the LFS pointer).
const _kEnvironmentBaseUrl =
    'https://media.githubusercontent.com/media/KhronosGroup/'
    'glTF-Sample-Environments/main';

/// The environments offered by [EnvironmentMenu].
const exampleEnvironments = <ExampleEnvironment>[
  ExampleEnvironment(id: 'studio', title: 'Studio (built-in)'),
  ExampleEnvironment(id: 'axis_test', title: 'Axis Test (solid colors)'),
  ExampleEnvironment(
    id: 'neutral',
    title: 'Studio Neutral',
    url: '$_kEnvironmentBaseUrl/neutral.hdr',
  ),
  ExampleEnvironment(
    id: 'footprint_court',
    title: 'Footprint Court',
    url: '$_kEnvironmentBaseUrl/footprint_court.hdr',
  ),
  ExampleEnvironment(
    id: 'pisa',
    title: 'Pisa',
    url: '$_kEnvironmentBaseUrl/pisa.hdr',
  ),
  ExampleEnvironment(
    id: 'doge2',
    title: "Doge's Palace",
    url: '$_kEnvironmentBaseUrl/doge2.hdr',
  ),
  ExampleEnvironment(
    id: 'ennis',
    title: 'Ennis House',
    url: '$_kEnvironmentBaseUrl/ennis.hdr',
  ),
  ExampleEnvironment(
    id: 'field',
    title: 'Field',
    url: '$_kEnvironmentBaseUrl/field.hdr',
  ),
  ExampleEnvironment(
    id: 'helipad',
    title: 'Helipad',
    url: '$_kEnvironmentBaseUrl/helipad.hdr',
  ),
  ExampleEnvironment(
    id: 'papermill',
    title: 'Papermill Ruins',
    url: '$_kEnvironmentBaseUrl/papermill.hdr',
  ),
  ExampleEnvironment(
    id: 'directional',
    title: 'Directional (test)',
    url: '$_kEnvironmentBaseUrl/directional.hdr',
  ),
  ExampleEnvironment(
    id: 'chromatic',
    title: 'Chromatic (test)',
    url: '$_kEnvironmentBaseUrl/chromatic.hdr',
  ),
];

/// Downloads [url] through the example resource cache.
Future<Uint8List> fetchResource(
  String url, {
  required void Function(int bytes) onChunk,
  int? expectedSize,
}) async {
  final cached = await loadCachedResource(url);
  if (cached != null) {
    // With a known size, reject a suspiciously short (interrupted) cache
    // entry; otherwise just require it to be non-empty.
    final usable = expectedSize == null
        ? cached.isNotEmpty
        : cached.lengthInBytes >= expectedSize * 0.95;
    if (usable) {
      onChunk(cached.lengthInBytes);
      return cached;
    }
  }

  final client = http.Client();
  try {
    final response = await client.send(http.Request('GET', Uri.parse(url)));
    if (response.statusCode != 200) {
      throw Exception('GET $url returned ${response.statusCode}');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      builder.add(chunk);
      onChunk(chunk.length);
    }
    final bytes = builder.takeBytes();
    await storeCachedResource(url, bytes);
    return bytes;
  } finally {
    client.close();
  }
}

/// Resolves environments to [EnvironmentMap]s with caching, tracking the
/// active selection and a loading flag for the menu.
class EnvironmentSelector extends ChangeNotifier {
  ExampleEnvironment _active = exampleEnvironments.first;
  bool _loading = false;
  final Map<String, EnvironmentMap> _cache = {};

  /// The currently selected environment.
  ExampleEnvironment get active => _active;

  /// Whether a selection is downloading or decoding.
  bool get loading => _loading;

  /// Selects [environment] and applies it to [scene]. Throws when the
  /// download or decode fails (the previous environment stays active).
  Future<void> select(ExampleEnvironment environment, Scene scene) async {
    if (environment.id == _active.id && !_loading) return;
    final previous = _active;
    _active = environment;
    _loading = true;
    notifyListeners();
    try {
      final map = await _resolve(environment);
      scene.environment = map;
    } catch (_) {
      _active = previous;
      rethrow;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // Returns the [EnvironmentMap] for [environment], or null for the
  // renderer's built-in studio default. HDR environments are downloaded,
  // decoded off the UI isolate, prefiltered, and cached; the axis-test
  // environment is generated procedurally.
  Future<EnvironmentMap?> _resolve(ExampleEnvironment environment) async {
    if (environment.id == 'studio') return null; // renderer's built-in

    final cached = _cache[environment.id];
    if (cached != null) return cached;

    final EnvironmentMap map;
    if (environment.id == 'axis_test') {
      final test = _buildAxisTestEquirect();
      map = await EnvironmentMap.fromEquirectHdr(
        linearPixels: test.pixels,
        width: test.width,
        height: test.height,
      );
    } else {
      final bytes = await fetchResource(environment.url!, onChunk: (_) {});
      final hdr = await compute(loadHdrEnvironment, bytes);
      map = await EnvironmentMap.fromEquirectHdr(
        linearPixels: hdr.pixels,
        width: hdr.width,
        height: hdr.height,
      );
    }
    _cache[environment.id] = map;
    return map;
  }
}

({Float32List pixels, int width, int height}) _buildAxisTestEquirect() {
  const width = 256;
  const height = 128;
  final pixels = Float32List(width * height * 4);
  for (var py = 0; py < height; py++) {
    // Row 0 is the up pole, the standard equirect convention.
    final v = (py + 0.5) / height;
    final latitude = (0.5 - v) * pi;
    final cosLat = cos(latitude);
    final dirY = sin(latitude);
    for (var px = 0; px < width; px++) {
      final u = (px + 0.5) / width;
      final longitude = (u - 0.5) * 2.0 * pi;
      final dirX = cosLat * cos(longitude);
      final dirZ = cosLat * sin(longitude);
      double r, g, b;
      if (dirX.abs() >= dirY.abs() && dirX.abs() >= dirZ.abs()) {
        r = dirX >= 0 ? 1.0 : 0.0; // +X red, -X cyan
        g = dirX >= 0 ? 0.0 : 1.0;
        b = dirX >= 0 ? 0.0 : 1.0;
      } else if (dirY.abs() >= dirZ.abs()) {
        r = dirY >= 0 ? 0.0 : 1.0; // +Y green, -Y magenta
        g = dirY >= 0 ? 1.0 : 0.0;
        b = dirY >= 0 ? 0.0 : 1.0;
      } else {
        r = dirZ >= 0 ? 0.0 : 1.0; // +Z blue, -Z yellow
        g = dirZ >= 0 ? 0.0 : 1.0;
        b = dirZ >= 0 ? 1.0 : 0.0;
      }
      final o = (py * width + px) * 4;
      pixels[o] = r;
      pixels[o + 1] = g;
      pixels[o + 2] = b;
      pixels[o + 3] = 1.0;
    }
  }
  return (pixels: pixels, width: width, height: height);
}

/// The HUD popup for picking an environment.
class EnvironmentMenu extends StatelessWidget {
  const EnvironmentMenu({
    super.key,
    required this.active,
    required this.loading,
    required this.onSelected,
  });

  final ExampleEnvironment active;
  final bool loading;
  final ValueChanged<ExampleEnvironment> onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white12,
      borderRadius: BorderRadius.circular(8),
      child: PopupMenuButton<ExampleEnvironment>(
        tooltip: 'Select environment',
        position: PopupMenuPosition.over,
        color: const Color(0xFF1E1E1E),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 300),
        onSelected: onSelected,
        itemBuilder: (context) => [
          for (final environment in exampleEnvironments)
            PopupMenuItem<ExampleEnvironment>(
              value: environment,
              child: Text(
                environment.title,
                style: const TextStyle(color: Colors.white),
              ),
            ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.light_mode, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Text(
                active.title,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              const SizedBox(width: 6),
              loading
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(
                      Icons.arrow_drop_down,
                      color: Colors.white,
                      size: 18,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
