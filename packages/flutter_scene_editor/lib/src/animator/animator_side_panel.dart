/// What is beside the canvas: the selected state or transition, and the
/// parameters the machine reads.
///
/// The canvas says what the machine's shape is; this says what each piece of
/// it actually does. A state is a clip or a blend across several; a transition
/// is a cross-fade and the conditions that trigger it; and the parameters are
/// simply every name those conditions mention, which is how the editor can
/// list them without the document declaring them.
library;

import 'package:flutter/material.dart';

import '../shell/editor_theme.dart';
import 'animator_document.dart';
import 'animator_graph_view.dart';

/// The panel beside the canvas.
class AnimatorSidePanel extends StatelessWidget {
  const AnimatorSidePanel({
    super.key,
    required this.graph,
    required this.layer,
    required this.selection,
    required this.availableClips,
    required this.onLayerChanged,
    required this.onSelect,
  });

  final AnimatorGraph graph;
  final AnimatorLayerGraph layer;
  final AnimatorSelection? selection;

  /// The clip names the node's model actually carries.
  final List<String> availableClips;

  final ValueChanged<AnimatorLayerGraph> onLayerChanged;
  final ValueChanged<AnimatorSelection?> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: editorPanelColor,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 16),
        children: [
          switch (selection) {
            AnimatorStateSelection(:final name)
                when layer.state(name) != null =>
              _StateEditor(
                key: ValueKey('state:$name'),
                layer: layer,
                state: layer.state(name)!,
                parameters: graph.parameters,
                availableClips: availableClips,
                onLayerChanged: onLayerChanged,
                onSelect: onSelect,
              ),
            AnimatorTransitionSelection(:final index)
                when index < layer.transitions.length =>
              _TransitionEditor(
                key: ValueKey('transition:$index'),
                layer: layer,
                index: index,
                parameters: graph.parameters,
                onLayerChanged: onLayerChanged,
                onSelect: onSelect,
              ),
            _ => _LayerEditor(layer: layer, onLayerChanged: onLayerChanged),
          },
          const SizedBox(height: 16),
          const EditorSectionHeader(label: 'Parameters'),
          _Parameters(parameters: graph.parameters),
        ],
      ),
    );
  }
}

/// Shown when nothing on the canvas is selected: the layer itself.
class _LayerEditor extends StatelessWidget {
  const _LayerEditor({required this.layer, required this.onLayerChanged});

  final AnimatorLayerGraph layer;
  final ValueChanged<AnimatorLayerGraph> onLayerChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      EditorSectionHeader(label: 'Layer "${layer.name}"'),
      _TextRow(
        label: 'Name',
        value: layer.name,
        onSubmit: (value) => onLayerChanged(layer.copyWith(name: value.trim())),
      ),
      _SliderRow(
        label: 'Weight',
        hint: 'How strongly the layer contributes. Zero skips it entirely.',
        value: layer.weight,
        min: 0,
        max: 1,
        onCommit: (value) => onLayerChanged(layer.copyWith(weight: value)),
      ),
      const SizedBox(height: 8),
      Text(
        '${layer.states.length} states, ${layer.transitions.length} '
        'transitions. Double-click a state to make it the one the layer '
        'starts in; alt-drag from one onto another to wire a transition.',
        style: editorDetailText,
      ),
    ],
  );
}

class _StateEditor extends StatelessWidget {
  const _StateEditor({
    super.key,
    required this.layer,
    required this.state,
    required this.parameters,
    required this.availableClips,
    required this.onLayerChanged,
    required this.onSelect,
  });

  final AnimatorLayerGraph layer;
  final AnimatorStateNode state;
  final Map<String, String> parameters;
  final List<String> availableClips;
  final ValueChanged<AnimatorLayerGraph> onLayerChanged;
  final ValueChanged<AnimatorSelection?> onSelect;

  void _replace(AnimatorStateNode updated) => onLayerChanged(
    layer.copyWith(
      states: [
        for (final candidate in layer.states)
          if (candidate.name == state.name) updated else candidate,
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final isInitial = layer.initial.isEmpty
        ? layer.states.isNotEmpty && layer.states.first.name == state.name
        : layer.initial == state.name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: EditorSectionHeader(label: 'State')),
            _IconAction(
              icon: Icons.delete_outline,
              tooltip: 'Delete the state, and every arrow touching it',
              onPressed: () {
                onLayerChanged(removeState(layer, state.name));
                onSelect(null);
              },
            ),
          ],
        ),
        _TextRow(
          label: 'Name',
          value: state.name,
          onSubmit: (value) {
            final wanted = value.trim();
            if (wanted.isEmpty || wanted == state.name) return;
            onLayerChanged(renameState(layer, state.name, wanted));
            onSelect(AnimatorStateSelection(wanted));
          },
        ),
        _ToggleRow(
          label: 'Starts here',
          hint: 'The state the layer is in before anything happens.',
          value: isInitial,
          onChanged: (on) => onLayerChanged(
            layer.copyWith(initial: on ? state.name : layer.initial),
          ),
        ),
        const SizedBox(height: 8),
        _ToggleRow(
          label: 'Blend across clips',
          hint:
              'One clip, or several blended by a parameter: a walk becoming a '
              'run as speed rises.',
          value: state.blends,
          onChanged: (on) => _replace(
            on
                ? state.copyWith(
                    clip: null,
                    blendParameter: parameters.keys.isEmpty
                        ? 'speed'
                        : parameters.keys.first,
                    stops: state.clip == null
                        ? const []
                        : [AnimatorStop(clip: state.clip!)],
                  )
                : state.copyWith(
                    blendParameter: null,
                    blendParameterY: null,
                    stops: const [],
                    clip: state.stops.isEmpty ? null : state.stops.first.clip,
                  ),
          ),
        ),
        if (!state.blends)
          _ClipRow(
            label: 'Clip',
            value: state.clip ?? '',
            available: availableClips,
            onChanged: (value) => _replace(state.copyWith(clip: value)),
          )
        else ...[
          _TextRow(
            label: 'Blend by',
            value: state.blendParameter ?? '',
            onSubmit: (value) =>
                _replace(state.copyWith(blendParameter: value.trim())),
          ),
          _TextRow(
            label: 'And by',
            hint:
                'A second parameter makes the blend a plane rather than a '
                'line. Leave it empty for one.',
            value: state.blendParameterY ?? '',
            onSubmit: (value) {
              final trimmed = value.trim();
              _replace(
                state.copyWith(
                  blendParameterY: trimmed.isEmpty ? null : trimmed,
                ),
              );
            },
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < state.stops.length; i++)
            _StopRow(
              stop: state.stops[i],
              is2D: state.is2D,
              available: availableClips,
              onChanged: (stop) => _replace(
                state.copyWith(
                  stops: [
                    for (var j = 0; j < state.stops.length; j++)
                      if (j == i) stop else state.stops[j],
                  ],
                ),
              ),
              onRemove: () => _replace(
                state.copyWith(
                  stops: [
                    for (var j = 0; j < state.stops.length; j++)
                      if (j != i) state.stops[j],
                  ],
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              icon: const Icon(Icons.add, size: 13),
              label: const Text('Add clip', style: TextStyle(fontSize: 11)),
              onPressed: () => _replace(
                state.copyWith(
                  stops: [
                    ...state.stops,
                    AnimatorStop(
                      clip: availableClips.isEmpty ? '' : availableClips.first,
                      at: state.stops.length.toDouble(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        _ToggleRow(
          label: 'Loop',
          value: state.loop,
          onChanged: (value) => _replace(state.copyWith(loop: value)),
        ),
        _SliderRow(
          label: 'Speed',
          value: state.speed,
          min: 0,
          max: 3,
          onCommit: (value) => _replace(state.copyWith(speed: value)),
        ),
      ],
    );
  }
}

class _TransitionEditor extends StatelessWidget {
  const _TransitionEditor({
    super.key,
    required this.layer,
    required this.index,
    required this.parameters,
    required this.onLayerChanged,
    required this.onSelect,
  });

  final AnimatorLayerGraph layer;
  final int index;
  final Map<String, String> parameters;
  final ValueChanged<AnimatorLayerGraph> onLayerChanged;
  final ValueChanged<AnimatorSelection?> onSelect;

  AnimatorTransitionEdge get transition => layer.transitions[index];

  void _replace(AnimatorTransitionEdge updated) => onLayerChanged(
    layer.copyWith(
      transitions: [
        for (var i = 0; i < layer.transitions.length; i++)
          if (i == index) updated else layer.transitions[i],
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final names = [for (final state in layer.states) state.name];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: EditorSectionHeader(label: 'Transition')),
            _IconAction(
              icon: Icons.delete_outline,
              tooltip: 'Delete this transition',
              onPressed: () {
                onLayerChanged(
                  layer.copyWith(
                    transitions: [
                      for (var i = 0; i < layer.transitions.length; i++)
                        if (i != index) layer.transitions[i],
                    ],
                  ),
                );
                onSelect(null);
              },
            ),
          ],
        ),
        _DropdownRow(
          label: 'From',
          hint:
              'Any State applies whatever is playing, which is how a hit '
              'reaction or a death interrupts it.',
          value: transition.fromAny ? '' : transition.from!,
          options: {'': 'Any State', for (final name in names) name: name},
          onChanged: (value) =>
              _replace(transition.copyWith(from: value.isEmpty ? null : value)),
        ),
        _DropdownRow(
          label: 'To',
          value: transition.to,
          options: {for (final name in names) name: name},
          onChanged: (value) => _replace(transition.copyWith(to: value)),
        ),
        _SliderRow(
          label: 'Cross-fade',
          hint: 'Seconds. Zero is a cut.',
          value: transition.duration,
          min: 0,
          max: 1.5,
          onCommit: (value) => _replace(transition.copyWith(duration: value)),
        ),
        const SizedBox(height: 10),
        const EditorSectionHeader(label: 'Conditions'),
        if (transition.conditions.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'No conditions, so this fires the instant the state is entered. '
              'That is what you want out of an intro, and rarely otherwise.',
              style: editorDetailText,
            ),
          ),
        for (var i = 0; i < transition.conditions.length; i++)
          _ConditionRow(
            condition: transition.conditions[i],
            known: parameters.keys.toList(),
            onChanged: (condition) => _replace(
              transition.copyWith(
                conditions: [
                  for (var j = 0; j < transition.conditions.length; j++)
                    if (j == i) condition else transition.conditions[j],
                ],
              ),
            ),
            onRemove: () => _replace(
              transition.copyWith(
                conditions: [
                  for (var j = 0; j < transition.conditions.length; j++)
                    if (j != i) transition.conditions[j],
                ],
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            icon: const Icon(Icons.add, size: 13),
            label: const Text('Add condition', style: TextStyle(fontSize: 11)),
            onPressed: () => _replace(
              transition.copyWith(
                conditions: [
                  ...transition.conditions,
                  AnimatorConditionEdit(
                    parameter: parameters.keys.isEmpty
                        ? 'parameter'
                        : parameters.keys.first,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The parameters, which are whatever the conditions read.
class _Parameters extends StatelessWidget {
  const _Parameters({required this.parameters});

  final Map<String, String> parameters;

  @override
  Widget build(BuildContext context) {
    if (parameters.isEmpty) {
      return Text(
        'None yet. A parameter comes into existence the moment a condition '
        'reads it, so add a condition to a transition and it appears here.',
        style: editorDetailText,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in parameters.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(
                  switch (entry.value) {
                    'number' => Icons.numbers,
                    'trigger' => Icons.bolt_outlined,
                    _ => Icons.toggle_on_outlined,
                  },
                  size: 13,
                  color: editorMutedTextColor,
                ),
                const SizedBox(width: 6),
                Expanded(child: Text(entry.key, style: editorBodyText)),
                Text(entry.value, style: editorMicroText),
              ],
            ),
          ),
        const SizedBox(height: 6),
        Text(
          'Set them from a script or a graph: Set Animator Number, Flag, or '
          'Trigger.',
          style: editorDetailText,
        ),
      ],
    );
  }
}

// --- rows --------------------------------------------------------------------

class _ConditionRow extends StatelessWidget {
  const _ConditionRow({
    required this.condition,
    required this.known,
    required this.onChanged,
    required this.onRemove,
  });

  final AnimatorConditionEdit condition;
  final List<String> known;
  final ValueChanged<AnimatorConditionEdit> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.fromLTRB(8, 6, 4, 8),
    decoration: BoxDecoration(
      color: editorSurfaceColor,
      border: Border.all(color: editorLineColor),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _TextRow(
                label: 'Reads',
                value: condition.parameter,
                dense: true,
                onSubmit: (value) =>
                    onChanged(condition.copyWith(parameter: value.trim())),
              ),
            ),
            _IconAction(
              icon: Icons.close,
              tooltip: 'Remove this condition',
              onPressed: onRemove,
            ),
          ],
        ),
        _DropdownRow(
          label: 'Is',
          dense: true,
          value: condition.comparison,
          options: const {
            'isTrue': 'true',
            'isFalse': 'false',
            'greater': 'greater than',
            'less': 'less than',
            'triggered': 'triggered',
          },
          onChanged: (value) =>
              onChanged(condition.copyWith(comparison: value)),
        ),
        if (comparisonUsesThreshold(condition.comparison))
          _NumberRow(
            label: 'Than',
            dense: true,
            value: condition.threshold,
            onSubmit: (value) =>
                onChanged(condition.copyWith(threshold: value)),
          ),
      ],
    ),
  );
}

class _StopRow extends StatelessWidget {
  const _StopRow({
    required this.stop,
    required this.is2D,
    required this.available,
    required this.onChanged,
    required this.onRemove,
  });

  final AnimatorStop stop;
  final bool is2D;
  final List<String> available;
  final ValueChanged<AnimatorStop> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.fromLTRB(8, 6, 4, 8),
    decoration: BoxDecoration(
      color: editorSurfaceColor,
      border: Border.all(color: editorLineColor),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _ClipRow(
                label: 'Clip',
                dense: true,
                value: stop.clip,
                available: available,
                onChanged: (value) => onChanged(stop.copyWith(clip: value)),
              ),
            ),
            _IconAction(
              icon: Icons.close,
              tooltip: 'Remove this clip from the blend',
              onPressed: onRemove,
            ),
          ],
        ),
        if (!is2D)
          _NumberRow(
            label: 'At',
            dense: true,
            value: stop.at,
            onSubmit: (value) => onChanged(stop.copyWith(at: value)),
          )
        else
          Row(
            children: [
              Expanded(
                child: _NumberRow(
                  label: 'X',
                  dense: true,
                  value: stop.position?.dx ?? 0,
                  onSubmit: (value) => onChanged(
                    stop.copyWith(
                      position: Offset(value, stop.position?.dy ?? 0),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _NumberRow(
                  label: 'Y',
                  dense: true,
                  value: stop.position?.dy ?? 0,
                  onSubmit: (value) => onChanged(
                    stop.copyWith(
                      position: Offset(stop.position?.dx ?? 0, value),
                    ),
                  ),
                ),
              ),
            ],
          ),
      ],
    ),
  );
}

/// A clip name, offered from the model's own animations.
class _ClipRow extends StatelessWidget {
  const _ClipRow({
    required this.label,
    required this.value,
    required this.available,
    required this.onChanged,
    this.dense = false,
  });

  final String label;
  final String value;
  final List<String> available;
  final ValueChanged<String> onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    // A model with no parsed animations (nothing loaded yet, or a rig whose
    // clips live elsewhere) still needs the name typed, so it falls back to a
    // text field rather than to an empty menu.
    if (available.isEmpty) {
      return _TextRow(
        label: label,
        value: value,
        dense: dense,
        onSubmit: onChanged,
      );
    }
    return _DropdownRow(
      label: label,
      dense: dense,
      value: available.contains(value) ? value : '',
      options: {
        if (!available.contains(value)) '': value.isEmpty ? 'none' : value,
        for (final clip in available) clip: clip,
      },
      onChanged: onChanged,
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.child,
    this.hint,
    this.dense = false,
  });

  final String label;
  final Widget child;
  final String? hint;
  final bool dense;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: dense ? 1 : 3),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: dense ? 46 : 72,
              child: Text(
                label,
                style: editorDetailText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(child: child),
          ],
        ),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 2),
            child: Text(hint!, style: editorMicroText),
          ),
      ],
    ),
  );
}

class _TextRow extends StatefulWidget {
  const _TextRow({
    required this.label,
    required this.value,
    required this.onSubmit,
    this.hint,
    this.dense = false,
  });

  final String label;
  final String value;
  final String? hint;
  final bool dense;
  final ValueChanged<String> onSubmit;

  @override
  State<_TextRow> createState() => _TextRowState();
}

class _TextRowState extends State<_TextRow> {
  late final TextEditingController _text = TextEditingController(
    text: widget.value,
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) widget.onSubmit(_text.text);
    });
  }

  @override
  void didUpdateWidget(_TextRow old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && widget.value != _text.text) {
      _text.text = widget.value;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Row(
    label: widget.label,
    hint: widget.hint,
    dense: widget.dense,
    child: SizedBox(
      height: 22,
      child: TextField(
        controller: _text,
        focusNode: _focus,
        style: editorBodyText,
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 6),
        ),
        onSubmitted: widget.onSubmit,
      ),
    ),
  );
}

class _NumberRow extends StatelessWidget {
  const _NumberRow({
    required this.label,
    required this.value,
    required this.onSubmit,
    this.dense = false,
  });

  final String label;
  final double value;
  final ValueChanged<double> onSubmit;
  final bool dense;

  @override
  Widget build(BuildContext context) => _TextRow(
    label: label,
    dense: dense,
    value: value == value.roundToDouble()
        ? value.round().toString()
        : value.toStringAsFixed(2),
    onSubmit: (text) {
      final parsed = double.tryParse(text.trim());
      if (parsed != null) onSubmit(parsed);
    },
  );
}

class _DropdownRow extends StatelessWidget {
  const _DropdownRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.hint,
    this.dense = false,
  });

  final String label;
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;
  final String? hint;
  final bool dense;

  @override
  Widget build(BuildContext context) => _Row(
    label: label,
    hint: hint,
    dense: dense,
    child: SizedBox(
      height: 24,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: options.containsKey(value) ? value : null,
          isDense: true,
          isExpanded: true,
          style: editorBodyText.copyWith(color: editorTextColor),
          dropdownColor: editorRaisedColor,
          items: [
            for (final entry in options.entries)
              DropdownMenuItem(
                value: entry.key,
                child: Text(entry.value, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (picked) => picked == null ? null : onChanged(picked),
        ),
      ),
    ),
  );
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) => _Row(
    label: label,
    hint: hint,
    child: Align(
      alignment: Alignment.centerLeft,
      child: Switch(
        value: value,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onChanged: onChanged,
      ),
    ),
  );
}

class _SliderRow extends StatefulWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onCommit,
    this.hint,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onCommit;
  final String? hint;

  @override
  State<_SliderRow> createState() => _SliderRowState();
}

class _SliderRowState extends State<_SliderRow> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final value = (_dragging ?? widget.value).clamp(widget.min, widget.max);
    return _Row(
      label: widget.label,
      hint: widget.hint,
      child: Row(
        children: [
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(trackHeight: 2),
              child: Slider(
                value: value,
                min: widget.min,
                max: widget.max,
                // Committed on release, so a drag is one undo step rather
                // than one per frame.
                onChanged: (next) => setState(() => _dragging = next),
                onChangeEnd: (next) {
                  setState(() => _dragging = null);
                  widget.onCommit(next);
                },
              ),
            ),
          ),
          SizedBox(
            width: 34,
            child: Text(
              value.toStringAsFixed(2),
              style: editorMicroText,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    icon: Icon(icon, size: 14),
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: 22, height: 22),
    tooltip: tooltip,
    onPressed: onPressed,
  );
}
