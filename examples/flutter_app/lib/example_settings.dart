import 'dart:math' as math;
import 'dart:ui' show FilterQuality;

import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

/// The rendering and post-processing settings an example runs with.
///
/// Each example gets its own instance (recreated by the app shell whenever
/// the selection changes, see [resetExampleSettings]), so tuning one scene
/// never leaks into another and an example can ship its own defaults. The
/// settings sidebar edits the current [exampleSettings] instance, and each
/// example copies it onto its own scene with [applyTo] right before
/// rendering.
class ExampleSettings {
  /// Color grading shared across the examples.
  final ColorGradingSettings colorGrading = ColorGradingSettings();

  /// Chromatic aberration shared across the examples.
  final ChromaticAberrationSettings chromaticAberration =
      ChromaticAberrationSettings();

  /// Vignette shared across the examples.
  final VignetteSettings vignette = VignetteSettings();

  /// Film grain shared across the examples.
  final FilmGrainSettings filmGrain = FilmGrainSettings();

  /// Bloom shared across the examples.
  final BloomSettings bloom = BloomSettings();

  /// Screen-space ambient occlusion shared across the examples.
  final AmbientOcclusionSettings ambientOcclusion = AmbientOcclusionSettings();

  /// Volumetric god rays shared across the examples. Disabled by default.
  final GodRaysSettings godRays = GodRaysSettings();

  /// Depth of field shared across the examples. Disabled by default.
  final DepthOfField depthOfField = DepthOfField();

  /// Anti-aliasing mode shared across the examples.
  AntiAliasingMode antiAliasingMode = AntiAliasingMode.auto;

  /// Render scale shared across the examples (resolution relative to the
  /// display's native, applied to screen views).
  double renderScale = 1.0;

  /// Sampling quality the rendered image is composited with, shared
  /// across the examples.
  FilterQuality filterQuality = FilterQuality.medium;

  /// Whether the shared directional light is attached to the scene.
  bool directionalLightEnabled = true;

  /// Compass angle of the directional light, in degrees, around the up axis.
  double lightAzimuthDegrees = 35.0;

  /// Height of the directional light above the horizon, in degrees. `90`
  /// points straight down.
  double lightElevationDegrees = 55.0;

  /// Directional light intensity.
  double lightIntensity = 3.0;

  /// Linear RGB color of the directional light.
  final Vector3 lightColor = Vector3(1.0, 1.0, 1.0);

  /// Whether the directional light casts (cascaded) shadows.
  bool lightCastsShadow = true;

  /// World-space radius of the shadow penumbra. `0` is a hard edge.
  double shadowSoftness = 0.08;

  /// World-space width of the fade band at the far shadow edge.
  double shadowFadeRange = 2.0;

  /// Number of shadow cascades (1 through 4).
  int shadowCascadeCount = 4;

  /// View distance the cascades cover, in world units.
  double shadowMaxDistance = 150.0;

  /// Cascade split spacing, uniform (`0`) to logarithmic (`1`).
  double shadowCascadeSplitLambda = 0.6;

  /// Pixel resolution of each cascade's shadow-map tile.
  int shadowMapResolution = 1024;

  /// World-space depth bias subtracted from the receiver.
  double shadowDepthBias = 0.02;

  /// World-space offset along the receiver's normal.
  double shadowNormalBias = 0.02;

  /// How much the shadow also darkens the IBL ambient.
  double shadowAmbientStrength = 0.0;

  /// Which caster faces render into the shadow map.
  ShadowCasterFaces shadowCasterFaces = ShadowCasterFaces.front;

  /// A custom, user-authored effect, built by [loadExampleEffects]. Null
  /// until the example shader bundle finishes loading.
  PostEffect? waveEffect;

  /// Amplitude of the custom wave effect.
  double waveAmplitude = 0.008;

  /// Every shared setting as a labeled multi-line block, for dumping a
  /// hand-tuned look to the log so it can be copied into code.
  String describe() =>
      '''
  directionalLightEnabled: $directionalLightEnabled
  lightAzimuthDegrees: $lightAzimuthDegrees
  lightElevationDegrees: $lightElevationDegrees
  lightIntensity: $lightIntensity
  lightColor: ${lightColor.x}, ${lightColor.y}, ${lightColor.z}
  lightCastsShadow: $lightCastsShadow
  shadowSoftness: $shadowSoftness
  shadowFadeRange: $shadowFadeRange
  shadowCascadeCount: $shadowCascadeCount
  shadowMaxDistance: $shadowMaxDistance
  shadowCascadeSplitLambda: $shadowCascadeSplitLambda
  shadowMapResolution: $shadowMapResolution
  shadowDepthBias: $shadowDepthBias
  shadowNormalBias: $shadowNormalBias
  shadowAmbientStrength: $shadowAmbientStrength
  ambientOcclusion: enabled ${ambientOcclusion.enabled}, radius ${ambientOcclusion.radius}, intensity ${ambientOcclusion.intensity}, bias ${ambientOcclusion.bias}, sampleCount ${ambientOcclusion.sampleCount}, halfResolution ${ambientOcclusion.halfResolution}, specularMode ${ambientOcclusion.specularMode}
  colorGrading: enabled ${colorGrading.enabled}, brightness ${colorGrading.brightness}, contrast ${colorGrading.contrast}, saturation ${colorGrading.saturation}, temperature ${colorGrading.temperature}, tint ${colorGrading.tint}
  bloom: enabled ${bloom.enabled}, threshold ${bloom.threshold}, intensity ${bloom.intensity}, scatter ${bloom.scatter}
  godRays: enabled ${godRays.enabled}, intensity ${godRays.intensity}, density ${godRays.density}, anisotropy ${godRays.anisotropy}, stepCount ${godRays.stepCount}, maxDistance ${godRays.maxDistance}, jitter ${godRays.jitter}, color ${godRays.color.x}, ${godRays.color.y}, ${godRays.color.z}
  depthOfField: enabled ${depthOfField.enabled}, focusDistance ${depthOfField.focusDistance}, fStop ${depthOfField.fStop}, focalLength ${depthOfField.focalLength}, sensorHeight ${depthOfField.sensorHeight}, blurScale ${depthOfField.blurScale}, maxForegroundBlur ${depthOfField.maxForegroundBlur}, maxBackgroundBlur ${depthOfField.maxBackgroundBlur}, bladeCount ${depthOfField.bladeCount}, bladeRotation ${depthOfField.bladeRotation}, bladeCurvature ${depthOfField.bladeCurvature}, quality ${depthOfField.quality}
  chromaticAberration: enabled ${chromaticAberration.enabled}, intensity ${chromaticAberration.intensity}
  vignette: enabled ${vignette.enabled}, intensity ${vignette.intensity}, radius ${vignette.radius}, smoothness ${vignette.smoothness}
  filmGrain: enabled ${filmGrain.enabled}, intensity ${filmGrain.intensity}
  antiAliasingMode: $antiAliasingMode
  renderScale: $renderScale''';

  /// Copies the shared settings onto [scene] so its next frame uses them.
  void applyTo(Scene scene) {
    if (scene.antiAliasingMode != antiAliasingMode) {
      scene.antiAliasingMode = antiAliasingMode;
    }
    scene.renderScale = renderScale;
    scene.filterQuality = filterQuality;

    final grading = scene.postProcess.colorGrading;
    grading.enabled = colorGrading.enabled;
    grading.brightness = colorGrading.brightness;
    grading.contrast = colorGrading.contrast;
    grading.saturation = colorGrading.saturation;
    grading.temperature = colorGrading.temperature;
    grading.tint = colorGrading.tint;
    grading.lift.setFrom(colorGrading.lift);
    grading.gamma.setFrom(colorGrading.gamma);
    grading.gain.setFrom(colorGrading.gain);

    final aberration = scene.postProcess.chromaticAberration;
    aberration.enabled = chromaticAberration.enabled;
    aberration.intensity = chromaticAberration.intensity;

    final vig = scene.postProcess.vignette;
    vig.enabled = vignette.enabled;
    vig.intensity = vignette.intensity;
    vig.radius = vignette.radius;
    vig.smoothness = vignette.smoothness;

    final grain = scene.postProcess.filmGrain;
    grain.enabled = filmGrain.enabled;
    grain.intensity = filmGrain.intensity;

    final sceneBloom = scene.postProcess.bloom;
    sceneBloom.enabled = bloom.enabled;
    sceneBloom.threshold = bloom.threshold;
    sceneBloom.intensity = bloom.intensity;
    sceneBloom.scatter = bloom.scatter;

    final ao = scene.ambientOcclusion;
    ao.enabled = ambientOcclusion.enabled;
    ao.radius = ambientOcclusion.radius;
    ao.intensity = ambientOcclusion.intensity;
    ao.bias = ambientOcclusion.bias;
    ao.sampleCount = ambientOcclusion.sampleCount;
    ao.halfResolution = ambientOcclusion.halfResolution;
    ao.specularMode = ambientOcclusion.specularMode;

    final rays = scene.godRays;
    rays.enabled = godRays.enabled;
    rays.intensity = godRays.intensity;
    rays.density = godRays.density;
    rays.anisotropy = godRays.anisotropy;
    rays.stepCount = godRays.stepCount;
    rays.maxDistance = godRays.maxDistance;
    rays.jitter = godRays.jitter;
    rays.color.setFrom(godRays.color);

    final dof = scene.depthOfField;
    dof.enabled = depthOfField.enabled;
    dof.focusDistance = depthOfField.focusDistance;
    dof.fStop = depthOfField.fStop;
    dof.focalLength = depthOfField.focalLength;
    dof.sensorHeight = depthOfField.sensorHeight;
    dof.blurScale = depthOfField.blurScale;
    dof.maxForegroundBlur = depthOfField.maxForegroundBlur;
    dof.maxBackgroundBlur = depthOfField.maxBackgroundBlur;
    dof.bladeCount = depthOfField.bladeCount;
    dof.bladeRotation = depthOfField.bladeRotation;
    dof.bladeCurvature = depthOfField.bladeCurvature;
    dof.quality = depthOfField.quality;

    if (directionalLightEnabled) {
      // Derive the travel direction from azimuth/elevation: elevation lifts
      // the light above the horizon (90 degrees points straight down).
      final azimuth = lightAzimuthDegrees * math.pi / 180.0;
      final elevation = lightElevationDegrees * math.pi / 180.0;
      final horizontal = math.cos(elevation);
      final direction = Vector3(
        horizontal * math.cos(azimuth),
        -math.sin(elevation),
        horizontal * math.sin(azimuth),
      );
      // Reuse the scene's directional light component, or attach one. The
      // light's node has no transform, so its world direction is the
      // direction set here.
      final existing = scene.root.getComponents<DirectionalLightComponent>();
      final DirectionalLightComponent component;
      if (existing.isEmpty) {
        scene.directionalLight = DirectionalLight();
        component = scene.root.getComponents<DirectionalLightComponent>().first;
      } else {
        component = existing.first;
      }
      final light = component.light;
      light.direction = direction;
      light.intensity = lightIntensity;
      light.color.setFrom(lightColor);
      light.castsShadow = lightCastsShadow;
      light.shadowSoftness = shadowSoftness;
      light.shadowFadeRange = shadowFadeRange;
      light.shadowCascadeCount = shadowCascadeCount;
      light.shadowMaxDistance = shadowMaxDistance;
      light.shadowCascadeSplitLambda = shadowCascadeSplitLambda;
      light.shadowMapResolution = shadowMapResolution;
      light.shadowDepthBias = shadowDepthBias;
      light.shadowNormalBias = shadowNormalBias;
      light.shadowAmbientStrength = shadowAmbientStrength;
      light.shadowCasterFaces = shadowCasterFaces;
    } else {
      for (final component
          in scene.root.getComponents<DirectionalLightComponent>().toList()) {
        scene.root.removeComponent(component);
      }
    }

    final wave = waveEffect;
    if (wave != null) {
      wave.setUniformBlockFromFloats('WaveInfo', [
        waveAmplitude,
        24.0,
        3.0,
        0.0,
      ]);
      if (!scene.postProcess.customEffects.contains(wave)) {
        scene.postProcess.customEffects.add(wave);
      }
    }
  }
}

/// The settings instance for the currently selected example. Examples read
/// this in their tick; the app shell replaces it via [resetExampleSettings]
/// when the selection changes.
ExampleSettings exampleSettings = ExampleSettings();

// The custom wave effect is loaded once at startup and carried across the
// per-example instances.
PostEffect? _waveEffect;

/// Replaces [exampleSettings] with a fresh instance for a newly selected
/// example, built by [defaults] when the example overrides the stock
/// defaults, and returns it.
ExampleSettings resetExampleSettings([ExampleSettings Function()? defaults]) {
  exampleSettings = (defaults?.call() ?? ExampleSettings())
    ..waveEffect = _waveEffect;
  return exampleSettings;
}

/// Loads the example shader bundle and builds the custom post-processing
/// effects. Awaited at startup alongside [Scene.initializeStaticResources].
Future<void> loadExampleEffects() async {
  final library = await gpu.loadShaderLibraryAsync(
    'packages/example_app/flutter_gpu_shaders/shaderbundles/'
    'example.shaderbundle',
  );
  final waveShader = library?['WaveFragment'];
  if (waveShader != null) {
    _waveEffect = PostEffect(
      fragmentShader: waveShader,
      insertion: PostInsertion.beforeTonemap,
      enabled: false,
      useFrameInfo: true,
    );
    exampleSettings.waveEffect = _waveEffect;
  }
}
