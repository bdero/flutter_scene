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
precision highp float;

void main() {
  // Bright-ish in-range color stored in the RGBA16F target.
  gl_FragColor = vec4(0.95, 0.55, 0.15, 1.0);
}
''';

/// Renders a triangle (diagonal edges) into an `r16g16b16a16Float` target,
/// optionally 4x MSAA with a resolve pass, then presents it. Exercises
/// HDR float render targets + `renderbufferStorageMultisample` +
/// `blitFramebuffer` resolve (StoreAction.multisampleResolve).
class HdrTab extends StatefulWidget {
  const HdrTab({super.key});

  @override
  State<HdrTab> createState() => _HdrTabState();
}

class _HdrTabState extends State<HdrTab> {
  static const int _size = 256;

  ui.Image? _image;
  String? _error;
  bool _rendering = false;
  bool _msaa = true;

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
        'V': (source: _vertSource, stage: gpu.ShaderStage.vertex),
        'F': (source: _fragSource, stage: gpu.ShaderStage.fragment),
      });
      final pipeline = gpu.gpuContext.createRenderPipeline(
        library['V']!,
        library['F']!,
      );

      final verts = Float32List.fromList([-0.85, -0.7, 0.85, -0.7, 0.0, 0.8]);
      final vb = gpu.gpuContext.createDeviceBuffer(
        gpu.StorageMode.hostVisible,
        verts.lengthInBytes,
      );
      vb.overwrite(verts.buffer.asByteData());

      // The texture we ultimately present: single-sample RGBA16F.
      final resolveTex = gpu.gpuContext.createTexture(
        gpu.StorageMode.devicePrivate,
        _size,
        _size,
        format: gpu.PixelFormat.r16g16b16a16Float,
      );

      final gpu.ColorAttachment colorAttachment;
      if (_msaa) {
        final msaaTex = gpu.gpuContext.createTexture(
          gpu.StorageMode.deviceTransient,
          _size,
          _size,
          format: gpu.PixelFormat.r16g16b16a16Float,
          sampleCount: 4,
        );
        colorAttachment = gpu.ColorAttachment(
          texture: msaaTex,
          resolveTexture: resolveTex,
          loadAction: gpu.LoadAction.clear,
          storeAction: gpu.StoreAction.multisampleResolve,
          clearValue: vm.Vector4(0.06, 0.07, 0.10, 1.0),
        );
      } else {
        colorAttachment = gpu.ColorAttachment(
          texture: resolveTex,
          loadAction: gpu.LoadAction.clear,
          storeAction: gpu.StoreAction.store,
          clearValue: vm.Vector4(0.06, 0.07, 0.10, 1.0),
        );
      }

      final cmd = gpu.gpuContext.createCommandBuffer();
      final pass = cmd.createRenderPass(
        gpu.RenderTarget.singleColor(colorAttachment),
      );
      pass.bindPipeline(pipeline);
      pass.bindVertexBuffer(
        gpu.BufferView(
          vb,
          offsetInBytes: 0,
          lengthInBytes: verts.lengthInBytes,
        ),
      );
      pass.setViewport(gpu.Viewport(x: 0, y: 0, width: _size, height: _size));
      pass.draw(3);
      pass.clearBindings();
      cmd.submit();

      final image = await gpu.presentTextureAsImage(resolveTex);
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
                child:
                    image != null
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'RGBA16F render target + MSAA resolve',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                Row(
                  children: [
                    Expanded(
                      child: SwitchListTile(
                        title: const Text('4x MSAA + resolve'),
                        subtitle: const Text('off: single-sample float target'),
                        value: _msaa,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        onChanged:
                            _rendering
                                ? null
                                : (v) {
                                  setState(() => _msaa = v);
                                  _render();
                                },
                      ),
                    ),
                    OutlinedButton(
                      onPressed: _rendering ? null : _render,
                      child: const Text('Re-render'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
