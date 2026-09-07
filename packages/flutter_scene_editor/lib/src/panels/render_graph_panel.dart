/// The Render Graph dock panel: capture-on-demand of the viewport's frame
/// (pass lane with thumbnails, CPU timings, data flow), the non-finite
/// scan, and the texture viewer with pixel inspection.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
// ignore: implementation_imports
import 'package:flutter_scene/src/render/render_graph_capture.dart';

import '../controller/editor_controller.dart';
import '../render_graph/debug_shaders.dart';
import '../render_graph/render_graph_inspector.dart';
import '../shell/editor_theme.dart';
import '../shell/panel_chrome.dart';
import '../shell/editor_dialog.dart';

/// The dockable Render Graph inspector.
class RenderGraphPanel extends StatefulWidget {
  const RenderGraphPanel({
    super.key,
    required this.controller,
    required this.inspector,
  });

  final EditorController controller;
  final RenderGraphInspector inspector;

  @override
  State<RenderGraphPanel> createState() => _RenderGraphPanelState();
}

class _RenderGraphPanelState extends State<RenderGraphPanel> {
  int? _selectedPass;

  RenderGraphInspector get _inspector => widget.inspector;

  @override
  void initState() {
    super.initState();
    _inspector.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(RenderGraphPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.inspector != widget.inspector) {
      oldWidget.inspector.removeListener(_onChanged);
      _inspector.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    _inspector.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    _inspector.scene = widget.controller.scene;
    final result = _inspector.result;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toolbar(),
        const Divider(height: 1),
        Expanded(
          child: result == null
              ? const Center(
                  child: Text(
                    'Capture a frame to inspect the render graph.',
                    style: editorDetailText,
                  ),
                )
              : _captureView(result),
        ),
      ],
    );
  }

  Widget _toolbar() {
    final busy = _inspector.busy;
    final report = _inspector.nonFiniteReport;
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Row(
        children: [
          FilledButton.tonalIcon(
            onPressed: busy ? null : () => _inspector.captureFrame(),
            icon: const Icon(Icons.camera_alt_outlined, size: 14),
            label: const Text('Capture', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 6),
          OutlinedButton(
            onPressed: busy || _inspector.result == null
                ? null
                : () => _inspector.scanForNonFinite(),
            child: const Text('Scan NaN/Inf', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 10),
          if (busy)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          if (!busy && report != null)
            Text(
              report.offenders.isEmpty
                  ? 'No non-finite values '
                        '(${report.scannedCount} targets scanned)'
                  : 'Non-finite values originate in '
                        '${report.offenders.first.passName}',
              style: editorDetailText.copyWith(
                color: report.offenders.isEmpty
                    ? editorSuccessColor
                    : editorErrorColor,
              ),
            ),
          if (!busy && _inspector.lastError != null)
            Expanded(
              child: Text(
                _inspector.lastError!,
                style: editorDetailText.copyWith(color: editorErrorColor),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          const Spacer(),
          Tooltip(
            message:
                'Per-pass GPU timings need engine timestamp queries; this '
                'build reports CPU encode time.',
            child: Text('CPU timings', style: editorDetailText),
          ),
        ],
      ),
    );
  }

  Widget _captureView(RenderGraphCaptureResult result) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
          child: Text(
            '${result.passes.length} passes, '
            '${result.pixelWidth}x${result.pixelHeight}',
            style: editorDetailText,
          ),
        ),
        Expanded(
          flex: 3,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(8),
            itemCount: result.passes.length,
            itemBuilder: (context, index) =>
                _passCard(result, result.passes[index]),
          ),
        ),
        const Divider(height: 1),
        Expanded(flex: 2, child: _detailPane(result)),
      ],
    );
  }

  Widget _passCard(RenderGraphCaptureResult result, CapturedPass pass) {
    final selected = _selectedPass == pass.indexInGraph;
    final report = _inspector.nonFiniteReport;
    final offending =
        report != null &&
        report.offenders.any((entry) => entry.passIndex == pass.indexInGraph);
    final outputs = [
      for (final resource in _inspector.resources)
        if (resource.captured.passIndex == pass.indexInGraph) resource,
    ];
    return GestureDetector(
      onTap: () => setState(() => _selectedPass = pass.indexInGraph),
      child: Container(
        width: 168,
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: editorRaisedColor,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: offending
                ? editorErrorColor
                : selected
                ? editorAccentColor
                : editorLineColor,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${pass.indexInGraph}. ${pass.name}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text('${pass.cpuMicros} us', style: editorDetailText),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: outputs.isEmpty
                  ? const Center(
                      child: Text('no outputs', style: editorDetailText),
                    )
                  : ListView(
                      children: [
                        for (final resource in outputs) _resourceTile(resource),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resourceTile(InspectedResource resource) {
    final thumbnail = resource.thumbnail;
    final captured = resource.captured;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: captured.isTexture && captured.shaderReadable
            ? () => _openViewer(resource)
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (thumbnail != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: RawImage(
                  image: thumbnail,
                  fit: BoxFit.contain,
                  width: double.infinity,
                ),
              )
            else
              Container(
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: editorPanelColor,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  captured.isTexture
                      ? (captured.shaderReadable
                            ? 'no image'
                            : 'not shader-readable')
                      : '${captured.byteLength} bytes',
                  style: editorDetailText,
                ),
              ),
            Text(
              captured.key,
              style: const TextStyle(fontSize: 10),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailPane(RenderGraphCaptureResult result) {
    final index = _selectedPass;
    if (index == null || index >= result.passes.length) {
      return const Center(
        child: Text('Select a pass for details.', style: editorDetailText),
      );
    }
    final pass = result.passes[index];
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        Text('${pass.name} (pass $index)', style: editorSubheadText),
        const SizedBox(height: 4),
        Text('CPU encode: ${pass.cpuMicros} us', style: editorDetailText),
        const SizedBox(height: 8),
        Text('Reads', style: editorDetailText),
        for (final key in pass.reads)
          Text('  $key', style: const TextStyle(fontSize: 11)),
        if (pass.reads.isEmpty)
          const Text('  (none)', style: TextStyle(fontSize: 11)),
        const SizedBox(height: 6),
        Text('Writes', style: editorDetailText),
        for (final key in pass.writes)
          Text('  $key', style: const TextStyle(fontSize: 11)),
        if (pass.writes.isEmpty)
          const Text('  (none)', style: TextStyle(fontSize: 11)),
        const SizedBox(height: 8),
        Text('Resources written', style: editorDetailText),
        for (final resource in _inspector.resources)
          if (resource.captured.passIndex == index)
            Text(
              '  ${resource.key}  '
              '${resource.captured.width}x${resource.captured.height}  '
              '${resource.captured.format?.name ?? 'data'}'
              '${resource.captured.storageMode == gpu.StorageMode.deviceTransient ? '  (transient)' : ''}',
              style: const TextStyle(fontSize: 11),
            ),
      ],
    );
  }

  Future<void> _openViewer(InspectedResource resource) async {
    final snapshot = await _inspector.captureFullResolution(resource.key);
    if (!mounted) return;
    await showEditorDialog<void>(
      context,
      builder: (context) => Dialog(
        child: SizedBox(
          width: 900,
          height: 640,
          child: TextureViewer(
            resourceKey: resource.key,
            format: resource.captured.format,
            texture: snapshot ?? resource.captured.thumbnail,
            fullResolution: snapshot != null,
          ),
        ),
      ),
    );
  }
}

/// Full texture inspection: remapped display with zoom/pan, channel and
/// range controls, non-finite highlighting, and exact-value pixel picking.
class TextureViewer extends StatefulWidget {
  const TextureViewer({
    super.key,
    required this.resourceKey,
    required this.format,
    required this.texture,
    required this.fullResolution,
  });

  final String resourceKey;
  final gpu.PixelFormat? format;

  /// A same-format snapshot of the resource (full resolution when
  /// available, else the capture thumbnail).
  final gpu.Texture? texture;
  final bool fullResolution;

  @override
  State<TextureViewer> createState() => _TextureViewerState();
}

class _TextureViewerState extends State<TextureViewer> {
  late RemapSettings _settings;
  ui.Image? _image;
  Float32List? _floats;
  bool _floatsRequested = false;
  Offset? _pickedTexel;

  @override
  void initState() {
    super.initState();
    _settings = RemapSettings.defaultsFor(widget.format, widget.resourceKey);
    _rebuildImage();
  }

  void _rebuildImage() {
    final texture = widget.texture;
    if (texture == null) return;
    try {
      final image = remapToImage(texture, _settings);
      setState(() {
        _image?.dispose();
        _image = image;
      });
    } catch (error) {
      // Leave the previous image; the viewer stays usable.
    }
  }

  Future<void> _ensureFloats() async {
    if (_floatsRequested || widget.texture == null) return;
    _floatsRequested = true;
    final floats = await readbackFloats(widget.texture!);
    if (mounted) setState(() => _floats = floats);
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final texture = widget.texture;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${widget.resourceKey}  '
                  '${texture?.width ?? 0}x${texture?.height ?? 0}  '
                  '${widget.format?.name ?? ''}'
                  '${widget.fullResolution ? '' : '  (thumbnail)'}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        _controls(),
        const Divider(height: 1),
        Expanded(
          child: texture == null || _image == null
              ? const Center(
                  child: Text('No image captured.', style: editorDetailText),
                )
              : _imageView(),
        ),
        const Divider(height: 1),
        _pixelReadout(),
      ],
    );
  }

  Widget _controls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Wrap(
        spacing: 10,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          EditorDropdown<RemapMode>(
            value: _settings.mode,
            items: const [
              DropdownMenuItem(value: RemapMode.color, child: Text('Color')),
              DropdownMenuItem(
                value: RemapMode.singleChannel,
                child: Text('Channel'),
              ),
              DropdownMenuItem(value: RemapMode.depth, child: Text('Depth')),
              DropdownMenuItem(
                value: RemapMode.octahedralNormal,
                child: Text('Normals (oct gb)'),
              ),
            ],
            onChanged: (mode) {
              if (mode == null) return;
              _settings = _settings.copyWith(mode: mode);
              _rebuildImage();
            },
          ),
          if (_settings.mode == RemapMode.singleChannel)
            EditorDropdown<int>(
              value: _settings.channel,
              items: const [
                DropdownMenuItem(value: 0, child: Text('R')),
                DropdownMenuItem(value: 1, child: Text('G')),
                DropdownMenuItem(value: 2, child: Text('B')),
                DropdownMenuItem(value: 3, child: Text('A')),
              ],
              onChanged: (channel) {
                if (channel == null) return;
                _settings = _settings.copyWith(channel: channel);
                _rebuildImage();
              },
            ),
          _slider(
            'Exposure',
            _settings.exposure,
            0,
            8,
            (value) => _settings = _settings.copyWith(exposure: value),
          ),
          _slider(
            'White',
            _settings.whitePoint,
            0.01,
            _settings.mode == RemapMode.depth ? 200 : 16,
            (value) =>
                _settings = _settings.copyWith(whitePoint: value, far: value),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: _settings.highlightNonFinite,
                visualDensity: VisualDensity.compact,
                onChanged: (value) {
                  _settings = _settings.copyWith(
                    highlightNonFinite: value ?? false,
                  );
                  _rebuildImage();
                },
              ),
              const Text('NaN/Inf', style: TextStyle(fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    void Function(double) apply,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: editorDetailText),
        SizedBox(
          width: 120,
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: (next) {
              apply(next);
              _rebuildImage();
            },
          ),
        ),
        Text(value.toStringAsFixed(2), style: editorDetailText),
      ],
    );
  }

  Widget _imageView() {
    final image = _image!;
    return LayoutBuilder(
      builder: (context, constraints) => InteractiveViewer(
        maxScale: 64,
        child: Center(
          child: GestureDetector(
            onTapDown: (details) => _pick(details.localPosition),
            child: SizedBox(
              width: image.width.toDouble(),
              height: image.height.toDouble(),
              child: RawImage(image: image, fit: BoxFit.fill),
            ),
          ),
        ),
      ),
    );
  }

  void _pick(Offset local) {
    final texture = widget.texture;
    if (texture == null) return;
    final x = local.dx.floor().clamp(0, texture.width - 1);
    final y = local.dy.floor().clamp(0, texture.height - 1);
    setState(() => _pickedTexel = Offset(x.toDouble(), y.toDouble()));
    _ensureFloats();
  }

  Widget _pixelReadout() {
    final texel = _pickedTexel;
    final texture = widget.texture;
    String text;
    if (texel == null || texture == null) {
      text = 'Click a pixel for exact values.';
    } else if (_floats == null) {
      text = _floatsRequested
          ? 'Pixel (${texel.dx.toInt()}, ${texel.dy.toInt()}): float readback '
                'unavailable on this backend.'
          : 'Reading...';
    } else {
      final index = (texel.dy.toInt() * texture.width + texel.dx.toInt()) * 4;
      if (index + 3 < _floats!.length) {
        final r = _floats![index];
        final g = _floats![index + 1];
        final b = _floats![index + 2];
        final a = _floats![index + 3];
        String value(double v) => v.isNaN
            ? 'NaN'
            : v.isInfinite
            ? (v > 0 ? '+Inf' : '-Inf')
            : v.toStringAsFixed(6);
        text =
            'Pixel (${texel.dx.toInt()}, ${texel.dy.toInt()}):  '
            'R ${value(r)}  G ${value(g)}  B ${value(b)}  A ${value(a)}';
      } else {
        text = 'Pixel out of range.';
      }
    }
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(text, style: const TextStyle(fontSize: 12)),
    );
  }
}
