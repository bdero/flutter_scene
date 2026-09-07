/// The profiler: what a frame costs, what the scene weighs, and what the
/// engine is holding.
///
/// The engine already counts most of this; until now it counted into stdout
/// behind a compile-time flag, which is a number you can only read by
/// rebuilding the app that was supposed to be showing it to you. Three
/// questions get answered here, in the order people ask them: is the frame
/// late, what is in the scene that could be making it late, and how much
/// memory is pinned.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_scene/scene.dart'
    show Geometry, MemoryReport, Node, takeMemoryReport;

import '../controller/editor_controller.dart';
import '../inspector/property_editors.dart';
import '../shell/editor_theme.dart';
import '../shell/panel_chrome.dart';

/// A rolling window of frame timings, in microseconds.
///
/// Kept as a plain ring rather than a growing list: a profiler that allocates
/// per frame is measuring itself.
class FrameTimings {
  FrameTimings({this.window = 120});

  final int window;
  final List<int> build = [];
  final List<int> raster = [];

  void add(FrameTiming timing) {
    build.add(timing.buildDuration.inMicroseconds);
    raster.add(timing.rasterDuration.inMicroseconds);
    if (build.length > window) build.removeAt(0);
    if (raster.length > window) raster.removeAt(0);
  }

  bool get isEmpty => build.isEmpty;

  int get lastTotal => build.isEmpty ? 0 : build.last + raster.last;

  double get meanTotal {
    if (build.isEmpty) return 0;
    var sum = 0;
    for (var i = 0; i < build.length; i++) {
      sum += build[i] + raster[i];
    }
    return sum / build.length;
  }

  int get worstTotal {
    var worst = 0;
    for (var i = 0; i < build.length; i++) {
      final total = build[i] + raster[i];
      if (total > worst) worst = total;
    }
    return worst;
  }

  /// The frames in the window that missed a 60Hz budget.
  int get lateFrames {
    var late = 0;
    for (var i = 0; i < build.length; i++) {
      if (build[i] + raster[i] > _budgetMicroseconds) late++;
    }
    return late;
  }

  List<int> get totals => [
    for (var i = 0; i < build.length; i++) build[i] + raster[i],
  ];
}

const int _budgetMicroseconds = 16667;

/// What the open scene is made of.
///
/// Counted over the realized graph rather than the document, because what
/// costs a frame is what was realized: an instanced prefab is one document
/// node and many live ones.
class SceneWeight {
  const SceneWeight({
    required this.nodes,
    required this.meshes,
    required this.primitives,
    required this.triangles,
    required this.geometries,
    required this.materials,
    required this.unreadable,
  });

  factory SceneWeight.of(Node? root) {
    if (root == null) {
      return const SceneWeight(
        nodes: 0,
        meshes: 0,
        primitives: 0,
        triangles: 0,
        geometries: 0,
        materials: 0,
        unreadable: 0,
      );
    }
    var nodes = 0;
    var meshes = 0;
    var primitives = 0;
    var triangles = 0;
    var unreadable = 0;
    final geometries = <Geometry>{};
    final materials = <Object>{};

    void visit(Node node) {
      nodes++;
      final mesh = node.mesh;
      if (mesh != null) {
        meshes++;
        for (final primitive in mesh.primitives) {
          primitives++;
          final geometry = primitive.geometry;
          geometries.add(geometry);
          materials.add(primitive.material);
          final count = geometry.indexCount > 0
              ? geometry.indexCount
              : geometry.vertexCount;
          if (count == 0) {
            unreadable++;
          } else {
            triangles += count ~/ 3;
          }
        }
      }
      for (final child in node.children) {
        visit(child);
      }
    }

    visit(root);
    return SceneWeight(
      nodes: nodes,
      meshes: meshes,
      primitives: primitives,
      triangles: triangles,
      geometries: geometries.length,
      materials: materials.length,
      unreadable: unreadable,
    );
  }

  final int nodes;
  final int meshes;

  /// Draw calls, near enough: one primitive is one bind and one draw.
  final int primitives;
  final int triangles;
  final int geometries;
  final int materials;

  /// Primitives whose geometry reports no counts yet (a caller-managed buffer,
  /// or geometry that has not uploaded).
  final int unreadable;
}

/// The profiler screen.
class ProfilerPanel extends StatefulWidget {
  const ProfilerPanel({super.key, required this.controller});

  final EditorController controller;

  @override
  State<ProfilerPanel> createState() => _ProfilerPanelState();
}

class _ProfilerPanelState extends State<ProfilerPanel> {
  final FrameTimings _timings = FrameTimings();
  MemoryReport _memory = const MemoryReport([]);
  bool _recording = true;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _memory = takeMemoryReport();
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    super.dispose();
  }

  void _onTimings(List<FrameTiming> timings) {
    if (!_recording || !mounted) return;
    for (final timing in timings) {
      _timings.add(timing);
    }
    setState(() {});
  }

  String _ms(num microseconds) =>
      '${(microseconds / 1000).toStringAsFixed(2)} ms';

  @override
  Widget build(BuildContext context) {
    final weight = SceneWeight.of(widget.controller.realizedRoot);
    final late = _timings.lateFrames;
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
      children: [
        const EditorSectionHeader(label: 'Frame'),
        SizedBox(height: 64, child: _FrameGraph(totals: _timings.totals)),
        LabeledControlRow(
          label: 'Last',
          control: _Value(
            _timings.isEmpty ? '—' : _ms(_timings.lastTotal),
            warn: _timings.lastTotal > _budgetMicroseconds,
          ),
        ),
        LabeledControlRow(
          label: 'Mean',
          control: _Value(
            _timings.isEmpty ? '—' : _ms(_timings.meanTotal),
            warn: _timings.meanTotal > _budgetMicroseconds,
          ),
        ),
        LabeledControlRow(
          label: 'Worst',
          control: _Value(
            _timings.isEmpty ? '—' : _ms(_timings.worstTotal),
            warn: _timings.worstTotal > _budgetMicroseconds,
          ),
        ),
        LabeledControlRow(
          label: 'Late frames',
          tooltip: 'Frames over the 16.67 ms a 60Hz display allows',
          control: _Value('$late of ${_timings.totals.length}', warn: late > 0),
        ),
        LabeledControlRow(
          label: 'Recording',
          control: Align(
            alignment: Alignment.centerLeft,
            child: EditorPanelIconButton(
              icon: _recording ? Icons.pause : Icons.play_arrow,
              tooltip: _recording ? 'Pause' : 'Resume',
              selected: _recording,
              onPressed: () => setState(() => _recording = !_recording),
            ),
          ),
        ),

        const EditorSectionHeader(label: 'Scene'),
        LabeledControlRow(label: 'Nodes', control: _Value('${weight.nodes}')),
        LabeledControlRow(label: 'Meshes', control: _Value('${weight.meshes}')),
        LabeledControlRow(
          label: 'Draws',
          tooltip: 'One primitive is one bind and one draw call',
          control: _Value('${weight.primitives}'),
        ),
        LabeledControlRow(
          label: 'Triangles',
          control: _Value(_thousands(weight.triangles)),
        ),
        LabeledControlRow(
          label: 'Geometries',
          tooltip: 'Distinct geometry instances; the rest are shared',
          control: _Value('${weight.geometries}'),
        ),
        LabeledControlRow(
          label: 'Materials',
          control: _Value('${weight.materials}'),
        ),
        if (weight.unreadable > 0)
          LabeledControlRow(
            label: 'Uncounted',
            tooltip:
                'Primitives whose geometry reports no counts yet: a '
                'caller-managed vertex buffer, or one that has not uploaded',
            control: _Value('${weight.unreadable}', warn: true),
          ),

        const EditorSectionHeader(label: 'Memory'),
        for (final category in _memory.categories)
          LabeledControlRow(
            label: category.name,
            control: _Value(
              category.bytes == null
                  ? '${category.count}'
                  : '${category.count}  ·  ${_mib(category.bytes!)}',
            ),
          ),
        LabeledControlRow(
          label: 'Total',
          control: _Value(_mib(_memory.totalBytes)),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: EditorActionButton(
            label: 'Refresh memory',
            icon: Icons.refresh,
            onPressed: () => setState(() => _memory = takeMemoryReport()),
          ),
        ),
      ],
    );
  }

  static String _mib(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MiB';

  static String _thousands(int value) {
    final digits = value.toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }
}

/// A number, in the colour that says whether it is a problem.
class _Value extends StatelessWidget {
  const _Value(this.text, {this.warn = false});

  final String text;
  final bool warn;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 11,
      color: warn ? editorWarningColor : editorValueColor,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );
}

/// The window of frame totals, with the budget drawn across it.
///
/// A bar chart rather than a line: a dropped frame is one bar over the line,
/// and a line graph smooths exactly the thing you are looking for.
class _FrameGraph extends StatelessWidget {
  const _FrameGraph({required this.totals});

  final List<int> totals;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: CustomPaint(
      painter: _FrameGraphPainter(totals),
      child: const SizedBox.expand(),
    ),
  );
}

class _FrameGraphPainter extends CustomPainter {
  _FrameGraphPainter(this.totals);

  final List<int> totals;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = editorRaisedColor.withValues(alpha: 0.5),
    );
    if (totals.isEmpty) return;

    // The scale holds at twice the budget until something exceeds it, so a
    // quiet window does not magnify its own noise into a mountain range.
    var peak = _budgetMicroseconds * 2;
    for (final total in totals) {
      if (total > peak) peak = total;
    }

    final budgetY = size.height - size.height * _budgetMicroseconds / peak;
    canvas.drawLine(
      Offset(0, budgetY),
      Offset(size.width, budgetY),
      Paint()
        ..color = editorWarningColor.withValues(alpha: 0.6)
        ..strokeWidth = 1,
    );

    final barWidth = size.width / totals.length;
    for (var i = 0; i < totals.length; i++) {
      final height = size.height * totals[i] / peak;
      canvas.drawRect(
        Rect.fromLTWH(
          i * barWidth,
          size.height - height,
          barWidth > 2 ? barWidth - 1 : barWidth,
          height,
        ),
        Paint()
          ..color = totals[i] > _budgetMicroseconds
              ? editorWarningColor
              : editorAccentColor,
      );
    }
  }

  @override
  bool shouldRepaint(_FrameGraphPainter oldDelegate) =>
      !identical(oldDelegate.totals, totals) ||
      oldDelegate.totals.length != totals.length;
}
