import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'package:flutter_scene_input/src/core/actions.dart';
import 'package:flutter_scene_input/src/core/player_input.dart';

/// Shows a player's live input: the context stack, every live action's value,
/// paired devices, and the active device kind. Repaints every frame.
/// {@category Widgets}
class InputDebugOverlay extends StatefulWidget {
  /// An overlay for [player].
  const InputDebugOverlay({super.key, required this.player});

  /// The player shown.
  final PlayerInput player;

  @override
  State<InputDebugOverlay> createState() => _InputDebugOverlayState();
}

class _InputDebugOverlayState extends State<InputDebugOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) => setState(() {}))..start();

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    final lines = <String>[
      'device: ${player.activeDeviceKind?.name ?? '-'}'
          '${player.textEntryActive ? '  (text entry)' : ''}',
      'paired: ${player.pairedDevices.map((d) => d.name).join(', ')}',
    ];
    for (final entry in player.contexts.entries) {
      lines.add('');
      lines.add('${entry.set.name}${entry.opaque ? '  [opaque]' : ''}');
      for (final action in entry.set.actions) {
        lines.add('  ${action.name}  ${_describe(player, action)}');
      }
    }
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.all(8),
        color: const Color(0xAA000000),
        child: Text(
          lines.join('\n'),
          style: const TextStyle(
            color: Color(0xFFFFFFFF),
            fontFamily: 'monospace',
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  static String _describe(PlayerInput player, InputAction action) {
    String f(double v) => v.toStringAsFixed(2);
    return switch (action) {
      ButtonAction() => () {
        final state = player.button(action);
        return '${state.pressed ? 'down' : 'up'}'
            '  presses ${state.pressCount}'
            '${state.pressed ? '  held ${f(state.heldFor)}s' : ''}';
      }(),
      AxisAction() => f(player.axis(action)),
      VectorAction() => () {
        final v = player.vector(action);
        return '(${f(v.x)}, ${f(v.y)})';
      }(),
      DeltaAction() => () {
        final v = player.delta(action);
        return '(${f(v.x)}, ${f(v.y)})';
      }(),
    };
  }
}
