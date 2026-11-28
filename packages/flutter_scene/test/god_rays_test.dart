@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_scene/gpu.dart' as gpu;
// ignore: implementation_imports
import 'package:flutter_scene/src/god_rays.dart';
import 'package:flutter_scene/scene.dart' show RenderInput, RenderStage;
import 'package:flutter_test/flutter_test.dart';

String _shader(String name) =>
    File('shaders/$name').readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  test(
    'GodRaysPass uses a nearest clamp-to-edge sampler for depth and shadow',
    () {
      final pass = GodRaysPass(GodRaysSettings());
      expect(pass.stage, RenderStage.afterScene);
      expect(pass.inputs, {RenderInput.depth, RenderInput.shadowMap});

      final sampler = GodRaysPass.depthAndShadowSampler;
      expect(sampler.minFilter, gpu.MinMagFilter.nearest);
      expect(sampler.magFilter, gpu.MinMagFilter.nearest);
      expect(sampler.widthAddressMode, gpu.SamplerAddressMode.clampToEdge);
      expect(sampler.heightAddressMode, gpu.SamplerAddressMode.clampToEdge);
    },
  );

  test(
    'god rays shader guards cascade depth range, tile UV, and atlas row math',
    () {
      final source = _shader('flutter_scene_god_rays.frag');
      expect(source, contains('proj.z >= 0.0 && proj.z <= 1.0'));
      expect(
        source,
        contains('clamp(proj.xy * 0.5 + 0.5, vec2(0.001), vec2(0.999))'),
      );
      expect(source, contains('max(shadow.cascade_atlas.z, 1.0)'));
      expect(source, contains('floor((float(IDX) + 0.5) / cols)'));
    },
  );
}
