/// Inspector editor for scene-wide stage settings (environment/lighting,
/// exposure, tone mapping, sky), shown when no node is selected. The same
/// environment and sky controls drive either the stage's global environment
/// resource or a volume component's, picked by the resource passed in.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
// ignore: implementation_imports
import 'package:scene/scene.dart';
// ignore: implementation_imports
import 'package:vector_math/vector_math.dart' show Vector3;

import '../shell/editor_theme.dart';
import 'weather_controls.dart';
import '../controller/editor_controller.dart';
import '../assets/environment_image_picker.dart';
import '../assets/environment_thumbnail.dart';
import '../io/scene_io.dart';
import 'property_editors.dart';
import 'live_fields.dart';
import 'resource_origin.dart';
import 'resource_slot_card.dart';

const _toneMappingModes = ['pbrNeutral', 'aces', 'reinhard', 'linear', 'agx'];

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
    // No heading of its own: this is the whole content of the Scene Settings
    // dialog, which is already titled.
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        InspectorAccordion(
          identity: environment?.id,
          initiallyExpanded: const {0, 1},
          children: [
            InspectorAccordionItem(
              title: const Text('Environment lighting'),
              child: EnvironmentControls(
                controller: controller,
                environment: environment,
                allowEnvironmentImport: true,
              ),
            ),
            InspectorAccordionItem(
              title: const Text('Background'),
              child: SkySection(
                controller: controller,
                environment: environment,
                showHeading: false,
              ),
            ),
            InspectorAccordionItem(
              title: const Text('Color management'),
              child: ColorManagementControls(
                controller: controller,
                environment: environment,
              ),
            ),
            InspectorAccordionItem(
              title: const Text('Rendering'),
              child: StageRenderControls(
                controller: controller,
                environment: environment,
              ),
            ),
          ],
        ),
        EnvironmentEffectsControls(
          controller: controller,
          environment: environment,
        ),
      ],
    );
  }
}

/// Image-based lighting and reflection controls for an environment resource.
class EnvironmentControls extends StatelessWidget {
  const EnvironmentControls({
    super.key,
    required this.controller,
    this.environment,
    this.volumeNodeId,
    this.allowEnvironmentImport = false,
  });

  final EditorController controller;

  /// The environment resource to edit (the stage's global one or a volume's).
  final EnvironmentResource? environment;

  /// When set (a volume component's environment), slider drags preview onto
  /// that node's live volume; otherwise preview targets the stage/global.
  final LocalId? volumeNodeId;

  /// Whether the source image may be replaced from a native file dialog.
  final bool allowEnvironmentImport;

  void _set(Map<String, Object> properties) {
    final env = environment;
    if (env == null) return;
    controller.run('setEnvironmentProperties', {
      'environmentId': env.id.toToken(),
      'properties': properties,
    });
  }

  void _previewIntensity(double value) {
    final node = volumeNodeId;
    if (node != null) {
      controller.previewVolumeStage(node, environmentIntensity: value);
    } else {
      controller.previewStage(environmentIntensity: value);
    }
  }

  Future<void> _pickEnvironmentImage(
    BuildContext context, {
    required bool showAsBackground,
  }) async {
    if (!allowEnvironmentImport) return;
    final current = environment?.environment;
    final selectedPath = current is AssetEnvironment
        ? controller.resolveAssetPath(current.asset.key)
        : null;
    final path = await showEnvironmentImagePicker(
      context,
      projectDirectory: controller.baseDirectory,
      selectedPath: selectedPath,
    );
    if (path == null) return;
    await importEnvironmentMap(
      controller,
      path,
      environmentId: environment?.id,
      showAsBackground: showAsBackground,
    );
  }

  void _removeEnvironmentImage() {
    final env = environment;
    if (env == null) return;
    controller.run('setEnvironmentImage', {
      'environmentId': env.id.toToken(),
      'asset': '',
    });
  }

  @override
  Widget build(BuildContext context) {
    final env = environment;
    if (env == null) return const SizedBox.shrink();
    final envType = switch (env.environment) {
      EmptyEnvironment() => 'empty',
      AssetEnvironment() => 'asset',
      ConstantEnvironment() => 'constant',
      StudioEnvironment() => 'studio',
      PayloadEnvironment() => 'embedded',
    };
    final usesEnvironmentBackground = env.skybox?.source is EnvironmentSkySpec;
    final asset = env.environment is AssetEnvironment
        ? (env.environment as AssetEnvironment).asset
        : null;
    final assetPath = asset == null
        ? null
        : controller.resolveAssetPath(asset.key);
    final payloadId = env.environment is PayloadEnvironment
        ? (env.environment as PayloadEnvironment).payload
        : null;
    final payload = payloadId == null
        ? null
        : controller.document.payload(payloadId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LabeledControlRow(
          label: 'Source',
          control: DropdownButton<String>(
            value: envType,
            items: const [
              DropdownMenuItem(value: 'studio', child: Text('Built-in studio')),
              DropdownMenuItem(
                value: 'asset',
                child: Text('Environment image'),
              ),
              DropdownMenuItem(
                value: 'constant',
                child: Text('Constant color'),
              ),
              DropdownMenuItem(
                value: 'embedded',
                enabled: false,
                child: Text('Embedded image'),
              ),
              DropdownMenuItem(value: 'empty', child: Text('None')),
            ],
            onChanged: (value) {
              if (value == null || value == envType) return;
              if (value == 'asset') {
                _pickEnvironmentImage(context, showAsBackground: true);
              } else {
                _set({'environment': value});
              }
            },
          ),
        ),
        if (asset != null)
          ResourceSlotCard(
            title: _assetFileName(asset.key),
            kind: env.name.isEmpty
                ? _environmentAssetKind(asset.key)
                : '${_environmentAssetKind(asset.key)} · ${env.name}',
            locality: ResourceLocality.external,
            path: asset.key,
            reference: asset.key,
            previewIcon: Icons.panorama_outlined,
            missing: assetPath == null || !File(assetPath).existsSync(),
            missingLabel: 'Environment image data is unavailable',
            preview: assetPath == null
                ? null
                : EnvironmentThumbnail(path: assetPath),
            onReplace: allowEnvironmentImport
                ? () => _pickEnvironmentImage(
                    context,
                    showAsBackground: usesEnvironmentBackground,
                  )
                : null,
            onRemove: allowEnvironmentImport ? _removeEnvironmentImage : null,
            removeTooltip: 'Remove environment image',
          ),
        if (payloadId != null)
          ResourceSlotCard(
            title: 'Embedded environment image',
            kind: env.name.isEmpty
                ? 'Embedded ${payload?.format ?? 'image'}'
                : 'Embedded ${payload?.format ?? 'image'} · ${env.name}',
            locality: ResourceLocality.builtIn,
            reference: payloadId.toToken(),
            previewIcon: Icons.panorama_outlined,
            missing: payload?.bytes == null,
            missingLabel: 'Environment image data is unavailable',
            preview: payload?.bytes == null
                ? null
                : EnvironmentThumbnail.memory(
                    bytes: payload!.bytes!,
                    cacheKey: payloadId.toToken(),
                  ),
            onReplace: allowEnvironmentImport
                ? () => _pickEnvironmentImage(
                    context,
                    showAsBackground: usesEnvironmentBackground,
                  )
                : null,
            onRemove: allowEnvironmentImport ? _removeEnvironmentImage : null,
            removeTooltip: 'Remove environment image',
          ),
        if (env.environment case ConstantEnvironment(:final color))
          ColorEditor(
            channelBuilder: sliderColorChannel,
            label: 'Ambient color',
            r: color.x,
            g: color.y,
            b: color.z,
            a: 1,
            showAlpha: false,
            onPreview: (_, _, _, _) {},
            onCommit: (r, g, b, _) => _set({
              'environmentColor': {'x': r, 'y': g, 'z': b},
            }),
          ),
        if (envType != 'asset' &&
            envType != 'embedded' &&
            allowEnvironmentImport)
          Align(
            alignment: Alignment.centerLeft,
            child: FButton(
              variant: .outline,
              size: .xs,
              mainAxisSize: .min,
              onPress: () =>
                  _pickEnvironmentImage(context, showAsBackground: true),
              prefix: const Icon(Icons.panorama_outlined, size: 14),
              child: const Text('Import environment image…'),
            ),
          ),
        SliderNumberField(
          label: 'Intensity',
          value: env.environmentIntensity,
          max: 12,
          onPreview: _previewIntensity,
          onCommit: (v) => _set({'environmentIntensity': v}),
        ),
        SliderNumberField(
          label: 'Rotation',
          value: env.environmentRotationY * 180 / math.pi,
          min: -180,
          max: 180,
          onPreview: (_) {},
          onCommit: (v) => _set({'environmentRotationY': v * math.pi / 180}),
        ),
        LabeledControlRow(
          label: 'Reflection resolution',
          control: DropdownButton<int>(
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
            onChanged: (v) => v == null ? null : _set({'radianceCubeSize': v}),
          ),
        ),
      ],
    );
  }
}

String _assetFileName(String key) => key.replaceAll('\\', '/').split('/').last;

String _environmentAssetKind(String key) {
  final lower = key.toLowerCase();
  if (lower.endsWith('.exr')) return 'OpenEXR environment';
  if (lower.endsWith('.hdr')) return 'Radiance HDR environment';
  return 'Image environment';
}

class ColorManagementControls extends StatelessWidget {
  const ColorManagementControls({
    super.key,
    required this.controller,
    required this.environment,
    this.volumeNodeId,
  });

  final EditorController controller;
  final EnvironmentResource? environment;
  final LocalId? volumeNodeId;

  void _preview(String key, Object value) {
    final env = environment;
    if (env == null) return;
    controller.previewEnvironmentProperty(env.id, key, value);
  }

  void _set(String key, Object value) {
    final env = environment;
    if (env == null) return;
    controller.run('setEnvironmentProperties', {
      'environmentId': env.id.toToken(),
      'properties': {key: value},
    });
  }

  void _previewExposure(double exposure) {
    final node = volumeNodeId;
    if (node != null) {
      controller.previewVolumeStage(node, exposure: exposure);
    } else {
      controller.previewStage(exposure: exposure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final env = environment;
    if (env == null) return const SizedBox.shrink();
    return Column(
      children: [
        SliderNumberField(
          label: 'Exposure',
          value: env.exposure,
          max: 8,
          onPreview: _previewExposure,
          onCommit: (v) => _set('exposure', v),
        ),
        LabeledControlRow(
          label: 'Tone mapping',
          control: DropdownButton<String>(
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
        if (env.toneMapping == 'agx') ...[
          SliderNumberField(
            label: 'AgX white point',
            value: env.agxWhite,
            min: 1,
            max: 64,
            onPreview: (v) => _preview('agxWhite', v),
            onCommit: (v) => _set('agxWhite', v),
          ),
          SliderNumberField(
            label: 'AgX contrast',
            value: env.agxContrast,
            min: 0.5,
            max: 2,
            onPreview: (v) => _preview('agxContrast', v),
            onCommit: (v) => _set('agxContrast', v),
          ),
        ],
      ],
    );
  }
}

class StageRenderControls extends StatelessWidget {
  const StageRenderControls({
    super.key,
    required this.controller,
    this.environment,
  });

  final EditorController controller;

  /// The environment resource carrying the anti-aliasing tuning shown under
  /// the mode selector; null leaves the selected mode's settings out.
  final EnvironmentResource? environment;

  void _set(String key, Object value) => controller.run('setStageProperties', {
    'properties': {key: value},
  });

  @override
  Widget build(BuildContext context) {
    final stage = controller.document.stage;
    return Column(
      children: [
        LabeledControlRow(
          label: 'Anti-aliasing',
          control: DropdownButton<String>(
            value: stage.antiAliasingMode,
            // The full set AntiAliasingMode carries. SMAA and TAA shipped in
            // the engine and were reachable from code and from a hand-edited
            // document, but not from here.
            items: const [
              DropdownMenuItem(value: 'auto', child: Text('Auto')),
              DropdownMenuItem(value: 'none', child: Text('None')),
              DropdownMenuItem(value: 'msaa', child: Text('MSAA')),
              DropdownMenuItem(value: 'fxaa', child: Text('FXAA')),
              DropdownMenuItem(value: 'smaa', child: Text('SMAA')),
              DropdownMenuItem(value: 'taa', child: Text('TAA')),
            ],
            onChanged: (v) => v == null ? null : _set('antiAliasingMode', v),
          ),
        ),
        // The selected technique's own settings, inline under the selector.
        // Only TAA and SMAA have any; the rest leave this out entirely.
        _AntiAliasingSettings(
          controller: controller,
          environment: environment,
          mode: stage.antiAliasingMode,
        ),
        SliderNumberField(
          label: 'Render scale',
          value: stage.renderScale,
          min: 0.25,
          max: 2,
          onPreview: (_) {},
          onCommit: (v) => _set('renderScale', v),
        ),
        LabeledControlRow(
          label: 'Texture filtering',
          control: DropdownButton<String>(
            value: stage.filterQuality,
            items: const [
              DropdownMenuItem(value: 'none', child: Text('Nearest')),
              DropdownMenuItem(value: 'low', child: Text('Low')),
              DropdownMenuItem(value: 'medium', child: Text('Medium')),
              DropdownMenuItem(value: 'high', child: Text('High')),
            ],
            onChanged: (v) => v == null ? null : _set('filterQuality', v),
          ),
        ),
      ],
    );
  }
}

/// A muted explanatory line inside an inspector group, for stating why a
/// control is absent or inert rather than leaving the reader guessing.
class _InspectorHint extends StatelessWidget {
  const _InspectorHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11,
        color: context.theme.colors.mutedForeground,
      ),
    ),
  );
}

/// The selected anti-aliasing technique's own settings, shown inline under the
/// mode selector in the Rendering box. They live on the environment resource
/// (like the other authored effects) while the mode itself lives on the stage,
/// so this reads the stage's mode and writes environment properties.
class _AntiAliasingSettings extends StatelessWidget {
  const _AntiAliasingSettings({
    required this.controller,
    required this.environment,
    required this.mode,
  });

  final EditorController controller;
  final EnvironmentResource? environment;
  final String mode;

  void _set(String key, Object value) {
    final env = environment;
    if (env == null) return;
    controller.run('setEnvironmentProperties', {
      'environmentId': env.id.toToken(),
      'properties': {key: value},
    });
  }

  void _preview(String key, Object value) {
    final env = environment;
    if (env == null) return;
    controller.previewEnvironmentProperty(env.id, key, value);
  }

  Widget _slider(
    String label,
    String key,
    double value, {
    double min = 0,
    double max = 1,
  }) => SliderNumberField(
    label: label,
    value: value,
    min: min,
    max: max,
    onPreview: (v) => _preview(key, v),
    onCommit: (v) => _set(key, v),
  );

  Widget _integer(
    String label,
    String key,
    int value, {
    required int min,
    required int max,
  }) => SliderNumberField(
    label: label,
    value: value.toDouble(),
    min: min.toDouble(),
    max: max.toDouble(),
    scrubStep: 1,
    snapStep: 1,
    fractionDigits: 0,
    onPreview: (v) => _preview(key, v.round()),
    onCommit: (v) => _set(key, v.round()),
  );

  Widget _toggle(String label, String key, bool value, {String? description}) =>
      InspectorSwitch(
        label: label,
        description: description,
        value: value,
        onChanged: (v) => _set(key, v),
        padding: const EdgeInsets.symmetric(vertical: 5),
      );

  @override
  Widget build(BuildContext context) {
    final env = environment;
    if (env == null || (mode != 'taa' && mode != 'smaa')) {
      return const SizedBox.shrink();
    }
    final e = env.effects;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
          child: Text(
            mode == 'taa' ? 'Temporal AA' : 'SMAA',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
        if (mode == 'taa') ...[
          _slider(
            'Current weight',
            'temporalAntiAliasingMinimumCurrentWeight',
            e.temporalAntiAliasingMinimumCurrentWeight,
            min: 0.01,
          ),
          _slider(
            'Variance gamma',
            'temporalAntiAliasingVarianceGamma',
            e.temporalAntiAliasingVarianceGamma,
            min: 0.5,
            max: 2,
          ),
          _slider(
            'Sharpness',
            'temporalAntiAliasingSharpness',
            e.temporalAntiAliasingSharpness,
          ),
          _integer(
            'Jitter sequence',
            'temporalAntiAliasingJitterSequenceLength',
            e.temporalAntiAliasingJitterSequenceLength,
            min: 1,
            max: 32,
          ),
          _slider(
            'Jitter scale',
            'temporalAntiAliasingJitterScale',
            e.temporalAntiAliasingJitterScale,
          ),
          _toggle(
            'Object motion',
            'temporalAntiAliasingObjectMotion',
            e.temporalAntiAliasingObjectMotion,
            description:
                'Moving objects render a velocity buffer so they reproject '
                'without trails.',
          ),
          _toggle(
            'Skinned motion',
            'temporalAntiAliasingSkinnedMotion',
            e.temporalAntiAliasingSkinnedMotion,
            description: 'Skinned deformation contributes velocity.',
          ),
        ] else ...[
          _slider(
            'Edge threshold',
            'smaaThreshold',
            e.smaaThreshold,
            min: 0.02,
            max: 0.3,
          ),
          _integer(
            'Search steps',
            'smaaMaxSearchSteps',
            e.smaaMaxSearchSteps,
            min: 4,
            max: 112,
          ),
          _integer(
            'Diagonal steps',
            'smaaMaxDiagonalSearchSteps',
            e.smaaMaxDiagonalSearchSteps,
            min: 1,
            max: 20,
          ),
          _slider(
            'Corner rounding',
            'smaaCornerRounding',
            e.smaaCornerRounding,
            max: 100,
          ),
        ],
      ],
    );
  }
}

/// Complete authored rendering look shared by the stage and environment boxes.
class EnvironmentEffectsControls extends StatelessWidget {
  const EnvironmentEffectsControls({
    super.key,
    required this.controller,
    required this.environment,
  });

  final EditorController controller;
  final EnvironmentResource? environment;

  void _set(String key, Object value) {
    final env = environment;
    if (env == null) return;
    controller.run('setEnvironmentProperties', {
      'environmentId': env.id.toToken(),
      'properties': {key: value},
    });
  }

  void _preview(String key, Object value) {
    final env = environment;
    if (env == null) return;
    controller.previewEnvironmentProperty(env.id, key, value);
  }

  Widget _slider(
    String label,
    String key,
    double value, {
    double min = 0,
    double max = 1,
  }) => SliderNumberField(
    label: label,
    value: value,
    min: min,
    max: max,
    onPreview: (v) => _preview(key, v),
    onCommit: (v) => _set(key, v),
  );

  Widget _integer(
    String label,
    String key,
    int value, {
    required int min,
    required int max,
  }) => SliderNumberField(
    label: label,
    value: value.toDouble(),
    min: min.toDouble(),
    max: max.toDouble(),
    scrubStep: 1,
    snapStep: 1,
    fractionDigits: 0,
    onPreview: (v) => _preview(key, v.round()),
    onCommit: (v) => _set(key, v.round()),
  );

  Widget _toggle(String label, String key, bool value, {String? description}) =>
      InspectorSwitch(
        label: label,
        description: description,
        value: value,
        onChanged: (v) => _set(key, v),
        padding: const EdgeInsets.symmetric(vertical: 5),
      );

  Widget _select(
    String label,
    String key,
    String value,
    List<(String, String)> options,
  ) => LabeledControlRow(
    label: label,
    control: DropdownButton<String>(
      value: options.any((o) => o.$1 == value) ? value : options.first.$1,
      items: [
        for (final option in options)
          DropdownMenuItem(value: option.$1, child: Text(option.$2)),
      ],
      onChanged: (v) => v == null ? null : _set(key, v),
    ),
  );

  Widget _vectorStepped(
    String label,
    String key,
    Vector3 value, {
    required double step,
  }) => Vec3Field(
    label: label,
    x: value.x,
    y: value.y,
    z: value.z,
    scrubStep: step,
    snapStep: step,
    onSubmit: (value) => _set(key, value),
  );

  Widget _vector(String label, String key, Vector3 value) => Vec3Field(
    label: label,
    x: value.x,
    y: value.y,
    z: value.z,
    scrubStep: 0.01,
    snapStep: 0.1,
    onSubmit: (value) => _set(key, value),
  );

  Widget _color(
    String label,
    String key,
    Vector3 value, {
    double channelMax = 1,
  }) => ColorEditor(
    channelBuilder: sliderColorChannel,
    label: label,
    r: value.x,
    g: value.y,
    b: value.z,
    a: 1,
    channelMax: channelMax,
    showAlpha: false,
    onPreview: (_, _, _, _) {},
    onCommit: (r, g, b, _) => _set(key, {'x': r, 'y': g, 'z': b}),
  );

  Widget _title(BuildContext context, String label, bool enabled) {
    final colors = context.theme.colors;
    return Row(
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            color: enabled ? colors.primary : colors.mutedForeground,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        const SizedBox(width: 7),
        Expanded(child: Text(label)),
        Text(
          enabled ? 'ON' : 'OFF',
          style: TextStyle(
            color: enabled ? colors.primary : colors.mutedForeground,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.7,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final env = environment;
    if (env == null) return const SizedBox.shrink();
    final e = env.effects;
    return InspectorAccordion(
      identity: env.id,
      children: [
        InspectorAccordionItem(
          title: _title(context, 'Auto exposure', e.autoExposureEnabled),
          child: Column(
            children: [
              _toggle('Enabled', 'autoExposureEnabled', e.autoExposureEnabled),
              _slider(
                'Strength',
                'autoExposureStrength',
                e.autoExposureStrength,
              ),
              _slider(
                'Compensation',
                'autoExposureCompensation',
                e.autoExposureCompensation,
                min: -8,
                max: 8,
              ),
              _slider(
                'Minimum EV',
                'autoExposureMinEv',
                e.autoExposureMinEv,
                min: -16,
                max: 0,
              ),
              _slider(
                'Maximum EV',
                'autoExposureMaxEv',
                e.autoExposureMaxEv,
                min: 0,
                max: 16,
              ),
              _slider(
                'Bright adaptation',
                'autoExposureSpeedUp',
                e.autoExposureSpeedUp,
                max: 10,
              ),
              _slider(
                'Dark adaptation',
                'autoExposureSpeedDown',
                e.autoExposureSpeedDown,
                max: 10,
              ),
            ],
          ),
        ),
        InspectorAccordionItem(
          title: _title(context, 'Color grading', e.colorGradingEnabled),
          child: Column(
            children: [
              _toggle('Enabled', 'colorGradingEnabled', e.colorGradingEnabled),
              _slider('Brightness', 'brightness', e.brightness, max: 2),
              _slider('Contrast', 'contrast', e.contrast, max: 2),
              _slider('Saturation', 'saturation', e.saturation, max: 2),
              _slider(
                'Temperature',
                'temperature',
                e.temperature,
                min: -1,
                max: 1,
              ),
              _slider('Tint', 'tint', e.tint, min: -1, max: 1),
              _vector('Lift', 'lift', e.lift),
              _vector('Gamma', 'gamma', e.gamma),
              _vector('Gain', 'gain', e.gain),
            ],
          ),
        ),
        InspectorAccordionItem(
          title: _title(context, 'Bloom', e.bloomEnabled),
          child: Column(
            children: [
              _toggle('Enabled', 'bloomEnabled', e.bloomEnabled),
              _slider('Threshold', 'bloomThreshold', e.bloomThreshold, max: 16),
              _slider('Intensity', 'bloomIntensity', e.bloomIntensity, max: 4),
              _slider('Scatter', 'bloomScatter', e.bloomScatter),
            ],
          ),
        ),
        InspectorAccordionItem(
          title: _title(context, 'Lens flare', e.lensFlareEnabled),
          child: Column(
            children: [
              _toggle('Enabled', 'lensFlareEnabled', e.lensFlareEnabled),
              _slider(
                'Intensity',
                'lensFlareIntensity',
                e.lensFlareIntensity,
                max: 4,
              ),
              _slider(
                'Ghosts',
                'lensFlareGhostCount',
                e.lensFlareGhostCount.toDouble(),
                max: 8,
              ),
              _slider(
                'Ghost spacing',
                'lensFlareGhostSpacing',
                e.lensFlareGhostSpacing,
              ),
              _slider(
                'Halo radius',
                'lensFlareHaloRadius',
                e.lensFlareHaloRadius,
              ),
              _slider(
                'Halo intensity',
                'lensFlareHaloIntensity',
                e.lensFlareHaloIntensity,
                max: 4,
              ),
              _slider(
                'Dispersion',
                'lensFlareChromaticAberration',
                e.lensFlareChromaticAberration,
                max: 0.05,
              ),
            ],
          ),
        ),
        InspectorAccordionItem(
          title: _title(
            context,
            'Ambient occlusion',
            e.ambientOcclusionEnabled,
          ),
          child: Column(
            children: [
              _toggle(
                'Enabled',
                'ambientOcclusionEnabled',
                e.ambientOcclusionEnabled,
              ),
              _select(
                'Method',
                'ambientOcclusionMethod',
                e.ambientOcclusionMethod,
                const [
                  ('obscurance', 'Obscurance'),
                  ('groundTruth', 'Ground truth'),
                ],
              ),
              _slider(
                'Radius',
                'ambientOcclusionRadius',
                e.ambientOcclusionRadius,
                max: 10,
              ),
              _slider(
                'Intensity',
                'ambientOcclusionIntensity',
                e.ambientOcclusionIntensity,
                max: 8,
              ),
              _slider(
                'Power',
                'ambientOcclusionPower',
                e.ambientOcclusionPower,
                max: 4,
              ),
              _slider(
                'Detail',
                'ambientOcclusionDetail',
                e.ambientOcclusionDetail,
              ),
              _slider(
                'Bias',
                'ambientOcclusionBias',
                e.ambientOcclusionBias,
                max: 1,
              ),
              _slider(
                'Horizon angle',
                'ambientOcclusionHorizonAngle',
                e.ambientOcclusionHorizonAngle,
                max: 1,
              ),
              _slider(
                'Direct light affect',
                'ambientOcclusionDirectLightAffect',
                e.ambientOcclusionDirectLightAffect,
              ),
              _slider(
                'Multi bounce',
                'ambientOcclusionMultiBounce',
                e.ambientOcclusionMultiBounce,
              ),
              _integer(
                'Samples',
                'ambientOcclusionSampleCount',
                e.ambientOcclusionSampleCount,
                min: 4,
                max: 64,
              ),
              _integer(
                'Slices',
                'ambientOcclusionSliceCount',
                e.ambientOcclusionSliceCount,
                min: 1,
                max: 8,
              ),
              _integer(
                'Steps per slice',
                'ambientOcclusionStepsPerSlice',
                e.ambientOcclusionStepsPerSlice,
                min: 1,
                max: 8,
              ),
              _toggle(
                'Visibility bitmask',
                'ambientOcclusionVisibilityBitmask',
                e.ambientOcclusionVisibilityBitmask,
              ),
              _slider(
                'Thickness',
                'ambientOcclusionThickness',
                e.ambientOcclusionThickness,
                max: 4,
              ),
              _slider(
                'Thickness heuristic',
                'ambientOcclusionThicknessHeuristic',
                e.ambientOcclusionThicknessHeuristic,
              ),
              _toggle(
                'Bent normals',
                'ambientOcclusionBentNormals',
                e.ambientOcclusionBentNormals,
              ),
              _slider(
                'Indirect light',
                'ambientOcclusionIndirectLight',
                e.ambientOcclusionIndirectLight,
                max: 4,
              ),
              _toggle(
                'Half resolution',
                'ambientOcclusionHalfResolution',
                e.ambientOcclusionHalfResolution,
              ),
              _toggle(
                'Depth mip chain',
                'ambientOcclusionDepthMipChain',
                e.ambientOcclusionDepthMipChain,
              ),
              _select(
                'Specular occlusion',
                'ambientOcclusionSpecularMode',
                e.ambientOcclusionSpecularMode,
                const [
                  ('none', 'None'),
                  ('simple', 'Simple'),
                  ('bentCone', 'Bent cone'),
                ],
              ),
            ],
          ),
        ),
        InspectorAccordionItem(
          title: _title(
            context,
            'Screen-space reflections',
            e.screenSpaceReflectionsEnabled,
          ),
          child: Column(
            children: [
              _toggle(
                'Enabled',
                'screenSpaceReflectionsEnabled',
                e.screenSpaceReflectionsEnabled,
              ),
              _slider(
                'Intensity',
                'screenSpaceReflectionsIntensity',
                e.screenSpaceReflectionsIntensity,
                max: 4,
              ),
              _slider(
                'Maximum distance',
                'screenSpaceReflectionsMaxDistance',
                e.screenSpaceReflectionsMaxDistance,
                max: 500,
              ),
              _slider(
                'Thickness',
                'screenSpaceReflectionsThickness',
                e.screenSpaceReflectionsThickness,
                max: 5,
              ),
              _slider(
                'Stride',
                'screenSpaceReflectionsStride',
                e.screenSpaceReflectionsStride,
                min: 1,
                max: 32,
              ),
              _integer(
                'Maximum steps',
                'screenSpaceReflectionsMaxSteps',
                e.screenSpaceReflectionsMaxSteps,
                min: 1,
                max: 256,
              ),
              _slider(
                'Blur',
                'screenSpaceReflectionsBlur',
                e.screenSpaceReflectionsBlur,
              ),
              _slider(
                'Distance fade start',
                'screenSpaceReflectionsDistanceFadeStart',
                e.screenSpaceReflectionsDistanceFadeStart,
              ),
              _slider(
                'Resolution scale',
                'screenSpaceReflectionsResolutionScale',
                e.screenSpaceReflectionsResolutionScale,
                min: 0.25,
                max: 1,
              ),
            ],
          ),
        ),
        InspectorAccordionItem(
          title: _title(
            context,
            'Global illumination',
            e.globalIlluminationEnabled,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _toggle(
                'Enabled',
                'globalIlluminationEnabled',
                e.globalIlluminationEnabled,
              ),
              _select(
                'Volume',
                'globalIlluminationVolumeMode',
                e.globalIlluminationVolumeMode,
                const [
                  ('fitScene', 'Fit scene'),
                  ('followCamera', 'Follow camera'),
                  ('component', 'Placed volumes'),
                ],
              ),
              // Bounds and density are per-volume when volumes are placed
              // (the component supplies them), and global otherwise.
              if (e.globalIlluminationVolumeMode == 'component')
                const _InspectorHint(
                  'Bounds and probe counts come from the Irradiance Volume '
                  'components placed in the scene.',
                )
              else ...[
                _vectorStepped(
                  'Probe counts',
                  'globalIlluminationResolution',
                  e.globalIlluminationResolution,
                  step: 1,
                ),
                _vector(
                  'Extents',
                  'globalIlluminationExtents',
                  e.globalIlluminationExtents,
                ),
              ],
              _slider(
                'Intensity',
                'globalIlluminationIntensity',
                e.globalIlluminationIntensity,
                max: 4,
              ),
              _toggle(
                'Bake only',
                'globalIlluminationBakeOnly',
                e.globalIlluminationBakeOnly,
                description:
                    'Freeze the field instead of updating it each frame.',
              ),
              // TODO(gi-bake-action): drive Scene.bakeIrradianceField from a
              // Bake button here, stepping the returned stepper across frames
              // with a progress indicator; the settings alone cannot start a
              // bake.
              InspectorAccordion(
                identity: environment?.id,
                children: [
                  InspectorAccordionItem(
                    title: const Text('Advanced'),
                    child: Column(
                      children: [
                        _slider(
                          'Hysteresis',
                          'globalIlluminationHysteresis',
                          e.globalIlluminationHysteresis,
                        ),
                        _slider(
                          'Shadow bias',
                          'globalIlluminationShadowBias',
                          e.globalIlluminationShadowBias,
                          max: 2,
                        ),
                        _slider(
                          'Visibility',
                          'globalIlluminationVisibility',
                          e.globalIlluminationVisibility,
                        ),
                        _slider(
                          'Visibility bias',
                          'globalIlluminationVisibilityBias',
                          e.globalIlluminationVisibilityBias,
                          max: 1,
                        ),
                        _integer(
                          'Probe update budget',
                          'globalIlluminationProbeUpdateBudget',
                          e.globalIlluminationProbeUpdateBudget,
                          min: 0,
                          max: 4096,
                        ),
                        _select(
                          'Injection resolution',
                          'globalIlluminationInjectionResolution',
                          e.globalIlluminationInjectionResolution,
                          const [
                            ('half', 'Half'),
                            ('quarter', 'Quarter'),
                            ('eighth', 'Eighth'),
                          ],
                        ),
                        _slider(
                          'Firefly clamp',
                          'globalIlluminationFireflyClamp',
                          e.globalIlluminationFireflyClamp,
                          max: 32,
                        ),
                        _slider(
                          'Emissive boost',
                          'globalIlluminationEmissiveBoost',
                          e.globalIlluminationEmissiveBoost,
                          max: 8,
                        ),
                        _toggle(
                          'Update when idle only',
                          'globalIlluminationUpdateWhenIdleOnly',
                          e.globalIlluminationUpdateWhenIdleOnly,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        InspectorAccordionItem(
          title: _title(context, 'Fog', e.fogEnabled),
          child: Column(
            children: [
              _toggle('Enabled', 'fogEnabled', e.fogEnabled),
              _select('Mode', 'fogMode', e.fogMode, const [
                ('none', 'None'),
                ('linear', 'Linear'),
                ('exponential', 'Exponential'),
                ('exponentialSquared', 'Exponential squared'),
              ]),
              _color('Color', 'fogColor', e.fogColor),
              _slider(
                'Sky influence',
                'fogSkyColorInfluence',
                e.fogSkyColorInfluence,
              ),
              _slider('Density', 'fogDensity', e.fogDensity, max: 1),
              _slider('Start', 'fogStart', e.fogStart, max: 1000),
              _slider('End', 'fogEnd', e.fogEnd, max: 5000),
              _slider('Maximum opacity', 'fogMaxOpacity', e.fogMaxOpacity),
              _slider(
                'Cutoff distance',
                'fogCutoffDistance',
                e.fogCutoffDistance,
                max: 5000,
              ),
              _slider(
                'Height',
                'fogHeight',
                e.fogHeight,
                min: -1000,
                max: 1000,
              ),
              _slider(
                'Height falloff',
                'fogHeightFalloff',
                e.fogHeightFalloff,
                max: 10,
              ),
              _slider(
                'Sun in-scatter',
                'fogSunInScatter',
                e.fogSunInScatter,
                max: 8,
              ),
              _slider(
                'Sun in-scatter exponent',
                'fogSunInScatterExponent',
                e.fogSunInScatterExponent,
                min: 1,
                max: 128,
              ),
            ],
          ),
        ),
        InspectorAccordionItem(
          title: _title(context, 'God rays', e.godRaysEnabled),
          child: Column(
            children: [
              _toggle('Enabled', 'godRaysEnabled', e.godRaysEnabled),
              _slider(
                'Intensity',
                'godRaysIntensity',
                e.godRaysIntensity,
                max: 8,
              ),
              _slider('Density', 'godRaysDensity', e.godRaysDensity, max: 4),
              _slider(
                'Anisotropy',
                'godRaysAnisotropy',
                e.godRaysAnisotropy,
                min: -0.95,
                max: 0.95,
              ),
              _integer(
                'Steps',
                'godRaysStepCount',
                e.godRaysStepCount,
                min: 1,
                max: 64,
              ),
              _slider(
                'Maximum distance',
                'godRaysMaxDistance',
                e.godRaysMaxDistance,
                max: 2000,
              ),
              _slider('Jitter', 'godRaysJitter', e.godRaysJitter, max: 2),
              _color('Color', 'godRaysColor', e.godRaysColor, channelMax: 8),
            ],
          ),
        ),
        InspectorAccordionItem(
          title: _title(context, 'Depth of field', e.depthOfFieldEnabled),
          child: Column(
            children: [
              _toggle('Enabled', 'depthOfFieldEnabled', e.depthOfFieldEnabled),
              _slider(
                'Focus distance',
                'depthOfFieldFocusDistance',
                e.depthOfFieldFocusDistance,
                max: 2000,
              ),
              _slider(
                'F-stop',
                'depthOfFieldFStop',
                e.depthOfFieldFStop,
                min: 0.1,
                max: 32,
              ),
              _slider(
                'Focal length',
                'depthOfFieldFocalLength',
                e.depthOfFieldFocalLength,
                max: 0.3,
              ),
              _slider(
                'Sensor height',
                'depthOfFieldSensorHeight',
                e.depthOfFieldSensorHeight,
                min: 0.001,
                max: 0.1,
              ),
              _slider(
                'Blur scale',
                'depthOfFieldBlurScale',
                e.depthOfFieldBlurScale,
                max: 4,
              ),
              _slider(
                'Foreground blur',
                'depthOfFieldMaxForegroundBlur',
                e.depthOfFieldMaxForegroundBlur,
                max: 64,
              ),
              _slider(
                'Background blur',
                'depthOfFieldMaxBackgroundBlur',
                e.depthOfFieldMaxBackgroundBlur,
                max: 64,
              ),
              _integer(
                'Aperture blades',
                'depthOfFieldBladeCount',
                e.depthOfFieldBladeCount,
                min: 0,
                max: 16,
              ),
              _slider(
                'Blade rotation',
                'depthOfFieldBladeRotation',
                e.depthOfFieldBladeRotation,
                min: -math.pi,
                max: math.pi,
              ),
              _slider(
                'Blade curvature',
                'depthOfFieldBladeCurvature',
                e.depthOfFieldBladeCurvature,
              ),
              _select(
                'Quality',
                'depthOfFieldQuality',
                e.depthOfFieldQuality,
                const [('low', 'Low'), ('medium', 'Medium'), ('high', 'High')],
              ),
            ],
          ),
        ),
        InspectorAccordionItem(
          title: _title(context, 'Vignette', e.vignetteEnabled),
          child: Column(
            children: [
              _toggle('Enabled', 'vignetteEnabled', e.vignetteEnabled),
              _slider('Intensity', 'vignetteIntensity', e.vignetteIntensity),
              _slider('Radius', 'vignetteRadius', e.vignetteRadius),
              _slider('Smoothness', 'vignetteSmoothness', e.vignetteSmoothness),
            ],
          ),
        ),
        InspectorAccordionItem(
          title: _title(
            context,
            'Chromatic aberration',
            e.chromaticAberrationEnabled,
          ),
          child: Column(
            children: [
              _toggle(
                'Enabled',
                'chromaticAberrationEnabled',
                e.chromaticAberrationEnabled,
              ),
              _slider(
                'Intensity',
                'chromaticAberrationIntensity',
                e.chromaticAberrationIntensity,
              ),
            ],
          ),
        ),
        InspectorAccordionItem(
          title: _title(context, 'Film grain', e.filmGrainEnabled),
          child: Column(
            children: [
              _toggle('Enabled', 'filmGrainEnabled', e.filmGrainEnabled),
              _slider('Intensity', 'filmGrainIntensity', e.filmGrainIntensity),
            ],
          ),
        ),
        InspectorAccordionItem(
          title: _title(
            context,
            'Global illumination',
            e.globalIlluminationEnabled,
          ),
          child: Column(
            children: [
              _toggle(
                'Enabled',
                'globalIlluminationEnabled',
                e.globalIlluminationEnabled,
                description:
                    'A grid of irradiance probes carrying bounce light, so a '
                    'surface the camera is not looking at still lights what '
                    'is around it.',
              ),
              _select(
                'Volume',
                'globalIlluminationVolumeMode',
                e.globalIlluminationVolumeMode,
                const [
                  ('followCamera', 'Follow camera'),
                  ('fitScene', 'Fit scene'),
                  ('manual', 'Manual'),
                ],
              ),
              _vector(
                'Resolution',
                'globalIlluminationResolution',
                e.globalIlluminationResolution,
              ),
              _vector(
                'Extents',
                'globalIlluminationExtents',
                e.globalIlluminationExtents,
              ),
              _slider(
                'Intensity',
                'globalIlluminationIntensity',
                e.globalIlluminationIntensity,
                max: 4,
              ),
              _slider(
                'Emissive boost',
                'globalIlluminationEmissiveBoost',
                e.globalIlluminationEmissiveBoost,
                max: 8,
              ),
              _slider(
                'Hysteresis',
                'globalIlluminationHysteresis',
                e.globalIlluminationHysteresis,
              ),
              _slider(
                'Visibility',
                'globalIlluminationVisibility',
                e.globalIlluminationVisibility,
              ),
              _slider(
                'Visibility bias',
                'globalIlluminationVisibilityBias',
                e.globalIlluminationVisibilityBias,
                max: 0.5,
              ),
              _slider(
                'Shadow bias',
                'globalIlluminationShadowBias',
                e.globalIlluminationShadowBias,
                max: 2,
              ),
              _slider(
                'Firefly clamp',
                'globalIlluminationFireflyClamp',
                e.globalIlluminationFireflyClamp,
                max: 32,
              ),
              _select(
                'Injection resolution',
                'globalIlluminationInjectionResolution',
                e.globalIlluminationInjectionResolution,
                const [
                  ('full', 'Full'),
                  ('half', 'Half'),
                  ('quarter', 'Quarter'),
                  ('eighth', 'Eighth'),
                ],
              ),
              _integer(
                'Probe update budget',
                'globalIlluminationProbeUpdateBudget',
                e.globalIlluminationProbeUpdateBudget,
                min: 0,
                max: 1024,
              ),
              _toggle(
                'Update when idle only',
                'globalIlluminationUpdateWhenIdleOnly',
                e.globalIlluminationUpdateWhenIdleOnly,
                description:
                    'Refresh the field only while the camera is still, so a '
                    'moving shot pays nothing for it.',
              ),
              _toggle(
                'Bake only',
                'globalIlluminationBakeOnly',
                e.globalIlluminationBakeOnly,
                description:
                    'Light from the baked field alone, with no refresh at '
                    'runtime.',
              ),
            ],
          ),
        ),
        InspectorAccordionItem(
          // Switched on by the Rendering section's anti-aliasing mode rather
          // than by a toggle here: two switches for one thing can disagree,
          // and the mode is the one the engine reads.
          title: _title(
            context,
            'Temporal anti-aliasing',
            e.temporalAntiAliasingEnabled,
          ),
          child: Column(
            children: [
              _slider(
                'Minimum current weight',
                'temporalAntiAliasingMinimumCurrentWeight',
                e.temporalAntiAliasingMinimumCurrentWeight,
                max: 0.5,
              ),
              _slider(
                'Variance gamma',
                'temporalAntiAliasingVarianceGamma',
                e.temporalAntiAliasingVarianceGamma,
                min: 0.5,
                max: 2,
              ),
              _slider(
                'Sharpness',
                'temporalAntiAliasingSharpness',
                e.temporalAntiAliasingSharpness,
              ),
              _integer(
                'Jitter sequence length',
                'temporalAntiAliasingJitterSequenceLength',
                e.temporalAntiAliasingJitterSequenceLength,
                min: 2,
                max: 32,
              ),
              _slider(
                'Jitter scale',
                'temporalAntiAliasingJitterScale',
                e.temporalAntiAliasingJitterScale,
              ),
              _toggle(
                'Object motion',
                'temporalAntiAliasingObjectMotion',
                e.temporalAntiAliasingObjectMotion,
                description:
                    'Reproject moving geometry as well as the camera. Off, '
                    'moving objects leave trails.',
              ),
              _toggle(
                'Skinned motion',
                'temporalAntiAliasingSkinnedMotion',
                e.temporalAntiAliasingSkinnedMotion,
                description:
                    'Include skinned deformation in that velocity, which '
                    'keeps the previous frame\'s joint matrices alive.',
              ),
            ],
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
    this.showHeading = true,
  });

  final EditorController controller;

  /// The environment resource to edit (the stage's global one or a volume's).
  final EnvironmentResource? environment;

  /// When set, slider drags preview onto that node's live volume; otherwise
  /// preview targets the stage/global (see [EnvironmentControls.volumeNodeId]).
  final LocalId? volumeNodeId;
  final bool showHeading;

  /// Whether the weather controls lead the section.
  ///
  /// The stage's sky only. A volume's sky is a local override of the look in
  /// one region; weather is scene-wide -- it adds rain to the whole level and
  /// a lightning driver to it -- so offering it per volume would promise
  /// something a volume cannot do.
  bool get _showWeather => volumeNodeId == null;

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
      WeatherSkySpec() => 'weather',
      EnvironmentSkySpec() => 'environment',
      FmatSkySpec() => 'fmat',
      _ => 'none',
    };
    final sun = switch (source) {
      GradientSkySpec(:final sunDirection) => sunDirection,
      PhysicalSkySpec(:final sunDirection) => sunDirection,
      WeatherSkySpec(:final sunDirection) => sunDirection,
      _ => Vector3(0.4, 0.5, 0.6),
    };
    final lightScene = skyEnvironmentSpec != null;
    final sunLight = skyEnvironmentSpec?.sunLight;
    final castShadows = sunLight?.castsShadow ?? false;
    final proceduralSky =
        type == 'gradient' || type == 'physical' || type == 'weather';

    // The look is an environment resource (the stage's global one or a
    // volume's); edits target it by id.
    const skyboxCommand = 'setEnvironmentSkybox';
    const paramsCommand = 'setEnvironmentSkyParameters';
    Map<String, Object> target() => {'environmentId': env.id.toToken()};

    // The type dropdown and lighting toggles are structural (the skybox command
    // keeps the tuned parameters across them); the per-parameter fields below
    // patch the current sky. Picking a procedural sky lights the scene and
    // casts sun shadows by default (the user can then turn them off).
    Future<void> setType(String newType) async {
      final procedural =
          newType == 'gradient' ||
          newType == 'physical' ||
          newType == 'weather';
      // A shader sky needs its .fmat source; picking cancel keeps the current
      // sky. Selecting it lights the scene by default like a procedural sky
      // (the compiled sky drives the image-based lighting), but without sun
      // shadows (an arbitrary shader sky has no sun).
      String? asset;
      if (newType == 'fmat') {
        final path = await pickFmatPath();
        if (path == null) return;
        asset = referenceFmatAsset(controller.baseDirectory, path);
      }
      await controller.run(skyboxCommand, {
        'sky': newType,
        if (asset != null) 'asset': asset,
        if (procedural || newType == 'fmat') 'lightScene': true,
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
    void runSun(Map<String, Object> properties) => controller.run(
      'setEnvironmentSunLightProperties',
      {'properties': properties, ...target()},
    );
    // Preview a sun tweak on the realized global environment during a drag;
    // a volume's sun stays commit-only (the global preview path would
    // restyle the whole scene).
    void previewSun(String key, Object raw) {
      final env = environment;
      if (env == null || volumeNodeId != null) return;
      controller.previewEnvironmentSunProperty(env.id, key, raw);
    }

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
        SliderNumberField(
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
    }) => SliderNumberField(
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
      channelBuilder: sliderColorChannel,
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
        if (showHeading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text('Background', style: TextStyle(fontSize: 13)),
          ),
        // Weather leads: picking one is the fastest way to a sky that looks
        // like somewhere, and it sets the mode below on its way past.
        if (_showWeather) ...[
          WeatherControls(controller: controller),
          const SizedBox(height: 14),
          const EditorSectionHeader(label: 'Sky'),
        ],
        LabeledControlRow(
          label: 'Mode',
          control: DropdownButton<String>(
            value: type,
            items: const [
              DropdownMenuItem(value: 'none', child: Text('None')),
              DropdownMenuItem(
                value: 'environment',
                child: Text('Lighting environment'),
              ),
              DropdownMenuItem(value: 'gradient', child: Text('Gradient sky')),
              DropdownMenuItem(value: 'physical', child: Text('Physical sky')),
              DropdownMenuItem(
                value: 'weather',
                child: Text('Weather sky (clouds)'),
              ),
              DropdownMenuItem(value: 'fmat', child: Text('Shader (.fmat)')),
            ],
            onChanged: (v) => v == null ? null : setType(v),
          ),
        ),
        if (source is FmatSkySpec) ...[
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              source.asset.key,
              style: const TextStyle(fontSize: 11, color: editorMutedTextColor),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (controller.fmatLibrary.errorForKey(source.asset.key)
              case final String skyError)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                skyError,
                style: const TextStyle(fontSize: 11, color: editorErrorColor),
              ),
            ),
          scalar(
            'Intensity',
            'intensity',
            skyboxSpec?.intensity ?? 1.0,
            max: 4,
          ),
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
        ],
        if (proceduralSky) ...[
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Sun direction',
              style: TextStyle(fontSize: 12, color: editorMutedTextColor),
            ),
          ),
          axis('X', sun.x, (v) => Vector3(v, sun.y, sun.z)),
          axis('Y', sun.y, (v) => Vector3(sun.x, v, sun.z)),
          axis('Z', sun.z, (v) => Vector3(sun.x, sun.y, v)),
          InspectorSwitch(
            label: 'Light scene with sky',
            value: lightScene,
            onChanged: setLight,
            padding: const EdgeInsets.symmetric(vertical: 5),
          ),
          if (lightScene)
            InspectorSwitch(
              label: 'Cast sun shadows',
              description: 'Hard shadows that track the sun.',
              value: castShadows,
              onChanged: setShadows,
              padding: const EdgeInsets.symmetric(vertical: 5),
            ),
          if (sunLight != null)
            InspectorAccordion(
              identity: env.id,
              children: [
                InspectorAccordionItem(
                  title: const Text('Sun shadows'),
                  child: Column(
                    children: [
                      SliderNumberField(
                        label: 'Intensity scale',
                        value: sunLight.intensityScale,
                        min: 0,
                        max: 10,
                        onPreview: (v) => previewSun('intensityScale', v),
                        onCommit: (v) => runSun({'intensityScale': v}),
                      ),
                      SliderNumberField(
                        label: 'Primary priority',
                        value: sunLight.priority.toDouble(),
                        min: -10,
                        max: 10,
                        scrubStep: 1,
                        snapStep: 1,
                        fractionDigits: 0,
                        onPreview: (v) => previewSun('priority', v.round()),
                        onCommit: (v) => runSun({'priority': v.round()}),
                      ),
                      InspectorSwitch(
                        label: 'Cache static shadows',
                        value: sunLight.cacheStaticShadows,
                        onChanged: (v) => runSun({'cacheStaticShadows': v}),
                        padding: const EdgeInsets.symmetric(vertical: 5),
                      ),
                      SliderNumberField(
                        label: 'Maximum distance',
                        value: sunLight.shadowMaxDistance,
                        min: 1,
                        max: 1000,
                        onPreview: (v) => previewSun('shadowMaxDistance', v),
                        onCommit: (v) => runSun({'shadowMaxDistance': v}),
                      ),
                      SliderNumberField(
                        label: 'Fade distance',
                        value: sunLight.shadowFadeRange,
                        min: 0,
                        max: 100,
                        onPreview: (v) => previewSun('shadowFadeRange', v),
                        onCommit: (v) => runSun({'shadowFadeRange': v}),
                      ),
                      SliderNumberField(
                        label: 'Softness',
                        value: sunLight.shadowSoftness,
                        min: 0,
                        max: 2,
                        onPreview: (v) => previewSun('shadowSoftness', v),
                        onCommit: (v) => runSun({'shadowSoftness': v}),
                      ),
                      SliderNumberField(
                        label: 'Cascade distribution',
                        value: sunLight.shadowCascadeSplitLambda,
                        onPreview: (v) =>
                            previewSun('shadowCascadeSplitLambda', v),
                        onCommit: (v) =>
                            runSun({'shadowCascadeSplitLambda': v}),
                      ),
                      SliderNumberField(
                        label: 'Depth bias',
                        value: sunLight.shadowDepthBias,
                        min: 0,
                        max: 0.2,
                        onPreview: (v) => previewSun('shadowDepthBias', v),
                        onCommit: (v) => runSun({'shadowDepthBias': v}),
                      ),
                      SliderNumberField(
                        label: 'Normal bias',
                        value: sunLight.shadowNormalBias,
                        min: 0,
                        max: 0.2,
                        onPreview: (v) => previewSun('shadowNormalBias', v),
                        onCommit: (v) => runSun({'shadowNormalBias': v}),
                      ),
                      SliderNumberField(
                        label: 'Ambient shadow strength',
                        value: sunLight.shadowAmbientStrength,
                        onPreview: (v) =>
                            previewSun('shadowAmbientStrength', v),
                        onCommit: (v) => runSun({'shadowAmbientStrength': v}),
                      ),
                      SliderNumberField(
                        label: 'Cascades',
                        value: sunLight.shadowCascadeCount.toDouble(),
                        min: 1,
                        max: 4,
                        scrubStep: 1,
                        snapStep: 1,
                        fractionDigits: 0,
                        onPreview: (v) =>
                            previewSun('shadowCascadeCount', v.round()),
                        onCommit: (v) =>
                            runSun({'shadowCascadeCount': v.round()}),
                      ),
                      SliderNumberField(
                        label: 'Resolution',
                        value: sunLight.shadowMapResolution.toDouble(),
                        min: 128,
                        max: 4096,
                        scrubStep: 128,
                        snapStep: 128,
                        fractionDigits: 0,
                        onPreview: (v) =>
                            previewSun('shadowMapResolution', v.round()),
                        onCommit: (v) =>
                            runSun({'shadowMapResolution': v.round()}),
                      ),
                      LabeledControlRow(
                        label: 'Filter',
                        control: DropdownButton<String>(
                          value:
                              const [
                                'rotatedPoisson',
                                'fixedPcf',
                              ].contains(sunLight.shadowFilter)
                              ? sunLight.shadowFilter
                              : 'rotatedPoisson',
                          items: const [
                            DropdownMenuItem(
                              value: 'rotatedPoisson',
                              child: Text('Rotated Poisson'),
                            ),
                            DropdownMenuItem(
                              value: 'fixedPcf',
                              child: Text('Fixed PCF'),
                            ),
                          ],
                          onChanged: (v) =>
                              v == null ? null : runSun({'shadowFilter': v}),
                        ),
                      ),
                      LabeledControlRow(
                        label: 'Caster faces',
                        control: DropdownButton<String>(
                          value:
                              const [
                                'front',
                                'back',
                                'both',
                              ].contains(sunLight.shadowCasterFaces)
                              ? sunLight.shadowCasterFaces
                              : 'front',
                          items: const [
                            DropdownMenuItem(
                              value: 'front',
                              child: Text('Front'),
                            ),
                            DropdownMenuItem(
                              value: 'back',
                              child: Text('Back'),
                            ),
                            DropdownMenuItem(
                              value: 'both',
                              child: Text('Both'),
                            ),
                          ],
                          onChanged: (v) => v == null
                              ? null
                              : runSun({'shadowCasterFaces': v}),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
        if (source is EnvironmentSkySpec) ...[
          const Divider(height: 12),
          scalar('Blurriness', 'blurriness', source.blurriness, max: 1),
          scalar(
            'Background intensity',
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
        if (source is WeatherSkySpec) ...[
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
          InspectorAccordion(
            identity: env.id,
            children: [
              InspectorAccordionItem(
                title: const Text('Clouds'),
                child: Column(
                  children: [
                    // Coverage is a threshold the noise has to clear, so
                    // raising it grows the clouds outward rather than fading a
                    // uniform haze up from nothing.
                    scalar('Coverage', 'coverage', source.coverage),
                    scalar('Density', 'density', source.density),
                    scalar(
                      'Altitude',
                      'altitude',
                      source.altitude,
                      min: 0.2,
                      max: 6,
                    ),
                    scalar('Detail', 'detail', source.detail),
                    scalar(
                      'Edge softness',
                      'softness',
                      source.softness,
                      min: 0.005,
                      max: 0.5,
                    ),
                    scalar('Shading', 'cloudShading', source.cloudShading),
                    colorField('Cloud color', 'cloudColor', source.cloudColor),
                    scalar('Wind X', 'windX', source.wind.x, min: -3, max: 3),
                    scalar('Wind Z', 'windY', source.wind.y, min: -3, max: 3),
                  ],
                ),
              ),
              InspectorAccordionItem(
                title: const Text('Storm'),
                child: Column(
                  children: [
                    // Drains the sky toward its own extinction colour rather
                    // than toward grey, so an overcast sunset stays warm.
                    scalar('Overcast', 'stormDarkening', source.stormDarkening),
                  ],
                ),
              ),
              InspectorAccordionItem(
                title: const Text('Atmosphere'),
                child: Column(
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
                    scalar(
                      'Mie',
                      'mieCoefficient',
                      source.mieCoefficient,
                      max: 0.05,
                    ),
                    colorField('Mie color', 'mieColor', source.mieColor),
                    scalar(
                      'Mie eccentricity',
                      'mieEccentricity',
                      source.mieEccentricity,
                    ),
                    colorField(
                      'Ground color',
                      'groundColor',
                      source.groundColor,
                    ),
                  ],
                ),
              ),
            ],
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
          InspectorAccordion(
            identity: env.id,
            children: [
              InspectorAccordionItem(
                title: const Text('Atmosphere'),
                child: Column(
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
                    scalar(
                      'Mie',
                      'mieCoefficient',
                      source.mieCoefficient,
                      max: 0.05,
                    ),
                    scalar(
                      'Mie eccentricity',
                      'mieEccentricity',
                      source.mieEccentricity,
                      max: 0.99,
                    ),
                    colorField('Mie color', 'mieColor', source.mieColor),
                    colorField(
                      'Ground color',
                      'groundColor',
                      source.groundColor,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
