import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_scene/scene.dart';

import 'micro.dart';
import 'scenarios.dart';

const int kWarmupFrames = 20;
const int kMeasuredFrames = 100;
const double kDt = 1 / 60;
const ui.Rect kViewport = ui.Rect.fromLTWH(0, 0, 960, 540);

void main() {
  runApp(const BenchApp());
}

class BenchApp extends StatelessWidget {
  const BenchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: BenchRunner()),
      ),
    );
  }
}

/// Aggregates one phase's per-frame samples.
class PhaseStats {
  final List<double> _samples = [];

  void add(double ms) => _samples.add(ms);

  double get mean =>
      _samples.isEmpty ? 0 : _samples.reduce((a, b) => a + b) / _samples.length;

  double _percentile(double p) {
    if (_samples.isEmpty) return 0;
    final sorted = List<double>.from(_samples)..sort();
    final index = ((sorted.length - 1) * p).round();
    return sorted[index];
  }

  double get p50 => _percentile(0.5);
  double get p95 => _percentile(0.95);
  double get max =>
      _samples.isEmpty ? 0 : _samples.reduce((a, b) => a > b ? a : b);

  Map<String, double> toJson() => {
    'mean': mean,
    'p50': p50,
    'p95': p95,
    'max': max,
  };
}

class ScenarioResult {
  ScenarioResult(this.name, this.itemCount);

  final String name;
  final int itemCount;
  final Map<String, PhaseStats> phases = {
    'mutate': PhaseStats(),
    'update': PhaseStats(),
    'bvh': PhaseStats(),
    'render': PhaseStats(),
    'frame': PhaseStats(),
  };
}

class BenchRunner extends StatefulWidget {
  const BenchRunner({super.key});

  @override
  State<BenchRunner> createState() => _BenchRunnerState();
}

class _BenchRunnerState extends State<BenchRunner>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  Scene? _scene;
  late BenchResources _resources;
  late List<Scenario> _scenarios;
  final List<ScenarioResult> _results = [];

  var _scenarioIndex = 0;
  Scenario? _current;
  ScenarioResult? _currentResult;
  var _frame = 0;
  var _status = 'initializing';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await Scene.initializeStaticResources();
    _scene = Scene();
    _resources = BenchResources();
    _scenarios = [
      StaticField(_resources),
      MoversField(_resources, moverFraction: 0.1),
      MoversField(_resources, moverFraction: 1.0),
      TranslucentField(_resources),
      LitField(_resources),
      InstancedField(_resources),
      ChurnField(_resources),
    ];
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final scene = _scene!;

    if (_current == null) {
      if (_scenarioIndex >= _scenarios.length) {
        _finish();
        return;
      }
      final scenario = _scenarios[_scenarioIndex];
      scenario.build();
      scene.add(scenario.mount);
      _current = scenario;
      _currentResult = ScenarioResult(scenario.name, scenario.itemCount);
      _frame = 0;
      setState(() => _status = scenario.name);
      return;
    }

    final scenario = _current!;
    final result = _currentResult!;
    final swTotal = Stopwatch()..start();
    final sw = Stopwatch();

    sw.start();
    scenario.perFrame(_frame);
    sw.stop();
    final mutateUs = sw.elapsedMicroseconds;

    sw
      ..reset()
      ..start();
    scene.update(kDt);
    sw.stop();
    final updateUs = sw.elapsedMicroseconds;

    // Timed here so the render call below sees clean flags; this is the
    // same maintenance render would otherwise perform.
    sw
      ..reset()
      ..start();
    scene.renderScene.rebuildIfDirty();
    sw.stop();
    final bvhUs = sw.elapsedMicroseconds;

    sw
      ..reset()
      ..start();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    scene.render(scenario.camera, canvas, viewport: kViewport, pixelRatio: 1.0);
    recorder.endRecording().dispose();
    sw.stop();
    final renderUs = sw.elapsedMicroseconds;
    swTotal.stop();

    if (_frame >= kWarmupFrames) {
      result.phases['mutate']!.add(mutateUs / 1000);
      result.phases['update']!.add(updateUs / 1000);
      result.phases['bvh']!.add(bvhUs / 1000);
      result.phases['render']!.add(renderUs / 1000);
      result.phases['frame']!.add(swTotal.elapsedMicroseconds / 1000);
    }

    _frame++;
    if (_frame >= kWarmupFrames + kMeasuredFrames) {
      scene.remove(scenario.mount);
      _results.add(result);
      _current = null;
      _currentResult = null;
      _scenarioIndex++;
    }
  }

  void _finish() {
    _ticker?.stop();
    setState(() => _status = 'micro benchmarks');
    // Let the status frame paint before the synchronous micro loops.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final micro = runMicroBenchmarks();
      _printReport(micro);
      exit(0);
    });
    setState(() {});
  }

  void _printReport(Map<String, double> micro) {
    final mode = kReleaseMode
        ? 'release'
        : kProfileMode
        ? 'profile'
        : 'debug';
    final buffer = StringBuffer()
      ..writeln('')
      ..writeln(
        '=== stress_bench ($mode, $kMeasuredFrames frames/scenario, '
        '${kViewport.width.toInt()}x${kViewport.height.toInt()}) ===',
      );
    if (!kProfileMode) {
      buffer.writeln('WARNING run with --profile for representative timings');
    }
    for (final result in _results) {
      buffer
        ..writeln('')
        ..writeln('--- ${result.name} (${result.itemCount} items) ---')
        ..writeln('  phase     mean     p50     p95     max  (ms)');
      for (final entry in result.phases.entries) {
        final s = entry.value;
        buffer.writeln(
          '  ${entry.key.padRight(8)}'
          '${s.mean.toStringAsFixed(2).padLeft(7)}'
          '${s.p50.toStringAsFixed(2).padLeft(8)}'
          '${s.p95.toStringAsFixed(2).padLeft(8)}'
          '${s.max.toStringAsFixed(2).padLeft(8)}',
        );
      }
    }
    buffer
      ..writeln('')
      ..writeln('--- micro (ms/op) ---');
    for (final entry in micro.entries) {
      buffer.writeln(
        '  ${entry.key.padRight(24)}${entry.value.toStringAsFixed(4).padLeft(10)}',
      );
    }
    final json = jsonEncode({
      'mode': mode,
      'scenarios': {
        for (final r in _results)
          r.name: {
            'items': r.itemCount,
            for (final e in r.phases.entries) e.key: e.value.toJson(),
          },
      },
      'micro': micro,
    });
    buffer
      ..writeln('')
      ..writeln('BENCH_JSON $json');
    // One print per line keeps flutter run from truncating long output.
    for (final line in buffer.toString().split('\n')) {
      print(line);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      'stress_bench\n$_status',
      textAlign: TextAlign.center,
      style: const TextStyle(color: Colors.white70, fontSize: 16),
    );
  }
}
