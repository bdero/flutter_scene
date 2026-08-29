/// The Weather dock panel: time of day, and one-click weather.
///
/// Deliberately not a second sky inspector. Every field of the sky is already
/// editable in the stage inspector, and duplicating them here would be two
/// places to look. What this panel has is the two gestures the inspector
/// cannot express: dragging a clock and watching the sun move, and setting the
/// weather as one thing, which is a sky *and* the particle effect that goes
/// with it *and*, for a storm, the driver that fires the lightning.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_scene/kit.dart' show sunDirectionForHour;
import 'package:flutter_scene/scene.dart' show vfxPresetById;
import 'package:scene/scene.dart';

import '../controller/editor_controller.dart';
import '../shell/editor_theme.dart';

/// One preset weather state: what the sky does, and what falls out of it.
class WeatherPreset {
  const WeatherPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.coverage,
    required this.stormDarkening,
    required this.turbidity,
    this.softness = 0.12,
    this.density = 0.95,
    this.effect,
    this.lightning = false,
  });

  final String id;
  final String name;
  final String description;
  final IconData icon;

  /// The cloud and atmosphere settings the sky is put into.
  final double coverage;
  final double stormDarkening;
  final double turbidity;
  final double softness;
  final double density;

  /// The VFX preset added alongside the sky, or null when the weather is
  /// nothing but sky.
  final String? effect;

  /// Whether a lightning driver is added with it.
  final bool lightning;
}

/// The shipped weather states, driest first.
const List<WeatherPreset> weatherPresets = [
  WeatherPreset(
    id: 'clear',
    name: 'Clear',
    description: 'Open sky, a few high wisps.',
    icon: Icons.wb_sunny_outlined,
    coverage: 0.12,
    stormDarkening: 0,
    turbidity: 6,
    softness: 0.2,
    density: 0.7,
  ),
  WeatherPreset(
    id: 'fair',
    name: 'Fair',
    description: 'Scattered cloud with clear gaps.',
    icon: Icons.filter_drama_outlined,
    coverage: 0.45,
    stormDarkening: 0,
    turbidity: 10,
  ),
  WeatherPreset(
    id: 'overcast',
    name: 'Overcast',
    description: 'A solid deck and flat, grey light.',
    icon: Icons.cloud_outlined,
    coverage: 0.92,
    stormDarkening: 0.45,
    turbidity: 14,
    softness: 0.28,
  ),
  WeatherPreset(
    id: 'fog',
    name: 'Fog',
    description: 'Low cloud, plus drifting ground fog.',
    icon: Icons.blur_on,
    coverage: 0.7,
    stormDarkening: 0.3,
    turbidity: 18,
    softness: 0.35,
    effect: 'groundFog',
  ),
  WeatherPreset(
    id: 'rain',
    name: 'Rain',
    description: 'Heavy cloud and falling rain.',
    icon: Icons.water_drop_outlined,
    coverage: 0.95,
    stormDarkening: 0.55,
    turbidity: 16,
    softness: 0.3,
    effect: 'rain',
  ),
  WeatherPreset(
    id: 'storm',
    name: 'Thunderstorm',
    description: 'Rain, gloom, and lightning with its thunder.',
    icon: Icons.thunderstorm_outlined,
    coverage: 1.0,
    stormDarkening: 0.8,
    turbidity: 18,
    softness: 0.22,
    effect: 'rain',
    lightning: true,
  ),
  WeatherPreset(
    id: 'snow',
    name: 'Snow',
    description: 'Flat white cloud and drifting flakes.',
    icon: Icons.ac_unit,
    coverage: 0.9,
    stormDarkening: 0.35,
    turbidity: 8,
    softness: 0.34,
    effect: 'snow',
  ),
];

/// The Weather panel.
class WeatherPanel extends StatefulWidget {
  const WeatherPanel({super.key, required this.controller});

  final EditorController controller;

  @override
  State<WeatherPanel> createState() => _WeatherPanelState();
}

class _WeatherPanelState extends State<WeatherPanel> {
  EditorController get _ctrl => widget.controller;

  double _hour = 12;
  double _tilt = 0.35;
  String? _applied;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(WeatherPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// The stage's environment resource, which is what the sky hangs off.
  EnvironmentResource? get _environment {
    final ref = _ctrl.document.stage.environmentRef;
    final resource = ref == null ? null : _ctrl.document.resource(ref);
    return resource is EnvironmentResource ? resource : null;
  }

  WeatherSkySpec? get _sky {
    final source = _environment?.skybox?.source;
    return source is WeatherSkySpec ? source : null;
  }

  /// Points the sun at the hour on the clock.
  ///
  /// Runs through the same sky command the inspector uses, so dragging the
  /// clock is undoable and is one edit rather than one per frame: the slider
  /// commits on release.
  Future<void> _applySun() async {
    final env = _environment;
    if (env == null) return;
    final direction = sunDirectionForHour(_hour, tilt: _tilt);
    await _ctrl.run('setEnvironmentSkyParameters', {
      'environmentId': env.id.toToken(),
      'properties': {
        'sunDirection': {'x': direction.x, 'y': direction.y, 'z': direction.z},
      },
    });
  }

  /// Puts the scene into [preset]: the sky, the effect that falls out of it,
  /// and a storm driver where the weather has one.
  Future<void> _apply(WeatherPreset preset) async {
    setState(() => _applied = preset.id);
    final env = _environment;

    // A weather sky first: the cloud settings have nowhere to land without
    // one, and switching to it keeps whatever the current sky was tuned to.
    await _ctrl.run('setSkybox', {
      'sky': 'weather',
      'lightScene': true,
      'castShadows': preset.stormDarkening < 0.5,
    });

    final target = env ?? _environment;
    if (target != null) {
      await _ctrl.run('setEnvironmentSkyParameters', {
        'environmentId': target.id.toToken(),
        'properties': {
          'coverage': preset.coverage,
          'density': preset.density,
          'softness': preset.softness,
          'turbidity': preset.turbidity,
          'stormDarkening': preset.stormDarkening,
        },
      });
    }

    final effect = preset.effect;
    if (effect != null) await _addEffect(effect, preset.name);
    if (preset.lightning) await _addLightning();
  }

  Future<void> _addEffect(String presetId, String label) async {
    final vfx = vfxPresetById(presetId);
    if (vfx == null) return;
    final built = vfx.build();
    final properties = _ctrl.capturePropertiesOf(built);

    final before = Set.of(_ctrl.document.nodes.keys);
    await _ctrl.run('createNode', {'name': '$label ${vfx.name}'});
    final nodeId = _ctrl.document.nodes.keys.firstWhere(
      (id) => !before.contains(id),
    );
    await _ctrl.run('addComponent', {
      'nodeId': nodeId.toToken(),
      'componentType': 'particleEmitter',
    });
    if (properties != null && properties.isNotEmpty) {
      await _ctrl.run('setComponentProperties', {
        'nodeId': nodeId.toToken(),
        'componentType': 'particleEmitter',
        'properties': properties,
      });
    }
  }

  Future<void> _addLightning() async {
    final before = Set.of(_ctrl.document.nodes.keys);
    await _ctrl.run('createNode', {'name': 'Lightning'});
    final nodeId = _ctrl.document.nodes.keys.firstWhere(
      (id) => !before.contains(id),
    );
    await _ctrl.run('addComponent', {
      'nodeId': nodeId.toToken(),
      'componentType': 'lightning',
    });
  }

  @override
  Widget build(BuildContext context) {
    final sky = _sky;
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 16),
      children: [
        const EditorSectionHeader(label: 'Time of day'),
        _TimeOfDay(
          hour: _hour,
          tilt: _tilt,
          onHourChanged: (value) => setState(() => _hour = value),
          onTiltChanged: (value) => setState(() => _tilt = value),
          onCommit: _environment == null ? null : _applySun,
        ),
        const SizedBox(height: 14),
        const EditorSectionHeader(label: 'Weather'),
        if (sky == null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Picking a weather state switches the scene to the weather sky, '
              'which is what carries the clouds.',
              style: editorDetailText,
            ),
          ),
        for (final preset in weatherPresets)
          _WeatherTile(
            preset: preset,
            selected: _applied == preset.id,
            onTap: () => _apply(preset),
          ),
        if (sky != null) ...[const SizedBox(height: 12), _SkyReadout(sky: sky)],
      ],
    );
  }
}

/// The clock and the arc it swings the sun through.
class _TimeOfDay extends StatelessWidget {
  const _TimeOfDay({
    required this.hour,
    required this.tilt,
    required this.onHourChanged,
    required this.onTiltChanged,
    required this.onCommit,
  });

  final double hour;
  final double tilt;
  final ValueChanged<double> onHourChanged;
  final ValueChanged<double> onTiltChanged;
  final Future<void> Function()? onCommit;

  static String _clock(double hour) {
    final whole = hour.floor() % 24;
    final minutes = ((hour - hour.floor()) * 60).round();
    return '${whole.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}';
  }

  /// What the sky is called at this hour, so the number means something at a
  /// glance.
  static String _describe(double hour) {
    if (hour < 5 || hour >= 21) return 'Night';
    if (hour < 7) return 'Dawn';
    if (hour < 9) return 'Early morning';
    if (hour < 11) return 'Morning';
    if (hour < 14) return 'Midday';
    if (hour < 17) return 'Afternoon';
    if (hour < 19.5) return 'Golden hour';
    return 'Dusk';
  }

  @override
  Widget build(BuildContext context) {
    final direction = sunDirectionForHour(hour, tilt: tilt);
    final elevation = math.asin(direction.y.clamp(-1.0, 1.0)) * 180 / math.pi;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(_clock(hour), style: editorDialogTitleText),
            const SizedBox(width: 8),
            Text(_describe(hour), style: editorDetailText),
            const Spacer(),
            Text(
              '${elevation.toStringAsFixed(0)}° above the horizon',
              style: editorMicroText,
            ),
          ],
        ),
        Slider(
          value: hour,
          max: 24,
          divisions: 24 * 4,
          onChanged: onCommit == null ? null : onHourChanged,
          onChangeEnd: (_) => onCommit?.call(),
        ),
        Row(
          children: [
            Text('Arc tilt', style: editorDetailText),
            Expanded(
              child: Slider(
                value: tilt,
                max: 1.2,
                onChanged: onCommit == null ? null : onTiltChanged,
                onChangeEnd: (_) => onCommit?.call(),
              ),
            ),
          ],
        ),
        if (onCommit == null)
          Text(
            'The scene has no environment yet; pick a weather state to make '
            'one.',
            style: editorDetailText,
          ),
      ],
    );
  }
}

class _WeatherTile extends StatelessWidget {
  const _WeatherTile({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final WeatherPreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
          decoration: BoxDecoration(
            color: editorPanelColor,
            border: Border.all(
              color: selected ? editorAccentColor : editorLineColor,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Icon(
                preset.icon,
                size: 17,
                color: selected ? editorAccentColor : editorMutedTextColor,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(preset.name, style: editorSubheadText),
                    Text(preset.description, style: editorDetailText),
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

/// What the sky is currently set to, so the panel's own state and the
/// document's cannot drift apart unnoticed.
class _SkyReadout extends StatelessWidget {
  const _SkyReadout({required this.sky});

  final WeatherSkySpec sky;

  @override
  Widget build(BuildContext context) {
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(width: 96, child: Text(label, style: editorDetailText)),
          Text(value, style: editorBodyText),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.all(9),
      decoration: editorPanelBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Current sky', style: editorSubheadText),
          const SizedBox(height: 5),
          row('Coverage', '${(sky.coverage * 100).round()}%'),
          row('Overcast', '${(sky.stormDarkening * 100).round()}%'),
          row('Turbidity', sky.turbidity.toStringAsFixed(1)),
          row(
            'Wind',
            '${sky.wind.x.toStringAsFixed(2)}, '
                '${sky.wind.y.toStringAsFixed(2)}',
          ),
          const SizedBox(height: 5),
          Text(
            'Every field is editable under Stage in the inspector.',
            style: editorMicroText,
          ),
        ],
      ),
    );
  }
}
