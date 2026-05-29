import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vm;

const String _bundleAsset = 'assets/base.shaderbundle';

/// Renders an indexed quad through flutter_scene's real `UnskinnedVertex` +
/// `UnlitFragment` shaders loaded from the bundle: full 48-byte vertex
/// layout (position / normal / texcoords / color), a FrameInfo uniform
/// (two mat4 + a vec3), a FragInfo uniform (vec4 + float), and a sampled
/// texture. The keystone test for the bundle-loader + reflection path.
class MeshTab extends StatefulWidget {
  const MeshTab({super.key});

  @override
  State<MeshTab> createState() => _MeshTabState();
}

class _MeshTabState extends State<MeshTab> {
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
      final library = await gpu.loadShaderLibraryAsync(_bundleAsset);
      if (library == null) {
        throw Exception('Failed to load shader bundle');
      }
      final vert = library['UnskinnedVertex'];
      final frag = library['UnlitFragment'];
      if (vert == null || frag == null) {
        throw Exception('Bundle is missing UnskinnedVertex/UnlitFragment');
      }
      final pipeline = gpu.gpuContext.createRenderPipeline(vert, frag);

      // 48-byte vertex layout: position(3) normal(3) texcoords(2) color(4).
      final verts = Float32List.fromList([
        // pos              normal      uv      color (rgba)
        -0.8, -0.8, 0.0, 0, 0, 1, 0, 0, 1, 0, 0, 1, // 0 red
        0.8, -0.8, 0.0, 0, 0, 1, 1, 0, 0, 1, 0, 1, // 1 green
        0.8, 0.8, 0.0, 0, 0, 1, 1, 1, 0, 0, 1, 1, // 2 blue
        -0.8, 0.8, 0.0, 0, 0, 1, 0, 1, 1, 1, 0, 1, // 3 yellow
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

      // FrameInfo (192 bytes): model_transform@0, camera_transform@64,
      // camera_position@128. Identity transforms => NDC passthrough.
      final frameInfo = Float32List(48);
      _identity(frameInfo, 0);
      _identity(frameInfo, 16);
      // FragInfo (32 bytes): color@0 = white, vertex_color_weight@16 = 1.
      final fragInfo = Float32List(8);
      fragInfo[0] = 1;
      fragInfo[1] = 1;
      fragInfo[2] = 1;
      fragInfo[3] = 1;
      fragInfo[4] = 1.0;

      final transients = gpu.gpuContext.createHostBuffer();
      final frameView = transients.emplace(ByteData.sublistView(frameInfo));
      final fragView = transients.emplace(ByteData.sublistView(fragInfo));

      // 1x1 white texture so the unlit shader shows the vertex colors.
      final whiteTex = gpu.gpuContext.createTexture(
        gpu.StorageMode.hostVisible,
        1,
        1,
      );
      whiteTex.overwrite(
        ByteData.sublistView(Uint8List.fromList([255, 255, 255, 255])),
      );

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
      pass.bindUniform(vert.getUniformSlot('FrameInfo'), frameView);
      pass.bindUniform(frag.getUniformSlot('FragInfo'), fragView);
      pass.bindTexture(frag.getUniformSlot('base_color_texture'), whiteTex);
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

  static void _identity(Float32List out, int offset) {
    for (var i = 0; i < 16; i++) {
      out[offset + i] = (i % 5 == 0) ? 1.0 : 0.0;
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
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "flutter_scene's UnskinnedVertex + UnlitFragment",
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      Text(
                        '48-byte verts, FrameInfo + FragInfo uniforms, '
                        'sampled texture, all from the bundle',
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
