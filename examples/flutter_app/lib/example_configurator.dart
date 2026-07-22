import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' hide BoxShape;
import 'package:vector_math/vector_math.dart' as vm;

import 'environment_menu.dart';

/// A product configurator built entirely with the declarative scene API.
///
/// The scene is described in `build()`: a [SceneView.declarative] owns the
/// scene, a [SceneModel] mounts the downloaded shoe on a turntable, and
/// tapping a swatch just calls setState with a new variant name. The
/// engine's KHR_materials_variants support swaps the mapped materials in
/// place, so switching is instant (no reload, no re-upload).
///
/// The lighting is a small showroom rig that reacts to the selected
/// colorway: a shadow-casting key spot over a glossy pedestal, two rim
/// lights behind the shoe, and an emissive floor ring. The rig's structure
/// is declared once; the color transitions run engine-side in [Component]s
/// that ease toward targets each frame, so nothing rebuilds per frame
/// ("rebuild for structure, mutate for motion").
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

/// A colorway pairing the shoe's declared variant with swatch and lighting
/// accent colors.
typedef _Colorway = ({
  String name,
  String label,
  Color swatch,
  Color rimLeft,
  Color rimRight,
});

/// The shoe's declared variants, with swatch colors for the chips and the
/// accent colors the lighting rig glides to.
const List<_Colorway> _kColorways = [
  (
    name: 'midnight',
    label: 'Midnight',
    swatch: Color(0xff2b3a67),
    rimLeft: Color(0xff3d7bff), // electric blue
    rimRight: Color(0xff8a4dff), // violet
  ),
  (
    name: 'beach',
    label: 'Beach',
    swatch: Color(0xffe8b89d),
    rimLeft: Color(0xffff7a52), // coral
    rimRight: Color(0xffffc266), // amber
  ),
  (
    name: 'street',
    label: 'Street',
    swatch: Color(0xff9ba0a8),
    rimLeft: Color(0xff2effd4), // cyan
    rimRight: Color(0xffff40b0), // magenta
  ),
];

vm.Vector3 _colorToVec3(Color color) => vm.Vector3(color.r, color.g, color.b);

/// Spins the owning node about its Y axis, the product turntable.
class _TurntableComponent extends Component {
  _TurntableComponent(this.radiansPerSecond);

  final double radiansPerSecond;

  @override
  void update(double deltaSeconds) {
    // In place, so the per-frame path allocates nothing.
    node.localTransform.rotateY(radiansPerSecond * deltaSeconds);
    node.markTransformDirty();
  }
}

/// Eases a [PointLight]'s color toward [target] each frame, engine-side, so
/// colorway changes fade smoothly without any widget rebuilding per frame.
class _ColorGlideComponent extends Component {
  _ColorGlideComponent(this.light, this.target);

  final PointLight light;
  vm.Vector3 target;

  @override
  void update(double deltaSeconds) {
    // Component-wise in place, so the per-frame path allocates nothing.
    final blend = 1.0 - exp(-deltaSeconds * 6.0);
    final color = light.color;
    color.x += (target.x - color.x) * blend;
    color.y += (target.y - color.y) * blend;
    color.z += (target.z - color.z) * blend;
  }
}

/// Eases an [UnlitMaterial]'s color toward [target] with a gentle pulse, for
/// the emissive floor ring.
class _RingPulseComponent extends Component {
  _RingPulseComponent(this.material, this.target);

  final UnlitMaterial material;
  vm.Vector3 target;

  final vm.Vector3 _eased = vm.Vector3.zero();
  double _elapsed = 0;

  @override
  void update(double deltaSeconds) {
    _elapsed += deltaSeconds;
    final blend = 1.0 - exp(-deltaSeconds * 6.0);
    _eased.x += (target.x - _eased.x) * blend;
    _eased.y += (target.y - _eased.y) * blend;
    _eased.z += (target.z - _eased.z) * blend;
    final pulse = 0.8 + 0.2 * sin(_elapsed * 1.8);
    material.baseColorFactor.setValues(
      _eased.x * pulse,
      _eased.y * pulse,
      _eased.z * pulse,
      1.0,
    );
  }
}

class ExampleConfiguratorState extends State<ExampleConfigurator> {
  Uint8List? _modelBytes;
  Object? _downloadError;
  int _downloadedBytes = 0;
  String _variant = _kColorways.first.name;

  // The lighting rig and set dressing. Engine objects and components are
  // created once and kept stable across rebuilds (scene widgets identity-diff
  // them); swatch taps only retarget the glide components.
  late final SpotLight _keyLight = SpotLight(
    color: vm.Vector3(1.0, 0.96, 0.9),
    intensity: 65.0,
    range: 30.0,
    direction: vm.Vector3(-1.3, -3.0, 1.9).normalized(),
    innerConeAngle: 12 * pi / 180,
    outerConeAngle: 38 * pi / 180,
    castsShadow: true,
    shadowSoftness: 2.0,
  );
  late final PointLight _rimLeftLight = PointLight(
    color: _colorToVec3(_kColorways.first.rimLeft),
    intensity: 9.0,
    range: 14.0,
  );
  late final PointLight _rimRightLight = PointLight(
    color: _colorToVec3(_kColorways.first.rimRight),
    intensity: 7.0,
    range: 14.0,
  );
  late final PointLight _fillLight = PointLight(
    color: vm.Vector3(0.5, 0.6, 0.8),
    intensity: 2.5,
    range: 12.0,
  );
  late final _ColorGlideComponent _rimLeftGlide = _ColorGlideComponent(
    _rimLeftLight,
    _colorToVec3(_kColorways.first.rimLeft),
  );
  late final _ColorGlideComponent _rimRightGlide = _ColorGlideComponent(
    _rimRightLight,
    _colorToVec3(_kColorways.first.rimRight),
  );
  late final UnlitMaterial _ringMaterial = UnlitMaterial();
  late final _RingPulseComponent _ringPulse = _RingPulseComponent(
    _ringMaterial,
    _colorToVec3(_kColorways.first.rimLeft),
  );
  late final _TurntableComponent _turntable = _TurntableComponent(0.45);
  late final Geometry _pedestalGeometry = CylinderGeometry(
    bottomRadius: 1.75,
    topRadius: 1.6,
    height: 0.12,
    radialSegments: 64,
  );
  late final PhysicallyBasedMaterial _pedestalMaterial =
      PhysicallyBasedMaterial()
        ..baseColorFactor = vm.Vector4(0.045, 0.045, 0.055, 1.0)
        ..metallicFactor = 0.85
        ..roughnessFactor = 0.32;
  late final Geometry _ringGeometry = RingGeometry(
    innerRadius: 1.72,
    outerRadius: 1.86,
    segments: 96,
  );

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

  void _selectColorway(_Colorway colorway) {
    setState(() => _variant = colorway.name);
    // Retarget the engine-side glides; they ease over the next frames.
    _rimLeftGlide.target = _colorToVec3(colorway.rimLeft);
    _rimRightGlide.target = _colorToVec3(colorway.rimRight);
    _ringPulse.target = _colorToVec3(colorway.rimLeft);
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
          // Dimmed studio environment so the rig's key and rim lights carry
          // the image.
          environmentIntensity: 0.32,
          exposure: 1.45,
          cameraBuilder: (elapsed) {
            // A fixed product-shot framing with a slow breathing sway; the
            // turntable provides the rotation.
            final t = elapsed.inMicroseconds / 1e6;
            final yaw = pi * 0.94 + sin(t * 0.22) * 0.10;
            return PerspectiveCamera(
              position: vm.Vector3(sin(yaw) * 3.1, 1.45, cos(yaw) * 3.1),
              target: vm.Vector3(0, 0.52, 0),
              fovRadiansY: 31 * pi / 180,
            );
          },
          children: [
            // Warm shadow-casting key light above front-left.
            SceneNode(
              position: vm.Vector3(1.3, 3.3, -1.9),
              components: [SpotLightComponent(_keyLight)],
            ),
            // Colorway rim lights behind the shoe; their colors glide when
            // the selection changes.
            SceneNode(
              position: vm.Vector3(-2.7, 1.3, 2.3),
              components: [PointLightComponent(_rimLeftLight), _rimLeftGlide],
            ),
            SceneNode(
              position: vm.Vector3(2.7, 1.0, 2.1),
              components: [PointLightComponent(_rimRightLight), _rimRightGlide],
            ),
            // Faint cool fill from the camera side.
            SceneNode(
              position: vm.Vector3(0, 0.7, -3.4),
              components: [PointLightComponent(_fillLight)],
            ),
            // Glossy pedestal that catches the key shadow and rim
            // reflections.
            SceneMesh(
              geometry: _pedestalGeometry,
              material: _pedestalMaterial,
              position: vm.Vector3(0, -0.06, 0),
            ),
            // Emissive floor ring pulsing in the colorway accent.
            SceneMesh(
              geometry: _ringGeometry,
              material: _ringMaterial,
              position: vm.Vector3(0, 0.004, 0),
              components: [_ringPulse],
            ),
            // The shoe, on a turntable.
            SceneModel.from(
              MemoryModelSource(bytes, key: _kShoeUrl),
              variant: _variant,
              scale: vm.Vector3.all(8.0),
              components: [_turntable],
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
            '(${(_downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} of '
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
                      onTap: () => _selectColorway(colorway),
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
