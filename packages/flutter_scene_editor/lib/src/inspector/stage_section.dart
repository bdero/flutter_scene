/// Inspector editor for scene-wide stage settings (environment/lighting,
/// exposure, tone mapping). Shown when no node is selected; commits through the
/// `setStageProperties` command.
library;

import 'package:flutter/material.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/specs.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

import '../controller/editor_controller.dart';
import 'live_fields.dart';

const _toneMappingModes = ['pbrNeutral', 'aces', 'reinhard', 'linear'];

class StageSection extends StatelessWidget {
  const StageSection({super.key, required this.controller});

  final EditorController controller;

  void _set(String key, Object value) {
    controller.run('setStageProperties', {
      'properties': {key: value},
    });
  }

  @override
  Widget build(BuildContext context) {
    final stage = controller.document.stage;
    final envType = switch (stage.environment) {
      EmptyEnvironment() => 'empty',
      AssetEnvironment() => 'asset',
      _ => 'studio',
    };
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        Text('Scene settings', style: Theme.of(context).textTheme.labelMedium),
        const Padding(
          padding: EdgeInsets.fromLTRB(0, 0, 0, 8),
          child: Text(
            'Select a node to edit it.',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ),
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Environment', style: TextStyle(fontSize: 13)),
          trailing: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'studio', label: Text('Studio')),
              ButtonSegment(value: 'empty', label: Text('None')),
            ],
            selected: {envType == 'empty' ? 'empty' : 'studio'},
            onSelectionChanged: (s) => _set('environment', s.first),
          ),
        ),
        if (envType == 'asset')
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text(
              'An image environment is set; choose Studio or None to replace it.',
              style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
            ),
          ),
        LiveSlider(
          label: 'Environment intensity',
          value: stage.environmentIntensity,
          max: 3,
          onPreview: (v) => controller.previewStage(environmentIntensity: v),
          onCommit: (v) => _set('environmentIntensity', v),
        ),
        LiveSlider(
          label: 'Exposure',
          value: stage.exposure,
          max: 8,
          onPreview: (v) => controller.previewStage(exposure: v),
          onCommit: (v) => _set('exposure', v),
        ),
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Tone mapping', style: TextStyle(fontSize: 13)),
          trailing: DropdownButton<String>(
            value: _toneMappingModes.contains(stage.toneMapping)
                ? stage.toneMapping
                : 'pbrNeutral',
            items: [
              for (final mode in _toneMappingModes)
                DropdownMenuItem(value: mode, child: Text(mode)),
            ],
            onChanged: (v) => v == null ? null : _set('toneMapping', v),
          ),
        ),
        const Divider(),
        SkySection(controller: controller),
      ],
    );
  }
}

/// Editor for the skybox and sky-driven lighting. Procedural skies (gradient /
/// physical) and the environment sky render with no asset loading; HDR image
/// environments are not yet authorable here. Edits apply on release (a sky
/// change re-bakes lighting, too heavy to preview every frame).
class SkySection extends StatelessWidget {
  const SkySection({super.key, required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final stage = controller.document.stage;
    final source = stage.skybox?.source;
    final type = switch (source) {
      GradientSkySpec() => 'gradient',
      PhysicalSkySpec() => 'physical',
      EnvironmentSkySpec() => 'environment',
      _ => 'none',
    };
    final sun = switch (source) {
      GradientSkySpec(:final sunDirection) => sunDirection,
      PhysicalSkySpec(:final sunDirection) => sunDirection,
      _ => Vector3(0.4, 0.5, 0.6),
    };
    final lightScene = stage.skyEnvironment != null;
    final proceduralSky = type == 'gradient' || type == 'physical';

    void commit({String? newType, Vector3? newSun, bool? newLight}) {
      final s = newSun ?? sun;
      controller.run('setSkybox', {
        'sky': newType ?? type,
        'sunDirection': {'x': s.x, 'y': s.y, 'z': s.z},
        'lightScene': newLight ?? lightScene,
      });
    }

    Widget axis(String name, double value, Vector3 Function(double) make) =>
        LiveSlider(
          label: name,
          value: value,
          min: -1,
          max: 1,
          // Sky edits re-bake lighting; apply on release only.
          onPreview: (_) {},
          onCommit: (v) => commit(newSun: make(v)),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Text('Sky', style: TextStyle(fontSize: 13)),
        ),
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Skybox', style: TextStyle(fontSize: 13)),
          trailing: DropdownButton<String>(
            value: type,
            items: const [
              DropdownMenuItem(value: 'none', child: Text('None')),
              DropdownMenuItem(
                value: 'environment',
                child: Text('Environment'),
              ),
              DropdownMenuItem(value: 'gradient', child: Text('Gradient')),
              DropdownMenuItem(value: 'physical', child: Text('Physical')),
            ],
            onChanged: (v) => v == null ? null : commit(newType: v),
          ),
        ),
        if (proceduralSky) ...[
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Sun direction',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          axis('X', sun.x, (v) => Vector3(v, sun.y, sun.z)),
          axis('Y', sun.y, (v) => Vector3(sun.x, v, sun.z)),
          axis('Z', sun.z, (v) => Vector3(sun.x, sun.y, v)),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Light scene with sky',
              style: TextStyle(fontSize: 13),
            ),
            value: lightScene,
            onChanged: (v) => commit(newLight: v),
          ),
        ],
      ],
    );
  }
}
