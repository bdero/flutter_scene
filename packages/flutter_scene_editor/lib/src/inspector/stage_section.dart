/// Inspector editor for scene-wide stage settings (environment/lighting,
/// exposure, tone mapping). Shown when no node is selected; commits through the
/// `setStageProperties` command.
library;

import 'package:flutter/material.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/specs.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

import '../controller/editor_controller.dart';
import '../io/scene_io.dart';
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
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.image_outlined, size: 16),
            label: const Text(
              'Import HDR environment',
              style: TextStyle(fontSize: 12),
            ),
            onPressed: () async {
              final path = await pickEnvironmentPath();
              if (path != null) await importEnvironmentMap(controller, path);
            },
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
/// environments are not yet authorable here. The parameter sliders and colors
/// preview live (the background follows immediately, the lighting re-bakes as
/// they drag); choosing a skybox type or toggling sky lighting applies on
/// release. Per-parameter edits flow through `setSkyParameters`, structural
/// changes through `setSkybox`.
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
    final castShadows = stage.skyEnvironment?.castShadows ?? false;
    final proceduralSky = type == 'gradient' || type == 'physical';

    // The type dropdown and lighting toggles are structural (setSkybox keeps
    // the tuned parameters across them); the per-parameter fields below patch
    // the current sky through setSkyParameters.
    void setType(String newType) =>
        controller.run('setSkybox', {'sky': newType});
    void setLight(bool on) =>
        controller.run('setSkybox', {'sky': type, 'lightScene': on});
    void setShadows(bool on) =>
        controller.run('setSkybox', {'sky': type, 'castShadows': on});
    void runParams(Map<String, Object> properties) =>
        controller.run('setSkyParameters', {'properties': properties});
    Map<String, double> vecMap(Vector3 v) => {'x': v.x, 'y': v.y, 'z': v.z};

    Widget axis(String name, double value, Vector3 Function(double) make) =>
        LiveSlider(
          label: name,
          value: value,
          min: -1,
          max: 1,
          // Aim the live sky as the slider drags; the background follows every
          // frame and the lighting re-bakes (time-sliced) so it catches up.
          onPreview: (v) =>
              controller.previewSkyParameter('sunDirection', make(v)),
          onCommit: (v) => runParams({'sunDirection': vecMap(make(v))}),
        );

    Widget scalar(
      String label,
      String key,
      double value, {
      double min = 0,
      double max = 1,
    }) => LiveSlider(
      label: label,
      value: value,
      min: min,
      max: max,
      onPreview: (v) => controller.previewSkyParameter(key, v),
      onCommit: (v) => runParams({key: v}),
    );

    Widget colorField(
      String label,
      String key,
      Vector3 value, {
      double channelMax = 1.0,
    }) => ColorEditor(
      label: label,
      r: value.x,
      g: value.y,
      b: value.z,
      a: 1.0,
      channelMax: channelMax,
      showAlpha: false,
      onPreview: (r, g, b, _) =>
          controller.previewSkyParameter(key, Vector3(r, g, b)),
      onCommit: (r, g, b, _) => runParams({
        key: {'x': r, 'y': g, 'z': b},
      }),
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
            onChanged: (v) => v == null ? null : setType(v),
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
            onChanged: setLight,
          ),
          if (lightScene)
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Cast sun shadows',
                style: TextStyle(fontSize: 13),
              ),
              subtitle: const Text(
                'Hard shadows that track the sun.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              value: castShadows,
              onChanged: setShadows,
            ),
        ],
        if (source is EnvironmentSkySpec) ...[
          const Divider(height: 12),
          scalar('Blurriness', 'blurriness', source.blurriness, max: 1),
          scalar(
            'Intensity',
            'intensity',
            stage.skybox?.intensity ?? 1.0,
            max: 4,
          ),
        ],
        if (source is GradientSkySpec) ...[
          const Divider(height: 12),
          colorField('Zenith color', 'zenithColor', source.zenithColor),
          colorField('Horizon color', 'horizonColor', source.horizonColor),
          colorField('Ground color', 'groundColor', source.groundColor),
          colorField('Sun color', 'sunColor', source.sunColor, channelMax: 8),
          scalar(
            'Sun sharpness',
            'sunSharpness',
            source.sunSharpness,
            min: 1,
            max: 2000,
          ),
        ],
        if (source is PhysicalSkySpec) ...[
          const Divider(height: 12),
          scalar('Energy', 'energy', source.energy, max: 4),
          scalar('Turbidity', 'turbidity', source.turbidity, min: 1, max: 20),
          scalar(
            'Sun size',
            'sunAngularRadius',
            source.sunAngularRadius,
            min: 0.001,
            max: 0.1,
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Atmosphere', style: TextStyle(fontSize: 13)),
            childrenPadding: const EdgeInsets.only(bottom: 8),
            children: [
              scalar(
                'Rayleigh',
                'rayleighCoefficient',
                source.rayleighCoefficient,
                max: 6,
              ),
              colorField(
                'Rayleigh color',
                'rayleighColor',
                source.rayleighColor,
              ),
              scalar('Mie', 'mieCoefficient', source.mieCoefficient, max: 0.05),
              scalar(
                'Mie eccentricity',
                'mieEccentricity',
                source.mieEccentricity,
                max: 0.99,
              ),
              colorField('Mie color', 'mieColor', source.mieColor),
              colorField('Ground color', 'groundColor', source.groundColor),
            ],
          ),
        ],
      ],
    );
  }
}
