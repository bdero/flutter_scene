// ignore_for_file: implementation_imports
import 'package:flutter_scene/src/fmat/depth_surface_fallback.dart';
import 'package:flutter_test/flutter_test.dart';

const _owners = {
  'LitCutoutDepthSurface': 'LitCutout',
  'LitCutoutDepthNormalSurface': 'LitCutout',
  'LitCutoutShadowSurface': 'LitCutout',
};
const _entries = {
  'LitCutout',
  'LitCutoutShadow',
  'LitCutoutCube',
  'LitCutoutDepthSurface',
  'LitCutoutDepthNormalSurface',
  'LitCutoutShadowSurface',
  'Other',
};

void main() {
  test('blames the material when only its depth passes fail to compile', () {
    const error =
        'Compilation failed for bundled shader "LitCutoutShadowSurface".\n'
        '"LitCutoutShadowSurface": GLSL to SPIRV failed; Compilation error.\n'
        "LitCutoutShadowSurface:35: error: 'void' : type cannot have "
        'precision qualifier';
    expect(materialsFailingOnlyInDepthPasses(error, _owners, _entries), {
      'LitCutout',
    });
  });

  test('blames the material when only its depth passes fail the sidecar', () {
    const error =
        'WgslSidecarException: LitCutoutShadowSurface: sampler bindings in '
        '"LitCutoutShadowSurface" disagree, predicted [128] but Tint emitted '
        '[129, 130]\n'
        'LitCutoutDepthSurface: sampler bindings in "LitCutoutDepthSurface" '
        'disagree, predicted [128] but Tint emitted [129, 130]';
    expect(materialsFailingOnlyInDepthPasses(error, _owners, _entries), {
      'LitCutout',
    });
  });

  test('blames the material for a lint problem in its depth passes', () {
    const error =
        'LitCutoutShadowSurface: declares a sample mask it never writes, '
        'which drops every sample on Vulkan and WebGPU';
    expect(materialsFailingOnlyInDepthPasses(error, _owners, _entries), {
      'LitCutout',
    });
  });

  test('keeps the failure when any other entry is named', () {
    const error =
        'Compilation failed for bundled shader "LitCutoutShadowSurface".\n'
        'Compilation failed for bundled shader "Other".';
    expect(materialsFailingOnlyInDepthPasses(error, _owners, _entries), isNull);
  });

  test('keeps the failure when no entry is named', () {
    expect(
      materialsFailingOnlyInDepthPasses('impellerc crashed', _owners, _entries),
      isNull,
    );
  });

  test('drops only the depth_surface map from a sidecar', () {
    final sidecar = {
      'shading_model': 'lit',
      'depth_surface': {'shadow': 'LitCutoutShadowSurface'},
    };
    expect(withoutDepthSurfaces(sidecar), {'shading_model': 'lit'});
    expect(sidecar, contains('depth_surface'));
  });
}
