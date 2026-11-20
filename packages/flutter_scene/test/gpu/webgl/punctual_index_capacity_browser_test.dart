// ignore_for_file: implementation_imports
@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/web/_gpu.dart' show useWebGpuBackend;
import 'package:flutter_scene/src/gpu/web/webgl/_webgl.dart';
import 'package:flutter_scene/src/render/bvh.dart';
import 'package:flutter_scene/src/render/punctual_lights.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:web/web.dart' as web;

class _StubGeometry extends Geometry {
  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Matrix4 modelTransform,
    Matrix4 cameraTransform,
    Vector3 cameraPosition, {
    gpu.Shader? shaderOverride,
    double depthBias = 0.0,
  }) => throw UnsupportedError('stub');
}

class _StubMaterial extends Material {
  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Lighting lighting,
  ) => throw UnsupportedError('stub');
}

class _Fixture {
  _Fixture() {
    final geometry = _StubGeometry();
    final material = _StubMaterial();
    for (var i = 0; i < 2051; i++) {
      final x = i * 4.0;
      items.add(
        RenderItem(geometry: geometry, material: material)
          ..worldBounds = Aabb3.minMax(
            Vector3(x - .25, -.25, -.25),
            Vector3(x + .25, .25, .25),
          ),
      );
      final component = PointLightComponent(PointLight(range: .75));
      Node(
        localTransform: Matrix4.translationValues(x, 0, 0),
      ).addComponent(component);
      points.add(component);
    }
    bvh = Bvh.build(items);
  }

  final buffer = PunctualLightBuffer();
  final items = <RenderItem>[];
  final points = <PointLightComponent>[];
  final textures = Set<gpu.Texture>.identity();
  late final Bvh bvh;

  PunctualLighting build(int count, int rotation, {bool includeItems = true}) {
    final result = buffer.build(
      directionals: const [],
      primaryDirectional: null,
      points: [
        for (var i = 0; i < count; i++) points[(i + rotation) % points.length],
      ],
      spots: const [],
      items: includeItems ? items : const [],
      bvh: includeItems ? bvh : Bvh.build(const []),
      enableFroxels: false,
    );
    if (result.paramsTexture case final texture?) textures.add(texture);
    if (result.indexTexture case final texture?) textures.add(texture);
    expect(buffer.overflowedItemCount, 0);
    return result;
  }

  void expectSlices(Float32List pixels, int count, int rotation) {
    final expected = <List<double>>[];
    final flat = <double>[];
    for (var i = 0; i < items.length; i++) {
      final row = (i - rotation + points.length) % points.length;
      final slice = row < count ? [row.toDouble()] : <double>[];
      expected.add(slice);
      flat.addAll(slice);
    }
    expect([
      for (final item in items)
        [
          for (var j = 0; j < item.lightListCount; j++)
            pixels[(item.lightListOffset + j) * 4],
        ],
    ], expected);
    expect([for (var i = 0; i < count; i++) pixels[i * 4]], flat);
  }

  void dispose() {
    buffer.releaseTextures();
    textures.forEach(gpu.gpuHost.releaseTexture);
  }
}

class _IndexReader {
  _IndexReader(this.gl) : framebuffer = gl.createFramebuffer()!;

  final web.WebGL2RenderingContext gl;
  final web.WebGLFramebuffer framebuffer;
  final recent = <(gpu.Texture, Float32List)>[];

  Float32List read(gpu.Texture texture) {
    final previous =
        gl.getParameter(web.WebGL2RenderingContext.READ_FRAMEBUFFER_BINDING)
            as web.WebGLFramebuffer?;
    try {
      gl.bindFramebuffer(
        web.WebGL2RenderingContext.READ_FRAMEBUFFER,
        framebuffer,
      );
      gl.framebufferTexture2D(
        web.WebGL2RenderingContext.READ_FRAMEBUFFER,
        web.WebGL2RenderingContext.COLOR_ATTACHMENT0,
        web.WebGL2RenderingContext.TEXTURE_2D,
        (texture as WebGlTexture).glTexture,
        0,
      );
      expect(
        gl.checkFramebufferStatus(web.WebGL2RenderingContext.READ_FRAMEBUFFER),
        web.WebGL2RenderingContext.FRAMEBUFFER_COMPLETE,
      );
      final pixels = JSFloat32Array.withLength(
        texture.width * texture.height * 4,
      );
      gl.readPixels(
        0,
        0,
        texture.width,
        texture.height,
        web.WebGL2RenderingContext.RGBA,
        web.WebGL2RenderingContext.FLOAT,
        pixels,
      );
      expect(gl.getError(), web.WebGL2RenderingContext.NO_ERROR);
      return pixels.toDart;
    } finally {
      gl.bindFramebuffer(web.WebGL2RenderingContext.READ_FRAMEBUFFER, previous);
    }
  }

  void expectRetained() {
    for (final (texture, pixels) in recent) {
      expect(read(texture), pixels);
    }
  }

  void verify(
    _Fixture fixture,
    PunctualLighting lighting,
    int count,
    int rotation,
    int width,
    int height,
  ) {
    final texture = lighting.indexTexture!;
    expect(lighting.indexWidth, width);
    expect(lighting.indexHeight, height);
    expect(texture.width, width);
    expect(texture.height, height);
    expect(texture.format, gpu.PixelFormat.r32g32b32a32Float);
    for (final (previous, _) in recent) {
      expect(texture, isNot(same(previous)));
    }
    expectRetained();
    final pixels = read(texture);
    fixture.expectSlices(pixels, count, rotation);
    recent.add((texture, pixels));
    if (recent.length > 2) recent.removeAt(0);
  }

  void dispose() => gl.deleteFramebuffer(framebuffer);
}

void main() {
  if (useWebGpuBackend) {
    test('needs the WebGL2 shim', () {
      markTestSkipped('The shim is WebGPU in this build.');
    });
    return;
  }

  test(
    'punctual index capacity survives count changes and empty frames',
    () async {
      await gpu.initializeGpuBackend();
      final gl = (gpu.gpuContext as WebGlContext).gl;
      expect(gl.getExtension('EXT_color_buffer_float'), isNotNull);
      final fixture = _Fixture();
      final reader = _IndexReader(gl);
      addTearDown(fixture.dispose);
      addTearDown(reader.dispose);

      final smallSlots = <gpu.Texture>[];
      const counts = [513, 700, 1000, 9, 800, 32, 1001, 600, 1, 512, 899, 2];
      for (var frame = 0; frame < counts.length; frame++) {
        final count = counts[frame];
        final rotation = frame * 37;
        final lighting = fixture.build(count, rotation);
        reader.verify(fixture, lighting, count, rotation, 1024, 1);
        if (frame < 3) {
          smallSlots.add(lighting.indexTexture!);
        } else {
          expect(lighting.indexTexture, same(smallSlots[frame % 3]));
        }
      }

      for (final count in [2047, 2048]) {
        final boundary = fixture.build(count, 3);
        reader.verify(fixture, boundary, count, 3, 2048, 1);
      }
      final largeSlots = <gpu.Texture>[];
      for (final (count, rotation) in [(2049, 4), (17, 7), (900, 11)]) {
        final lighting = fixture.build(count, rotation);
        reader.verify(fixture, lighting, count, rotation, 2048, 2);
        largeSlots.add(lighting.indexTexture!);
      }

      void expectEmpty(PunctualLighting empty) {
        expect(empty.indexTexture, isNull);
        expect(empty.indexWidth, 0);
        expect(empty.indexHeight, 0);
        reader.expectRetained();
      }

      expectEmpty(fixture.build(1, 0, includeItems: false));
      expectEmpty(fixture.build(0, 0));

      const smallerCounts = [3, 31, 1025, 2049, 2, 100];
      for (var frame = 0; frame < smallerCounts.length; frame++) {
        final count = smallerCounts[frame];
        final rotation = 19 + frame * 41;
        final lighting = fixture.build(count, rotation);
        reader.verify(fixture, lighting, count, rotation, 2048, 2);
        expect(lighting.indexTexture, same(largeSlots[frame % 3]));
      }

      fixture.buffer.releaseTextures();
      reader.recent.clear();
      final restarted = fixture.build(3, 13);
      reader.verify(fixture, restarted, 3, 13, 4, 1);
      for (final previous in [...smallSlots, ...largeSlots]) {
        expect(restarted.indexTexture, isNot(same(previous)));
      }
    },
  );
}
