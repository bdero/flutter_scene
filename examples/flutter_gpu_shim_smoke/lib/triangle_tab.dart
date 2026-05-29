import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vm;

const String _vertSource = '''
#version 100
attribute vec2 position;

void main() {
  gl_Position = vec4(position, 0.0, 1.0);
}
''';

const String _fragSource = '''
#version 100
precision mediump float;

void main() {
  vec2 uv = gl_FragCoord.xy / 256.0;
  gl_FragColor = vec4(uv.x, uv.y, 0.5, 1.0);
}
''';

class TriangleTab extends StatefulWidget {
  const TriangleTab({super.key});

  @override
  State<TriangleTab> createState() => _TriangleTabState();
}

class _TriangleTabState extends State<TriangleTab> {
  static const int _size = 256;

  ui.Image? _image;
  String? _error;
  bool _rendering = false;

  @override
  void initState() {
    super.initState();
    _render();
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _render() async {
    if (_rendering) return;
    setState(() {
      _rendering = true;
      _error = null;
    });
    try {
      final library = gpu.compileShaderLibraryInline({
        'TriangleVert': (source: _vertSource, stage: gpu.ShaderStage.vertex),
        'TriangleFrag': (source: _fragSource, stage: gpu.ShaderStage.fragment),
      });
      final pipeline = gpu.gpuContext.createRenderPipeline(
        library['TriangleVert']!,
        library['TriangleFrag']!,
      );

      // An indexed quad: 4 corner vertices, 6 indices (two triangles that
      // share the 0->2 diagonal). Exercises drawElements + index reuse.
      final verts = Float32List.fromList([
        // x,    y
        -0.8, -0.8, // 0 bottom left
        0.8, -0.8, // 1 bottom right
        0.8, 0.8, // 2 top right
        -0.8, 0.8, // 3 top left
      ]);
      final vb = gpu.gpuContext.createDeviceBuffer(
        gpu.StorageMode.hostVisible,
        verts.lengthInBytes,
      );
      vb.overwrite(verts.buffer.asByteData());

      final indices = Uint16List.fromList([0, 1, 2, 0, 2, 3]);
      final ib = gpu.gpuContext.createDeviceBuffer(
        gpu.StorageMode.hostVisible,
        indices.lengthInBytes,
      );
      ib.overwrite(indices.buffer.asByteData());

      final colorTex = gpu.gpuContext.createTexture(
        gpu.StorageMode.devicePrivate,
        _size,
        _size,
      );

      final cmd = gpu.gpuContext.createCommandBuffer();
      final pass = cmd.createRenderPass(
        gpu.RenderTarget.singleColor(
          gpu.ColorAttachment(
            texture: colorTex,
            loadAction: gpu.LoadAction.clear,
            clearValue: vm.Vector4(0.06, 0.07, 0.10, 1.0),
          ),
        ),
      );
      pass.bindPipeline(pipeline);
      pass.bindVertexBuffer(
        gpu.BufferView(
          vb,
          offsetInBytes: 0,
          lengthInBytes: verts.lengthInBytes,
        ),
      );
      pass.bindIndexBuffer(
        gpu.BufferView(
          ib,
          offsetInBytes: 0,
          lengthInBytes: indices.lengthInBytes,
        ),
        gpu.IndexType.int16,
      );
      pass.setViewport(gpu.Viewport(x: 0, y: 0, width: _size, height: _size));
      pass.drawIndexed(6);
      pass.clearBindings();
      cmd.submit();

      final image = await gpu.presentTextureAsImage(colorTex);

      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() {
        _image?.dispose();
        _image = image;
        _rendering = false;
      });
    } catch (e, st) {
      if (mounted) {
        setState(() {
          _error = '$e\n$st';
          _rendering = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Center(
              child: SizedBox(
                width: _size.toDouble(),
                height: _size.toDouble(),
                child: image != null
                    ? RawImage(image: image, fit: BoxFit.fill)
                    : _error != null
                    ? SingleChildScrollView(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      )
                    : const Center(child: CircularProgressIndicator()),
              ),
            ),
          ),
        ),
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Indexed quad via shim GpuContext + RenderPass',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      Text(
                        '256 x 256, drawElements (4 verts / 6 indices), '
                        'inline GLSL ES 1.00 -> 300 es',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.black.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton(
                  onPressed: _rendering ? null : _render,
                  child: const Text('Re-render'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
