/// The Navigation dock panel: bake settings and the button that runs them.
///
/// A nav mesh is baked for one agent, so the panel leads with the agent and
/// draws it: the radius, height, step, and slope are four numbers that only
/// mean something together, and a diagram says in a glance what four labelled
/// fields say slowly.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_scene/navigation.dart';
import 'package:flutter_scene/scene.dart' show Node;

import '../controller/editor_controller.dart';
import '../shell/editor_theme.dart';

/// The Navigation panel.
class NavMeshPanel extends StatefulWidget {
  const NavMeshPanel({super.key, required this.controller});

  final EditorController controller;

  @override
  State<NavMeshPanel> createState() => _NavMeshPanelState();
}

class _NavMeshPanelState extends State<NavMeshPanel> {
  EditorController get _ctrl => widget.controller;

  // The settings live in the panel rather than the document until a bake
  // happens, so tuning the agent does not fill the undo history with edits
  // that changed nothing on screen.
  double _agentRadius = 0.6;
  double _agentHeight = 2.0;
  double _agentMaxClimb = 0.9;
  double _agentMaxSlope = 45;
  double _cellSize = 0.3;
  double _cellHeight = 0.2;
  double _minRegionArea = 8;
  double _mergeRegionArea = 20;
  double _maxEdgeLength = 12;
  double _maxSimplificationError = 1.3;
  String _includePattern = '';
  bool _includeInstances = true;
  bool _includeWaterVolumes = true;
  bool _advancedOpen = false;

  bool _tiled = false;
  double _tileCells = 64;

  NavBakeResult? _result;
  NavTiledBakeResult? _tiledResult;
  NavBakeStage? _stage;
  bool _baking = false;
  int _tilesDone = 0;
  int _tilesTotal = 0;
  String? _error;

  NavMeshConfig get _config => NavMeshConfig(
    cellSize: _cellSize,
    cellHeight: _cellHeight,
    agentRadius: _agentRadius,
    agentHeight: _agentHeight,
    agentMaxClimb: _agentMaxClimb,
    agentMaxSlopeDegrees: _agentMaxSlope,
    minRegionArea: _minRegionArea,
    mergeRegionArea: _mergeRegionArea,
    maxEdgeLength: _maxEdgeLength,
    maxSimplificationError: _maxSimplificationError,
  );

  /// How many voxels wide the agent is, which is the number that decides
  /// whether a bake is fast and coarse or slow and exact.
  double get _voxelsPerRadius => _cellSize <= 0 ? 0 : _agentRadius / _cellSize;

  Node? get _root => _ctrl.realizedRoot;

  NavTileConfig get _tiling => NavTileConfig(tileCells: _tileCells.round());

  Future<void> _bake() async {
    final root = _root;
    if (root == null || _baking) return;
    setState(() {
      _baking = true;
      _error = null;
      _stage = null;
      _result = null;
      _tiledResult = null;
      _tilesDone = 0;
      _tilesTotal = 0;
    });
    try {
      final surface = NavMeshSurfaceComponent(
        config: _config,
        includePattern: _includePattern,
        includeInstances: _includeInstances,
        includeWaterVolumes: _includeWaterVolumes,
        tiling: _tiled ? _tiling : null,
      );
      // Off the calling isolate either way: a large level is seconds of work
      // and the editor still has to draw while it runs. Tiled, it is also
      // several tiles at a time.
      if (_tiled) {
        final result = await surface.bakeTiledAsync(
          root: root,
          onProgress: (done, total) {
            if (!mounted) return;
            setState(() {
              _tilesDone = done;
              _tilesTotal = total;
            });
          },
        );
        if (!mounted) return;
        setState(() => _tiledResult = result);
      } else {
        final result = await surface.bakeAsync(root: root);
        if (!mounted) return;
        setState(() => _result = result);
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _baking = false);
    }
  }

  void _clear() => setState(() {
    _result = null;
    _tiledResult = null;
    _error = null;
  });

  @override
  Widget build(BuildContext context) {
    final ready = _root != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
            children: [
              const EditorSectionHeader(label: 'Agent'),
              AgentDiagram(
                radius: _agentRadius,
                height: _agentHeight,
                climb: _agentMaxClimb,
                slopeDegrees: _agentMaxSlope,
              ),
              const SizedBox(height: 6),
              _Field(
                label: 'Radius',
                hint: 'How close the agent\'s centre may get to a wall.',
                value: _agentRadius,
                min: 0.05,
                max: 3,
                onChanged: (v) => setState(() => _agentRadius = v),
              ),
              _Field(
                label: 'Height',
                hint: 'Clearance needed, so it never paths under a low beam.',
                value: _agentHeight,
                min: 0.3,
                max: 5,
                onChanged: (v) => setState(() => _agentHeight = v),
              ),
              _Field(
                label: 'Step height',
                hint: 'The tallest step it walks up without jumping.',
                value: _agentMaxClimb,
                min: 0,
                max: 2,
                onChanged: (v) => setState(() => _agentMaxClimb = v),
              ),
              _Field(
                label: 'Max slope',
                hint: 'Steeper than this is a wall, not a ramp.',
                value: _agentMaxSlope,
                min: 1,
                max: 89,
                suffix: '°',
                onChanged: (v) => setState(() => _agentMaxSlope = v),
              ),
              const SizedBox(height: 12),
              const EditorSectionHeader(label: 'What to collect'),
              _TextField(
                label: 'Name contains',
                hint:
                    'Only nodes whose name contains this contribute. Empty '
                    'takes everything, which also takes the characters.',
                value: _includePattern,
                onChanged: (v) => setState(() => _includePattern = v),
              ),
              _Toggle(
                label: 'Instanced meshes',
                hint:
                    'A scattered forest is exactly the obstacle to path '
                    'around, and also where a bake gets expensive.',
                value: _includeInstances,
                onChanged: (v) => setState(() => _includeInstances = v),
              ),
              _Toggle(
                label: 'Carve blocked water',
                hint:
                    'Water set to blocked removes its volume, taking the bed '
                    'under it so nothing paths along the bottom.',
                value: _includeWaterVolumes,
                onChanged: (v) => setState(() => _includeWaterVolumes = v),
              ),
              const SizedBox(height: 12),
              const EditorSectionHeader(label: 'Tiling'),
              _Toggle(
                label: 'Bake in tiles',
                hint:
                    'Cuts the world into squares baked in parallel, one tile '
                    'in memory at a time, and lets an edited corner rebake on '
                    'its own. Worth it past a few hundred units a side.',
                value: _tiled,
                onChanged: (v) => setState(() => _tiled = v),
              ),
              if (_tiled) ...[
                _Field(
                  label: 'Tile size',
                  hint:
                      'Voxels per side. Every tile pays for a border, so tiny '
                      'tiles spend more time on margins than on middles.',
                  value: _tileCells,
                  min: 16,
                  max: 256,
                  decimals: 0,
                  divisions: 30,
                  onChanged: (v) => setState(() => _tileCells = v),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 4),
                  child: Text(
                    '${_tiling.tileSize(_config).toStringAsFixed(1)} units a '
                    'side, ${defaultNavBakeConcurrency()} baking at once.',
                    style: editorMicroText,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _AdvancedSection(
                open: _advancedOpen,
                onToggle: () => setState(() => _advancedOpen = !_advancedOpen),
                voxelsPerRadius: _voxelsPerRadius,
                children: [
                  _Field(
                    label: 'Voxel size',
                    hint:
                        'The smallest gap the bake can resolve. Halving it '
                        'quadruples the work.',
                    value: _cellSize,
                    min: 0.02,
                    max: 1,
                    onChanged: (v) => setState(() => _cellSize = v),
                  ),
                  _Field(
                    label: 'Voxel height',
                    hint: 'How precisely a step or a ledge is placed.',
                    value: _cellHeight,
                    min: 0.02,
                    max: 1,
                    onChanged: (v) => setState(() => _cellHeight = v),
                  ),
                  _Field(
                    label: 'Min region area',
                    hint:
                        'Smaller patches are discarded as unreachable specks: '
                        'window sills and pebbles.',
                    value: _minRegionArea,
                    max: 100,
                    onChanged: (v) => setState(() => _minRegionArea = v),
                  ),
                  _Field(
                    label: 'Merge region area',
                    hint: 'Regions under this are merged into a neighbour.',
                    value: _mergeRegionArea,
                    max: 200,
                    onChanged: (v) => setState(() => _mergeRegionArea = v),
                  ),
                  _Field(
                    label: 'Max edge length',
                    hint: 'Long contour edges are split at this.',
                    value: _maxEdgeLength,
                    max: 60,
                    onChanged: (v) => setState(() => _maxEdgeLength = v),
                  ),
                  _Field(
                    label: 'Simplification',
                    hint:
                        'How far a simplified contour may stray from the '
                        'voxel outline, in voxels.',
                    value: _maxSimplificationError,
                    min: 0.1,
                    max: 6,
                    onChanged: (v) =>
                        setState(() => _maxSimplificationError = v),
                  ),
                ],
              ),
            ],
          ),
        ),
        _BakeBar(
          ready: ready,
          baking: _baking,
          stage: _stage,
          result: _result,
          tiledResult: _tiledResult,
          tilesDone: _tilesDone,
          tilesTotal: _tilesTotal,
          error: _error,
          onBake: _bake,
          onClear: _clear,
        ),
      ],
    );
  }
}

/// The agent, drawn: a capsule of the configured radius and height beside a
/// step it can climb and a ramp at the steepest slope it can stand on.
///
/// The four numbers only mean anything in relation to each other and to the
/// world, and a picture is how that lands. Modelled on the diagram every nav
/// baker ships for the same reason.
class AgentDiagram extends StatelessWidget {
  const AgentDiagram({
    super.key,
    required this.radius,
    required this.height,
    required this.climb,
    required this.slopeDegrees,
  });

  final double radius;
  final double height;
  final double climb;
  final double slopeDegrees;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 116,
    child: CustomPaint(
      painter: _AgentPainter(
        radius: radius,
        height: height,
        climb: climb,
        slopeDegrees: slopeDegrees,
      ),
      size: Size.infinite,
    ),
  );
}

class _AgentPainter extends CustomPainter {
  _AgentPainter({
    required this.radius,
    required this.height,
    required this.climb,
    required this.slopeDegrees,
  });

  final double radius;
  final double height;
  final double climb;
  final double slopeDegrees;

  @override
  void paint(Canvas canvas, Size size) {
    // One scale for everything, fitted to the tallest thing on screen, so the
    // agent visibly grows against the step rather than the drawing rescaling
    // under it.
    final worldHeight = math.max(height, climb * 3) * 1.25;
    final scale = (size.height - 24) / math.max(worldHeight, 0.001);
    final groundY = size.height - 14;
    final agentX = size.width * 0.32;

    final ground = Paint()
      ..color = editorLineColor
      ..strokeWidth = 1.4;
    final guide = Paint()
      ..color = editorMutedTextColor.withValues(alpha: 0.6)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final body = Paint()..color = editorAccentColor.withValues(alpha: 0.75);

    void label(String text, Offset at, {TextAlign align = TextAlign.left}) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: editorMicroText),
        textDirection: TextDirection.ltr,
        textAlign: align,
      )..layout();
      painter.paint(canvas, at);
    }

    // Ground, then the step the agent can climb onto.
    final stepX = size.width * 0.62;
    final stepTop = groundY - climb * scale;
    canvas.drawLine(Offset(6, groundY), Offset(stepX, groundY), ground);
    canvas.drawLine(Offset(stepX, groundY), Offset(stepX, stepTop), ground);
    canvas.drawLine(
      Offset(stepX, stepTop),
      Offset(size.width * 0.78, stepTop),
      ground,
    );
    label('step ${climb.toStringAsFixed(2)}', Offset(stepX + 4, stepTop - 12));

    // The ramp at the steepest walkable slope.
    final rampRun = size.width * 0.2;
    final rampRise = rampRun * math.tan(slopeDegrees * math.pi / 180);
    final rampEnd = Offset(
      size.width - 8,
      math.max(6, stepTop - rampRise.clamp(0, size.height)),
    );
    canvas.drawLine(Offset(size.width * 0.78, stepTop), rampEnd, ground);
    label(
      '${slopeDegrees.toStringAsFixed(0)}°',
      Offset(size.width * 0.80, stepTop - 14),
    );

    // The agent: a capsule of the configured radius and height.
    final agentTop = groundY - height * scale;
    final halfWidth = radius * scale;
    final capsule = RRect.fromRectAndRadius(
      Rect.fromLTRB(agentX - halfWidth, agentTop, agentX + halfWidth, groundY),
      Radius.circular(halfWidth),
    );
    canvas.drawRRect(capsule, body);

    // Height and radius callouts.
    canvas.drawLine(
      Offset(agentX + halfWidth + 8, agentTop),
      Offset(agentX + halfWidth + 8, groundY),
      guide,
    );
    label(
      'H ${height.toStringAsFixed(2)}',
      Offset(agentX + halfWidth + 12, (agentTop + groundY) / 2 - 6),
    );
    canvas.drawLine(
      Offset(agentX - halfWidth, groundY + 6),
      Offset(agentX + halfWidth, groundY + 6),
      guide,
    );
    label(
      'R ${radius.toStringAsFixed(2)}',
      Offset(agentX - halfWidth, groundY + 1),
    );
  }

  @override
  bool shouldRepaint(_AgentPainter old) =>
      old.radius != radius ||
      old.height != height ||
      old.climb != climb ||
      old.slopeDegrees != slopeDegrees;
}

class _AdvancedSection extends StatelessWidget {
  const _AdvancedSection({
    required this.open,
    required this.onToggle,
    required this.voxelsPerRadius,
    required this.children,
  });

  final bool open;
  final VoidCallback onToggle;
  final double voxelsPerRadius;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onToggle,
          child: Row(
            children: [
              Icon(
                open ? Icons.expand_more : Icons.chevron_right,
                size: 15,
                color: editorMutedTextColor,
              ),
              Text('Advanced', style: editorSubheadText),
              const Spacer(),
              // The one derived number worth surfacing: under about two
              // voxels per radius the erosion that keeps a path off the walls
              // has nothing to work with, and the mesh comes out ragged.
              Text(
                '${voxelsPerRadius.toStringAsFixed(2)} voxels per radius',
                style: voxelsPerRadius < 2
                    ? editorMicroText.copyWith(color: editorWarningColor)
                    : editorMicroText,
              ),
            ],
          ),
        ),
        if (open) ...[const SizedBox(height: 6), ...children],
      ],
    );
  }
}

class _BakeBar extends StatelessWidget {
  const _BakeBar({
    required this.ready,
    required this.baking,
    required this.stage,
    required this.result,
    required this.tiledResult,
    required this.tilesDone,
    required this.tilesTotal,
    required this.error,
    required this.onBake,
    required this.onClear,
  });

  final bool ready;
  final bool baking;
  final NavBakeStage? stage;
  final NavBakeResult? result;
  final NavTiledBakeResult? tiledResult;
  final int tilesDone;
  final int tilesTotal;
  final String? error;
  final VoidCallback onBake;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final tiled = tiledResult;
    final message =
        error ??
        (baking
            ? (tilesTotal > 0
                  ? 'Baking tile $tilesDone of $tilesTotal…'
                  : 'Baking${stage == null ? '' : ' (${stage!.name})'}…')
            : tiled?.describe() ??
                  result?.describe() ??
                  (ready
                      ? 'Nothing baked yet.'
                      : 'Open a scene to bake its navigation.'));
    final bad =
        error != null ||
        (result?.isEmpty ?? false) ||
        (tiled != null && tiled.tiles.tileCount == 0);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: editorLineColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            message,
            style: bad
                ? editorDetailText.copyWith(color: editorWarningColor)
                : editorDetailText,
          ),
          if (baking && tilesTotal > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(
                value: tilesDone / tilesTotal,
                minHeight: 3,
              ),
            ),
          if (result != null && !result!.isEmpty && result!.volumeCount > 0)
            Text(
              '${result!.volumeCount} volume'
              '${result!.volumeCount == 1 ? '' : 's'} applied.',
              style: editorMicroText,
            ),
          if (result != null && result!.report.unreadableNodes.isNotEmpty)
            Text(
              '${result!.report.unreadableNodes.length} node'
              '${result!.report.unreadableNodes.length == 1 ? '' : 's'} could '
              'not be read (skinned meshes, particles, caller-managed '
              'buffers).',
              style: editorMicroText,
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: (result == null && tiledResult == null) || baking
                      ? null
                      : onClear,
                  child: const Text('Clear'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: ready && !baking ? onBake : null,
                  child: baking
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Bake'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A labelled slider with its number, and a hint under it.
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.suffix = '',
    this.decimals = 2,
    this.divisions,
  });

  final String label;
  final String hint;
  final double value;
  final double min;
  final double max;
  final String suffix;

  /// Digits after the point in the readout. Zero for a count of things.
  final int decimals;

  /// Steps the slider snaps to, for a value that is only meaningful whole.
  final int? divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(width: 108, child: Text(label, style: editorBodyText)),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(trackHeight: 2),
                  child: Slider(
                    value: value.clamp(min, max),
                    min: min,
                    max: max,
                    divisions: divisions,
                    onChanged: onChanged,
                  ),
                ),
              ),
              SizedBox(
                width: 46,
                child: Text(
                  '${value.toStringAsFixed(decimals)}$suffix',
                  style: editorBodyText,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 108, bottom: 2),
            child: Text(hint, style: editorMicroText),
          ),
        ],
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  const _TextField({
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(width: 108, child: Text(label, style: editorBodyText)),
              Expanded(
                child: SizedBox(
                  height: 24,
                  child: TextFormField(
                    initialValue: value,
                    style: editorBodyText,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 6),
                    ),
                    onChanged: onChanged,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 108, top: 2),
            child: Text(hint, style: editorMicroText),
          ),
        ],
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(width: 108, child: Text(label, style: editorBodyText)),
              Transform.scale(
                scale: 0.75,
                child: Switch(value: value, onChanged: onChanged),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 108),
            child: Text(hint, style: editorMicroText),
          ),
        ],
      ),
    );
  }
}
