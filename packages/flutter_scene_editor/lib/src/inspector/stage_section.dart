/// Inspector editor for scene-wide stage settings (environment/lighting,
/// exposure, tone mapping, sky) and the spatial environment-volume stack. Shown
/// when no node is selected. The same environment/sky controls drive either the
/// base stage or a volume, picked by a volume index threaded into the commands.
library;

import 'package:flutter/material.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/specs.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

import '../controller/editor_controller.dart';
import '../io/scene_io.dart';
import 'live_fields.dart';

const _toneMappingModes = ['pbrNeutral', 'aces', 'reinhard', 'linear'];

// Reflection/ambient cubemap sizes offered per environment (the Godot
// radiance-size equivalent). null is the engine default.
const _reflectionSizes = <int?>[null, 128, 256, 512, 1024, 2048];

// The look fields shared by the base stage and a volume, read for whichever a
// section targets.
typedef _Look = ({
  EnvironmentSpec environment,
  double environmentIntensity,
  double exposure,
  String toneMapping,
  int? radianceCubeSize,
  SkyboxSpec? skybox,
});

_Look _lookOf(StageMetadata stage, int? volumeIndex) {
  if (volumeIndex == null) {
    return (
      environment: stage.environment,
      environmentIntensity: stage.environmentIntensity,
      exposure: stage.exposure,
      toneMapping: stage.toneMapping,
      radianceCubeSize: stage.radianceCubeSize,
      skybox: stage.skybox,
    );
  }
  final v = stage.volumes[volumeIndex];
  return (
    environment: v.environment,
    environmentIntensity: v.environmentIntensity,
    exposure: v.exposure,
    toneMapping: v.toneMapping,
    radianceCubeSize: v.radianceCubeSize,
    skybox: v.skybox,
  );
}

class StageSection extends StatelessWidget {
  const StageSection({super.key, required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
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
        EnvironmentControls(controller: controller),
        const Divider(),
        SkySection(controller: controller),
        const Divider(),
        VolumesSection(controller: controller),
      ],
    );
  }
}

/// The environment look controls (environment kind, intensity, exposure, tone
/// mapping, reflection resolution) for the base stage ([volumeIndex] null) or a
/// volume.
class EnvironmentControls extends StatelessWidget {
  const EnvironmentControls({
    super.key,
    required this.controller,
    this.volumeIndex,
  });

  final EditorController controller;
  final int? volumeIndex;

  void _set(String key, Object value) {
    controller.run('setStageProperties', {
      'properties': {key: value},
      if (volumeIndex != null) 'volume': volumeIndex,
    });
  }

  @override
  Widget build(BuildContext context) {
    final look = _lookOf(controller.document.stage, volumeIndex);
    final envType = switch (look.environment) {
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
        // Importing an HDR drives the disk-loaded base environment; a volume
        // cannot reference one yet.
        // TODO(volume-hdr): allow importing an image environment per volume.
        if (volumeIndex == null)
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
          value: look.environmentIntensity,
          max: 3,
          onPreview: (v) => controller.previewStage(
            environmentIntensity: v,
            volumeIndex: volumeIndex,
          ),
          onCommit: (v) => _set('environmentIntensity', v),
        ),
        LiveSlider(
          label: 'Exposure',
          value: look.exposure,
          max: 8,
          onPreview: (v) =>
              controller.previewStage(exposure: v, volumeIndex: volumeIndex),
          onCommit: (v) => _set('exposure', v),
        ),
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Tone mapping', style: TextStyle(fontSize: 13)),
          trailing: DropdownButton<String>(
            value: _toneMappingModes.contains(look.toneMapping)
                ? look.toneMapping
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
            value: _reflectionSizes.contains(look.radianceCubeSize)
                ? (look.radianceCubeSize ?? 0)
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

/// Editor for the skybox and sky-driven lighting of the base stage
/// ([volumeIndex] null) or a volume. Procedural skies (gradient/physical) and
/// the environment sky render with no asset loading. Parameter sliders and
/// colors preview live; choosing a skybox type or toggling sky lighting applies
/// on release. Per-parameter edits flow through `setSkyParameters`, structural
/// changes through `setSkybox`.
class SkySection extends StatelessWidget {
  const SkySection({super.key, required this.controller, this.volumeIndex});

  final EditorController controller;
  final int? volumeIndex;

  @override
  Widget build(BuildContext context) {
    final stage = controller.document.stage;
    final skyboxSpec = volumeIndex == null
        ? stage.skybox
        : stage.volumes[volumeIndex!].skybox;
    final skyEnvironmentSpec = volumeIndex == null
        ? stage.skyEnvironment
        : stage.volumes[volumeIndex!].skyEnvironment;
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

    final volumeArg = volumeIndex == null
        ? const <String, Object>{}
        : {'volume': volumeIndex!};

    // The type dropdown and lighting toggles are structural (setSkybox keeps
    // the tuned parameters across them); the per-parameter fields below patch
    // the current sky through setSkyParameters.
    void setType(String newType) =>
        controller.run('setSkybox', {'sky': newType, ...volumeArg});
    void setLight(bool on) => controller.run('setSkybox', {
      'sky': type,
      'lightScene': on,
      ...volumeArg,
    });
    void setShadows(bool on) => controller.run('setSkybox', {
      'sky': type,
      'castShadows': on,
      ...volumeArg,
    });
    void runParams(Map<String, Object> properties) => controller.run(
      'setSkyParameters',
      {'properties': properties, ...volumeArg},
    );
    Map<String, double> vecMap(Vector3 v) => {'x': v.x, 'y': v.y, 'z': v.z};

    Widget axis(String name, double value, Vector3 Function(double) make) =>
        LiveSlider(
          label: name,
          value: value,
          min: -1,
          max: 1,
          // Aim the live sky as the slider drags; the background follows every
          // frame and the lighting re-bakes (time-sliced) so it catches up.
          onPreview: (v) => controller.previewSkyParameter(
            'sunDirection',
            make(v),
            volumeIndex: volumeIndex,
          ),
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
      onPreview: (v) =>
          controller.previewSkyParameter(key, v, volumeIndex: volumeIndex),
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
      onPreview: (r, g, b, _) => controller.previewSkyParameter(
        key,
        Vector3(r, g, b),
        volumeIndex: volumeIndex,
      ),
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

/// The environment-volume stack: an add control plus one expandable card per
/// volume, each carrying its region/blend controls and the reused
/// environment/sky inspector targeting that volume.
class VolumesSection extends StatelessWidget {
  const VolumesSection({super.key, required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final volumes = controller.document.stage.volumes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Environment volumes', style: TextStyle(fontSize: 13)),
            PopupMenuButton<String>(
              tooltip: 'Add volume',
              icon: const Icon(Icons.add, size: 18),
              onSelected: (bounds) =>
                  controller.run('addEnvironmentVolume', {'bounds': bounds}),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'box', child: Text('Add box volume')),
                PopupMenuItem(
                  value: 'sphere',
                  child: Text('Add sphere volume'),
                ),
                PopupMenuItem(
                  value: 'global',
                  child: Text('Add global volume'),
                ),
              ],
            ),
          ],
        ),
        if (volumes.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text(
              'Volumes blend their look over the scene by camera position.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
        for (var i = 0; i < volumes.length; i++)
          _VolumeCard(
            // The index is the identity here; rebuild a card when its slot
            // changes contents.
            key: ValueKey('volume-$i-${volumes[i].name}'),
            controller: controller,
            index: i,
          ),
      ],
    );
  }
}

class _VolumeCard extends StatelessWidget {
  const _VolumeCard({super.key, required this.controller, required this.index});

  final EditorController controller;
  final int index;

  void _setProps(Map<String, Object> properties) {
    controller.run('setVolumeProperties', {
      'index': index,
      'properties': properties,
    });
  }

  @override
  Widget build(BuildContext context) {
    final v = controller.document.stage.volumes[index];
    final boundsType = switch (v.bounds) {
      BoxBoundsSpec() => 'box',
      SphereBoundsSpec() => 'sphere',
      _ => 'global',
    };
    final center = switch (v.bounds) {
      BoxBoundsSpec(:final center) => center,
      SphereBoundsSpec(:final center) => center,
      _ => Vector3.zero(),
    };

    Map<String, double> vecMap(Vector3 vec) => {
      'x': vec.x,
      'y': vec.y,
      'z': vec.z,
    };

    // Center axis slider: previews live (coverage updates as it drags), commits
    // on release.
    Widget centerAxis(String name, int axis) => LiveSlider(
      label: 'Center $name',
      value: center[axis],
      min: -20,
      max: 20,
      onPreview: (val) {
        final next = center.clone()..[axis] = val;
        controller.previewVolumeBounds(index, center: next);
      },
      onCommit: (val) {
        final next = center.clone()..[axis] = val;
        _setProps({'center': vecMap(next)});
      },
    );

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 8),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        title: Text(
          v.name.isEmpty ? 'Volume ${index + 1}' : v.name,
          style: const TextStyle(fontSize: 13),
        ),
        subtitle: Text(
          boundsType,
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, size: 18),
          tooltip: 'Remove volume',
          onPressed: () =>
              controller.run('removeEnvironmentVolume', {'index': index}),
        ),
        children: [
          TextFormField(
            initialValue: v.name,
            decoration: const InputDecoration(labelText: 'Name', isDense: true),
            style: const TextStyle(fontSize: 13),
            onFieldSubmitted: (name) => _setProps({'name': name}),
          ),
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Bounds', style: TextStyle(fontSize: 13)),
            trailing: DropdownButton<String>(
              value: boundsType,
              items: const [
                DropdownMenuItem(value: 'box', child: Text('Box')),
                DropdownMenuItem(value: 'sphere', child: Text('Sphere')),
                DropdownMenuItem(value: 'global', child: Text('Global')),
              ],
              onChanged: (t) => t == null ? null : _setProps({'boundsType': t}),
            ),
          ),
          if (boundsType != 'global') ...[
            centerAxis('X', 0),
            centerAxis('Y', 1),
            centerAxis('Z', 2),
          ],
          if (v.bounds is BoxBoundsSpec) ...[
            for (var axis = 0; axis < 3; axis++)
              LiveSlider(
                label: 'Half extent ${'XYZ'[axis]}',
                value: (v.bounds as BoxBoundsSpec).halfExtents[axis],
                max: 20,
                onPreview: (val) {
                  final next = (v.bounds as BoxBoundsSpec).halfExtents.clone()
                    ..[axis] = val;
                  controller.previewVolumeBounds(index, halfExtents: next);
                },
                onCommit: (val) {
                  final next = (v.bounds as BoxBoundsSpec).halfExtents.clone()
                    ..[axis] = val;
                  _setProps({'halfExtents': vecMap(next)});
                },
              ),
          ],
          if (v.bounds is SphereBoundsSpec)
            LiveSlider(
              label: 'Radius',
              value: (v.bounds as SphereBoundsSpec).radius,
              max: 20,
              onPreview: (val) =>
                  controller.previewVolumeBounds(index, radius: val),
              onCommit: (val) => _setProps({'radius': val}),
            ),
          if (boundsType != 'global')
            LiveSlider(
              label: 'Blend distance',
              value: v.blendDistance,
              max: 20,
              onPreview: (val) =>
                  controller.previewVolumeBounds(index, blendDistance: val),
              onCommit: (val) => _setProps({'blendDistance': val}),
            ),
          LiveSlider(
            label: 'Weight',
            value: v.weight,
            onPreview: (val) =>
                controller.previewVolumeBounds(index, weight: val),
            onCommit: (val) => _setProps({'weight': val}),
          ),
          LiveSlider(
            label: 'Priority',
            value: v.priority,
            max: 10,
            onPreview: (val) =>
                controller.previewVolumeBounds(index, priority: val),
            onCommit: (val) => _setProps({'priority': val}),
          ),
          const Divider(),
          EnvironmentControls(controller: controller, volumeIndex: index),
          const Divider(),
          SkySection(controller: controller, volumeIndex: index),
        ],
      ),
    );
  }
}
