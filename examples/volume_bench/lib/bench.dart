// The benchmark proper: uploads one volume in each storage, then times a
// planar reslice and a ray-marched MIP over a fixed viewport, drawing
// straight through the GPU shim so nothing but the fetch path differs.
//
// ignore_for_file: implementation_imports
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart';

import 'volume_data.dart';

/// The fixed render size every workload draws.
const int kViewport = 1024;

/// How a variant stores the volume.
enum Storage {
  atlas('RGBA8 atlas', 'Atlas'),
  arrayR8('2D array r8', 'ArrayR'),
  arrayRg8('2D array rg8', 'ArrayRg'),
  arrayR32f('2D array r32f', 'ArrayR'),
  volumeR8('3D r8', 'VolumeR'),
  volumeRg8('3D rg8', 'VolumeRg'),
  volumeR32f('3D r32f', 'VolumeR');

  const Storage(this.label, this.shaderPrefix);

  final String label;
  final String shaderPrefix;

  bool get is3D => name.startsWith('volume');

  /// Bytes per voxel, and so the precision kept.
  String get precision => switch (this) {
    atlas || arrayRg8 || volumeRg8 => '16-bit',
    arrayR8 || volumeR8 => '8-bit',
    arrayR32f || volumeR32f => 'float32',
  };

  /// What filtering the material does itself.
  String get fetches => switch (this) {
    atlas => '8 texelFetch',
    arrayR8 || arrayRg8 || arrayR32f => '2 bilinear',
    _ => '1 trilinear',
  };
}

enum Workload {
  reslice('Reslice'),
  mip('Mip');

  const Workload(this.shaderSuffix);
  final String shaderSuffix;
}

class WorkloadResult {
  WorkloadResult({
    required this.gpuMsPerFrame,
    required this.spreadMs,
    required this.framesPerSample,
    required this.timingSource,
    required this.maxDiff,
    required this.meanDiff,
    required this.preview,
  });

  /// Median over the samples of each sample's time divided by the full-screen
  /// draws in it.
  final double gpuMsPerFrame;

  /// Max minus min of the per-frame samples.
  final double spreadMs;
  final int framesPerSample;
  final gpu.GpuTimingSource timingSource;

  /// Gray-level difference from the atlas render, out of 255.
  final int maxDiff;
  final double meanDiff;
  final ui.Image preview;
}

class VariantResult {
  VariantResult(this.storage, this.prepareMs, this.uploadMs, this.bytes);

  final Storage storage;

  /// CPU time packing the source values into this storage.
  final double prepareMs;

  /// Creating the textures and writing every texel, until the GPU is idle.
  final double uploadMs;

  /// Texel bytes allocated (excluding driver padding).
  final int bytes;
  final Map<Workload, WorkloadResult> workloads = {};
  String? skipped;
}

/// The textures one variant samples, bound under their shader names.
typedef _Bound =
    Map<String, ({gpu.Texture texture, gpu.SamplerOptions sampler})>;

class VolumeBench {
  VolumeBench(this.volume, this.library);

  final VolumeData volume;
  final gpu.ShaderLibrary library;

  late final gpu.Texture _target = gpu.gpuContext.createTexture(
    gpu.StorageMode.devicePrivate,
    kViewport,
    kViewport,
  );

  late final gpu.DeviceBuffer _triangle = gpu.gpuContext
      .createDeviceBufferWithCopy(
        ByteData.sublistView(Float32List.fromList([-1, -1, 3, -1, -1, 3])),
      );

  late final AtlasLayout _layout = AtlasLayout(volume);

  /// The atlas renders every other variant is compared against.
  final Map<Workload, Uint8List> _reference = {};

  /// The cost of one empty pass (clear and store, no draw) timed the same
  /// way, so the floor under the per-frame numbers is visible.
  Future<double> passOverheadMs() async {
    const frames = 48;
    Future<gpu.GpuWorkTiming> clear() => gpu.timeGpuWork((newCommandBuffer) {
      for (var frame = 0; frame < frames; frame++) {
        newCommandBuffer().createRenderPass(
          gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: _target)),
        );
      }
    });
    await clear();
    final samples = [
      for (var i = 0; i < 7; i++)
        (await clear()).elapsed.inMicroseconds / 1000 / frames,
    ]..sort();
    return samples[samples.length ~/ 2];
  }

  /// Runs every variant the backend supports, reporting each as it finishes.
  Stream<VariantResult> run() async* {
    final limits = gpu.gpuLimits;
    for (final storage in Storage.values) {
      if (storage.is3D && !limits.supports3DTextures) {
        yield VariantResult(storage, 0, 0, 0)
          ..skipped = 'no 3D textures on this backend';
        continue;
      }
      yield await _runVariant(storage);
    }
  }

  Future<VariantResult> _runVariant(Storage storage) async {
    final stopwatch = Stopwatch()..start();
    final packed = _pack(storage);
    final prepareMs = _ms(stopwatch);
    _trace('${storage.name}: packed in ${prepareMs.toStringAsFixed(0)} ms');

    stopwatch.reset();
    final (bound, bytes) = _upload(storage, packed);
    // Wait for the writes to land: the GPU idles once an empty buffer
    // submitted after them completes.
    await gpu.timeGpuWork((_) {});
    final uploadMs = _ms(stopwatch);
    _trace('${storage.name}: uploaded in ${uploadMs.toStringAsFixed(0)} ms');

    final result = VariantResult(storage, prepareMs, uploadMs, bytes);
    for (final workload in Workload.values) {
      result.workloads[workload] = await _time(storage, workload, bound);
    }
    return result;
  }

  Object _pack(Storage storage) => switch (storage) {
    Storage.atlas => packAtlas(volume, _layout),
    Storage.arrayR8 || Storage.volumeR8 => packR8Slices(volume),
    Storage.arrayRg8 || Storage.volumeRg8 => packRg8Slices(volume),
    Storage.arrayR32f || Storage.volumeR32f => packR32fSlices(volume),
  };

  (_Bound, int) _upload(Storage storage, Object packed) {
    if (storage == Storage.atlas) {
      final pages = packed as List<Uint8List>;
      final textures = [
        for (var p = 0; p < pages.length; p++)
          Texture2D.fromData(
            pages[p],
            _layout.pageWidth,
            _layout.pageHeight(p, volume.depth),
            sampling: const TextureSampling(
              mipmaps: false,
              minFilter: gpu.MinMagFilter.nearest,
              magFilter: gpu.MinMagFilter.nearest,
              addressMode: gpu.SamplerAddressMode.clampToEdge,
            ),
          ),
      ];
      return (
        {
          // Unused page slots repeat the first page.
          for (var p = 0; p < 4; p++)
            'page$p': (
              texture: textures[math.min(p, textures.length - 1)].gpuTexture,
              sampler: textures.first.sampledSampler,
            ),
        },
        pages.fold(0, (sum, page) => sum + page.lengthInBytes),
      );
    }
    final layers = (packed as List).cast<TypedData>();
    final format = switch (storage) {
      Storage.arrayR8 || Storage.volumeR8 => gpu.PixelFormat.r8UNormInt,
      Storage.arrayRg8 || Storage.volumeRg8 => gpu.PixelFormat.r8g8UNormInt,
      _ => gpu.PixelFormat.r32Float,
    };
    if (storage.is3D) {
      final texture = Texture3D.empty(
        width: volume.width,
        height: volume.height,
        depth: volume.depth,
        format: format,
      );
      for (var z = 0; z < layers.length; z++) {
        texture.writeSlice(z, layers[z]);
      }
      return (
        {
          'volume': (
            texture: texture.gpuTexture,
            sampler: texture.sampledSampler,
          ),
        },
        texture.byteSize,
      );
    }
    final texture = Texture2DArray.fromLayers(
      layers,
      width: volume.width,
      height: volume.height,
      format: format,
    );
    return (
      {
        'layers': (
          texture: texture.gpuTexture,
          sampler: texture.sampledSampler,
        ),
      },
      texture.byteSize,
    );
  }

  Future<WorkloadResult> _time(
    Storage storage,
    Workload workload,
    _Bound bound,
  ) async {
    final fragment =
        library['${storage.shaderPrefix}${workload.shaderSuffix}Fragment']!;
    final pipeline = gpu.gpuContext.createRenderPipeline(
      library['FullscreenVertex']!,
      fragment,
    );

    // [frames] passes (one command buffer each, as Flutter GPU wants), each
    // clearing the whole target and drawing over it [draws] times. Repeated
    // draws blend additively, so a tile-based GPU cannot cull all but the
    // last as hidden; the reslice is too cheap to time one draw per pass
    // above the pass overhead. The reference frame is one opaque draw.
    final drawsPerPass = workload == Workload.reslice ? 16 : 1;
    Future<gpu.GpuWorkTiming> draw(
      int frames, {
      gpu.Texture? into,
      int draws = 1,
    }) => gpu.timeGpuWork((newCommandBuffer) {
      final transients = gpu.gpuContext.createHostBuffer();
      for (var frame = 0; frame < frames; frame++) {
        final pass = newCommandBuffer().createRenderPass(
          gpu.RenderTarget.singleColor(
            gpu.ColorAttachment(texture: into ?? _target),
          ),
        );
        pass
          ..bindPipeline(pipeline)
          ..bindVertexBuffer(
            gpu.BufferView(_triangle, offsetInBytes: 0, lengthInBytes: 24),
          )
          ..bindUniform(
            fragment.getUniformSlot('BenchParams'),
            transients.emplace(_params(workload, frame)),
          );
        for (final MapEntry(key: name, value: binding) in bound.entries) {
          pass.bindTexture(
            fragment.getUniformSlot(name),
            binding.texture,
            sampler: binding.sampler,
          );
        }
        if (draws > 1) {
          pass
            ..setColorBlendEnable(true)
            ..setColorBlendEquation(
              gpu.ColorBlendEquation(
                destinationColorBlendFactor: gpu.BlendFactor.one,
                destinationAlphaBlendFactor: gpu.BlendFactor.one,
              ),
            );
        }
        for (var i = 0; i < draws; i++) {
          pass.draw(3);
        }
      }
    });

    // Warm up (pipeline compile, first-use residency), then size each sample
    // to about 50 ms of GPU work so submission overhead stays small.
    await draw(2, draws: drawsPerPass);
    final probe = await draw(2, draws: drawsPerPass);
    _trace('${storage.name} ${workload.name}: probe $probe');
    final perFrame = probe.elapsed.inMicroseconds / 2000;
    final frames = (50 / math.max(perFrame, 0.05)).ceil().clamp(2, 48);
    final samples = <double>[];
    late gpu.GpuTimingSource source;
    for (var i = 0; i < 7; i++) {
      final timing = await draw(frames, draws: drawsPerPass);
      source = timing.source;
      samples.add(
        timing.elapsed.inMicroseconds / 1000 / (frames * drawsPerPass),
      );
    }
    samples.sort();

    // A reference frame (frame index 0) for the image comparison, in a target
    // of its own: on native the image shares the texture's storage.
    final still = gpu.gpuContext.createTexture(
      gpu.StorageMode.devicePrivate,
      kViewport,
      kViewport,
    );
    await draw(1, into: still);
    final preview = still.asImage();
    final pixels = (await preview.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    final reference = _reference.putIfAbsent(workload, () => pixels);
    var maxDiff = 0;
    var sumDiff = 0;
    for (var i = 0; i < pixels.length; i += 4) {
      final diff = (pixels[i] - reference[i]).abs();
      sumDiff += diff;
      if (diff > maxDiff) maxDiff = diff;
    }
    return WorkloadResult(
      gpuMsPerFrame: samples[samples.length ~/ 2],
      spreadMs: samples.last - samples.first,
      framesPerSample: frames,
      timingSource: source,
      maxDiff: maxDiff,
      meanDiff: sumDiff / (pixels.length / 4),
      preview: preview,
    );
  }

  /// The uniform block for one frame. Frames turn the plane and the camera a
  /// little, so no two passes in a sample are identical.
  ByteData _params(Workload workload, int frame) {
    final data = Float32List(40);
    void put(int slot, Vector3 v, [double w = 0]) {
      data
        ..[slot * 4] = v.x
        ..[slot * 4 + 1] = v.y
        ..[slot * 4 + 2] = v.z
        ..[slot * 4 + 3] = w;
    }

    final center = Vector3.all(0.5);
    put(
      0,
      Vector3(
        volume.width.toDouble(),
        volume.height.toDouble(),
        volume.depth.toDouble(),
      ),
    );
    final angle = 0.5 + 0.004 * frame;
    if (workload == Workload.reslice) {
      // An oblique plane through the center, a little larger than the
      // volume so its edges show.
      final u = Vector3(math.cos(angle), 0.25, math.sin(angle)).normalized();
      final tilt = Vector3(0.2, 1, 0.3);
      final v = (tilt - u * tilt.dot(u)).normalized()..scale(1.25);
      u.scale(1.25);
      put(1, center - (u + v) * 0.5);
      put(2, u);
      put(3, v);
    } else {
      final forward = Vector3(
        math.sin(angle) * 0.9,
        -0.35,
        math.cos(angle) * 0.9,
      ).normalized();
      final position = center - forward * 1.7;
      final halfFov = math.tan(25 * math.pi / 180);
      final right = forward.cross(Vector3(0, 1, 0)).normalized()
        ..scale(halfFov);
      final up = right.cross(forward).normalized()..scale(halfFov);
      put(4, position);
      put(5, forward);
      put(6, right);
      put(7, up);
      final longest = math.max(
        volume.width,
        math.max(volume.height, volume.depth),
      );
      // One voxel per step, enough steps for the diagonal.
      data[32] = (math.sqrt(3) * longest).ceilToDouble() + 1;
      data[33] = 1 / longest;
    }
    data
      ..[36] = _layout.slicesPerRow.toDouble()
      ..[37] = _layout.slicesPerPage.toDouble()
      ..[38] = _layout.tileWidth.toDouble()
      ..[39] = _layout.tileHeight.toDouble();
    return ByteData.sublistView(data);
  }
}

/// Progress for a run that is watched from a terminal.
void _trace(String message) {
  developer.Timeline.instantSync(message);
  // ignore: avoid_print
  print('volume_bench: $message');
}

double _ms(Stopwatch stopwatch) => stopwatch.elapsedMicroseconds / 1000;
