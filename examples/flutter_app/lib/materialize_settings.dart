// The Materialize example's tunables and control widgets: the settings
// model (with a console dump for capturing tuned values), the side panel
// that edits it, and the playback bar. The scene/effect logic lives in
// example_materialize.dart.

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Every tunable of the effect. Lengths are fractions of the model's height;
/// noise scales are cycles per model height. The print button dumps the
/// current values.
class MaterializeSettings {
  // Wireframe.
  double wireThickness = 0.002;
  vm.Vector3 wireColor = vm.Vector3(0.16, 0.64, 1.0);
  double wireAlpha = 0.85;
  double wireGlow = 27.5;

  // Glass.
  vm.Vector3 glassTint = vm.Vector3(0.5, 0.85, 1.0);
  double glassAlpha = 0.2;
  vm.Vector3 glassGlowColor = vm.Vector3(1.0, 1.0, 0.6);
  double glassGlowStrength = 1.9;
  vm.Vector3 flyDir = vm.Vector3(0.0, 1.0, 0.0);
  double flyDistance = 0.0;
  double centerDistance = 0.45;
  double normalDistance = 1.5;
  double jitter = 0.32;
  double fadePortion = 0.64;
  double coolSpan = 0.62;
  double tumble = 2.3;
  double glassBand = 0.84;

  // Shell reveal.
  double seamWidth = 0.12;
  vm.Vector3 seamColor = vm.Vector3(0.3, 0.9, 1.0);
  double seamStrength = 40.0;

  // Boundary noise, shared by all three stages.
  vm.Vector3 noiseScale = vm.Vector3(3.4, 0.5, 3.9);
  double noiseAmp = 0.11;

  // Timing.
  double duration = 7.0;
  double lagWireToGlass = 0.0;
  double lagGlassToSolid = 1.5;

  String dump() {
    String v3(vm.Vector3 v) =>
        '${v.x.toStringAsFixed(3)}, ${v.y.toStringAsFixed(3)}, '
        '${v.z.toStringAsFixed(3)}';
    String f(double v) => v.toStringAsFixed(3);
    return '''
=== Materialize settings ===
wireThickness: ${f(wireThickness)}
wireColor: ${v3(wireColor)}
wireAlpha: ${f(wireAlpha)}
wireGlow: ${f(wireGlow)}
glassTint: ${v3(glassTint)}
glassAlpha: ${f(glassAlpha)}
glassGlowColor: ${v3(glassGlowColor)}
glassGlowStrength: ${f(glassGlowStrength)}
flyDir: ${v3(flyDir)}
flyDistance: ${f(flyDistance)}
centerDistance: ${f(centerDistance)}
normalDistance: ${f(normalDistance)}
jitter: ${f(jitter)}
fadePortion: ${f(fadePortion)}
coolSpan: ${f(coolSpan)}
tumble: ${f(tumble)}
glassBand: ${f(glassBand)}
seamWidth: ${f(seamWidth)}
seamColor: ${v3(seamColor)}
seamStrength: ${f(seamStrength)}
noiseScale: ${v3(noiseScale)}
noiseAmp: ${f(noiseAmp)}
duration: ${f(duration)}
lagWireToGlass: ${f(lagWireToGlass)}
lagGlassToSolid: ${f(lagGlassToSolid)}
============================''';
  }
}

/// The scrollable side panel that edits a [MaterializeSettings], with a
/// print button that dumps the current values to the console. [onChanged]
/// fires after any edit so the owner can push the values into its materials.
class MaterializeSettingsPanel extends StatefulWidget {
  const MaterializeSettingsPanel({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  final MaterializeSettings settings;
  final VoidCallback onChanged;

  @override
  State<MaterializeSettingsPanel> createState() =>
      _MaterializeSettingsPanelState();
}

class _MaterializeSettingsPanelState extends State<MaterializeSettingsPanel> {
  MaterializeSettings get _settings => widget.settings;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 290,
      child: Card(
        color: Colors.black54,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
              child: Row(
                children: [
                  const Text(
                    'Effect settings',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Print settings to console',
                    icon: const Icon(Icons.print, color: Colors.white),
                    onPressed: () => debugPrint(_settings.dump()),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                children: [
                  _section('Wireframe', [
                    _slider(
                      'Thickness',
                      _settings.wireThickness,
                      0.001,
                      0.03,
                      (v) => _settings.wireThickness = v,
                    ),
                    _colorRow(
                      'Color',
                      _settings.wireColor,
                      (v) => _settings.wireColor = v,
                    ),
                    _slider(
                      'Opacity',
                      _settings.wireAlpha,
                      0.0,
                      1.0,
                      (v) => _settings.wireAlpha = v,
                    ),
                    _slider(
                      'Front glow',
                      _settings.wireGlow,
                      0.0,
                      30.0,
                      (v) => _settings.wireGlow = v,
                    ),
                  ]),
                  _section('Glass', [
                    _colorRow(
                      'Tint',
                      _settings.glassTint,
                      (v) => _settings.glassTint = v,
                    ),
                    _slider(
                      'Translucency',
                      _settings.glassAlpha,
                      0.0,
                      1.0,
                      (v) => _settings.glassAlpha = v,
                    ),
                    _colorRow(
                      'Glow color',
                      _settings.glassGlowColor,
                      (v) => _settings.glassGlowColor = v,
                    ),
                    _slider(
                      'Glow intensity',
                      _settings.glassGlowStrength,
                      0.0,
                      30.0,
                      (v) => _settings.glassGlowStrength = v,
                    ),
                    _slider(
                      'Fly-in X',
                      _settings.flyDir.x,
                      -1.0,
                      1.0,
                      (v) => _settings.flyDir.x = v,
                    ),
                    _slider(
                      'Fly-in Y',
                      _settings.flyDir.y,
                      -1.0,
                      1.0,
                      (v) => _settings.flyDir.y = v,
                    ),
                    _slider(
                      'Fly-in Z',
                      _settings.flyDir.z,
                      -1.0,
                      1.0,
                      (v) => _settings.flyDir.z = v,
                    ),
                    _slider(
                      'Fly distance',
                      _settings.flyDistance,
                      0.0,
                      4.0,
                      (v) => _settings.flyDistance = v,
                    ),
                    _slider(
                      'From center',
                      _settings.centerDistance,
                      0.0,
                      3.0,
                      (v) => _settings.centerDistance = v,
                    ),
                    _slider(
                      'Off normal',
                      _settings.normalDistance,
                      0.0,
                      2.0,
                      (v) => _settings.normalDistance = v,
                    ),
                    _slider(
                      'Jitter',
                      _settings.jitter,
                      0.0,
                      1.0,
                      (v) => _settings.jitter = v,
                    ),
                    _slider(
                      'Fade portion',
                      _settings.fadePortion,
                      0.05,
                      1.0,
                      (v) => _settings.fadePortion = v,
                    ),
                    _slider(
                      'Glow cool span',
                      _settings.coolSpan,
                      0.05,
                      4.0,
                      (v) => _settings.coolSpan = v,
                    ),
                    _slider(
                      'Tumble',
                      _settings.tumble,
                      0.0,
                      3.0,
                      (v) => _settings.tumble = v,
                    ),
                    _slider(
                      'Assembly band',
                      _settings.glassBand,
                      0.05,
                      1.0,
                      (v) => _settings.glassBand = v,
                    ),
                  ]),
                  _section('Reveal', [
                    _slider(
                      'Seam thickness',
                      _settings.seamWidth,
                      0.005,
                      0.3,
                      (v) => _settings.seamWidth = v,
                    ),
                    _colorRow(
                      'Seam color',
                      _settings.seamColor,
                      (v) => _settings.seamColor = v,
                    ),
                    _slider(
                      'Seam brightness',
                      _settings.seamStrength,
                      0.0,
                      40.0,
                      (v) => _settings.seamStrength = v,
                    ),
                    _slider(
                      'Noise scale X',
                      _settings.noiseScale.x,
                      0.5,
                      30.0,
                      (v) => _settings.noiseScale.x = v,
                    ),
                    _slider(
                      'Noise scale Y',
                      _settings.noiseScale.y,
                      0.5,
                      30.0,
                      (v) => _settings.noiseScale.y = v,
                    ),
                    _slider(
                      'Noise scale Z',
                      _settings.noiseScale.z,
                      0.5,
                      30.0,
                      (v) => _settings.noiseScale.z = v,
                    ),
                    _slider(
                      'Noise amount',
                      _settings.noiseAmp,
                      0.0,
                      0.3,
                      (v) => _settings.noiseAmp = v,
                    ),
                  ]),
                  _section('Timing', [
                    _slider(
                      'Cycle seconds',
                      _settings.duration,
                      3.0,
                      20.0,
                      (v) => _settings.duration = v,
                    ),
                    _slider(
                      'Wire to glass lag',
                      _settings.lagWireToGlass,
                      0.0,
                      1.0,
                      (v) => _settings.lagWireToGlass = v,
                    ),
                    _slider(
                      'Glass to solid lag',
                      _settings.lagGlassToSolid,
                      0.0,
                      1.5,
                      (v) => _settings.lagGlassToSolid = v,
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
        ...children,
      ],
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    void Function(double) apply,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 108,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: value.clamp(min, max).toDouble(),
              min: min,
              max: max,
              onChanged: (v) {
                setState(() => apply(v));
                widget.onChanged();
              },
            ),
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            value.toStringAsFixed(2),
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
        ),
      ],
    );
  }

  Widget _colorRow(
    String label,
    vm.Vector3 color,
    void Function(vm.Vector3) apply,
  ) {
    Widget channel(String name, double value, void Function(double) set) {
      return Expanded(
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
          ),
          child: Slider(
            value: value.clamp(0.0, 1.0).toDouble(),
            onChanged: (v) {
              setState(() {
                set(v);
                apply(color);
              });
              widget.onChanged();
            },
          ),
        ),
      );
    }

    return Row(
      children: [
        SizedBox(
          width: 76,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ),
        Container(
          width: 14,
          height: 14,
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            color: Color.fromARGB(
              255,
              (color.x * 255).round(),
              (color.y * 255).round(),
              (color.z * 255).round(),
            ),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        channel('R', color.x, (v) => color.x = v),
        channel('G', color.y, (v) => color.y = v),
        channel('B', color.z, (v) => color.z = v),
      ],
    );
  }
}

/// The play/pause/replay/scrub bar. The owner keeps the timeline state; the
/// bar reports edits through the callbacks.
class MaterializePlaybackBar extends StatelessWidget {
  const MaterializePlaybackBar({
    super.key,
    required this.playing,
    required this.progress,
    required this.onPlayingChanged,
    required this.onRestart,
    required this.onScrub,
  });

  final bool playing;

  /// Clamped timeline position in [0, 1].
  final double progress;

  final ValueChanged<bool> onPlayingChanged;
  final VoidCallback onRestart;
  final ValueChanged<double> onScrub;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.black54,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                playing ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
              ),
              onPressed: () => onPlayingChanged(!playing),
            ),
            IconButton(
              icon: const Icon(Icons.replay, color: Colors.white),
              onPressed: onRestart,
            ),
            SizedBox(
              width: 220,
              child: Slider(
                value: progress,
                onChangeStart: (_) => onPlayingChanged(false),
                onChanged: onScrub,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
