import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/screen_distortion.dart'
    show ScreenDistortionPass;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('ScreenDistortionSettings defaults to off with no pulses', () {
    final settings = ScreenDistortionSettings();
    expect(settings.enabled, isFalse);
    expect(settings.pulses, isEmpty);
    expect(ScreenDistortionSettings.maxPulses, 4);
  });

  test('DistortionPulse defaults match the design values', () {
    final pulse = DistortionPulse();
    expect(pulse.center, Vector2(0.5, 0.5));
    expect(pulse.radius, 0.0);
    expect(pulse.thickness, 0.08);
    expect(pulse.strength, 0.02);
    expect(pulse.chromaticAberration, 0.5);
  });

  test('DistortionPulse constructor overrides every field', () {
    final pulse = DistortionPulse(
      center: Vector2(0.2, 0.7),
      radius: 1.5,
      thickness: 0.3,
      strength: 0.1,
      chromaticAberration: 0.9,
    );
    expect(pulse.center, Vector2(0.2, 0.7));
    expect(pulse.radius, 1.5);
    expect(pulse.thickness, 0.3);
    expect(pulse.strength, 0.1);
    expect(pulse.chromaticAberration, 0.9);
  });

  test('pulses is mutable and reflects add/remove per frame', () {
    final settings = ScreenDistortionSettings();
    final pulse = DistortionPulse();
    settings.pulses.add(pulse);
    expect(settings.pulses, [pulse]);

    settings.pulses.remove(pulse);
    expect(settings.pulses, isEmpty);
  });

  test('ScreenDistortionPass runs after tone mapping and needs no inputs', () {
    final pass = ScreenDistortionPass(ScreenDistortionSettings());
    expect(pass.stage, RenderStage.afterToneMapping);
    expect(pass.inputs, isEmpty);
    expect(pass.name, 'screen_distortion');
  });
}
