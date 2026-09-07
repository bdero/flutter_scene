/// Weather, inside the sky it belongs to.
///
/// Weather is not a second sky inspector, and it is not a panel of its own
/// either: it is part of setting the skybox up. What it adds to the fields
/// beside it are the two gestures those cannot express -- dragging a clock
/// and watching the sun move, and setting the weather as one thing, which is
/// a sky *and* the effect that falls out of it *and*, for a storm, the driver
/// that fires the lightning.
///
/// The states themselves live in the engine ([weatherPresets]), so the
/// weather set from this panel, from a script, and from a flow graph is the
/// same weather.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_scene/kit.dart'
    show WeatherPreset, sunDirectionForHour, weatherPresets;
import 'package:flutter_scene/scene.dart' show vfxPresetById;
import 'package:scene/scene.dart';

import '../controller/editor_controller.dart';
import 'live_fields.dart';
import 'property_editors.dart';
import '../shell/editor_theme.dart';
import '../shell/panel_chrome.dart';

/// The glyph for the weather with this id.
///
/// The only part of a weather state that is the editor's: an engine preset
/// carries no Material icon, and should not.
IconData weatherPresetIcon(String id) => switch (id) {
  'clear' => Icons.wb_sunny_outlined,
  'fair' => Icons.filter_drama_outlined,
  'overcast' => Icons.cloud_outlined,
  'fog' => Icons.blur_on,
  'rain' => Icons.water_drop_outlined,
  'storm' => Icons.thunderstorm_outlined,
  'snow' => Icons.ac_unit,
  _ => Icons.cloud_queue,
};

/// The weather controls, shown inside the sky's own setup.
class WeatherControls extends StatefulWidget {
  const WeatherControls({super.key, required this.controller});

  final EditorController controller;

  @override
  State<WeatherControls> createState() => _WeatherControlsState();
}

class _WeatherControlsState extends State<WeatherControls> {
  EditorController get _ctrl => widget.controller;

  double _hour = 12;
  double _tilt = 0.35;
  String? _applied;

  // Wind as a heading in degrees rather than a vector, because that is how
  // anyone describes it. Panel-local until a slider is let go, so dragging
  // one does not fill the undo history with edits nobody made.
  double _windHeading = 0;
  double _windSpeed = 3;
  double _windGust = 0.35;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(WeatherControls oldWidget) {
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

  /// The node carrying the scene's storm, or null when it has none.
  LocalId? get _stormNode {
    for (final entry in _ctrl.document.nodes.entries) {
      for (final component in entry.value.components) {
        if (component.type == 'lightning') return entry.key;
      }
    }
    return null;
  }

  /// Adds a storm: the driver, and the light it flashes.
  ///
  /// The light is the part that was missing. A lightning driver finds the
  /// scene's weather sky by itself, but it has no way to reference a light --
  /// a document cannot point at a live one -- so it adopts a directional
  /// light on its own node. Without one, a storm under anything but a weather
  /// sky fired strikes and thunder into a scene where nothing changed.
  ///
  /// The light rests at zero and is driven up by each strike, so between
  /// bolts it contributes nothing.
  Future<void> _addLightning() async {
    if (_stormNode != null) return;
    final before = Set.of(_ctrl.document.nodes.keys);
    await _ctrl.run('createNode', {'name': 'Storm'});
    final nodeId = _ctrl.document.nodes.keys.firstWhere(
      (id) => !before.contains(id),
    );
    await _ctrl.run('addComponent', {
      'nodeId': nodeId.toToken(),
      'componentType': 'lightning',
    });
    await _ctrl.run('addComponent', {
      'nodeId': nodeId.toToken(),
      'componentType': 'directionalLight',
      'properties': {'intensity': 0.0, 'castsShadows': false},
    });
  }

  Future<void> _removeLightning() async {
    final nodeId = _stormNode;
    if (nodeId == null) return;
    await _ctrl.run('deleteNode', {'nodeId': nodeId.toToken()});
  }

  @override
  Widget build(BuildContext context) {
    final sky = _sky;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const EditorSectionHeader(label: 'Time of day'),
        _TimeOfDay(
          hour: _hour,
          tilt: _tilt,
          onHourChanged: (value) => setState(() => _hour = value),
          onTiltChanged: (value) => setState(() => _tilt = value),
          onCommit: _environment == null ? null : _applySun,
        ),
        const EditorSectionHeader(label: 'Weather'),
        if (sky == null)
          EditorNote(
            'Picking a weather state switches the scene to the weather sky, '
            'which is what carries the clouds.',
          ),
        for (final preset in weatherPresets)
          _WeatherTile(
            preset: preset,
            selected: _applied == preset.id,
            onTap: () => _apply(preset),
          ),
        const EditorSectionHeader(label: 'Wind'),
        EditorNote(
          _windNode == null
              ? 'One wind, read by the clouds and by anything blowing '
                    'through them. Without it every effect drifts on its '
                    'own constant and a gust reaches none of them.'
              : 'Driving the scene wind. Clouds, rain and snow all lean '
                    'with it.',
        ),
        if (_windNode == null)
          EditorActionButton(
            label: 'Add wind',
            icon: Icons.air,
            tooltip: _ctrl.document.roots.isEmpty
                ? 'Add something to the scene for the wind to blow through'
                : null,
            onPressed: _ctrl.document.roots.isEmpty ? null : _addWind,
          )
        else ...[
          _WindDial(
            heading: _windHeading,
            speed: _windSpeed,
            gust: _windGust,
            onHeadingChanged: (v) => setState(() => _windHeading = v),
            onSpeedChanged: (v) => setState(() => _windSpeed = v),
            onGustChanged: (v) => setState(() => _windGust = v),
            onCommit: _applyWind,
          ),
        ],
        const EditorSectionHeader(label: 'Storm'),
        EditorNote(
          _stormNode == null
              ? 'Lightning that lights the clouds from inside, and thunder '
                    'delayed by how far away the bolt was. It comes with a '
                    'light for the flash, since a strike under a clear sky '
                    'has no clouds to show it.'
              : 'Running. Every field of it is on the Storm node; the '
                    'flash brightness is on the light beside the driver.',
        ),
        if (_stormNode == null)
          EditorActionButton(
            label: 'Add storm',
            icon: Icons.flash_on,
            tooltip: _environment == null
                ? 'A storm needs a scene environment to light'
                : null,
            onPressed: _environment == null ? null : _addStorm,
          )
        else
          EditorActionButton(
            label: 'Remove storm',
            icon: Icons.flash_off,
            onPressed: _removeLightning,
          ),
      ],
    );
  }

  /// Adds a storm, and the weather sky it needs to be seen against.
  Future<void> _addStorm() async {
    if (_sky == null) {
      await _ctrl.run('setSkybox', {
        'sky': 'weather',
        'lightScene': true,
        'castShadows': false,
      });
    }
    await _addLightning();
  }

  /// The document node carrying the scene's wind, or null when it has none.
  LocalId? get _windNode {
    for (final entry in _ctrl.document.nodes.entries) {
      for (final component in entry.value.components) {
        if (component.type == 'wind') return entry.key;
      }
    }
    return null;
  }

  Future<void> _addWind() async {
    final roots = _ctrl.document.roots;
    if (roots.isEmpty) return;
    await _ctrl.run('addComponent', {
      'nodeId': roots.first.toToken(),
      'componentType': 'wind',
    });
    await _applyWind();
  }

  Future<void> _applyWind() async {
    final nodeId = _windNode;
    if (nodeId == null) return;
    final radians = _windHeading * math.pi / 180;
    await _ctrl.run('setComponentProperties', {
      'nodeId': nodeId.toToken(),
      'componentType': 'wind',
      'properties': {
        'direction': {'x': math.cos(radians), 'y': math.sin(radians)},
        'speed': _windSpeed,
        'gustAmplitude': _windGust,
      },
    });
  }
}

/// Wind as a compass and two sliders: which way, how hard, how gusty.
///
/// A heading in degrees rather than a vector, because "north-easterly at 12"
/// is how anyone thinks about wind and `(0.71, 0.71)` is not.
class _WindDial extends StatelessWidget {
  const _WindDial({
    required this.heading,
    required this.speed,
    required this.gust,
    required this.onHeadingChanged,
    required this.onSpeedChanged,
    required this.onGustChanged,
    required this.onCommit,
  });

  final double heading;
  final double speed;
  final double gust;
  final ValueChanged<double> onHeadingChanged;
  final ValueChanged<double> onSpeedChanged;
  final ValueChanged<double> onGustChanged;
  final Future<void> Function() onCommit;

  /// What the speed reads as, so the number means weather rather than units.
  static String _describe(double speed) {
    if (speed < 0.5) return 'Still';
    if (speed < 2) return 'Light air';
    if (speed < 5) return 'Breeze';
    if (speed < 10) return 'Strong breeze';
    if (speed < 18) return 'Gale';
    return 'Storm';
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          SizedBox(width: 96, child: Text('Heading', style: editorBodyText)),
          Expanded(
            child: Slider(
              value: heading,
              max: 360,
              onChanged: onHeadingChanged,
              onChangeEnd: (_) => onCommit(),
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(
              '${heading.round()}°',
              style: editorBodyText,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
      Row(
        children: [
          SizedBox(width: 96, child: Text('Speed', style: editorBodyText)),
          Expanded(
            child: Slider(
              value: speed,
              max: 25,
              onChanged: onSpeedChanged,
              onChangeEnd: (_) => onCommit(),
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(
              speed.toStringAsFixed(1),
              style: editorBodyText,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
      Row(
        children: [
          SizedBox(width: 96, child: Text('Gust', style: editorBodyText)),
          Expanded(
            child: Slider(
              value: gust,
              onChanged: onGustChanged,
              onChangeEnd: (_) => onCommit(),
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(
              gust.toStringAsFixed(2),
              style: editorBodyText,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.only(left: 96, top: 2),
        child: Text(_describe(speed), style: editorMicroText),
      ),
    ],
  );
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
        // On the shared column like every other property: the hour used to
        // run the panel's whole width under a heading of its own, which is
        // why this section read as a different program from the one above it.
        LabeledControlRow(
          label: 'Hour',
          control: Row(
            children: [
              SizedBox(
                width: 52,
                child: Text(
                  _clock(hour),
                  style: const TextStyle(
                    fontSize: 12,
                    color: editorValueColor,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Expanded(
                child: InspectorSlider(
                  value: hour,
                  max: 24,
                  onChanged: onCommit == null ? (_) {} : onHourChanged,
                  onChangeEnd: (_) => onCommit?.call(),
                ),
              ),
            ],
          ),
        ),
        LabeledControlRow(
          label: 'Arc tilt',
          control: InspectorSlider(
            value: tilt,
            max: 1.2,
            onChanged: onCommit == null ? (_) {} : onTiltChanged,
            onChangeEnd: (_) => onCommit?.call(),
          ),
        ),
        // What the numbers mean, under them and in their column.
        Padding(
          padding: const EdgeInsets.only(
            left: editorPropertyLabelWidth + editorRowGutter + editorPanelInset,
            bottom: 2,
          ),
          child: Text(
            '${_describe(hour)}  ·  '
            '${elevation.toStringAsFixed(0)}° above the horizon',
            style: editorMicroText,
          ),
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

class _WeatherTile extends StatefulWidget {
  const _WeatherTile({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final WeatherPreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_WeatherTile> createState() => _WeatherTileState();
}

class _WeatherTileState extends State<_WeatherTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    // A row rather than a card, and a row that answers the pointer: a list
    // you pick from has to look pickable before you click it, not after.
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: editorPanelInset,
            vertical: 9,
          ),
          decoration: BoxDecoration(
            color: selected
                ? Color.alphaBlend(
                    editorAccentColor.withValues(alpha: 0.16),
                    editorRaisedColor,
                  )
                : _hovered
                ? editorRaisedColor
                : null,
            borderRadius: BorderRadius.circular(editorFieldRadius),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  weatherPresetIcon(widget.preset.id),
                  size: editorIconSizeLarge,
                  color: selected ? editorAccentColor : editorMutedTextColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.preset.name,
                      style: TextStyle(
                        fontSize: 12,
                        color: selected ? editorAccentColor : editorTextColor,
                      ),
                    ),
                    Text(
                      widget.preset.description,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        color: editorNoteColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check,
                  size: editorIconSize,
                  color: editorAccentColor,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
