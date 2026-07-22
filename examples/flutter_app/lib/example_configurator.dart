import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' hide BoxShape;
import 'package:vector_math/vector_math.dart' as vm;

import 'environment_menu.dart';

/// A product configurator built entirely with the declarative scene API.
///
/// The scene is described in `build()`: a [SceneView.declarative] owns the
/// scene, a [SceneModel] mounts the downloaded shoe, and tapping a swatch
/// just calls setState with a new variant name. The engine's
/// KHR_materials_variants support swaps the mapped materials in place, so
/// switching is instant (no reload, no re-upload).
///
/// The model (MaterialsVariantsShoe, (c) Shopify, CC BY 4.0) is downloaded
/// live from the Khronos glTF-Sample-Assets repository through the example
/// resource cache, so nothing is bundled with the app.
class ExampleConfigurator extends StatefulWidget {
  const ExampleConfigurator({super.key});

  @override
  State<ExampleConfigurator> createState() => ExampleConfiguratorState();
}

const String _kShoeUrl =
    'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/'
    'Models/MaterialsVariantsShoe/glTF-Binary/MaterialsVariantsShoe.glb';
const int _kShoeSizeBytes = 7833592;

/// The shoe's declared variants with swatch colors for the chips.
const List<({String name, String label, Color swatch})> _kColorways = [
  (name: 'midnight', label: 'Midnight', swatch: Color(0xff2b3a67)),
  (name: 'beach', label: 'Beach', swatch: Color(0xffe8b89d)),
  (name: 'street', label: 'Street', swatch: Color(0xff9ba0a8)),
];

class ExampleConfiguratorState extends State<ExampleConfigurator> {
  Uint8List? _modelBytes;
  Object? _downloadError;
  int _downloadedBytes = 0;
  String _variant = _kColorways.first.name;

  @override
  void initState() {
    super.initState();
    _download();
  }

  Future<void> _download() async {
    setState(() {
      _downloadError = null;
      _downloadedBytes = 0;
    });
    try {
      final bytes = await fetchResource(
        _kShoeUrl,
        expectedSize: _kShoeSizeBytes,
        onChunk: (chunk) {
          if (!mounted) return;
          setState(() => _downloadedBytes += chunk);
        },
      );
      if (!mounted) return;
      setState(() => _modelBytes = bytes);
    } catch (e) {
      if (!mounted) return;
      setState(() => _downloadError = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _modelBytes;
    if (bytes == null) {
      return _buildDownloadGate();
    }
    return Stack(
      children: [
        SceneView.declarative(
          exposure: 1.2,
          cameraBuilder: (elapsed) {
            // A slow orbit around the shoe; the scene itself never rebuilds
            // for camera motion.
            final t = elapsed.inMicroseconds / 1e6 * 0.35;
            return PerspectiveCamera(
              position: vm.Vector3(sin(t) * 2.8, 1.1, cos(t) * 2.8),
              target: vm.Vector3(0, 0.55, 0),
              fovRadiansY: 35 * pi / 180,
            );
          },
          children: [
            SceneModel.from(
              MemoryModelSource(bytes, key: _kShoeUrl),
              variant: _variant,
              scale: vm.Vector3.all(8.0),
            ),
          ],
        ),
        _buildSwatchBar(),
        _buildAttribution(),
      ],
    );
  }

  Widget _buildDownloadGate() {
    final error = _downloadError;
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Download failed'),
            const SizedBox(height: 8),
            Text('$error', style: const TextStyle(fontSize: 11)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _download, child: const Text('Retry')),
          ],
        ),
      );
    }
    final progress = (_downloadedBytes / _kShoeSizeBytes).clamp(0.0, 1.0);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 220, child: LinearProgressIndicator(value: progress)),
          const SizedBox(height: 12),
          Text(
            'Downloading shoe model '
            '(${(_downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} / '
            '${(_kShoeSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB)',
          ),
        ],
      ),
    );
  }

  Widget _buildSwatchBar() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 40),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xaa000000),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final colorway in _kColorways)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: _Swatch(
                      color: colorway.swatch,
                      label: colorway.label,
                      selected: _variant == colorway.name,
                      onTap: () => setState(() => _variant = colorway.name),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAttribution() {
    return const Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: EdgeInsets.all(8),
        child: Text(
          'Shoe model (c) Shopify, CC BY 4.0',
          style: TextStyle(fontSize: 10, color: Color(0x88ffffff)),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? Colors.white : Colors.white24,
                width: selected ? 3 : 1,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: selected ? Colors.white : Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
}
