// ignore_for_file: implementation_imports, avoid_print
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_scene/gpu.dart' show resolveShaderBundleKey;
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;

import 'bench.dart';
import 'volume_data.dart';

/// `WIDTHxHEIGHTxDEPTH`, set with `--dart-define=volume_bench.size=512x512x400`.
const String kSize = String.fromEnvironment(
  'volume_bench.size',
  defaultValue: '256x256x256',
);

const bool kWebGpu = bool.fromEnvironment('flutter_scene.webgpu');

String get backendName => kIsWeb
    ? (kWebGpu ? 'WebGPU' : 'WebGL2')
    : 'Flutter GPU (${defaultTargetPlatform.name})';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BenchApp());
}

class BenchApp extends StatefulWidget {
  const BenchApp({super.key});

  @override
  State<BenchApp> createState() => _BenchAppState();
}

class _BenchAppState extends State<BenchApp> {
  final List<VariantResult> _results = [];
  double _passOverheadMs = 0;
  String _status = 'Starting';

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    if (kDebugMode) {
      print(
        'volume_bench: debug build; run with --profile (or --release on '
        'web) for representative numbers.',
      );
    }
    await gpu.initializeGpuBackend();
    final library = (await gpu.loadShaderLibraryAsync(
      await resolveShaderBundleKey('volume_bench'),
    ))!;
    final [w, h, d] = [for (final s in kSize.split('x')) int.parse(s)];
    setState(() => _status = 'Generating a ${w}x${h}x$d volume');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final stopwatch = Stopwatch()..start();
    final volume = VolumeData(w, h, d);
    print(
      'volume_bench: generated ${w}x${h}x$d in '
      '${stopwatch.elapsedMilliseconds} ms on $backendName; ${gpu.gpuLimits}',
    );

    final bench = VolumeBench(volume, library);
    _passOverheadMs = await bench.passOverheadMs();
    print('volume_bench: empty pass ${_passOverheadMs.toStringAsFixed(3)} ms');
    await for (final result in bench.run()) {
      setState(() {
        _results.add(result);
        _status = 'Ran ${result.storage.label}';
      });
      print('volume_bench: ${_row(result)}');
    }
    print('\n${_table(volume)}');
    print('BENCH_JSON ${jsonEncode(_json(volume))}');
    setState(() => _status = 'Done');
  }

  String _row(VariantResult r) {
    if (r.skipped != null) {
      return '| ${r.storage.label} | skipped: ${r.skipped} |';
    }
    String gpuMs(Workload w) {
      final result = r.workloads[w]!;
      return '${result.gpuMsPerFrame.toStringAsFixed(3)} '
          '(±${(result.spreadMs / 2).toStringAsFixed(3)})';
    }

    String diff(Workload w) {
      final result = r.workloads[w]!;
      return '${result.maxDiff} / ${result.meanDiff.toStringAsFixed(2)}';
    }

    return '| ${r.storage.label} | ${r.storage.precision} | '
        '${r.storage.fetches} | ${(r.bytes / (1 << 20)).toStringAsFixed(1)} | '
        '${r.prepareMs.toStringAsFixed(0)} | ${r.uploadMs.toStringAsFixed(0)} | '
        '${gpuMs(Workload.reslice)} | ${gpuMs(Workload.mip)} | '
        '${diff(Workload.reslice)} | ${diff(Workload.mip)} |';
  }

  String _table(VolumeData volume) {
    final source = _results
        .expand((r) => r.workloads.values)
        .map((w) => w.timingSource.name)
        .toSet()
        .join(', ');
    return [
      '$backendName, ${volume.width}x${volume.height}x${volume.depth} '
          'volume, ${kViewport}x$kViewport viewport, GPU time from: $source, '
          'empty pass: ${_passOverheadMs.toStringAsFixed(3)} ms',
      '| Storage | Precision | Fetches/sample | MiB | Pack ms | Upload ms | '
          'Reslice ms/draw | MIP ms/draw | Reslice diff max/mean | '
          'MIP diff max/mean |',
      '|---|---|---|---|---|---|---|---|---|---|',
      for (final r in _results) _row(r),
    ].join('\n');
  }

  Map<String, Object?> _json(VolumeData volume) => {
    'backend': backendName,
    'size': [volume.width, volume.height, volume.depth],
    'viewport': kViewport,
    'empty_pass_ms': _passOverheadMs,
    'variants': [
      for (final r in _results)
        {
          'storage': r.storage.name,
          if (r.skipped != null) 'skipped': r.skipped,
          if (r.skipped == null) ...{
            'bytes': r.bytes,
            'prepare_ms': r.prepareMs,
            'upload_ms': r.uploadMs,
            for (final MapEntry(key: w, value: result) in r.workloads.entries)
              w.name: {
                'gpu_ms_per_frame': result.gpuMsPerFrame,
                'spread_ms': result.spreadMs,
                'frames_per_sample': result.framesPerSample,
                'timing_source': result.timingSource.name,
                'max_diff': result.maxDiff,
                'mean_diff': result.meanDiff,
              },
          },
        },
    ],
  };

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFF101114),
        child: DefaultTextStyle(
          style: const TextStyle(color: Color(0xFFE6E6E6), fontSize: 13),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('volume_bench on $backendName: $_status'),
                const SizedBox(height: 12),
                for (final result in _results) _VariantRow(result),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VariantRow extends StatelessWidget {
  const _VariantRow(this.result);

  final VariantResult result;

  @override
  Widget build(BuildContext context) {
    final skipped = result.skipped;
    String ms(Workload w) =>
        result.workloads[w]!.gpuMsPerFrame.toStringAsFixed(2);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 220,
            child: Text(
              skipped != null
                  ? '${result.storage.label}\nskipped: $skipped'
                  : '${result.storage.label}\n'
                        '${(result.bytes / (1 << 20)).toStringAsFixed(1)} MiB, '
                        'upload ${result.uploadMs.toStringAsFixed(0)} ms\n'
                        'reslice ${ms(Workload.reslice)} ms\n'
                        'MIP ${ms(Workload.mip)} ms',
            ),
          ),
          for (final workload in result.workloads.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 160,
                height: 160,
                child: RawImage(image: workload.preview),
              ),
            ),
        ],
      ),
    );
  }
}
