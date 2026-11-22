// Verifies WebGL2 present FBO caching, cached-VAO instanced attribute reuse,
// and non-redundant UBO binding calls.
//
//   flutter test --platform chrome \
//     test/gpu/webgl/webgl_present_and_vao_browser_test.dart
//   flutter test --platform chrome --wasm \
//     test/gpu/webgl/webgl_present_and_vao_browser_test.dart
//
// ignore_for_file: implementation_imports
@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/web/_gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/web/shader_bundle_generated.dart' as fb;
import 'package:flutter_scene/src/gpu/web/webgl/_webgl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

@JS('Reflect.apply')
external JSAny? _reflectApply(
  JSFunction target,
  JSAny? thisArg,
  JSArray<JSAny?> argumentsList,
);

class _GlCallSpy {
  _GlCallSpy(this._gl);

  final JSObject _gl;
  final Map<String, int> counts = {};
  final List<String> _wrapped = [];

  void spy(
    String name, {
    required int arity,
    bool Function(List<JSAny?> args)? filter,
  }) {
    counts[name] = 0;
    final original = _gl[name]! as JSFunction;
    _gl[name] =
        (([JSAny? a, JSAny? b, JSAny? c, JSAny? d, JSAny? e, JSAny? f]) {
          final all = <JSAny?>[a, b, c, d, e, f].sublist(0, arity);
          if (filter == null || filter(all)) {
            counts[name] = (counts[name] ?? 0) + 1;
          }
          return _reflectApply(original, _gl, all.toJS);
        }).toJS;
    _wrapped.add(name);
  }

  void resetCounts() {
    for (final key in counts.keys.toList()) {
      counts[key] = 0;
    }
  }

  void restore() {
    for (final name in _wrapped) {
      _gl.delete(name.toJS);
    }
    _wrapped.clear();
  }
}

class _InputBuilder extends fb.ShaderInputObjectBuilder {
  _InputBuilder(this.name, this.location) : super(name: name);

  final String name;
  final int location;

  @override
  int finish(fbBuilder) {
    final nameOffset = fbBuilder.writeString(name);
    fbBuilder.startTable(9);
    fbBuilder.addOffset(0, nameOffset);
    fbBuilder.addUint32(1, location);
    return fbBuilder.endTable();
  }
}

Uint8List _instancedBundle() {
  fb.ShaderObjectBuilder shader(
    String name,
    fb.ShaderStage stage,
    String source, {
    List<fb.ShaderInputObjectBuilder> inputs = const [],
    List<fb.ShaderUniformStructObjectBuilder> uniformStructs = const [],
  }) => fb.ShaderObjectBuilder(
    name: name,
    openglEs: fb.BackendShaderObjectBuilder(
      stage: stage,
      entrypoint: 'main',
      inputs: inputs,
      uniformStructs: uniformStructs,
      uniformTextures: const [],
      shader: utf8.encode(source),
    ),
  );

  return fb.ShaderBundleObjectBuilder(
    formatVersion: 2,
    shaders: [
      shader(
        'InstancedVert',
        fb.ShaderStage.kVertex,
        '#version 300 es\n'
            'layout(location = 0) in vec2 position;\n'
            'layout(location = 1) in vec4 instance_color;\n'
            'layout(location = 2) in uint instance_mask;\n'
            'layout(std140) uniform FrameBlock { vec4 tint; } frame_info;\n'
            'out vec4 v_color;\n'
            'void main() {\n'
            '  gl_Position = vec4(position, 0.5, 1.0);\n'
            '  vec3 rgb = instance_mask == 2u ? vec3(1.0, 1.0, 0.0) : instance_color.rgb;\n'
            '  v_color = vec4(rgb, instance_color.a) * frame_info.tint;\n'
            '}\n',
        inputs: [
          _InputBuilder('position', 0),
          _InputBuilder('instance_color', 1),
          _InputBuilder('instance_mask', 2),
        ],
        uniformStructs: [
          fb.ShaderUniformStructObjectBuilder(
            name: 'FrameBlock',
            fields: const [],
          ),
        ],
      ),
      shader(
        'InstancedFrag',
        fb.ShaderStage.kFragment,
        '#version 300 es\n'
            'precision mediump float;\n'
            'in vec4 v_color;\n'
            'out vec4 frag_color;\n'
            'void main() { frag_color = v_color; }\n',
      ),
      shader(
        'FloatInstVert',
        fb.ShaderStage.kVertex,
        '#version 300 es\n'
            'layout(location = 0) in vec2 position;\n'
            'layout(location = 1) in vec4 instance_color;\n'
            'out vec4 v_color;\n'
            'void main() {\n'
            '  gl_Position = vec4(position, 0.5, 1.0);\n'
            '  v_color = instance_color;\n'
            '}\n',
        inputs: [
          _InputBuilder('position', 0),
          _InputBuilder('instance_color', 1),
        ],
      ),
    ],
  ).toBytes();
}

ByteData _packInstanceRecord(double r, double g, double b, double a, int mask) {
  final bytes = ByteData(20)
    ..setFloat32(0, r, Endian.host)
    ..setFloat32(4, g, Endian.host)
    ..setFloat32(8, b, Endian.host)
    ..setFloat32(12, a, Endian.host)
    ..setUint32(16, mask, Endian.host);
  return bytes;
}

void main() {
  if (gpu.useWebGpuBackend) {
    test('needs the WebGL2 shim', () {
      markTestSkipped('The shim is WebGPU in this build.');
    });
    return;
  }

  setUpAll(gpu.initializeGpuBackend);

  test(
    'snapshotTextureBitmap reuses cached framebuffer without per-frame FBO churn '
    'or depth-attachment key collisions',
    () {
      final ctx = gpu.gpuContext as WebGlContext;
      final gl = ctx.gl;
      final spy = _GlCallSpy(gl as JSObject)
        ..spy('createFramebuffer', arity: 0)
        ..spy('checkFramebufferStatus', arity: 1)
        ..spy('deleteFramebuffer', arity: 1);
      addTearDown(spy.restore);

      final texture = gpu.gpuContext.createTexture(
        gpu.StorageMode.devicePrivate,
        4,
        4,
      );
      // Render once into texture so _framebufferCache already holds its FBO,
      // matching post-process presentation in steady state.
      final commands = gpu.gpuContext.createCommandBuffer();
      commands.createRenderPass(
        gpu.RenderTarget.singleColor(
          gpu.ColorAttachment(
            texture: texture,
            loadAction: gpu.LoadAction.clear,
          ),
        ),
      );
      commands.submit();
      expect(spy.counts['createFramebuffer'], 1);
      expect(spy.counts['checkFramebufferStatus'], 1);
      expect(spy.counts['deleteFramebuffer'], 0);

      spy.resetCounts();
      for (var i = 0; i < 10; i++) {
        final bitmap = ctx.snapshotTextureBitmap(texture);
        expect(bitmap.width, 4);
        expect(bitmap.height, 4);
        bitmap.close();
      }
      expect(
        spy.counts['createFramebuffer'],
        0,
        reason: 'Present blit should reuse the render target cached FBO',
      );
      expect(
        spy.counts['checkFramebufferStatus'],
        0,
        reason: 'Cached present FBO skips synchronous status round-trips',
      );
      expect(
        spy.counts['deleteFramebuffer'],
        0,
        reason: 'Present blit must not delete the FBO every frame',
      );
      expect(gl.getError(), web.WebGL2RenderingContext.NO_ERROR);

      gpu.gpuHost.releaseTexture(texture);
      expect(
        spy.counts['deleteFramebuffer'],
        1,
        reason: 'Releasing the texture evicts its cached FBO cleanly',
      );

      // Verify color+depth render-pass FBO `(color, 0, 0, depth)` coexists
      // cleanly alongside color-only present FBO `(color, 0, 0, null)`.
      spy.resetCounts();
      final colorWithDepth = gpu.gpuContext.createTexture(
        gpu.StorageMode.devicePrivate,
        4,
        4,
      );
      final depth = gpu.gpuContext.createTexture(
        gpu.StorageMode.devicePrivate,
        4,
        4,
        format: gpu.PixelFormat.d24UnormS8Uint,
      );
      void renderAndPresent() {
        final cb = gpu.gpuContext.createCommandBuffer();
        cb.createRenderPass(
          gpu.RenderTarget.singleColor(
            gpu.ColorAttachment(texture: colorWithDepth),
            depthStencilAttachment: gpu.DepthStencilAttachment(texture: depth),
          ),
        );
        cb.submit();
        ctx.snapshotTextureBitmap(colorWithDepth).close();
      }

      renderAndPresent();
      expect(spy.counts['createFramebuffer'], 2);

      spy.resetCounts();
      for (var i = 0; i < 3; i++) {
        renderAndPresent();
      }
      expect(spy.counts['createFramebuffer'], 0);
      expect(spy.counts['deleteFramebuffer'], 0);

      gpu.gpuHost.releaseTexture(colorWithDepth);
      expect(
        spy.counts['deleteFramebuffer'],
        2,
        reason: 'Both color+depth and color-only FBOs are deleted on release',
      );
      gpu.gpuHost.releaseTexture(depth);
    },
  );

  test(
    'cached VAO skips redundant enable/divisor and retained instance re-points '
    'across float, integer, and recycled BumpHostBuffer streams, and '
    'bindUniform skips redundant UNIFORM_BUFFER bindBuffer',
    () async {
      final ctx = gpu.gpuContext as WebGlContext;
      final gl = ctx.gl;
      final library = (await gpu.loadShaderLibraryFromBytesAsync(
        ByteData.sublistView(_instancedBundle()),
      ))!;
      final vert = library['InstancedVert']!;
      final frag = library['InstancedFrag']!;
      final pipeline = gpu.gpuContext.createRenderPipeline(
        vert,
        frag,
        vertexLayout: const gpu.VertexLayout(
          buffers: [
            gpu.VertexBuffer(
              strideInBytes: 8,
              attributes: [
                gpu.VertexAttribute(
                  name: 'position',
                  format: gpu.VertexFormat.float32x2,
                ),
              ],
            ),
            gpu.VertexBuffer(
              strideInBytes: 20,
              stepMode: gpu.VertexStepMode.instance,
              attributes: [
                gpu.VertexAttribute(
                  name: 'instance_color',
                  format: gpu.VertexFormat.float32x4,
                ),
                gpu.VertexAttribute(
                  name: 'instance_mask',
                  format: gpu.VertexFormat.uint32,
                  offsetInBytes: 16,
                ),
              ],
            ),
          ],
        ),
      );

      final quad = Float32List.fromList([
        -1,
        -1,
        1,
        -1,
        1,
        1,
        -1,
        -1,
        1,
        1,
        -1,
        1,
      ]);
      final geomBuffer = gpu.gpuContext.createDeviceBufferWithCopy(
        ByteData.sublistView(quad),
      );
      final geomView = gpu.BufferView(
        geomBuffer,
        offsetInBytes: 0,
        lengthInBytes: quad.lengthInBytes,
      );

      final instA = gpu.gpuContext.createDeviceBufferWithCopy(
        _packInstanceRecord(1, 0, 0, 1, 1),
      );
      final instB = gpu.gpuContext.createDeviceBufferWithCopy(
        _packInstanceRecord(0, 1, 0, 1, 1),
      );
      final instViewA = gpu.BufferView(
        instA,
        offsetInBytes: 0,
        lengthInBytes: 20,
      );
      final instViewB = gpu.BufferView(
        instB,
        offsetInBytes: 0,
        lengthInBytes: 20,
      );

      final hostBuffer = gpu.gpuContext.createHostBuffer(
        blockLengthInBytes: 1024,
      );

      final ubo = gpu.gpuContext.createDeviceBufferWithCopy(
        ByteData.sublistView(Float32List.fromList([1, 1, 1, 1])),
      );
      final uboView = gpu.BufferView(ubo, offsetInBytes: 0, lengthInBytes: 16);
      final tintSlot = vert.getUniformSlot('FrameBlock');

      final target = gpu.gpuContext.createTexture(
        gpu.StorageMode.devicePrivate,
        4,
        4,
      );
      addTearDown(() {
        gpu.gpuHost.releaseBuffer(geomBuffer);
        gpu.gpuHost.releaseBuffer(instA);
        gpu.gpuHost.releaseBuffer(instB);
        gpu.gpuHost.releaseBuffer(ubo);
        gpu.gpuHost.releaseTexture(target);
      });

      final spy = _GlCallSpy(gl as JSObject)
        ..spy('enableVertexAttribArray', arity: 1)
        ..spy('vertexAttribDivisor', arity: 2)
        ..spy('vertexAttribPointer', arity: 6)
        ..spy('vertexAttribIPointer', arity: 5)
        ..spy(
          'bindBuffer',
          arity: 2,
          filter: (args) =>
              (args[0] as JSNumber).toDartInt ==
              web.WebGL2RenderingContext.UNIFORM_BUFFER,
        )
        ..spy('bindBufferRange', arity: 5);
      addTearDown(spy.restore);

      List<int> readPixel() {
        final pixel = JSUint8Array.withLength(4);
        gl.readPixels(
          1,
          1,
          1,
          1,
          web.WebGL2RenderingContext.RGBA,
          web.WebGL2RenderingContext.UNSIGNED_BYTE,
          pixel,
        );
        return pixel.toDart;
      }

      final commands = gpu.gpuContext.createCommandBuffer();
      final pass = commands.createRenderPass(
        gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: target)),
      );

      // Draw 1 (VAO cache miss + initial UBO upload): configures all 3 inputs.
      pass
        ..bindPipeline(pipeline)
        ..bindVertexBuffer(geomView, slot: 0)
        ..bindVertexBuffer(instViewA, slot: 1)
        ..bindUniform(tintSlot, uboView)
        ..draw(6, instanceCount: 1);
      expect(spy.counts['enableVertexAttribArray'], 3);
      expect(spy.counts['vertexAttribDivisor'], 3);
      expect(spy.counts['vertexAttribPointer'], 2);
      expect(spy.counts['vertexAttribIPointer'], 1);
      expect(spy.counts['bindBuffer'], greaterThanOrEqualTo(1));
      expect(spy.counts['bindBufferRange'], greaterThanOrEqualTo(1));
      expect(readPixel(), [255, 0, 0, 255]);

      // Draws 2..6 with the SAME retained instance BufferView: zero attribute
      // calls and zero UNIFORM_BUFFER bindBuffer calls.
      spy.resetCounts();
      for (var i = 0; i < 5; i++) {
        pass
          ..bindVertexBuffer(geomView, slot: 0)
          ..bindVertexBuffer(instViewA, slot: 1)
          ..bindUniform(tintSlot, uboView)
          ..draw(6, instanceCount: 1);
      }
      expect(spy.counts['enableVertexAttribArray'], 0);
      expect(spy.counts['vertexAttribDivisor'], 0);
      expect(spy.counts['vertexAttribPointer'], 0);
      expect(spy.counts['vertexAttribIPointer'], 0);
      expect(spy.counts['bindBuffer'], 0);
      expect(spy.counts['bindBufferRange'], 5);

      // Draw 7 switching to a different pooled instance buffer (instViewB):
      // re-points ONLY slot 1's float + integer attributes without enable/divisor.
      spy.resetCounts();
      pass
        ..bindVertexBuffer(geomView, slot: 0)
        ..bindVertexBuffer(instViewB, slot: 1)
        ..bindUniform(tintSlot, uboView)
        ..draw(6, instanceCount: 1);
      expect(spy.counts['enableVertexAttribArray'], 0);
      expect(spy.counts['vertexAttribDivisor'], 0);
      expect(spy.counts['vertexAttribPointer'], 1);
      expect(spy.counts['vertexAttribIPointer'], 1);
      expect(spy.counts['bindBuffer'], 0);
      expect(spy.counts['bindBufferRange'], 1);
      expect(readPixel(), [0, 255, 0, 255]);

      // Draw 8..9 with BumpHostBuffer recycled across reset() back to the same
      // `(buffer, offset: 0)`: new bytes overwritten via bufferSubData are
      // observed by the VAO with zero attribute re-points.
      final hostView1 = hostBuffer.emplace(_packInstanceRecord(0, 0, 1, 1, 1));
      pass
        ..bindVertexBuffer(geomView, slot: 0)
        ..bindVertexBuffer(hostView1, slot: 1)
        ..bindUniform(tintSlot, uboView)
        ..draw(6, instanceCount: 1);
      expect(readPixel(), [0, 0, 255, 255]);

      for (var i = 0; i < hostBuffer.frameCount; i++) {
        hostBuffer.reset();
      }
      final hostViewRecycled = hostBuffer.emplace(
        _packInstanceRecord(0, 1, 1, 1, 2),
      );
      expect(identical(hostViewRecycled.buffer, hostView1.buffer), isTrue);
      expect(hostViewRecycled.offsetInBytes, hostView1.offsetInBytes);

      spy.resetCounts();
      pass
        ..bindVertexBuffer(geomView, slot: 0)
        ..bindVertexBuffer(hostViewRecycled, slot: 1)
        ..bindUniform(tintSlot, uboView)
        ..draw(6, instanceCount: 1);
      expect(spy.counts['enableVertexAttribArray'], 0);
      expect(spy.counts['vertexAttribDivisor'], 0);
      expect(spy.counts['vertexAttribPointer'], 0);
      expect(spy.counts['vertexAttribIPointer'], 0);
      expect(readPixel(), [255, 255, 0, 255]);

      // Clearing bindings and binding only slot 0 on an instanced pipeline must
      // not collide with the instanced VAO key (`|i:1`). Uses a float-only
      // vertex shader because WebGL2 disallows disabled `in uint` attributes.
      final floatPipeline = gpu.gpuContext.createRenderPipeline(
        library['FloatInstVert']!,
        frag,
        vertexLayout: const gpu.VertexLayout(
          buffers: [
            gpu.VertexBuffer(
              strideInBytes: 8,
              attributes: [
                gpu.VertexAttribute(
                  name: 'position',
                  format: gpu.VertexFormat.float32x2,
                ),
              ],
            ),
            gpu.VertexBuffer(
              strideInBytes: 20,
              stepMode: gpu.VertexStepMode.instance,
              attributes: [
                gpu.VertexAttribute(
                  name: 'instance_color',
                  format: gpu.VertexFormat.float32x4,
                ),
              ],
            ),
          ],
        ),
      );
      pass
        ..clearBindings()
        ..bindPipeline(floatPipeline)
        ..bindVertexBuffer(geomView, slot: 0)
        ..bindVertexBuffer(instViewB, slot: 1)
        ..draw(6, instanceCount: 1);
      expect(readPixel(), [0, 255, 0, 255]);

      spy.resetCounts();
      pass
        ..clearBindings()
        ..bindVertexBuffer(geomView, slot: 0)
        ..draw(6);
      expect(spy.counts['enableVertexAttribArray'], 1);
      expect(spy.counts['vertexAttribDivisor'], 1);
      expect(spy.counts['vertexAttribPointer'], 1);
      expect(spy.counts['vertexAttribIPointer'], 0);
      expect(readPixel(), [0, 0, 0, 255]);

      expect(gl.getError(), web.WebGL2RenderingContext.NO_ERROR);
      commands.submit();
    },
  );
}
