/// Inspector editor for scene-wide stage settings (environment/lighting,
/// exposure, tone mapping, sky), shown when no node is selected. The same
/// environment and sky controls drive either the stage's global environment
/// resource or a volume component's, picked by the resource passed in.
library;

import 'package:flutter/material.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/id.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/specs.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

import '../controller/editor_controller.dart';
import '../io/scene_io.dart';
import 'live_fields.dart';

const _toneMappingModes = ['pbrNeutral', 'aces', 'reinhard', 'linear'];

// Reflection/ambient cubemap sizes offered per environment (the Godot
// radiance-size equivalent). null is the engine default. The minimum is 256:
// the prefiltered cube stores 8 roughness bands as mip levels, which a smaller
// face cannot hold (see kMinRadianceCubeSize).
const _reflectionSizes = <int?>[null, 256, 512, 1024, 2048];

class StageSection extends StatelessWidget {
  const StageSection({super.key, required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    // The stage's global look is its referenced environment resource (the editor
    // guarantees one exists on open).
    final ref = controller.document.stage.environmentRef;
    final resource = ref == null ? null : controller.document.resource(ref);
    final environment = resource is EnvironmentResource ? resource : null;
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
        EnvironmentControls(
          controller: controller,
          environment: environment,
          allowHdrImport: true,
        ),
        const Divider(),
        SkySection(controller: controller, environment: environment),
      ],
    );
  }
}

/// The environment look controls (environment kind, intensity, exposure, tone
/// mapping, reflection resolution) for an environment resource (the stage's
/// global one or a volume's).
class EnvironmentControls extends StatelessWidget {
  const EnvironmentControls({
    super.key,
    required this.controller,
    this.environment,
    this.volumeNodeId,
    this.allowHdrImport = false,
  });

  final EditorController controller;

  /// The environment resource to edit (the stage's global one or a volume's).
  final EnvironmentResource? environment;

  /// When set (a volume component's environment), slider drags preview onto
  /// that node's live volume; otherwise preview targets the stage/global.
  final LocalId? volumeNodeId;

  /// Whether to show the "Import HDR environment" action.
  final bool allowHdrImport;

  void _set(String key, Object value) {
    final env = environment;
    if (env == null) return;
    controller.run('setEnvironmentProperties', {
      'environmentId': env.id.toToken(),
      'properties': {key: value},
    });
  }

  void _previewExposure({double? exposure, double? environmentIntensity}) {
    final node = volumeNodeId;
    if (node != null) {
      controller.previewVolumeStage(
        node,
        exposure: exposure,
        environmentIntensity: environmentIntensity,
      );
    } else {
      controller.previewStage(
        exposure: exposure,
        environmentIntensity: environmentIntensity,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final env = environment;
    if (env == null) return const SizedBox.shrink();
    final envType = switch (env.environment) {
      EmptyEnvironment() => 'empty',
      AssetEnvironment() => 'asset',
      _ => 'studio',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        // Importing an HDR drives the disk-loaded environment, targeting the
        // resource being edited (the global stage environment or a volume's).
        if (allowHdrImport)
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
                if (path != null) {
                  await importEnvironmentMap(
                    controller,
                    path,
                    environmentId: environment?.id,
                  );
                }
              },
            ),
          ),
        LiveSlider(
          label: 'Environment intensity',
          value: env.environmentIntensity,
          max: 3,
          onPreview: (v) => _previewExposure(environmentIntensity: v),
          onCommit: (v) => _set('environmentIntensity', v),
        ),
        LiveSlider(
          label: 'Exposure',
          value: env.exposure,
          max: 8,
          onPreview: (v) => _previewExposure(exposure: v),
          onCommit: (v) => _set('exposure', v),
        ),
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Tone mapping', style: TextStyle(fontSize: 13)),
          trailing: DropdownButton<String>(
            value: _toneMappingModes.contains(env.toneMapping)
                ? env.toneMapping
                : 'pbrNeutral',
            items: [
              for (final mode in _toneMappingModes)
                DropdownMenuItem(value: mode, child: Text(mode)),
            ],
            onChanged: (v) => v == null ? null : _set('toneMapping', v),
          ),
        ),
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Reflection resolution',
            style: TextStyle(fontSize: 13),
          ),
          trailing: DropdownButton<int>(
            value: _reflectionSizes.contains(env.radianceCubeSize)
                ? (env.radianceCubeSize ?? 0)
                : 0,
            items: [
              for (final size in _reflectionSizes)
                DropdownMenuItem(
                  value: size ?? 0,
                  child: Text(size == null ? 'Default' : '$size'),
                ),
            ],
            // 0 is the "Default" sentinel; the command clears the override.
            onChanged: (v) => v == null ? null : _set('radianceCubeSize', v),
          ),
        ),
      ],
    );
  }
}

/// Editor for the skybox and sky-driven lighting of an environment resource (the
/// stage's global one or a volume's). Procedural skies (gradient/physical) and
/// the environment sky render with no asset loading. Parameter sliders and
/// colors preview live; choosing a skybox type or toggling sky lighting applies
/// on release. Per-parameter edits flow through `setEnvironmentSkyParameters`,
/// structural changes through `setEnvironmentSkybox`.
class SkySection extends StatelessWidget {
  const SkySection({
    super.key,
    required this.controller,
    this.environment,
    this.volumeNodeId,
  });

  final EditorController controller;

  /// The environment resource to edit (the stage's global one or a volume's).
  final EnvironmentResource? environment;

  /// When set, slider drags preview onto that node's live volume; otherwise
  /// preview targets the stage/global (see [EnvironmentControls.volumeNodeId]).
  final LocalId? volumeNodeId;

  @override
  Widget build(BuildContext context) {
    final env = environment;
    if (env == null) return const SizedBox.shrink();
    final skyboxSpec = env.skybox;
    final skyEnvironmentSpec = env.skyEnvironment;
    final source = skyboxSpec?.source;
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
    final lightScene = skyEnvironmentSpec != null;
    final castShadows = skyEnvironmentSpec?.castShadows ?? false;
    final proceduralSky = type == 'gradient' || type == 'physical';

    // The look is an environment resource (the stage's global one or a
    // volume's); edits target it by id.
    const skyboxCommand = 'setEnvironmentSkybox';
    const paramsCommand = 'setEnvironmentSkyParameters';
    Map<String, Object> target() => {'environmentId': env.id.toToken()};

    // The type dropdown and lighting toggles are structural (the skybox command
    // keeps the tuned parameters across them); the per-parameter fields below
    // patch the current sky. Picking a procedural sky lights the scene and
    // casts sun shadows by default (the user can then turn them off).
    void setType(String newType) {
      final procedural = newType == 'gradient' || newType == 'physical';
      controller.run(skyboxCommand, {
        'sky': newType,
        if (procedural) 'lightScene': true,
        if (procedural) 'castShadows': true,
        ...target(),
      });
    }

    void setLight(bool on) => controller.run(skyboxCommand, {
      'sky': type,
      'lightScene': on,
      ...target(),
    });
    void setShadows(bool on) => controller.run(skyboxCommand, {
      'sky': type,
      'castShadows': on,
      ...target(),
    });
    void runParams(Map<String, Object> properties) =>
        controller.run(paramsCommand, {'properties': properties, ...target()});
    void preview(String key, Object raw) {
      final node = volumeNodeId;
      if (node != null) {
        controller.previewVolumeSkyParameter(node, key, raw);
      } else {
        controller.previewSkyParameter(key, raw);
      }
    }

    Map<String, double> vecMap(Vector3 v) => {'x': v.x, 'y': v.y, 'z': v.z};

    Widget axis(String name, double value, Vector3 Function(double) make) =>
        LiveSlider(
          label: name,
          value: value,
          min: -1,
          max: 1,
          // Aim the live sky as the slider drags; the background follows every
          // frame and the lighting re-bakes (time-sliced) so it catches up.
          onPreview: (v) => preview('sunDirection', make(v)),
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
      onPreview: (v) => preview(key, v),
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
      onPreview: (r, g, b, _) => preview(key, Vector3(r, g, b)),
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
            skyboxSpec?.intensity ?? 1.0,
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
