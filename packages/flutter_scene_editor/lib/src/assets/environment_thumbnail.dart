import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/material/equirect_image.dart';

/// A display-referred panorama preview for an environment image.
class EnvironmentThumbnail extends StatefulWidget {
  const EnvironmentThumbnail({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
  }) : bytes = null,
       cacheKey = null;

  const EnvironmentThumbnail.memory({
    super.key,
    required Uint8List this.bytes,
    required String this.cacheKey,
    this.fit = BoxFit.cover,
  }) : path = null;

  final String? path;
  final Uint8List? bytes;
  final String? cacheKey;
  final BoxFit fit;

  @override
  State<EnvironmentThumbnail> createState() => _EnvironmentThumbnailState();
}

class _EnvironmentThumbnailState extends State<EnvironmentThumbnail> {
  Future<ui.Image>? _hdrImage;

  bool get _isHdr {
    final bytes = widget.bytes;
    if (bytes != null) {
      return detectEquirectImageFormat(bytes) != EquirectImageFormat.ldr;
    }
    final lower = widget.path!.toLowerCase();
    return lower.endsWith('.hdr') || lower.endsWith('.exr');
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(EnvironmentThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.cacheKey != widget.cacheKey) {
      _load();
    }
  }

  void _load() {
    _hdrImage = _isHdr
        ? widget.bytes == null
              ? _environmentThumbnail(widget.path!)
              : _environmentThumbnailBytes(widget.bytes!, widget.cacheKey!)
        : null;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isHdr) {
      final bytes = widget.bytes;
      return bytes == null
          ? Image.file(
              File(widget.path!),
              fit: widget.fit,
              cacheWidth: 384,
              errorBuilder: (_, _, _) => const _EnvironmentPreviewError(),
            )
          : Image.memory(
              bytes,
              fit: widget.fit,
              cacheWidth: 384,
              errorBuilder: (_, _, _) => const _EnvironmentPreviewError(),
            );
    }
    return FutureBuilder<ui.Image>(
      future: _hdrImage,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const _EnvironmentPreviewError();
        final image = snapshot.data;
        if (image == null) {
          return Center(
            child: Icon(
              Icons.panorama_outlined,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          );
        }
        return RawImage(image: image, fit: widget.fit);
      },
    );
  }
}

class _EnvironmentPreviewError extends StatelessWidget {
  const _EnvironmentPreviewError();

  @override
  Widget build(BuildContext context) => Center(
    child: Icon(
      Icons.broken_image_outlined,
      size: 22,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

final Map<String, Future<ui.Image>> _environmentThumbnailCache = {};

Future<ui.Image> _environmentThumbnail(String path) async {
  final file = File(path);
  final stat = await file.stat();
  final key = '$path|${stat.modified.microsecondsSinceEpoch}|${stat.size}';
  return _environmentThumbnailCache.putIfAbsent(key, () async {
    final bytes = await file.readAsBytes();
    return _decodeEnvironmentThumbnail(bytes);
  });
}

Future<ui.Image> _environmentThumbnailBytes(Uint8List bytes, String cacheKey) =>
    _environmentThumbnailCache.putIfAbsent(
      'memory:$cacheKey:${bytes.length}',
      () => _decodeEnvironmentThumbnail(bytes),
    );

Future<ui.Image> _decodeEnvironmentThumbnail(Uint8List bytes) async {
  final result = await compute(_decodeEnvironmentPreview, bytes);
  final pixels = result[0] as Uint8List;
  final width = result[1] as int;
  final height = result[2] as int;
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
    rowBytes: width * 4,
  );
  return completer.future;
}

List<Object> _decodeEnvironmentPreview(Uint8List bytes) {
  final source = decodeEquirectHdrImage(bytes, maxWidth: 384);
  if (source == null) throw const FormatException('Not an HDR image');
  final pixels = source.pixels;
  var logSum = 0.0;
  var count = 0;
  for (var i = 0; i < pixels.length; i += 4) {
    final luminance = math.max(
      1e-6,
      pixels[i] * 0.2126 + pixels[i + 1] * 0.7152 + pixels[i + 2] * 0.0722,
    );
    logSum += math.log(luminance);
    count++;
  }
  final average = count == 0 ? 0.18 : math.exp(logSum / count);
  final exposure = (0.18 / average).clamp(0.01, 100.0);
  final out = Uint8List(source.width * source.height * 4);
  for (var i = 0; i < pixels.length; i += 4) {
    final mapped = _pbrNeutral(
      pixels[i] * exposure,
      pixels[i + 1] * exposure,
      pixels[i + 2] * exposure,
    );
    out[i] = (_linearToSrgb(mapped.$1) * 255).round().clamp(0, 255);
    out[i + 1] = (_linearToSrgb(mapped.$2) * 255).round().clamp(0, 255);
    out[i + 2] = (_linearToSrgb(mapped.$3) * 255).round().clamp(0, 255);
    out[i + 3] = 255;
  }
  return [out, source.width, source.height];
}

@visibleForTesting
List<Object> decodeEnvironmentPreviewForTesting(Uint8List bytes) =>
    _decodeEnvironmentPreview(bytes);

(double, double, double) _pbrNeutral(double r, double g, double b) {
  const startCompression = 0.76;
  const desaturation = 0.15;
  final x = math.min(r, math.min(g, b));
  final offset = x < 0.08 ? x - 6.25 * x * x : 0.04;
  r = math.max(0, r - offset);
  g = math.max(0, g - offset);
  b = math.max(0, b - offset);
  final peak = math.max(r, math.max(g, b));
  if (peak < startCompression) return (r, g, b);
  const d = 1.0 - startCompression;
  final newPeak = 1.0 - d * d / (peak + d - startCompression);
  final scale = newPeak / peak;
  r *= scale;
  g *= scale;
  b *= scale;
  final blend = 1.0 - 1.0 / (desaturation * (peak - newPeak) + 1.0);
  return (
    r + (newPeak - r) * blend,
    g + (newPeak - g) * blend,
    b + (newPeak - b) * blend,
  );
}

double _linearToSrgb(double value) {
  final v = value.clamp(0.0, 1.0);
  return v <= 0.0031308 ? v * 12.92 : 1.055 * math.pow(v, 1 / 2.4) - 0.055;
}
