/// Inspector editor for scene-wide stage settings (environment/lighting,
/// exposure, tone mapping). Shown when no node is selected; commits through the
/// `setStageProperties` command.
library;

import 'package:flutter/material.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/specs.dart';

import '../controller/editor_controller.dart';

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
        _StageSlider(
          label: 'Environment intensity',
          value: stage.environmentIntensity,
          max: 3,
          onChanged: (v) => _set('environmentIntensity', v),
        ),
        _StageSlider(
          label: 'Exposure',
          value: stage.exposure,
          max: 8,
          onChanged: (v) => _set('exposure', v),
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
      ],
    );
  }
}

class _StageSlider extends StatefulWidget {
  const _StageSlider({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
  });
  final String label;
  final double value;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  State<_StageSlider> createState() => _StageSliderState();
}

class _StageSliderState extends State<_StageSlider> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final value = (_dragging ?? widget.value).clamp(0.0, widget.max);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(widget.label, style: const TextStyle(fontSize: 13)),
      subtitle: Slider(
        value: value,
        max: widget.max,
        onChanged: (v) => setState(() => _dragging = v),
        onChangeEnd: (v) {
          setState(() => _dragging = null);
          widget.onChanged(v);
        },
      ),
      trailing: Text(value.toStringAsFixed(2)),
    );
  }
}
