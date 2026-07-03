import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/light.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/render/custom_render_pass.dart'
    show packPostShadowInfo;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

class _NoopPass extends CustomRenderPass {
  @override
  String get name => 'noop';
  @override
  RenderStage get stage => RenderStage.afterScene;
  @override
  void execute(RenderPassContext context) {}
}

class _DepthPass extends CustomRenderPass {
  @override
  String get name => 'depth';
  @override
  RenderStage get stage => RenderStage.beforeToneMapping;
  @override
  Set<RenderInput> get inputs => const {
    RenderInput.depth,
    RenderInput.shadowMap,
  };
  @override
  void execute(RenderPassContext context) {}
}

void main() {
  test(
    'CustomRenderPass.inputs defaults to empty; declared inputs surface',
    () {
      expect(_NoopPass().inputs, isEmpty);
      expect(_DepthPass().inputs, {RenderInput.depth, RenderInput.shadowMap});
    },
  );

  test('packPostShadowInfo matches the PostShadowInfo std140 layout', () {
    final c0 = ShadowCascade(
      lightSpaceMatrix: Matrix4.identity()..scale(2.0, 3.0, 4.0),
      splitDistance: 10.0,
      boxSize: 5.0,
    );
    final c1 = ShadowCascade(
      lightSpaceMatrix: Matrix4.zero(),
      splitDistance: 40.0,
      boxSize: 20.0,
    );
    final bytes = packPostShadowInfo(
      [c0, c1],
      Vector3(0.0, -1.0, 0.0),
      Vector3(1.0, 0.9, 0.8),
    );
    final f = bytes.buffer.asFloat32List(bytes.offsetInBytes, 76);

    // mat4 light_space_matrix[4] at [0..63]: cascades 0 and 1, rest zero.
    expect(f.sublist(0, 16), c0.lightSpaceMatrix.storage);
    expect(f.sublist(16, 32), c1.lightSpaceMatrix.storage);
    expect(f.sublist(32, 64).every((v) => v == 0.0), isTrue);
    // vec4 cascade_splits at [64..67].
    expect(f[64], 10.0);
    expect(f[65], 40.0);
    // vec4 light_direction (xyz + count) at [68..71].
    expect([f[68], f[69], f[70], f[71]], [0.0, -1.0, 0.0, 2.0]);
    // vec4 light_color at [72..75].
    expect(f[72], closeTo(1.0, 1e-6));
    expect(f[73], closeTo(0.9, 1e-6));
    expect(f[74], closeTo(0.8, 1e-6));
  });
}
