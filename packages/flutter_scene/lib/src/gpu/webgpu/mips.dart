part of 'webgpu_backend.dart';

/// Builds a texture's mip chain on the GPU with the engine's 2x2 box filter
/// (linear light for color, raw for data, renormalized for normals), the same
/// filter WebGL2's generator runs, so chains match across backends.
///
/// Each level renders from a view of the level above. They are different
/// subresources of one texture, which WebGPU allows in one pass, so unlike
/// WebGL2 no scratch texture is needed.
final class _MipGenerator {
  _MipGenerator(this._device);

  final WebGpuDevice _device;
  final Map<(String, int), GPURenderPipeline> _pipelines = {};

  static const String _source = r'''
override MODE: u32 = 0u;

@group(0) @binding(0) var source: texture_2d<f32>;

@vertex
fn vs(@builtin(vertex_index) i: u32) -> @builtin(position) vec4f {
  let p = vec2f(f32((i << 1u) & 2u), f32(i & 2u));
  return vec4f(p * 2.0 - 1.0, 0.0, 1.0);
}

fn srgbToLinear(c: vec3f) -> vec3f {
  return select(pow((c + 0.055) / 1.055, vec3f(2.4)), c / 12.92,
                c < vec3f(0.04045));
}

fn linearToSrgb(c: vec3f) -> vec3f {
  return select(1.055 * pow(c, vec3f(1.0 / 2.4)) - 0.055, c * 12.92,
                c < vec3f(0.0031308));
}

@fragment
fn fs(@builtin(position) position: vec4f) -> @location(0) vec4f {
  let limit = vec2i(textureDimensions(source)) - 1;
  let origin = vec2i(position.xy) * 2;
  let a = textureLoad(source, min(origin, limit), 0);
  let b = textureLoad(source, min(origin + vec2i(1, 0), limit), 0);
  let c = textureLoad(source, min(origin + vec2i(0, 1), limit), 0);
  let d = textureLoad(source, min(origin + vec2i(1, 1), limit), 0);
  var alpha = (a.a + b.a + c.a + d.a) * 0.25;
  var rgb: vec3f;
  if (MODE == 0u) {
    rgb = linearToSrgb((srgbToLinear(a.rgb) + srgbToLinear(b.rgb) +
                        srgbToLinear(c.rgb) + srgbToLinear(d.rgb)) * 0.25);
  } else if (MODE == 2u) {
    var n = (a.rgb + b.rgb + c.rgb + d.rgb) * 2.0 - 4.0;
    let len = length(n);
    n = select(vec3f(0.0, 0.0, 1.0), n / len, len > 1e-6);
    rgb = n * 0.5 + 0.5;
    alpha = 1.0;
  } else {
    rgb = (a.rgb + b.rgb + c.rgb + d.rgb) * 0.25;
  }
  return vec4f(rgb, alpha);
}
''';

  late final GPUShaderModule _module = _device.device.createShaderModule(
    _obj({'code': _source, 'label': 'flutter_scene mip generator'}),
  );

  static int _mode(MipContent content) => switch (content) {
    MipContent.color => 0,
    MipContent.data => 1,
    MipContent.normal => 2,
  };

  GPURenderPipeline _pipeline(String format, int mode) =>
      _pipelines[(format, mode)] ??= _device.device.createRenderPipeline(
        _obj({
          'layout': 'auto',
          'vertex': {'module': _module, 'entryPoint': 'vs'},
          'fragment': {
            'module': _module,
            'entryPoint': 'fs',
            'targets': [
              {'format': format},
            ],
            'constants': {'MODE': mode},
          },
          'primitive': {'topology': 'triangle-list'},
        }),
      );

  /// Fills levels 1 and up of [texture] from its level 0.
  void generate(_WebGpuTexture texture, MipContent content) {
    if (texture.mipLevelCount <= 1) return;
    if (texture.textureType != TextureType.texture2D) {
      throw UnsupportedError(
        'Mip generation is only supported for 2D textures',
      );
    }
    final pipeline = _pipeline(texture._format.name, _mode(content));
    final layout = pipeline.getBindGroupLayout(0);
    final encoder = _device.device.createCommandEncoder();
    for (var level = 1; level < texture.mipLevelCount; level++) {
      final bindGroup = _device.device.createBindGroup(
        _obj({
          'layout': layout,
          'entries': [
            {'binding': 0, 'resource': texture.levelView(level - 1)},
          ],
        }),
      );
      final pass = encoder.beginRenderPass(
        _obj({
          'colorAttachments': [
            {
              'view': texture.levelView(level),
              'loadOp': 'clear',
              'storeOp': 'store',
              'clearValue': [0, 0, 0, 0],
            },
          ],
        }),
      );
      pass
        ..setPipeline(pipeline)
        ..setBindGroup(0, bindGroup)
        ..draw(3)
        ..end();
    }
    _device.device.queue.submit([encoder.finish()].toJS);
  }
}
