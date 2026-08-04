import 'package:flutter_scene/src/fmat/target_shader_bundle.dart';
import 'package:flutter_scene/src/gpu/web/shader_bundle_generated.dart' as fb;
import 'package:flutter_test/flutter_test.dart';

fb.BackendShaderObjectBuilder _backend(int byte) =>
    fb.BackendShaderObjectBuilder(
      stage: fb.ShaderStage.kFragment,
      entrypoint: 'main',
      shader: List<int>.filled(128, byte),
    );

void main() {
  test('shader bundle trimming keeps only requested backends', () {
    final source = fb.ShaderBundleObjectBuilder(
      formatVersion: fb.ShaderBundleFormatVersion.kVersion.value,
      shaders: [
        fb.ShaderObjectBuilder(
          name: 'Fragment',
          metalIos: _backend(1),
          metalDesktop: _backend(2),
          openglEs: _backend(3),
          openglDesktop: _backend(4),
          vulkan: _backend(5),
        ),
      ],
    ).toBytes('IPSB');

    final trimmed = trimShaderBundle(source, const {
      ShaderBundleBackend.openglEs,
      ShaderBundleBackend.vulkan,
    });
    final shader = fb.ShaderBundle(trimmed).shaders!.single;

    expect(trimmed.length, lessThan(source.length * 0.6));
    expect(shader.name, 'Fragment');
    expect(shader.metalIos, isNull);
    expect(shader.metalDesktop, isNull);
    expect(shader.openglEs?.shader, everyElement(3));
    expect(shader.openglDesktop, isNull);
    expect(shader.vulkan?.shader, everyElement(5));
  });
}
