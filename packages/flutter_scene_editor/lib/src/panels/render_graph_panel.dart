/// The Render Graph dock panel: the live frame stats strip,
/// capture-on-demand of the viewport's frame (pass lane with thumbnails,
/// CPU timings, data flow, draws), the non-finite scan, and the texture
/// viewer with pixel inspection.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_scene/scene.dart'
    show
        BatchBreakReason,
        RenderFrameStats,
        RenderViewStats,
        ShaderUniformValue;
// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
// ignore: implementation_imports
import 'package:flutter_scene/src/render/render_graph_capture.dart';

import '../controller/editor_controller.dart';
import '../render_graph/debug_shaders.dart';
import '../render_graph/render_graph_inspector.dart';
import '../shell/editor_theme.dart';
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
  int? _expandedDraw;
  Timer? _statsTimer;
  int? _statsFrame;

  RenderGraphInspector get _inspector => widget.inspector;

  @override
  void initState() {
    super.initState();
    _inspector.addListener(_onChanged);
    _statsTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _pollStats(),
    );
  }

  // Repaints only when a new frame has landed, so an idle viewport costs
  // nothing but the tick.
  void _pollStats() {
    final frame = widget.controller.scene.renderStats.latest?.frameIndex;
    if (frame == _statsFrame || !mounted) return;
    setState(() => _statsFrame = frame);
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
    _statsTimer?.cancel();
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
        _statsStrip(),
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
          const SizedBox(width: 6),
          OutlinedButton(
            onPressed: busy || _inspector.result == null ? null : _saveCapture,
            child: const Text('Save capture', style: TextStyle(fontSize: 12)),
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
      onTap: () => setState(() {
        _selectedPass = pass.indexInGraph;
        _expandedDraw = null;
      }),
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
        Text(
          '${pass.name} (pass $index)',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
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
        const SizedBox(height: 8),
        _drawsSection(pass),
      ],
    );
  }

  Widget _drawsSection(CapturedPass pass) {
    final skips = <String, int>{};
    for (final skip in pass.skips) {
      skips[skip.reason.name] = (skips[skip.reason.name] ?? 0) + 1;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Draws (${pass.draws.length})', style: editorDetailText),
        if (pass.draws.isEmpty)
          const Text('  (none)', style: TextStyle(fontSize: 11))
        else
          SizedBox(
            height: 180,
            child: ListView.builder(
              itemCount: pass.draws.length,
              itemBuilder: (context, index) => _drawRow(pass.draws[index]),
            ),
          ),
        const SizedBox(height: 4),
        Text(
          skips.isEmpty
              ? 'Nothing skipped'
              : 'Skipped ${pass.skips.length} '
                    '(${skips.entries.map((e) => '${e.key} ${e.value}').join(', ')})',
          style: editorDetailText,
        ),
      ],
    );
  }

  Widget _drawRow(CapturedDraw draw) {
    final expanded = _expandedDraw == draw.order;
    final vertex = draw.vertexShaderName ?? '?';
    final fragment = draw.fragmentShaderName ?? '?';
    return InkWell(
      onTap: () => setState(() => _expandedDraw = expanded ? null : draw.order),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        decoration: BoxDecoration(
          color: expanded ? editorRaisedColor : null,
          border: const Border(
            bottom: BorderSide(color: editorLineColor, width: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text('${draw.order}', style: editorDetailText),
                ),
                Expanded(
                  child: Text(
                    draw.nodePath ?? '(unnamed)',
                    style: const TextStyle(fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${_count(draw.vertexCount)} v'
                  '${draw.instanceCount > 1 ? '  x${draw.instanceCount}' : ''}'
                  '${draw.batchedItems > 1 ? '  ${draw.batchedItems} batched' : ''}',
                  style: editorDetailText,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 28),
              child: Text(
                '${draw.materialType ?? draw.materialSource ?? 'unknown material'}'
                '  $vertex/$fragment'
                '${draw.batchBreak == BatchBreakReason.none ? '' : '  break ${draw.batchBreak.name}'}',
                style: editorDetailText,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (expanded) ...[
              const SizedBox(height: 3),
              if (draw.uniformBlocks.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(left: 28),
                  child: Text(
                    'no uniform blocks',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              for (final block in draw.uniformBlocks)
                _uniformBlock(draw, block),
            ],
          ],
        ),
      ),
    );
  }

  Widget _uniformBlock(CapturedDraw draw, CapturedUniformBlock block) {
    final name = block.nameFor(draw);
    final values = block.decode(draw);
    final candidates = name == null
        ? block.candidatesFor(draw).map((info) => info.name).toList()
        : const <String>[];
    return Padding(
      padding: const EdgeInsets.only(left: 28, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${name ?? 'unresolved block'}  ${block.byteLength} bytes',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
          if (name == null)
            Text(
              candidates.isEmpty
                  ? 'no declared block of this size'
                  : 'candidates ${candidates.join(', ')}',
              style: editorDetailText,
            ),
          if (values != null)
            for (final value in values)
              Text(
                '${value.name} = ${_uniformValueText(value)}',
                style: const TextStyle(fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
        ],
      ),
    );
  }

  Future<void> _saveCapture() async {
    final result = _inspector.result;
    if (result == null) return;
    final location = await getSaveLocation(
      suggestedName: 'render_capture',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'JSON', extensions: ['json']),
      ],
    );
    final chosen = location?.path;
    if (chosen == null) return;
    final path = chosen.toLowerCase().endsWith('.json')
        ? chosen
        : '$chosen.json';
    String message;
    try {
      final json = await result.toJsonString(
        includeImages: true,
        includeUniformBytes: true,
      );
      await File(path).writeAsString(json);
      message = 'Capture saved to $path';
    } catch (error) {
      message = 'Could not save the capture. $error';
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _statsStrip() {
    final stats = widget.controller.scene.renderStats.latest;
    if (stats == null) return const SizedBox.shrink();
    final view = stats.views.isEmpty ? null : _primaryView(stats);
    final counters = view?.counters ?? stats.counters;
    return Container(
      color: editorPanelColor,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 2,
            children: [
              _stat('frame', _ms(stats.cpuMicros)),
              _stat('draws', _count(counters.draws)),
              _stat('instances', _count(counters.instances)),
              _stat('vertices', _count(counters.vertices)),
              _stat('culled', _count(counters.culled)),
              _stat(
                'batches',
                '${_count(counters.batches)} '
                    '(${_count(counters.batchedItems)} items)',
              ),
              _stat('binds', _count(counters.pipelineBinds)),
              _stat('builds', _count(counters.pipelineBuilds)),
            ],
          ),
          if (view != null && view.passes.isNotEmpty)
            SizedBox(
              height: 15,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final pass in view.passes)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Text(
                        '${pass.name} ${_ms(pass.cpuMicros)}',
                        style: editorDetailText,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static Widget _stat(String label, String value) => Text.rich(
    TextSpan(
      children: [
        TextSpan(text: '$label ', style: editorDetailText),
        TextSpan(text: value, style: const TextStyle(fontSize: 11)),
      ],
    ),
  );

  // The onscreen view the viewport draws, else whatever rendered.
  static RenderViewStats _primaryView(RenderFrameStats stats) {
    for (final view in stats.views) {
      if (!view.offscreen) return view;
    }
    return stats.views.first;
  }

  static String _ms(int micros) => '${(micros / 1000).toStringAsFixed(2)} ms';

  static String _count(int value) {
    if (value < 10000) return '$value';
    if (value < 10000000) return '${(value / 1000).toStringAsFixed(1)}k';
    return '${(value / 1000000).toStringAsFixed(1)}M';
  }

  static String _uniformValueText(ShaderUniformValue value) {
    const shown = 16;
    final head = value.values
        .take(shown)
        .map(
          (scalar) => scalar is double ? scalar.toStringAsFixed(3) : '$scalar',
        )
        .join(', ');
    final rest = value.values.length - shown;
    return rest > 0 ? '$head, +$rest more' : head;
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
          DropdownButton<RemapMode>(
            value: _settings.mode,
            isDense: true,
            style: const TextStyle(fontSize: 12),
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
            DropdownButton<int>(
              value: _settings.channel,
              isDense: true,
              style: const TextStyle(fontSize: 12),
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
