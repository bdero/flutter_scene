// Locks the raw-material scene-input header against the `.fmat` accessors it
// mirrors. The two are separate sources (a raw shader has no FragInfo to read
// gates and the screen mapping out of), so nothing but a test keeps them
// meaning the same thing.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

File _resolveFile(String relativePath) {
  final direct = File(relativePath);
  if (direct.existsSync()) return direct;
  final inPackage = File('packages/flutter_scene/$relativePath');
  if (inPackage.existsSync()) return inPackage;
  throw FileSystemException('Could not find $relativePath');
}

void main() {
  final header = _resolveFile('shaders/scene_inputs.glsl').readAsStringSync();
  // The `.fmat` accessors the header has to agree with.
  final emitter = _resolveFile(
    'shaders/material_scene_inputs.glsl',
  ).readAsStringSync();

  test('each sampler is behind the define that declares it', () {
    // A declared-but-unsampled sampler is eliminated while the reflection
    // still lists it, which fails at bind time, so a material that took only
    // one input must compile with only that one.
    for (final (define, sampler) in const [
      ('FLUTTER_SCENE_SCENE_COLOR', 'uniform sampler2D scene_opaque_color;'),
      ('FLUTTER_SCENE_SCENE_DEPTH', 'uniform highp sampler2D scene_depth;'),
      (
        'FLUTTER_SCENE_FILTERED_SCENE_COLOR',
        'uniform sampler2D scene_filtered_color;',
      ),
    ]) {
      final guard = header.indexOf('#ifdef $define');
      expect(guard, isNonNegative, reason: '$define has no guard');
      final end = header.indexOf('#endif', guard);
      expect(header.substring(guard, end), contains(sampler));
    }
  });

  test('reads are gated on the frame producing the input', () {
    // Ungated, a missing input samples the opaque-white placeholder. The
    // sentinels are the emitter's, so an effect fades out the same way on
    // either path.
    expect(header, contains('scene_input_info.available.x >= 0.5'));
    expect(header, contains('scene_input_info.available.y >= 0.5'));
    expect(emitter, contains('frag_info.scene_inputs.x < 0.5'));
    expect(emitter, contains('frag_info.scene_inputs.y < 0.5'));

    // Missing color reads black and missing depth reads far, matching
    // `GetSceneColor` and `GetSceneDepth` in the emitter. The `.fmat` side
    // names the far sentinel, so the value is locked through the constant and
    // through the unprojection that reuses it.
    expect(header, contains('vec3 result = vec3(0.0);'));
    expect(header, contains('float result = 1.0e8;'));
    expect(emitter, contains('return vec3(0.0);'));
    expect(emitter, contains('const float kSceneDepthUnavailable = 1.0e8;'));
    expect(emitter, contains('return kSceneDepthUnavailable;'));
    // An unavailable depth unprojects to that same distance, so a projection
    // volume's inside test lands outside instead of on its own boundary.
    expect(
      emitter,
      contains('frag_info.camera_forward.xyz * kSceneDepthUnavailable'),
    );
  });

  test('samples at the same clamped screen UV as a .fmat material', () {
    expect(header, contains('gl_FragCoord.xy * scene_input_info.screen.zw'));
    expect(emitter, contains('clamp(GetScreenUv() + uv_offset, vec2(0.001)'));
    expect(header, contains('clamp(GetScreenUv() + uv_offset, vec2(0.001)'));
  });

  test('the block matches what bindSceneInputInfo packs', () {
    // Five vec4s in this order, which is the Float32List the engine writes.
    final block = header.substring(
      header.indexOf('uniform SceneInputInfo'),
      header.indexOf('scene_input_info;'),
    );
    expect(
      RegExp(r'vec4 (\w+);').allMatches(block).map((m) => m.group(1)).toList(),
      ['available', 'screen', 'camera_forward', 'camera_right', 'camera_up'],
    );
  });
}
