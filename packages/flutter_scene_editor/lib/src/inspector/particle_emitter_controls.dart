/// The live half of an effect: play, pause, restart, and what it is costing.
///
/// The inspector edits the emitter's authored fields; none of that reaches
/// the running simulation's clock. Restarting is how a one-shot effect (a
/// muzzle flash, an impact) is fired at all, and the particle count against
/// the cap is the first thing to look at when an effect is thinner than
/// intended.
///
/// Shown inside the particleEmitter component's own section, because that is
/// what it is about. The catalogue that used to sit above it is under
/// Add > VFX.
library;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:scene/scene.dart' show LocalId;

import '../controller/editor_controller.dart';
import '../shell/editor_theme.dart';
import 'vfx_editing.dart';

/// The transport for the emitter on [nodeId], plus the button that swaps
/// which effect it is.
class ParticleEmitterControls extends StatefulWidget {
  const ParticleEmitterControls({
    super.key,
    required this.controller,
    required this.nodeId,
  });

  final EditorController controller;
  final LocalId nodeId;

  @override
  State<ParticleEmitterControls> createState() =>
      _ParticleEmitterControlsState();
}

class _ParticleEmitterControlsState extends State<ParticleEmitterControls> {
  /// The live emitter this node realized to, or null before it has.
  ParticleEmitterComponent? get _emitter => widget.controller
      .liveNode(widget.nodeId)
      ?.getComponent<ParticleEmitterComponent>();

  Future<void> _changeEffect() async {
    final preset = await showVfxBrowser(
      context,
      title: 'Change Effect',
      action: 'Use',
    );
    if (preset == null) return;
    await applyVfxPresetTo(widget.controller, widget.nodeId, preset);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _EmitterTransport(emitter: _emitter, onChanged: () => setState(() {})),
      const SizedBox(height: 6),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          icon: const Icon(Icons.auto_awesome, size: 14),
          label: const Text('Change effect…', style: TextStyle(fontSize: 11)),
          onPressed: _changeEffect,
        ),
      ),
    ],
  );
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
            child: Icon(
              Icons.warning_amber,
              size: 13,
              color: editorWarningColor,
            ),
          ),
        ],
      ],
    );
  }
}
