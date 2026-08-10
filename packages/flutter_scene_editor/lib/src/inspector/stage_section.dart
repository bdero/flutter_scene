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

import '../controller/editor_controller.dart';
import '../assets/environment_image_picker.dart';
import '../assets/environment_thumbnail.dart';
import '../io/scene_io.dart';
import 'property_editors.dart';
import 'live_fields.dart';

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
              child: StageRenderControls(controller: controller),
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
          _EnvironmentImageField(
            displayName: _assetFileName(asset.key),
            kind: _environmentAssetKind(asset.key),
            resourceName: env.name,
            reference: asset.key,
            missing: assetPath == null || !File(assetPath).existsSync(),
            preview: assetPath == null
                ? null
                : EnvironmentThumbnail(path: assetPath),
            editable: allowEnvironmentImport,
            onReplace: () => _pickEnvironmentImage(
              context,
              showAsBackground: usesEnvironmentBackground,
            ),
            onRemove: _removeEnvironmentImage,
          ),
        if (payloadId != null)
          _EnvironmentImageField(
            displayName: 'Embedded environment image',
            kind: 'Embedded ${payload?.format ?? 'image'}',
            resourceName: env.name,
            reference: payloadId.toToken(),
            missing: payload?.bytes == null,
            preview: payload?.bytes == null
                ? null
                : EnvironmentThumbnail.memory(
                    bytes: payload!.bytes!,
                    cacheKey: payloadId.toToken(),
                  ),
            editable: allowEnvironmentImport,
            onReplace: () => _pickEnvironmentImage(
              context,
              showAsBackground: usesEnvironmentBackground,
            ),
            onRemove: _removeEnvironmentImage,
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

class _EnvironmentImageField extends StatelessWidget {
  const _EnvironmentImageField({
    required this.displayName,
    required this.kind,
    required this.resourceName,
    required this.reference,
    required this.missing,
    required this.preview,
    required this.editable,
    required this.onReplace,
    required this.onRemove,
  });

  final String displayName;
  final String kind;
  final String resourceName;
  final String reference;
  final bool missing;
  final Widget? preview;
  final bool editable;
  final VoidCallback onReplace;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: reference,
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        onTap: editable ? onReplace : null,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            border: Border.all(
              color: missing ? scheme.error : scheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(5),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 3.2,
                child: ColoredBox(
                  color: scheme.surfaceContainerHighest,
                  child: missing
                      ? Center(
                          child: Icon(
                            Icons.panorama_outlined,
                            size: 26,
                            color: scheme.error,
                          ),
                        )
                      : preview!,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            missing
                                ? 'Environment image data is unavailable'
                                : resourceName.isEmpty
                                ? kind
                                : '$kind · $resourceName',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              color: missing
                                  ? scheme.error
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (editable) ...[
                      const SizedBox(width: 4),
                      FButton(
                        variant: .ghost,
                        size: .xs,
                        mainAxisSize: .min,
                        onPress: onReplace,
                        child: const Text('Replace'),
                      ),
                      Tooltip(
                        message: 'Remove environment image',
                        child: FButton.icon(
                          variant: .ghost,
                          size: .xs,
                          onPress: onRemove,
                          child: const Icon(Icons.close, size: 14),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
            onPreview: (_) {},
            onCommit: (v) => _set('agxWhite', v),
          ),
          SliderNumberField(
            label: 'AgX contrast',
            value: env.agxContrast,
            min: 0.5,
            max: 2,
            onPreview: (_) {},
            onCommit: (v) => _set('agxContrast', v),
          ),
        ],
      ],
    );
  }
}

class StageRenderControls extends StatelessWidget {
  const StageRenderControls({super.key, required this.controller});

  final EditorController controller;

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
            items: const [
              DropdownMenuItem(value: 'auto', child: Text('Auto')),
              DropdownMenuItem(value: 'none', child: Text('None')),
              DropdownMenuItem(value: 'msaa', child: Text('MSAA')),
              DropdownMenuItem(value: 'fxaa', child: Text('FXAA')),
            ],
            onChanged: (v) => v == null ? null : _set('antiAliasingMode', v),
          ),
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
    onPreview: (_) {},
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
    onPreview: (_) {},
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
              _integer(
                'Samples',
                'ambientOcclusionSampleCount',
                e.ambientOcclusionSampleCount,
                min: 4,
                max: 64,
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
                const [('none', 'None'), ('simple', 'Simple')],
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
    final sunLight = skyEnvironmentSpec?.sunLight;
    final castShadows = sunLight?.castsShadow ?? false;
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
    void runSun(Map<String, Object> properties) => controller.run(
      'setEnvironmentSunLightProperties',
      {'properties': properties, ...target()},
    );
    // TODO(sun-preview): update the realized sun during slider drags without
    // adding history entries, matching the sky-parameter preview path.
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
                        onPreview: (_) {},
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
                        onPreview: (_) {},
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
                        onPreview: (_) {},
                        onCommit: (v) => runSun({'shadowMaxDistance': v}),
                      ),
                      SliderNumberField(
                        label: 'Fade distance',
                        value: sunLight.shadowFadeRange,
                        min: 0,
                        max: 100,
                        onPreview: (_) {},
                        onCommit: (v) => runSun({'shadowFadeRange': v}),
                      ),
                      SliderNumberField(
                        label: 'Softness',
                        value: sunLight.shadowSoftness,
                        min: 0,
                        max: 2,
                        onPreview: (_) {},
                        onCommit: (v) => runSun({'shadowSoftness': v}),
                      ),
                      SliderNumberField(
                        label: 'Cascade distribution',
                        value: sunLight.shadowCascadeSplitLambda,
                        onPreview: (_) {},
                        onCommit: (v) =>
                            runSun({'shadowCascadeSplitLambda': v}),
                      ),
                      SliderNumberField(
                        label: 'Depth bias',
                        value: sunLight.shadowDepthBias,
                        min: 0,
                        max: 0.2,
                        onPreview: (_) {},
                        onCommit: (v) => runSun({'shadowDepthBias': v}),
                      ),
                      SliderNumberField(
                        label: 'Normal bias',
                        value: sunLight.shadowNormalBias,
                        min: 0,
                        max: 0.2,
                        onPreview: (_) {},
                        onCommit: (v) => runSun({'shadowNormalBias': v}),
                      ),
                      SliderNumberField(
                        label: 'Ambient shadow strength',
                        value: sunLight.shadowAmbientStrength,
                        onPreview: (_) {},
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
                        onPreview: (_) {},
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
                        onPreview: (_) {},
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
