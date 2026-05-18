// Covers DirectionalLight.computeLightSpaceMatrix, in particular the
// texel snapping that pins the shadow map's texel grid to the world so
// shadow edges do not shimmer as the focus point moves.

import 'package:flutter_scene/src/light.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('DirectionalLight.computeLightSpaceMatrix', () {
    // Snapping shifts the projection so a fixed world reference lands on
    // a texel center. The world origin should therefore project to an
    // integer texel for any focus point; that is what keeps the texel
    // grid pinned to the world.
    test('texel snapping pins the world origin to a texel center', () {
      for (final focus in [
        Vector3(0.3, 0.0, 0.0),
        Vector3(5.123, 0.0, -2.7),
        Vector3(-11.9, 0.4, 8.05),
      ]) {
        final light = DirectionalLight(
          direction: Vector3(-0.3, -1.0, -0.2),
          castsShadow: true,
          shadowFocusPoint: focus,
        );
        final clip = light.computeLightSpaceMatrix().transformed(
          Vector4(0, 0, 0, 1),
        );
        final resolution = light.shadowMapResolution.toDouble();
        final texelX = (clip.x * 0.5 + 0.5) * resolution;
        final texelY = (clip.y * 0.5 + 0.5) * resolution;
        expect(texelX - texelX.roundToDouble(), closeTo(0.0, 1e-3));
        expect(texelY - texelY.roundToDouble(), closeTo(0.0, 1e-3));
      }
    });
  });
}
