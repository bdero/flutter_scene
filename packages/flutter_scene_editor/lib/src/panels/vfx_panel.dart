/// The VFX dock panel: a catalogue of ready-made effects, and a transport for
/// the one selected in the scene.
///
/// Adding an effect is the hard part to make easy. A plume of smoke is a
/// shape, a spawner, five distributions, and four modules, which is why nobody
/// builds one to put dust under a footstep. The catalogue drops a working
/// effect into the scene in a click; the inspector is still where every field
/// of it is edited afterwards.
///
/// The second half is what the inspector cannot do: play, pause, and restart
/// the live simulation, and say how many particles it is actually running
/// against its cap.
library;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';

import '../controller/editor_controller.dart';
import '../shell/editor_theme.dart';

/// The Effects panel.
class VfxPanel extends StatefulWidget {
  const VfxPanel({super.key, required this.controller});

  final EditorController controller;

  @override
  State<VfxPanel> createState() => _VfxPanelState();
}

class _VfxPanelState extends State<VfxPanel> {
  EditorController get _ctrl => widget.controller;

  String _query = '';
  String? _busyPreset;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onChanged);
    _ctrl.selection.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(VfxPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller
        ..removeListener(_onChanged)
        ..selection.removeListener(_onChanged);
      widget.controller
        ..addListener(_onChanged)
        ..selection.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    _ctrl
      ..removeListener(_onChanged)
      ..selection.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// The live emitter on the selected node, or null.
  ParticleEmitterComponent? get _selectedEmitter {
    final id = _ctrl.selection.primary;
    if (id == null) return null;
    return _ctrl.liveNode(id)?.getComponent<ParticleEmitterComponent>();
  }

  /// Adds [preset] as a new node, seeded from the effect it builds.
  ///
  /// The emitter is built in memory, serialized through its own codec, and
  /// the resulting properties set on a fresh component. That keeps the whole
  /// gesture inside the command layer: one undo step, and identical to the
  /// same effect authored by hand.
  Future<void> _add(VfxPreset preset) async {
    setState(() => _busyPreset = preset.id);
    try {
      final built = preset.build();
      final properties = _ctrl.capturePropertiesOf(built);

      final before = Set.of(_ctrl.document.nodes.keys);
      await _ctrl.run('createNode', {'name': preset.name});
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
      _ctrl.selection.selectOnly(nodeId);
    } finally {
      if (mounted) setState(() => _busyPreset = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final needle = _query.trim().toLowerCase();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildToolbar(context),
        _EmitterTransport(
          emitter: _selectedEmitter,
          onChanged: () => setState(() {}),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
            children: [
              for (final category in VfxCategory.values)
                ..._buildCategory(category, needle),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildCategory(VfxCategory category, String needle) {
    final matches = [
      for (final preset in vfxPresetsIn(category))
        if (needle.isEmpty ||
            preset.name.toLowerCase().contains(needle) ||
            preset.description.toLowerCase().contains(needle))
          preset,
    ];
    if (matches.isEmpty) return const [];
    return [
      EditorSectionHeader(label: category.label),
      for (final preset in matches)
        _PresetTile(
          preset: preset,
          busy: _busyPreset == preset.id,
          onAdd: () => _add(preset),
        ),
      const SizedBox(height: 6),
    ];
  }

  Widget _buildToolbar(BuildContext context) {
    return Container(
      height: editorToolbarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, size: 14),
          const SizedBox(width: 6),
          Text('Effects', style: editorBodyText),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 20,
              child: TextField(
                style: editorBodyText,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search effects',
                  hintStyle: editorDetailText,
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One catalogue row: what the effect is, and a button that puts it in the
/// scene.
class _PresetTile extends StatefulWidget {
  const _PresetTile({
    required this.preset,
    required this.busy,
    required this.onAdd,
  });

  final VfxPreset preset;
  final bool busy;
  final VoidCallback onAdd;

  @override
  State<_PresetTile> createState() => _PresetTileState();
}

class _PresetTileState extends State<_PresetTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final preset = widget.preset;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.busy ? null : widget.onAdd,
        child: Container(
          margin: const EdgeInsets.only(bottom: 5),
          padding: const EdgeInsets.fromLTRB(9, 7, 7, 8),
          decoration: BoxDecoration(
            color: editorPanelColor,
            border: Border.all(
              color: _hovered ? editorAccentColor : editorLineColor,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(preset.name, style: editorSubheadText),
                    const SizedBox(height: 3),
                    Text(preset.description, style: editorDetailText),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 22,
                height: 22,
                child: widget.busy
                    ? const Padding(
                        padding: EdgeInsets.all(4),
                        child: CircularProgressIndicator(strokeWidth: 1.6),
                      )
                    : IconButton(
                        icon: const Icon(Icons.add, size: 15),
                        padding: EdgeInsets.zero,
                        tooltip: 'Add ${preset.name} to the scene',
                        onPressed: widget.onAdd,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Play, pause, and restart for the selected emitter, plus what it is costing.
///
/// The inspector edits the emitter's authored fields; none of that reaches the
/// running simulation's clock. Restarting is how a one-shot effect (a muzzle
/// flash, an impact) is fired at all, and the particle count against the cap
/// is the first thing to look at when an effect is thinner than intended.
class _EmitterTransport extends StatelessWidget {
  const _EmitterTransport({required this.emitter, required this.onChanged});

  final ParticleEmitterComponent? emitter;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final emitter = this.emitter;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: editorLineColor)),
      ),
      child: emitter == null
          ? Text(
              'Select an emitter to play, pause, or restart it.',
              style: editorDetailText,
            )
          : Row(
              children: [
                IconButton(
                  icon: Icon(
                    emitter.paused ? Icons.play_arrow : Icons.pause,
                    size: 16,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 24,
                    height: 24,
                  ),
                  tooltip: emitter.paused ? 'Play' : 'Pause',
                  onPressed: () {
                    emitter.paused = !emitter.paused;
                    onChanged();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.replay, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 24,
                    height: 24,
                  ),
                  tooltip: 'Restart, which is how a one-shot effect is fired',
                  onPressed: () {
                    emitter.system.reset();
                    emitter.paused = false;
                    onChanged();
                  },
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ParticleGauge(
                    alive: emitter.system.storage.aliveCount,
                    capacity: emitter.system.storage.capacity,
                  ),
                ),
              ],
            ),
    );
  }
}

/// Live particles against the emitter's cap, as a bar plus the numbers.
///
/// Turns amber at the cap, which is the state worth noticing: an emitter
/// pinned there is dropping spawns, so the effect thins out and no field in
/// the inspector explains why.
class _ParticleGauge extends StatelessWidget {
  const _ParticleGauge({required this.alive, required this.capacity});

  final int alive;
  final int capacity;

  @override
  Widget build(BuildContext context) {
    final fraction = capacity <= 0 ? 0.0 : (alive / capacity).clamp(0.0, 1.0);
    final saturated = capacity > 0 && alive >= capacity;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 4,
              backgroundColor: editorSurfaceColor,
              valueColor: AlwaysStoppedAnimation(
                saturated ? editorWarningColor : editorAccentColor,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$alive / $capacity',
          style: saturated
              ? editorDetailText.copyWith(color: editorWarningColor)
              : editorDetailText,
        ),
        if (saturated) ...[
          const SizedBox(width: 5),
          const Tooltip(
            message:
                'At the cap: spawns are being dropped. Raise maxParticles, or '
                'lower the rate or the lifetime.',
            child: Icon(Icons.warning_amber, size: 13, color: editorWarningColor),
          ),
        ],
      ],
    );
  }
}
